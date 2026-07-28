import SwiftUI
import AVFoundation

// The phases of a night session, derived each tick from the clock — never stored
enum SessionPhase: Equatable {
    case whiteNoise   // white noise playing at full volume
    case fading       // white noise fading out
    case quiet        // silence before the wake window (alarm mode)
    case wakeWindow   // calibrating/listening (alarm mode)
    case complete     // fade finished in no-alarm mode; silence is the wake-up
}

struct MonitoringView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var audioMonitor = AudioMonitor()
    @StateObject private var motionMonitor = MotionMonitor()
    @StateObject private var whiteNoisePlayer = WhiteNoisePlayer()
    @State private var currentTime = Date()
    @State private var hasStarted = false
    @State private var sessionTimer: Timer?
    @State private var phase: SessionPhase = .whiteNoise
    @State private var hasStartedWhiteNoise = false
    @State private var sessionStart = Date()

    var body: some View {
        ZStack {
            SkyBackground(colors: NightSky.colors(
                now: currentTime,
                sessionStart: sessionStart,
                upBy: appState.settings.wakeUpBy
            ))
            .animation(.easeInOut(duration: 2), value: currentTime)

            VStack {
                MoonView()
                    .padding(.top, 24)

                Spacer()

                // Current time - large and quiet
                Text(timeString)
                    .font(.system(size: 72, weight: .ultraLight))
                    .foregroundColor(.white.opacity(0.85))

                Text(appState.upByFormatted)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.45))
                    .padding(.top, 8)

                // Status info
                VStack(spacing: 8) {
                    Text(statusText)
                        .font(.system(size: 12, weight: .semibold))
                        .kerning(2)
                        .textCase(.uppercase)
                        .foregroundColor(statusColor)

                    if phase == .fading {
                        ProgressView(value: Double(whiteNoisePlayer.fadeProgress))
                            .progressViewStyle(LinearProgressViewStyle(tint: .white.opacity(0.4)))
                            .frame(width: 120)
                    }

                    if audioMonitor.monitoringState.isCalibrating {
                        // Calibration progress
                        VStack(spacing: 4) {
                            ProgressView(value: audioMonitor.calibrationProgress)
                                .progressViewStyle(LinearProgressViewStyle(tint: .yellow.opacity(0.8)))
                                .frame(width: 120)

                            Text("\(Int(audioMonitor.calibrationProgress * 30))s / 30s")
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.white.opacity(0.4))
                        }
                    } else if let threshold = audioMonitor.monitoringState.threshold {
                        // Only show levels when listening
                        HStack(spacing: 16) {
                            VStack(spacing: 2) {
                                Text("\(String(format: "%.0f", audioMonitor.currentLevel))")
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                Text("dB")
                                    .font(.system(size: 9))
                            }
                            .foregroundColor(.white.opacity(0.4))

                            Text("/")
                                .foregroundColor(.white.opacity(0.2))

                            VStack(spacing: 2) {
                                Text("\(String(format: "%.0f", threshold))")
                                    .font(.system(size: 14, weight: .medium, design: .monospaced))
                                Text("trigger")
                                    .font(.system(size: 9))
                            }
                            .foregroundColor(.white.opacity(0.4))
                        }
                    }
                }
                .padding(.top, 20)

                Spacer()

                // Stop button - subtle; reads "done" once a no-alarm session completes
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        endSession()
                        appState.stopMonitoring()
                    }
                }) {
                    VStack(spacing: 8) {
                        Image(systemName: "chevron.up")
                            .font(.caption)
                        Text(phase == .complete ? "done" : "stop")
                            .font(.subheadline)
                    }
                    .foregroundColor(.white.opacity(0.3))
                }
                .padding(.bottom, 40)
            }
        }
        .animation(.easeInOut(duration: 0.6), value: audioMonitor.monitoringState)
        .animation(.easeInOut(duration: 0.6), value: phase)
        .task {
            await startSessionAsync()
        }
        .onReceive(audioMonitor.$monitoringState) { state in
            switch state {
            case .idle:
                break
            case .calibrating:
                YOLOLiveActivity.updateStatus("calibrating...")
            case .listening:
                YOLOLiveActivity.updateStatus("listening...")
            }
        }
        .onReceive(audioMonitor.$didTrigger) { triggered in
            if triggered {
                print("🚨 Audio trigger received, stopping monitors and switching to alarm")
                triggerAlarm()
            }
        }
        .onReceive(motionMonitor.$didTrigger) { triggered in
            if triggered {
                print("🚨 Motion trigger received, stopping monitors and switching to alarm")
                triggerAlarm()
            }
        }
        .onDisappear {
            // Clean up monitors but leave the Live Activity alone — when the alarm
            // fires this view disappears while the activity must stay in alarm state
            stopSessionTimer()
            whiteNoisePlayer.stop()
            audioMonitor.stop()
            motionMonitor.stop()
        }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: currentTime).lowercased()
    }

    private var statusText: String {
        switch phase {
        case .whiteNoise:
            return "white noise"
        case .fading:
            return "fading out..."
        case .quiet:
            return "quiet"
        case .complete:
            return "white noise ended — good morning"
        case .wakeWindow:
            switch audioMonitor.monitoringState {
            case .idle: return "waiting"
            case .calibrating: return "calibrating..."
            case .listening: return "listening"
            }
        }
    }

    private var statusColor: Color {
        switch phase {
        case .whiteNoise, .fading:
            return NightSky.cream.opacity(0.7)
        case .quiet:
            return .white.opacity(0.45)
        case .complete:
            return NightSky.dawnAmber
        case .wakeWindow:
            switch audioMonitor.monitoringState {
            case .idle: return .white.opacity(0.45)
            case .calibrating: return NightSky.dawnAmber.opacity(0.8)
            case .listening: return NightSky.dawnAmber
            }
        }
    }

    private func startSessionAsync() async {
        guard !hasStarted else { return }
        hasStarted = true
        sessionStart = Date()

        if appState.settings.alarmEnabled {
            audioMonitor.sensitivityMultiplier = appState.settings.sensitivityMultiplier

            // Start audio engine NOW while device is unlocked. This establishes the
            // shared .playAndRecord session before the device locks; white noise
            // plays through it and the app stays alive all night.
            audioMonitor.start()
        } else {
            // No-alarm mode: mic never activates. Playback-only session keeps the
            // app alive in the background while white noise plays.
            do {
                let session = AVAudioSession.sharedInstance()
                try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                try session.setActive(true)
            } catch {
                print("❌ Failed to configure playback session: \(error)")
            }
        }

        YOLOLiveActivity.start(wakeWindow: appState.upByFormatted)

        startSessionTimer()
        tick()
    }

    private func startSessionTimer() {
        sessionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [self] _ in
            Task { @MainActor in
                currentTime = Date()
                tick()
            }
        }
        print("⏰ Session timer started")
    }

    private func stopSessionTimer() {
        sessionTimer?.invalidate()
        sessionTimer = nil
    }

    // Drives the whole night: white noise → fade → quiet → wake window → alarm.
    // All boundaries are recomputed from appState each tick.
    private func tick() {
        let now = Date()
        let settings = appState.settings
        let fadeStart = appState.fadeStartTime
        let whiteNoiseEnd = appState.whiteNoiseEndTime

        // White noise lifecycle
        if settings.whiteNoiseEnabled {
            if !hasStartedWhiteNoise && now < whiteNoiseEnd {
                // Also covers a late bedtime landing mid-fade: start, then the fade
                // branch below compresses the remaining fade time
                hasStartedWhiteNoise = true
                startWhiteNoise()
            }

            if whiteNoisePlayer.isPlaying && !whiteNoisePlayer.isFadingOut && now >= fadeStart {
                whiteNoisePlayer.startFadeOut(duration: whiteNoiseEnd.timeIntervalSince(now)) {
                    // Player stops itself; phase transition happens on the next tick
                }
            }

            // Safety: never let white noise bleed past its end time
            if whiteNoisePlayer.isPlaying && now >= whiteNoiseEnd {
                whiteNoisePlayer.stop()
            }
        }

        // Alarm-mode monitoring (unchanged from pre-merge behavior)
        if settings.alarmEnabled {
            let windowStart = appState.windowStart
            let inWakeWindow = now >= windowStart && now <= settings.wakeUpBy

            // Start calibration when the wake window begins (audio engine already running)
            if inWakeWindow && audioMonitor.monitoringState == .idle {
                audioMonitor.startCalibration()
            }

            // Start motion monitoring when calibration completes and we're listening
            if audioMonitor.monitoringState.isListening &&
               settings.motionDetectionEnabled &&
               !motionMonitor.isMonitoring {
                motionMonitor.start()
            }

            // Fallback alarm at "up by"
            if now >= settings.wakeUpBy && appState.currentScreen == .monitoring {
                triggerAlarm()
                return
            }
        }

        updatePhase(now: now)
    }

    private func updatePhase(now: Date) {
        let newPhase: SessionPhase
        if appState.settings.alarmEnabled {
            if now >= appState.windowStart {
                newPhase = .wakeWindow
            } else if now >= appState.whiteNoiseEndTime || !appState.settings.whiteNoiseEnabled {
                newPhase = .quiet
            } else if whiteNoisePlayer.isFadingOut {
                newPhase = .fading
            } else {
                newPhase = .whiteNoise
            }
        } else {
            if now >= appState.whiteNoiseEndTime || !whiteNoisePlayer.isPlaying && hasStartedWhiteNoise {
                newPhase = .complete
            } else if whiteNoisePlayer.isFadingOut {
                newPhase = .fading
            } else {
                newPhase = .whiteNoise
            }
        }

        guard newPhase != phase else { return }
        phase = newPhase

        // Wake-window Live Activity updates come from AudioMonitor state changes
        switch newPhase {
        case .whiteNoise: YOLOLiveActivity.updateStatus("white noise")
        case .fading: YOLOLiveActivity.updateStatus("fading out...")
        case .quiet: YOLOLiveActivity.updateStatus("quiet")
        case .complete: YOLOLiveActivity.updateStatus("good morning")
        case .wakeWindow: break
        }
    }

    private func startWhiteNoise() {
        let settings = appState.settings
        if let customId = settings.whiteNoiseCustomSoundId,
           let custom = CustomSoundManager.shared.customSounds.first(where: { $0.id == customId }) {
            whiteNoisePlayer.playCustomSound(custom, volume: settings.whiteNoiseVolume)
        } else {
            whiteNoisePlayer.play(sound: settings.whiteNoiseSound, volume: settings.whiteNoiseVolume)
        }
    }

    private func endSession() {
        stopSessionTimer()
        whiteNoisePlayer.stop()
        audioMonitor.stop()
        motionMonitor.stop()
        YOLOLiveActivity.stop()
    }

    private func triggerAlarm() {
        stopSessionTimer()
        whiteNoisePlayer.stop()
        audioMonitor.stop()
        motionMonitor.stop()
        YOLOLiveActivity.triggerAlarm(message: appState.settings.tagline)
        appState.triggerAlarm()
    }
}

#Preview {
    MonitoringView()
        .environmentObject(AppState())
}
