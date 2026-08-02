import SwiftUI
@preconcurrency import AVFoundation
import CoreHaptics

struct AlarmView: View {
    @EnvironmentObject var appState: AppState
    @StateObject private var alarmPlayer = AlarmPlayer()
    @StateObject private var hapticManager = HapticManager()
    @State private var currentTime = Date()
    @State private var appeared = false

    let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            // Dawn synced to sound: black at first ring, warming to full gold
            // as the volume ramps — light and loudness rise together
            SkyBackground(colors: dawnColors)
                .animation(.easeInOut(duration: 1.2), value: alarmPlayer.rampProgress)

            VStack(spacing: 40) {
                Spacer()

                // Current time
                Text(timeString)
                    .font(.system(size: 64, weight: .light, design: .rounded))
                    .foregroundColor(.white)
                    .opacity(appeared ? 1 : 0)

                Text(appState.settings.tagline)
                    .font(.title2)
                    .foregroundColor(.white.opacity(0.7))
                    .padding(.horizontal, 48)
                    .multilineTextAlignment(.center)
                    .opacity(appeared ? 1 : 0)

                Spacer()

                // Dismiss button
                Button(action: {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        alarmPlayer.stop()
                        StirLiveActivity.stop()
                        AlarmBackstop.cancelBackstop()
                        appState.dismissAlarm()
                    }
                }) {
                    Text("stop")
                        .font(.title.bold())
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                        .background(Color.white)
                        .cornerRadius(20)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 60)
                .opacity(appeared ? 1 : 0)
            }
        }
        .onAppear {
            withAnimation(.easeIn(duration: 1.5)) {
                appeared = true
            }

            // Start audio after small delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                alarmPlayer.play(
                    sound: appState.settings.selectedSound,
                    customSoundId: appState.settings.customSoundId,
                    volume: appState.settings.volume
                )
            }

            // Start haptics after audio session is configured
            if appState.settings.hapticEnabled {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                    hapticManager.start(type: appState.settings.hapticType, targetIntensity: appState.settings.hapticIntensity)
                }
            }
        }
        .onDisappear {
            hapticManager.stop()
        }
        .onReceive(timer) { _ in
            currentTime = Date()
        }
    }

    private var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: currentTime).lowercased()
    }

    // Warmer than any sky the night screen ever had: deep gold morning.
    // Interpolated from black by ramp progress.
    private var dawnColors: [Color] {
        let warm: [(Double, Double, Double)] = [
            (0.16, 0.12, 0.24), (0.42, 0.24, 0.22), (0.80, 0.47, 0.26), (0.99, 0.76, 0.44)
        ]
        let t = alarmPlayer.rampProgress
        return warm.map { Color(red: $0.0 * t, green: $0.1 * t, blue: $0.2 * t) }
    }
}

@MainActor
class HapticManager: ObservableObject {
    private var hapticEngine: CHHapticEngine?
    private var hapticPlayer: CHHapticPatternPlayer?
    private var loopTimer: Timer?
    private var intensityRampTimer: Timer?
    private var currentIntensity: Float = 0.3
    private var targetIntensity: Float = 1.0
    private var hapticType: HapticType = .heartbeat
    private let rampDuration: Float = 60.0
    private let patternDuration: TimeInterval = 10.0 // Loop every 10 seconds
    private var isRunning = false

