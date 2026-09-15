import SwiftUI
import AVFoundation
import os

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
    // A brushed screen at 3am must not end the night — that also cancels the
    // backstop, leaving nothing to wake you. A hold is immune to a brush and,
    // unlike the two-tap confirm it replaces, states its own gesture: nothing
    // is hidden behind a state change you have to notice after acting, and
    // there is no timing window to fall outside of.
    private let holdDuration: TimeInterval = 1.2
    @State private var isHolding = false
    @State private var holdProgress: CGFloat = 0

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

                // Subtle by design; reads "done" once a no-alarm session completes
                VStack(spacing: 8) {
                    Image(systemName: "chevron.up")
                        .font(.caption)
                    Text(stopLabel)
                        .font(.subheadline)
                }
                .foregroundColor(.white.opacity(isHolding ? 0.7 : 0.3))
                // The glyphs alone were a 30x33pt target — under Apple's 44pt
                // minimum, so a tap aimed in the dark could miss entirely and
                // look like a dead button. The added area is transparent.
                .frame(minWidth: 120, minHeight: 60)
                .contentShape(Rectangle())
                // The only light the gesture adds: a hairline filling as you hold
                .overlay(alignment: .bottom) {
                    Capsule()
                        .fill(Color.white.opacity(0.45))
                        .frame(width: 120 * holdProgress, height: 1.5)
                        .opacity(isHolding ? 1 : 0)
                }
                .onTapGesture {
                    // A finished no-alarm night has nothing left to lose
                    if phase == .complete { endNight() }
                }
                .onLongPressGesture(minimumDuration: holdDuration, maximumDistance: 60) {
                    endNight()
                } onPressingChanged: { pressing in
                    isHolding = pressing
                    withAnimation(.linear(duration: pressing ? holdDuration : 0.2)) {
                        holdProgress = pressing ? 1 : 0
                    }
                }
                .padding(.bottom, 40)
                .accessibilityElement(children: .combine)
                .accessibilityAddTraits(.isButton)
                .accessibilityIdentifier("night.stop")
                // VoiceOver activates with a double-tap, which never becomes a
                // long press — give assistive tech a direct way to end the night
                .accessibilityAction { endNight() }
            }
        }
        .animation(.easeInOut(duration: 0.6), value: audioMonitor.monitoringState)
        .animation(.easeInOut(duration: 0.6), value: phase)
        // Nothing but sky. The status bar clock is the one piece of time the
        // night screen can't otherwise suppress, and it's the hardest thing to
        // read at 3am anyway — the sun and moon carry the hour instead.
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        .task {
            await startSessionAsync()
        }
        .onReceive(audioMonitor.$monitoringState) { state in
            switch state {
            case .idle:
                break
            case .calibrating:
                StirLiveActivity.updateStatus("calibrating...")
            case .listening:
                appState.markListeningStarted()
                StirLiveActivity.updateStatus("listening...")
            }
        }
        .onReceive(audioMonitor.$didTrigger) { triggered in
            if triggered {
                Logger.session.notice("🚨 Audio trigger received, stopping monitors and switching to alarm")
                triggerAlarm(.sound)
            }
        }
        .onReceive(motionMonitor.$didTrigger) { triggered in
            if triggered {
                Logger.session.notice("🚨 Motion trigger received, stopping monitors and switching to alarm")
                triggerAlarm(.motion)
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

    private var stopLabel: String {
        phase == .complete ? "done" : "hold to end"
    }

    private func endNight() {
        withAnimation(.easeInOut(duration: 0.3)) {
            endSession()
            // "done" on a finished no-alarm night is the night completing, not
            // being cut short
            if phase == .complete {
                appState.completeNight()
            } else {
                appState.stopMonitoring()
            }
        }
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
                Logger.session.error("❌ Failed to configure playback session: \(String(describing: error), privacy: .public)")
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
        Logger.session.notice("⏰ Session timer started")
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
                triggerAlarm(.upBy)
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

    private func triggerAlarm(_ reason: AlarmTrigger) {
        stopSessionTimer()
        whiteNoisePlayer.stop()
        audioMonitor.stop()
        motionMonitor.stop()
        StirLiveActivity.triggerAlarm(message: appState.settings.tagline)
        appState.triggerAlarm(reason)
    }
}

#Preview {
    MonitoringView()
        .environmentObject(AppState())
}
