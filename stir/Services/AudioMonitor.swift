import AVFoundation
import Combine

enum MonitoringState: Equatable {
    case idle
    case calibrating(startTime: Date)
    case listening(baseline: Float, stdDev: Float, threshold: Float)

    static func == (lhs: MonitoringState, rhs: MonitoringState) -> Bool {
        switch (lhs, rhs) {
        case (.idle, .idle):
            return true
        case (.calibrating, .calibrating):
            return true
        case (.listening(let lb, let ls, let lt), .listening(let rb, let rs, let rt)):
            return lb == rb && ls == rs && lt == rt
        default:
            return false
        }
    }

    var isCalibrating: Bool {
        if case .calibrating = self { return true }
        return false
    }

    var isListening: Bool {
        if case .listening = self { return true }
        return false
    }

    var baseline: Float? {
        if case .listening(let baseline, _, _) = self { return baseline }
        return nil
    }

    var standardDeviation: Float? {
        if case .listening(_, let stdDev, _) = self { return stdDev }
        return nil
    }

    var threshold: Float? {
        if case .listening(_, _, let threshold) = self { return threshold }
        return nil
    }
}

@MainActor
class AudioMonitor: ObservableObject {
    @Published var currentLevel: Float = -160.0
    @Published var didTrigger: Bool = false
    @Published var monitoringState: MonitoringState = .idle
    @Published var calibrationProgress: Double = 0.0
    // True once the first audio buffer arrives — ground truth that the audio
    // graph is actually live (session activation + routing can take seconds
    // on device, and anything played before then is silently swallowed)
    @Published var isAudioLive: Bool = false

    // Sensitivity multiplier for standard deviation (2.0 = most sensitive, 5.0 = least sensitive)
    var sensitivityMultiplier: Float = 3.5  // Default medium

    private var audioEngine: AVAudioEngine?
    private var isRunning = false

    // Thread-safe calibration state (accessed from audio thread)
    private let calibrationLock = NSLock()
    private var _calibrationSamples: [Float] = []
    private var _calibrationStartTime: Date?
    private var _isCalibrating = false
    private var _baseline: Float?
    private var _standardDeviation: Float?
    private var _threshold: Float?
    private let calibrationDuration: TimeInterval = 30.0
    private var _didTransitionToListening = false

    // Minimum standard deviation floor to prevent over-sensitivity in very stable environments
    private let minStandardDeviation: Float = 3.0

    // Require sustained noise before triggering
    private var consecutiveTriggerCount = 0
    private let requiredConsecutiveTriggers = 3  // Must exceed threshold 3 times in a row

    // Throttle Live Activity updates
    private var lastLiveActivityUpdate: Date = .distantPast
    private let liveActivityUpdateInterval: TimeInterval = 2.0  // Update every 2 seconds

    func start() {
        guard !isRunning else {
            print("🎤 Already running, skipping start")
            return
        }

        // Check microphone permission first
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            print("🎤 Microphone permission granted")
        case .denied:
            print("❌ Microphone permission denied")
            return
        case .undetermined:
            print("🎤 Requesting microphone permission...")
            AVAudioApplication.requestRecordPermission { granted in
                if granted {
                    Task { @MainActor in
                        self.configureAndStartAudio()
                    }
                } else {
                    print("❌ Microphone permission denied by user")
                }
            }
            return
        @unknown default:
            break
        }

