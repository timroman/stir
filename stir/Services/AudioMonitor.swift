import AVFoundation
import Combine
import os

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
            Logger.monitor.notice("🎤 Already running, skipping start")
            return
        }

        // Check microphone permission first
        switch AVAudioApplication.shared.recordPermission {
        case .granted:
            Logger.monitor.notice("🎤 Microphone permission granted")
        case .denied:
            Logger.monitor.error("❌ Microphone permission denied")
            return
        case .undetermined:
            Logger.monitor.notice("🎤 Requesting microphone permission...")
            AVAudioApplication.requestRecordPermission { granted in
                if granted {
                    Task { @MainActor in
                        self.configureAndStartAudio()
                    }
                } else {
                    Logger.monitor.error("❌ Microphone permission denied by user")
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
            Logger.monitor.notice("🔊 Audio session category set")
        } catch {
            Logger.monitor.error("❌ Failed to set audio category: \(String(describing: error), privacy: .public)")
            return
        }

        do {
            try session.setActive(true)
            Logger.monitor.notice("🔊 Audio session activated for monitoring")
        } catch {
            Logger.monitor.error("❌ Audio session activation failed: \(String(describing: error.localizedDescription), privacy: .public)")
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
        Logger.monitor.notice("🎤 Retrying audio session activation...")
        let session = AVAudioSession.sharedInstance()

        do {
            try session.setActive(true)
            Logger.monitor.notice("🔊 Audio session activated on retry")

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(handleInterruption),
                name: AVAudioSession.interruptionNotification,
                object: session
            )

            startAudioEngine()
        } catch {
            Logger.monitor.error("❌ Audio session retry failed: \(String(describing: error.localizedDescription), privacy: .public)")
            // Try again
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second
                self.retryActivation()
            }
        }
    }

    private func startAudioEngine() {
        Logger.monitor.notice("🎤 Creating audio engine...")
        audioEngine = AVAudioEngine()
        guard let audioEngine = audioEngine else {
            Logger.monitor.error("❌ Failed to create audio engine")
            return
        }

        let inputNode = audioEngine.inputNode
        let format = inputNode.outputFormat(forBus: 0)
        Logger.monitor.notice("🎤 Input format: \(String(describing: format), privacy: .public)")

        // Validate format before installing tap
        guard format.sampleRate > 0 && format.channelCount > 0 else {
            Logger.monitor.error("❌ Invalid audio format (sampleRate: \(String(describing: format.sampleRate), privacy: .public), channels: \(String(describing: format.channelCount), privacy: .public))")
            Logger.monitor.notice("🎤 Will retry in 1 second...")
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
        Logger.monitor.notice("🎤 Tap installed")

        do {
            try audioEngine.start()
            isRunning = true
            consecutiveTriggerCount = 0
            Logger.monitor.notice("🎤 Audio engine started successfully!")
        } catch {
            Logger.monitor.error("❌ Failed to start audio engine: \(String(describing: error), privacy: .public)")
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
            Logger.monitor.notice("🎤 Audio interrupted")
        case .ended:
            Logger.monitor.notice("🎤 Audio interruption ended, restarting...")
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                try audioEngine?.start()
                Logger.monitor.notice("🎤 Audio engine restarted after interruption")
            } catch {
                Logger.monitor.error("❌ Failed to restart after interruption: \(String(describing: error), privacy: .public)")
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
        Logger.monitor.notice("🎤 Starting 30-second calibration (statistical analysis)...")
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
            Logger.monitor.notice("🔊 Audio session deactivated")
        } catch {
            // This can fail if other audio is playing, that's okay
            Logger.monitor.error("⚠️ Audio session deactivation note: \(String(describing: error.localizedDescription), privacy: .public)")
        }
    }

    private var bufferCount = 0

    private func processAudioBuffer(_ buffer: AVAudioPCMBuffer) {
        bufferCount += 1
        if bufferCount == 1 {
            Logger.monitor.notice("🎤 First audio buffer received!")
            Task { @MainActor in self.isAudioLive = true }
        }

        guard let channelData = buffer.floatChannelData?[0] else {
            Logger.monitor.error("❌ No channel data in buffer")
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
                Logger.monitor.notice("🎤 Calibration complete (statistical analysis)")
                Logger.monitor.notice("   Baseline: \(String(describing: String(format: "%.1f", mean)), privacy: .public) dB")
                Logger.monitor.notice("   Std Dev: \(String(describing: String(format: "%.1f", rawStdDev)), privacy: .public) dB (using \(String(describing: String(format: "%.1f", stdDev)), privacy: .public) dB with floor)")
                Logger.monitor.notice("   Multiplier: \(String(describing: String(format: "%.1f", self.sensitivityMultiplier)), privacy: .public)×")
                Logger.monitor.notice("   Threshold: \(String(describing: String(format: "%.1f", calculatedThreshold)), privacy: .public) dB")

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
                    Logger.monitor.notice("🎤 Triggered! Level: \(String(describing: String(format: "%.1f", level)), privacy: .public) dB exceeded threshold: \(String(describing: String(format: "%.1f", currentThreshold)), privacy: .public) dB")
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