    func start(type: HapticType, targetIntensity: Float) {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else {
            print("📳 Haptics not supported on this device")
            return
        }

        self.hapticType = type
        self.targetIntensity = targetIntensity
        self.currentIntensity = max(0.3, targetIntensity * 0.3) // Start at 30% of target, minimum 0.3
        self.isRunning = true

        do {
            // Attach to the app's audio session: a default-initialized engine
            // runs its own session, which can silence the alarm's AVAudioPlayers
            // on device the moment it starts (simulators have no haptics, so
            // this never reproduces there)
            hapticEngine = try CHHapticEngine(audioSession: AVAudioSession.sharedInstance())
            hapticEngine?.isAutoShutdownEnabled = false
            hapticEngine?.playsHapticsOnly = true

            hapticEngine?.stoppedHandler = { [weak self] reason in
                print("📳 Haptic engine stopped: \(reason.rawValue)")
                Task { @MainActor in
                    guard let self = self, self.isRunning else { return }
                    try? self.hapticEngine?.start()
                    self.playPattern()
                }
            }

            hapticEngine?.resetHandler = { [weak self] in
                print("📳 Haptic engine reset")
                Task { @MainActor in
                    guard let self = self, self.isRunning else { return }
                    try? self.hapticEngine?.start()
                    self.playPattern()
                }
            }

            try hapticEngine?.start()
            print("📳 Haptic engine started")

            // Test haptic to verify device supports it
            let testEvent = CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: 1.0),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 1.0)
                ],
                relativeTime: 0
            )
            let testPattern = try CHHapticPattern(events: [testEvent], parameters: [])
            let testPlayer = try hapticEngine?.makePlayer(with: testPattern)
            try testPlayer?.start(atTime: CHHapticTimeImmediate)
            print("📳 Test haptic fired")

            // Play first pattern
            playPattern()

            // Set up looping timer
            loopTimer = Timer.scheduledTimer(withTimeInterval: patternDuration, repeats: true) { [weak self] _ in
                Task { @MainActor in
                    self?.playPattern()
                }
            }

            // Start intensity ramp
            startIntensityRamp()

            print("📳 Haptic feedback started: \(type.displayName), ramping to intensity \(targetIntensity)")
        } catch {
            print("📳 Haptic error: \(error)")
        }
    }

    private func playPattern() {
        guard isRunning, let engine = hapticEngine else {
            print("📳 playPattern skipped: isRunning=\(isRunning), engine=\(String(describing: hapticEngine))")
            return
        }

        do {
            let events = createHapticEvents(for: hapticType, intensity: currentIntensity)
            let pattern = try CHHapticPattern(events: events, parameters: [])
            hapticPlayer = try engine.makePlayer(with: pattern)
            try hapticPlayer?.start(atTime: CHHapticTimeImmediate)
            print("📳 Pattern playing with intensity: \(currentIntensity)")
        } catch {
            print("📳 Failed to play haptic pattern: \(error)")
        }
    }

    private func startIntensityRamp() {
        let updateInterval: TimeInterval = 2.0
        let totalSteps = Int(rampDuration / Float(updateInterval))
        let startIntensity = currentIntensity // Preserve the starting intensity
        var currentStep = 0

        intensityRampTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self, self.isRunning else {
                    timer.invalidate()
                    return
                }

                currentStep += 1
                let progress = Float(currentStep) / Float(totalSteps)
                // Ramp from startIntensity to targetIntensity
                self.currentIntensity = startIntensity + (self.targetIntensity - startIntensity) * progress

                if currentStep >= totalSteps {
                    self.currentIntensity = self.targetIntensity
                    print("📳 Haptic intensity ramp complete: \(self.targetIntensity)")
                    timer.invalidate()
                    self.intensityRampTimer = nil
                }
            }
        }
    }

    private func createHapticEvents(for type: HapticType, intensity: Float) -> [CHHapticEvent] {
        var events: [CHHapticEvent] = []
        // Ensure minimum intensity of 0.5 for all patterns to be noticeable
        let effectiveIntensity = max(0.5, intensity)

        switch type {
        case .heartbeat:
            for i in 0..<7 {
                let baseTime = Double(i) * 1.4
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: effectiveIntensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
                    ],
                    relativeTime: baseTime
                ))
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: effectiveIntensity * 0.8),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                    ],
                    relativeTime: baseTime + 0.2
                ))
            }

        case .pulse:
            // Gentle continuous pulses
            for i in 0..<10 {
                events.append(CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: effectiveIntensity * 0.8),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                    ],
                    relativeTime: Double(i) * 1.0,
                    duration: 0.6
                ))
            }

        case .escalating:
            for i in 0..<7 {
                let escalatingIntensity = max(0.5, 0.4 + (effectiveIntensity * Float(i) / 7.0))
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: escalatingIntensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.6)
                    ],
                    relativeTime: Double(i) * 1.4
                ))
            }

        case .steady:
            for i in 0..<5 {
                events.append(CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: effectiveIntensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                    ],
                    relativeTime: Double(i) * 2.0,
                    duration: 1.5
                ))
            }
        }

        return events
    }

    func stop() {
        isRunning = false

        loopTimer?.invalidate()
        loopTimer = nil

        intensityRampTimer?.invalidate()
        intensityRampTimer = nil

        try? hapticPlayer?.cancel()
        hapticPlayer = nil

        hapticEngine?.stop()
        hapticEngine = nil
        print("📳 Haptics stopped")
    }
}