        configureAndStartAudio()
    }

    private func configureAndStartAudio() {
        // Configure audio session for recording with background support
        let session = AVAudioSession.sharedInstance()

        do {
            // Set category first (doesn't require active session)
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .mixWithOthers])
            print("🔊 Audio session category set")
        } catch {
            print("❌ Failed to set audio category: \(error)")
            return
        }

        do {
            try session.setActive(true)
            print("🔊 Audio session activated for monitoring")
        } catch {
            print("❌ Audio session activation failed: \(error.localizedDescription)")
            // Retry after a delay
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                self.retryActivation()
            }
            return
        }

        // Listen for interruptions
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleInterruption),
            name: AVAudioSession.interruptionNotification,
            object: session
        )

        // Start the audio engine
        startAudioEngine()
    }

    private func retryActivation() {
        print("🎤 Retrying audio session activation...")
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setActive(true)
            print("🔊 Audio session activated on retry")

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleInterruption),
                name: AVAudioSession.interruptionNotification,
                object: session
            )

            startAudioEngine()
        } catch {
            print("❌ Audio session retry failed: \(error.localizedDescription)")
            // Try again
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                self.retryActivation()
            }
        }
    }

    private func startAudioEngine() {
        print("🎤 Creating audio engine...")
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            print("❌ Failed to create audio engine")
            return
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        print("🎤 Input format: \(format)")

        // Validate format before installing tap
        guard format.sampleRate > 0 && format.channelCount > 0 else {
            print("❌ Invalid audio format (sampleRate: \(format.sampleRate), channels: \(format.channelCount))")
            print("🎤 Will retry in 1 second...")
            self.audioEngine = nil
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                self.retryActivation()
            }
            return
        }

        // Install tap to monitor audio levels
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.processAudioBuffer(buffer)
        }
        print("🎤 Tap installed")

        do {
            try audioEngine.start()
            isRunning = true
            consecutiveTriggerCount = 0
            print("🎤 Audio engine started successfully!")
        } catch {
            print("❌ Failed to start audio engine: \(error)")
        }
    }

    @objc private func handleInterruption(_ notification: Notification) {
        guard let userInfo = notification.userInfo,
              let typeValue = userInfo[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: typeValue) else {
            return
        }

        switch type {
        case .began:
            print("🎤 Audio interrupted")
        case .ended:
            print("🎤 Audio interruption ended, restarting...")
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                try audioEngine?.start()
                print("🎤 Audio engine restarted after interruption")
            } catch {
                print("❌ Failed to restart after interruption: \(error)")
            }
        @unknown default:
            break
        }
    }

    func startCalibration() {
        calibrationLock.lock()
        _calibrationSamples.removeAll()
        _calibrationStartTime = Date()
        _isCalibrating = true
        _baseline = nil
        _standardDeviation = nil
        _threshold = nil
        _didTransitionToListening = false
        calibrationLock.unlock()

        calibrationProgress = 0.0
        monitoringState = .calibrating(startTime: Date())
        print("🎤 Starting 30-second calibration (statistical analysis)...")
    }

    func stop() {
        guard isRunning else { return }

        // Remove notification observer
        NotificationCenter.default.removeObserver(self, name: AVAudioSession.interruptionNotification, object: nil)

        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        isRunning = false
        didTrigger = false
        monitoringState = .idle
        calibrationProgress = 0.0
        isAudioLive = false
        bufferCount = 0

        calibrationLock.lock()
        _calibrationSamples.removeAll()
        _calibrationStartTime = nil
        _isCalibrating = false
        _baseline = nil
        _standardDeviation = nil
        _threshold = nil
        _didTransitionToListening = false
        calibrationLock.unlock()

        // Deactivate audio session - don't fail if it errors
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            print("🔊 Audio session deactivated")
        } catch {
            // This can fail if other audio is playing, that's okay
            print("⚠️ Audio session deactivation note: \(error.localizedDescription)")
        }
    }

    private var bufferCount = 0

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        bufferCount += 1
        if bufferCount == 1 {
            print("🎤 First audio buffer received!")
            Task { @MainActor in self.isAudioLive = true }
        }

        guard let channelData = buffer.floatChannelData?[0] else {
            print("❌ No channel data in buffer")
            return
        }

        let frameLength = Int(buffer.frameLength)

        // Calculate RMS (Root Mean Square) for the buffer
        var sum: Float = 0
        for i in 0..<frameLength {
            let sample = channelData[i]
            sum += sample * sample
        }

        let rms = sqrt(sum / Float(frameLength))
        let decibels = 20 * log10(max(rms, 0.000001))

        // Process calibration/trigger logic on audio thread (thread-safe)
        let result = processLevel(decibels)

        // Dispatch UI updates and Live Activity updates to main thread
        Task { @MainActor in
            self.currentLevel = decibels
            if let newProgress = result.progress {
                self.calibrationProgress = newProgress
            }
            if let newState = result.newState {
                self.monitoringState = newState
                // Update Live Activity when state changes
                if newState.isListening {
                    StirLiveActivity.updateStatus("listening...")
                }
            }
            if result.shouldTrigger {
                self.didTrigger = true
            }

            // Throttled audio level update for Live Activity
            if case .listening(_, _, let threshold) = self.monitoringState {
                let now = Date()
                if now.timeIntervalSince(self.lastLiveActivityUpdate) >= self.liveActivityUpdateInterval {
                    self.lastLiveActivityUpdate = now
                    // Calculate level as ratio of current to threshold (0.0 to 1.0+)
                    // Normalize so baseline is ~0.2 and threshold is 1.0
                    let normalizedLevel = Double((decibels + 60) / (threshold + 60))
                    let clampedLevel = max(0.0, min(1.0, normalizedLevel))
                    StirLiveActivity.updateAudioLevel(clampedLevel, status: "listening...")
                }
            }
        }
    }

    private struct ProcessResult {
        var progress: Double?
        var newState: MonitoringState?
        var shouldTrigger: Bool = false
    }

    // Process on audio thread - uses thread-safe state
    private func processLevel(_ level: Float) -> ProcessResult {
        var result = ProcessResult()

        calibrationLock.lock()
        let isCalibrating = _isCalibrating
        let threshold = _threshold
        let startTime = _calibrationStartTime
        let alreadyTransitioned = _didTransitionToListening
        calibrationLock.unlock()

        if isCalibrating {
            // Collect samples for baseline calculation
            calibrationLock.lock()
            _calibrationSamples.append(level)
            let sampleCount = _calibrationSamples.count
            let samples = _calibrationSamples
            calibrationLock.unlock()

            guard let calibrationStart = startTime else { return result }
            let elapsed = Date().timeIntervalSince(calibrationStart)
            result.progress = min(elapsed / calibrationDuration, 1.0)

            // Check if calibration is complete
            if elapsed >= calibrationDuration && sampleCount > 0 {
                // Calculate mean (baseline)
                let mean = samples.reduce(0, +) / Float(sampleCount)

                // Calculate standard deviation
                let squaredDifferences = samples.map { ($0 - mean) * ($0 - mean) }
                let variance = squaredDifferences.reduce(0, +) / Float(sampleCount)
                let rawStdDev = sqrt(variance)

                // Apply minimum floor to prevent over-sensitivity in very stable environments
                let stdDev = max(rawStdDev, minStandardDeviation)

                // Calculate threshold: mean + (multiplier × stdDev)
                let calculatedThreshold = mean + (sensitivityMultiplier * stdDev)

                calibrationLock.lock()
                _isCalibrating = false
                _baseline = mean
                _standardDeviation = stdDev
                _threshold = calculatedThreshold
                _didTransitionToListening = true
                calibrationLock.unlock()

                result.newState = .listening(baseline: mean, stdDev: stdDev, threshold: calculatedThreshold)
                print("🎤 Calibration complete (statistical analysis)")
                print("   Baseline: \(String(format: "%.1f", mean)) dB")
                print("   Std Dev: \(String(format: "%.1f", rawStdDev)) dB (using \(String(format: "%.1f", stdDev)) dB with floor)")
                print("   Multiplier: \(String(format: "%.1f", sensitivityMultiplier))×")
                print("   Threshold: \(String(format: "%.1f", calculatedThreshold)) dB")

                // Update Live Activity immediately from background thread
                StirLiveActivity.updateStatus("listening...")
            }
        } else if let currentThreshold = threshold {
            // Update Live Activity on first listen after calibration (in case main actor was slow)
            if !alreadyTransitioned {
                calibrationLock.lock()
                _didTransitionToListening = true
                calibrationLock.unlock()
                StirLiveActivity.updateStatus("listening...")
            }

            // Listening mode - check if noise exceeds calculated threshold
            if level > currentThreshold {
                consecutiveTriggerCount += 1
                if consecutiveTriggerCount >= requiredConsecutiveTriggers {
                    print("🎤 Triggered! Level: \(String(format: "%.1f", level)) dB exceeded threshold: \(String(format: "%.1f", currentThreshold)) dB")
                    result.shouldTrigger = true
                }
            } else {
                consecutiveTriggerCount = 0
            }
        } else {
            // Idle
            consecutiveTriggerCount = 0
        }

        return result
    }
}
