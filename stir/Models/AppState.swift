import Foundation
import Combine

enum AppScreen {
    case onboarding
    case setup
    case monitoring
    case alarm
}

@MainActor
class AppState: ObservableObject {
    @Published var currentScreen: AppScreen = .setup
    @Published var settings: AlarmSettings {
        didSet { saveSettings() }
    }
    @Published var currentDecibelLevel: Float = -160.0
    @Published var isMonitoring: Bool = false
    @Published var hasCompletedOnboarding: Bool {
        didSet { UserDefaults.standard.set(hasCompletedOnboarding, forKey: onboardingKey) }
    }

    private let settingsKey = "alarmSettings"
    private let onboardingKey = "hasCompletedOnboarding"

    init() {
        self.hasCompletedOnboarding = UserDefaults.standard.bool(forKey: onboardingKey)

        if let data = UserDefaults.standard.data(forKey: settingsKey),
           let decoded = try? JSONDecoder().decode(AlarmSettings.self, from: data) {
            self.settings = decoded
        } else {
            self.settings = .default
        }

        // Show onboarding if not completed
        if !hasCompletedOnboarding {
            currentScreen = .onboarding
        }

        #if DEBUG
        applyLaunchOverrides()
        #endif
    }

    #if DEBUG
    // Test support: jump straight to a screen with a synthetic session, e.g.
    //   -screen monitoring -upByMinutes 12
    private func applyLaunchOverrides() {
        let args = ProcessInfo.processInfo.arguments
        if let index = args.firstIndex(of: "-upByMinutes"), index + 1 < args.count,
           let minutes = Double(args[index + 1]) {
            settings.wakeUpBy = Date().addingTimeInterval(minutes * 60)
        }
        func intArg(_ name: String) -> Int? {
            guard let index = args.firstIndex(of: name), index + 1 < args.count else { return nil }
            return Int(args[index + 1])
        }
        if let minutes = intArg("-windowMinutes") { settings.wakeWindowMinutes = minutes }
        if let minutes = intArg("-quietGapMinutes") { settings.quietGapMinutes = minutes }
        if let minutes = intArg("-fadeMinutes") { settings.fadeOutMinutes = minutes }
        if let index = args.firstIndex(of: "-screen"), index + 1 < args.count {
            switch args[index + 1] {
            case "setup": currentScreen = .setup
            case "monitoring":
                currentScreen = .monitoring
                isMonitoring = true
            case "alarm": currentScreen = .alarm
            default: break
            }
        }
    }
    #endif

    func saveSettings() {
        if let encoded = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(encoded, forKey: settingsKey)
        }
    }

    func recalculateWakeUpBy() {
        let calendar = Calendar.current
        let now = Date()

        // Extract just the hour/minute from the selected time
        let hour = calendar.component(.hour, from: settings.wakeUpBy)
        let minute = calendar.component(.minute, from: settings.wakeUpBy)

        // Get today at midnight
        let todayStart = calendar.startOfDay(for: now)

        var upBy = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: todayStart)!

        // If we've already passed the time, use tomorrow
        if now > upBy {
            upBy = calendar.date(byAdding: .day, value: 1, to: upBy)!
        }

        settings.wakeUpBy = upBy
    }

    // MARK: - Derived timeline (always computed from wakeUpBy, never stored)

    // Listening begins here (alarm mode only)
    var windowStart: Date {
        settings.wakeUpBy.addingTimeInterval(-settings.wakeWindowSeconds)
    }

    // White noise fade completes here: before the quiet gap in alarm mode,
    // exactly at "up by" in no-alarm mode
    var whiteNoiseEndTime: Date {
        if settings.alarmEnabled {
            return windowStart.addingTimeInterval(-settings.quietGapSeconds)
        } else {
            return settings.wakeUpBy
        }
    }

    var fadeStartTime: Date {
        whiteNoiseEndTime.addingTimeInterval(-settings.fadeOutSeconds)
    }

    func startMonitoring() {
        currentScreen = .monitoring
        isMonitoring = true
    }

    func stopMonitoring() {
        isMonitoring = false
        currentScreen = .setup
    }

    func triggerAlarm() {
        currentScreen = .alarm
    }

    func dismissAlarm() {
        isMonitoring = false
        currentScreen = .setup
    }

    func completeOnboarding() {
        hasCompletedOnboarding = true
        currentScreen = .setup
    }

    // MARK: - Formatting

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private func timeString(_ date: Date) -> String {
        Self.timeFormatter.string(from: date).lowercased()
    }

    var upByFormatted: String {
        "up by \(timeString(settings.wakeUpBy))"
    }

    // One-line preview of tonight's derived timeline, shown on the setup screen
    var timelinePreview: String {
        switch (settings.whiteNoiseEnabled, settings.alarmEnabled) {
        case (true, true):
            return "white noise until \(timeString(whiteNoiseEndTime)) · listening from \(timeString(windowStart)) · up by \(timeString(settings.wakeUpBy))"
        case (true, false):
            return "white noise fades out by \(timeString(settings.wakeUpBy)) — silence is your wake-up"
        case (false, _):
            return "listening from \(timeString(windowStart)) · up by \(timeString(settings.wakeUpBy))"
        }
    }
}
