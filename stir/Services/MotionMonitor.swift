import Foundation
import CoreMotion
import Combine

@MainActor
class MotionMonitor: ObservableObject {
    private let motionManager = CMMotionManager()
    private var referenceAttitude: CMAttitude?
    private var isCalibrated = false

    @Published var didTrigger = false
    @Published var isMonitoring = false

    // Threshold for rotation detection (in radians)
    // ~0.15 radians = ~8.5 degrees of rotation
    private let rotationThreshold: Double = 0.15

    func start() {
        guard motionManager.isDeviceMotionAvailable else {
            print("📱 Device motion not available")
            return
        }

        didTrigger = false
        isCalibrated = false
        referenceAttitude = nil
        isMonitoring = true

        motionManager.deviceMotionUpdateInterval = 0.1 // 10Hz

        motionManager.startDeviceMotionUpdates(to: .main) { [weak self] motion, error in
            Task { @MainActor in
                self?.processMotion(motion, error: error)
            }
        }

        print("📱 Motion monitoring started")
    }

    private func processMotion(_ motion: CMDeviceMotion?, error: Error?) {
        guard let motion = motion, isMonitoring else { return }

        // Calibrate on first reading
        if !isCalibrated {
            referenceAttitude = motion.attitude.copy() as? CMAttitude
            isCalibrated = true
            print("📱 Motion calibrated at attitude: pitch=\(String(format: "%.2f", motion.attitude.pitch)), roll=\(String(format: "%.2f", motion.attitude.roll))")
            return
        }

        guard let reference = referenceAttitude else { return }

        // Get current attitude relative to reference
        let currentAttitude = motion.attitude
        currentAttitude.multiply(byInverseOf: reference)

        // Check if device has rotated significantly
        let pitchChange = abs(currentAttitude.pitch)
        let rollChange = abs(currentAttitude.roll)
        let yawChange = abs(currentAttitude.yaw)

        let maxRotation = max(pitchChange, max(rollChange, yawChange))

        if maxRotation > rotationThreshold {
            print("📱 Motion detected! Rotation: \(String(format: "%.2f", maxRotation)) rad (threshold: \(rotationThreshold))")
            didTrigger = true
            stop()
        }
    }

    func stop() {
        motionManager.stopDeviceMotionUpdates()
        isMonitoring = false
        referenceAttitude = nil
        isCalibrated = false
        print("📱 Motion monitoring stopped")
    }
}
