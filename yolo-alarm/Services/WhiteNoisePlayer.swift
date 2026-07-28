@preconcurrency import AVFoundation
import Combine

// Plays looping white noise with crossfade and a timed fade-out.
// Does NOT own the AVAudioSession: during a session the shared .playAndRecord
// session belongs to AudioMonitor (alarm mode) or is configured by the
// monitoring flow (no-alarm mode). Deactivating it here would kill monitoring.
@MainActor
class WhiteNoisePlayer: ObservableObject {
    @Published var isPlaying: Bool = false
    @Published var currentVolume: Float = 1.0
    @Published var isFadingOut: Bool = false
    @Published var fadeProgress: Float = 0.0  // 0.0 = full volume, 1.0 = silent

    private var playerA: AVAudioPlayer?
    private var playerB: AVAudioPlayer?
    private var activePlayer: AVAudioPlayer?
    private var soundURL: URL?
    private var fadeTimer: Timer?
    private var crossfadeTimer: Timer?
    private var targetVolume: Float = 1.0
    private var fadeStartTime: Date?
    private var fadeDuration: TimeInterval = 600  // 10 minutes default
    private let crossfadeDuration: TimeInterval = 1.5  // seconds for crossfade

    private let fadeUpdateInterval: TimeInterval = 5.0  // Update volume every 5 seconds

    func play(sound: WhiteNoiseSound, volume: Float) {
        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "mp3") else {
            print("Sound file not found: \(sound.rawValue).mp3")
            return
        }
        playURL(url, name: sound.displayName, volume: volume)
    }

    func playCustomSound(_ customSound: CustomSound, volume: Float) {
        guard let url = customSound.fileURL else {
            print("Custom sound file not found: \(customSound.name)")
            return
        }
        playURL(url, name: customSound.name, volume: volume)
    }

    private func playURL(_ url: URL, name: String, volume: Float) {
        stop()

        self.soundURL = url

        do {
            // Initialize both players with the same sound
            playerA = try AVAudioPlayer(contentsOf: url)
            playerB = try AVAudioPlayer(contentsOf: url)
            playerA?.prepareToPlay()
            playerB?.prepareToPlay()

            // Start player A
            playerA?.volume = volume
            playerA?.play()
            activePlayer = playerA

            targetVolume = volume
            currentVolume = volume
            isPlaying = true
            isFadingOut = false
            fadeProgress = 0.0

            print("Started playing: \(name) at volume \(volume) with crossfade looping")
            scheduleCrossfade()
        } catch {
            print("Failed to play sound: \(error)")
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

                // Use current volume level (which may be fading out)
                let effectiveVolume = self.currentVolume

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

    func startFadeOut(duration: TimeInterval, onComplete: @escaping () -> Void) {
        guard isPlaying, activePlayer != nil else { return }

        fadeDuration = max(duration, 1.0)
        fadeStartTime = Date()
        isFadingOut = true

        print("Starting fade-out over \(Int(fadeDuration / 60)) minutes")

        fadeTimer = Timer.scheduledTimer(withTimeInterval: fadeUpdateInterval, repeats: true) { [weak self] timer in
            Task { @MainActor in
                guard let self = self else {
                    timer.invalidate()
                    return
                }

                guard let startTime = self.fadeStartTime else {
                    timer.invalidate()
                    return
                }

                let elapsed = Date().timeIntervalSince(startTime)
                let progress = Float(min(elapsed / self.fadeDuration, 1.0))
                self.fadeProgress = progress

                // Calculate new volume (linear fade)
                let newVolume = self.targetVolume * (1.0 - progress)
                self.currentVolume = max(0, newVolume)

                // Apply to active player (crossfade handles both during transitions)
                self.activePlayer?.volume = self.currentVolume

                // Check if fade is complete
                if progress >= 1.0 {
                    timer.invalidate()
                    self.fadeTimer = nil
                    self.stop()
                    onComplete()
                }
            }
        }
    }

    func stop() {
        fadeTimer?.invalidate()
        fadeTimer = nil
        crossfadeTimer?.invalidate()
        crossfadeTimer = nil

        playerA?.stop()
        playerB?.stop()
        playerA = nil
        playerB = nil
        activePlayer = nil
        soundURL = nil

        isPlaying = false
        isFadingOut = false
        currentVolume = 0
        fadeProgress = 0
    }

    func setVolume(_ volume: Float) {
        targetVolume = volume
        if !isFadingOut {
            currentVolume = volume
            activePlayer?.volume = volume
        }
    }
}