@MainActor
class AlarmPlayer: ObservableObject {
    // 0 → 1 over the 60s volume ramp; the alarm screen's light tracks this,
    // so brightness and loudness rise together
    @Published var rampProgress: Double = 0

    private var playerA: AVAudioPlayer?
    private var playerB: AVAudioPlayer?
    private var activePlayer: AVAudioPlayer? // Currently playing at full volume
    private var soundURL: URL?
    private var volumeRampTimer: Timer?
    private var crossfadeTimer: Timer?
    private var targetVolume: Float = 1.0
    private var currentVolume: Float = 0.0 // Tracks actual volume during ramp
    private let rampDuration: Float = 60.0 // seconds
    private let crossfadeDuration: TimeInterval = 1.5 // seconds for crossfade

    func play(sound: AlarmSound, customSoundId: UUID?, volume: Float) {
        // Scale down the volume significantly - AVAudioPlayer is very loud
        // User's 0-100% maps to 0-0.05 actual volume (5% max)
        targetVolume = volume * 0.05

        // Configure audio session for playback
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            print("🔊 Audio session configured for alarm playback")
        } catch {
            print("⚠️ Failed to configure audio session: \(error)")
        }

        // Determine which sound URL to use
        let url: URL?
        if let customId = customSoundId,
           let customSound = CustomSoundManager.shared.customSounds.first(where: { $0.id == customId }),
           let customURL = customSound.fileURL {
            url = customURL
            print("🔔 Playing custom sound: \(customSound.name)")
        } else {
            url = bundledSoundURL(sound.rawValue)
        }

        guard let soundURL = url else {
            print("Sound file not found: \(sound.rawValue)")
            playFallbackSound()
            return
        }

        self.soundURL = soundURL

