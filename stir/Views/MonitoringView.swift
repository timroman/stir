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
    @StateObject private var moonTracker = MoonTracker()

    var body: some View {
        ZStack {
            // Black all night, no time-of-night signal in the light. The real
            // sun and moon on their rings are the only things on screen — read
            // them if you want, or let them be art.
            SkyBackground(colors: NightSky.colors(NightSky.deepNight))

            SkyFace(moonPosition: moonTracker.position,
                    sunPosition: moonTracker.sunPosition)
                .offset(burnInOffset)

            VStack {
                Spacer()

                // Only functional detail, kept low and out of the sky — no
                // status labels; the face stays clean
                VStack(spacing: 8) {
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
                .padding(.bottom, 28)

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
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            updateIdleTimer()
        }
        .onReceive(audioMonitor.$monitoringState) { state in
            switch state {
            case .idle:
                break
            case .calibrating:
                StirLiveActivity.updateStatus("calibrating...")
            case .listening:
                StirLiveActivity.updateStatus("listening...")
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
            UIApplication.shared.isIdleTimerDisabled = false
            UIDevice.current.isBatteryMonitoringEnabled = false
        }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: currentTime).lowercased()
    }

    // Keep the display alive through the night — but only while docked, so a
    // forgotten un-docked phone doesn't drain overnight
    private func updateIdleTimer() {
        let state = UIDevice.current.batteryState
        UIApplication.shared.isIdleTimerDisabled = (state == .charging || state == .full)
    }

    // A slow pixel drift so the moon never burns into an OLED panel
    private var burnInOffset: CGSize {
        let minute = Double(Calendar.current.component(.minute, from: currentTime))
        return CGSize(width: 5 * sin(minute / 60 * 2 * .pi),
                      height: 4 * cos(minute / 60 * 2 * .pi))
    }

    private func startSessionAsync() async {
        guard !hasStarted else { return }
        hasStarted = true

        UIDevice.current.isBatteryMonitoringEnabled = true
        updateIdleTimer()
        moonTracker.start()

        if appState.settings.alarmEnabled {
            audioMonitor.sensitivityMultiplier = appState.settings.sensitivityMultiplier

            // Start audio engine NOW while device is unlocked. This establishes the
            // shared .playAndRecord session before the device locks; white noise
            // plays through it and the app stays alive all night.
            audioMonitor.start()

            // System-level can't-oversleep net (iOS 26+); fires 2 min after "up by"
            // unless the session is stopped or the alarm is dismissed first
            AlarmBackstop.schedule(upBy: appState.settings.wakeUpBy, tagline: appState.settings.tagline)
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

        StirLiveActivity.start(wakeWindow: appState.upByFormatted)

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
        moonTracker.refresh(at: now)
        let settings = appState.settings
        let fadeStart = appState.fadeStartTime
        let whiteNoiseEnd = appState.whiteNoiseEndTime

        // White noise lifecycle. Enabled means you hear it — even a session
        // started inside the quiet gap or wake window plays white noise
        // (3s fade-in), then fades out; calibration waits for silence.
        if settings.whiteNoiseEnabled {
            // In alarm mode, wait for the mic engine's first buffer — proof the
            // audio graph is live — so the fade-in is actually heard instead of
            // ramping into a dead route
            let audioReady = !settings.alarmEnabled || audioMonitor.isAudioLive
            if !hasStartedWhiteNoise && audioReady {
                hasStartedWhiteNoise = true
                startWhiteNoise()
            }

            if whiteNoisePlayer.isPlaying && !whiteNoisePlayer.isFadingOut && now >= fadeStart {
                // Late starts get at least two gentle minutes before the fade completes
                let remaining = max(whiteNoiseEnd.timeIntervalSince(now), 120)
                whiteNoisePlayer.startFadeOut(duration: remaining) {
                    // Player stops itself; phase transition happens on the next tick
                }
            }
        }

        // Alarm-mode monitoring (unchanged from pre-merge behavior)
        if settings.alarmEnabled {
            let windowStart = appState.windowStart
            let inWakeWindow = now >= windowStart && now <= settings.wakeUpBy

            // Start calibration when the wake window begins (audio engine already running)
            // Never calibrate over our own white noise — a late-start session
            // waits for the fade to finish before learning the room
            if inWakeWindow && audioMonitor.monitoringState == .idle && !whiteNoisePlayer.isPlaying {
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
        case .whiteNoise: StirLiveActivity.updateStatus("white noise")
        case .fading: StirLiveActivity.updateStatus("fading out...")
        case .quiet: StirLiveActivity.updateStatus("quiet")
        case .complete: StirLiveActivity.updateStatus("good morning")
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
        whiteNoisePlayer.stopGently()
        audioMonitor.stop()
        motionMonitor.stop()
        StirLiveActivity.stop()
        AlarmBackstop.cancelBackstop()
    }

    private func triggerAlarm() {
        stopSessionTimer()
        whiteNoisePlayer.stop()
        audioMonitor.stop()
        motionMonitor.stop()
        StirLiveActivity.triggerAlarm(message: appState.settings.tagline)
        appState.triggerAlarm()
    }
}

#Preview {
    MonitoringView()
        .environmentObject(AppState())
}