        do {
            // Initialize both players with the same sound
            playerA = try AVAudioPlayer(contentsOf: soundURL)
            playerB = try AVAudioPlayer(contentsOf: soundURL)
            playerA?.prepareToPlay()
            playerB?.prepareToPlay()

            // Start player A
            playerA?.volume = 0
            playerA?.play()
            activePlayer = playerA

            print("🔔 Alarm started with crossfade looping, ramping volume over \(rampDuration) seconds")
            startVolumeRamp()
            scheduleCrossfade()

            // Diagnostics: leave evidence in the device log for overnight failures
            let session = AVAudioSession.sharedInstance()
            print("🔔 Post-play state — playing: \(playerA?.isPlaying ?? false), systemVolume: \(session.outputVolume), route: \(session.currentRoute.outputs.map(\.portName).joined(separator: ","))")

            // Watchdog: if playback died within 5s (e.g. session stolen), restart it
            DispatchQueue.main.asyncAfter(deadline: .now() + 5.0) { [weak self] in
                guard let self, let active = self.activePlayer, !active.isPlaying else { return }
                print("⚠️ Alarm playback died after start — reactivating session and restarting")
                try? AVAudioSession.sharedInstance().setActive(true)
                active.play()
            }
        } catch {
            print("Failed to play alarm: \(error)")
            playFallbackSound()
        }
    }

    private func startVolumeRamp() {
        // Update volume every 0.5 seconds over rampDuration
        let updateInterval: TimeInterval = 0.5
        let totalSteps = Int(rampDuration / Float(updateInterval))
        var currentStep = 0

        volumeRampTimer = Timer.scheduledTimer(withTimeInterval: updateInterval, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else {
                    timer.invalidate()
                    return
                }

                currentStep += 1
                let progress = Float(currentStep) / Float(totalSteps)
                self.currentVolume = self.targetVolume * progress
                self.rampProgress = Double(progress)

                // Apply to active player (crossfade will handle transitions)
                if let active = self.activePlayer {
                    active.volume = self.currentVolume
                }

                if currentStep >= totalSteps {
                    self.currentVolume = self.targetVolume
                    self.rampProgress = 1
                    print("🔔 Volume ramp complete: \(Int(self.targetVolume * 2000))% of max")
                    timer.invalidate()
                    self.volumeRampTimer = nil
                }
            }
        }
    }

    private func scheduleCrossfade() {
        guard let player = activePlayer, player.duration > crossfadeDuration * 2 else {
            // Sound too short for crossfade, use simple loop
            playerA?.numberOfLoops = -1
            return
        }

        // Schedule crossfade to start before the track ends
        let crossfadeStartTime = player.duration - crossfadeDuration

        crossfadeTimer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self, let active = self.activePlayer else {
                    timer.invalidate()
                    return
                }

                // Check if we're near the end of the track
                if active.currentTime >= crossfadeStartTime {
                    timer.invalidate()
                    self.performCrossfade()
                }
            }
        }
    }

    private func performCrossfade() {
        guard let soundURL = soundURL else { return }

        // Determine which player is next
        let outgoingPlayer = activePlayer
        let incomingPlayer: AVAudioPlayer?

        if activePlayer === playerA {
            // Reinitialize player B
            playerB = try? AVAudioPlayer(contentsOf: soundURL)
            playerB?.prepareToPlay()
            incomingPlayer = playerB
        } else {
            // Reinitialize player A
            playerA = try? AVAudioPlayer(contentsOf: soundURL)
            playerA?.prepareToPlay()
            incomingPlayer = playerA
        }

        guard let incoming = incomingPlayer else { return }

        // Start incoming player at zero volume
        incoming.volume = 0
        incoming.play()

        // Crossfade over crossfadeDuration
        let steps = 30
        let stepInterval = crossfadeDuration / Double(steps)
        var currentStep = 0

        Timer.scheduledTimer(withTimeInterval: stepInterval, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else {
                    timer.invalidate()
                    return
                }

                currentStep += 1
                let progress = Float(currentStep) / Float(steps)

                // Use current volume level (which may still be ramping up)
                let effectiveVolume = self.currentVolume > 0 ? self.currentVolume : self.targetVolume

                // Fade out outgoing, fade in incoming
                outgoingPlayer?.volume = effectiveVolume * (1.0 - progress)
                incoming.volume = effectiveVolume * progress

                if currentStep >= steps {
                    timer.invalidate()
                    outgoingPlayer?.stop()
                    incoming.volume = effectiveVolume
                    self.activePlayer = incoming
                    self.scheduleCrossfade() // Schedule next crossfade
                }
            }
        }
    }

    func stop() {
        volumeRampTimer?.invalidate()
        volumeRampTimer = nil
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil
        playerA?.stop()
        playerB?.stop()
        playerA = nil
        playerB = nil
        activePlayer = nil
        print("🔔 Alarm stopped")

        // Deactivate audio session
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            print("🔊 Audio session deactivated")
        } catch {
            print("⚠️ Failed to deactivate audio session: \(error)")
        }
    }

    private func playFallbackSound() {
        // Use system sound as fallback
        AudioServicesPlaySystemSound(1005)
    }
}

#Preview {
    AlarmView()
        .environmentObject(AppState())
}
