import Foundation
import Combine
import os

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
    // Auto sensitivity asked "was that too sensitive?" at the end of this
    // night (stir.md decision 67). Not persisted: the state already records
    // that it was asked, so leaving the app is an answer of no.
    @Published var sensitivityQuestionPending = false
    @Published var hasCompletedOnboarding: Bool {
        didSet { defaults.set(hasCompletedOnboarding, forKey: onboardingKey) }
    }

    private let settingsKey = "alarmSettings"
    private let onboardingKey = "hasCompletedOnboarding"
    private let defaults: UserDefaults
    private let nightStore: NightStore?

    // The clock every session timestamp is read from; tests move it
    var now: () -> Date = Date.init

    // Live for the length of one session, then folded into a SessionRecord and,
    // for a clean run, a NightRecord
    private var sessionStartedAt: Date?
    private var sessionSensitivity: Float = 0
    private var listeningStartedAt: Date?
    private var alarmFiredAt: Date?
    private var triggeredBy: AlarmTrigger = .none
    private var alarmVolume: Float?

    init(nightStore: NightStore? = nil, defaults: UserDefaults = .standard) {
        self.nightStore = nightStore
        self.defaults = defaults
        self.hasCompletedOnboarding = defaults.bool(forKey: onboardingKey)

        if let data = defaults.data(forKey: settingsKey),
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
    // Test support: jump straight to a screen with a synthetic session.
    // Launch arguments (-screen monitoring -upByMinutes 12) work when the
    // simulator delivers them; one-shot UserDefaults keys (debugScreen,
    // debugUpByMinutes — cleared after applying) are the reliable path for
    // scripted screenshots, since simctl arg delivery is flaky:
    //   xcrun simctl spawn <dev> defaults write <bundle> debugScreen monitoring
    private func applyLaunchOverrides() {
        var args = ProcessInfo.processInfo.arguments

        let defaults = UserDefaults.standard
        if let screen = defaults.string(forKey: "debugScreen") {
            args += ["-screen", screen]
            defaults.removeObject(forKey: "debugScreen")
        }
        if let minutes = defaults.string(forKey: "debugUpByMinutes") {
            args += ["-upByMinutes", minutes]
            defaults.removeObject(forKey: "debugUpByMinutes")
        }

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
                startMonitoring()
            case "alarm": currentScreen = .alarm
            default: break
            }
        }
    }
    #endif

    func saveSettings() {
        if let encoded = try? JSONEncoder().encode(settings) {
            defaults.set(encoded, forKey: settingsKey)
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

    // MARK: - The session

    func startMonitoring() {
        sessionStartedAt = now()
        // The record keeps the sensitivity the night started with, whatever
        // settings say by morning
        sessionSensitivity = settings.sensitivityValue
        listeningStartedAt = nil
        alarmFiredAt = nil
        triggeredBy = .none
        alarmVolume = nil
        currentScreen = .monitoring
        isMonitoring = true
        Logger.session.notice("night started, up by \(self.timeString(self.settings.wakeUpBy), privacy: .public)")
    }

    func stopMonitoring() {
        recordSessionEnd(.stopped)
        isMonitoring = false
        currentScreen = .setup
    }

    // A no-alarm night that reached silence, dismissed with "done" — not the
    // same as a night ended early by hand
    func completeNight() {
        recordSessionEnd(.completed)
        isMonitoring = false
        currentScreen = .setup
    }

    // Room calibration finished. Listening time for auto sensitivity starts
    // here, not when the window opened, because calibration waits for white
    // noise to fade and then takes 30 seconds (stir.md decision 62)
    func markListeningStarted() {
        guard sessionStartedAt != nil, listeningStartedAt == nil else { return }
        listeningStartedAt = now()
        Logger.session.notice("listening started")
    }

    func triggerAlarm(_ reason: AlarmTrigger) {
        if alarmFiredAt == nil {
            alarmFiredAt = now()
            triggeredBy = reason
        }
        currentScreen = .alarm
        Logger.session.notice("alarm fired by \(reason.rawValue, privacy: .public)")
    }

    func recordAlarmVolume(_ volume: Float) {
        guard alarmFiredAt != nil, alarmVolume == nil else { return }
        alarmVolume = volume
    }

    func dismissAlarm() {
        recordSessionEnd(.alarmDismissed)
        isMonitoring = false
        currentScreen = .setup
    }

    // Written on every exit from a session so the next morning has something to
    // read, on the phone and in the unified log. Only a clean run becomes a
    // NightRecord (stir.md decision 33).
    private func recordSessionEnd(_ ending: SessionRecord.Ending) {
        guard let startedAt = sessionStartedAt else { return }
        let endedAt = now()
        let session = SessionRecord(startedAt: startedAt,
                                    upBy: settings.wakeUpBy,
                                    alarmFiredAt: alarmFiredAt,
                                    endedAt: endedAt,
                                    ending: ending)
        session.save()
        Logger.session.notice("night ended after \(session.lengthText, privacy: .public) — \(ending.rawValue, privacy: .public), alarm \(session.alarmText, privacy: .public)")

        let nightEnding = NightEnding(rawValue: ending.rawValue) ?? .stopped
        let nightWindowStart: Date? = settings.alarmEnabled ? windowStart : nil
        let clean = CleanRun.isCleanRun(startedAt: startedAt, upBy: settings.wakeUpBy,
                                        windowStart: nightWindowStart, endedAt: endedAt,
                                        alarmFiredAt: alarmFiredAt, ending: nightEnding)
        if clean, let nightStore {
            nightStore.add(NightRecord(startedAt: startedAt,
                                       endedAt: endedAt,
                                       upBy: settings.wakeUpBy,
                                       windowStart: nightWindowStart,
                                       listeningStartedAt: listeningStartedAt,
                                       alarmFiredAt: alarmFiredAt,
                                       triggeredBy: triggeredBy,
                                       ending: nightEnding,
                                       sensitivity: sessionSensitivity,
                                       alarmVolume: alarmVolume))
        }
        Logger.session.notice("night \(clean ? "kept as a clean run" : "not a clean run, not kept", privacy: .public)")
        if clean {
            evaluateAutoSensitivity()
        }

        sessionStartedAt = nil
        listeningStartedAt = nil
        alarmFiredAt = nil
        triggeredBy = .none
        alarmVolume = nil
    }

    // MARK: - Auto sensitivity

    // After a clean run on auto: read every night, and apply what auto decides.
    // A step up changes the value the next night starts with, never the night
    // that just ended (stir.md decision 44).
    private func evaluateAutoSensitivity() {
        guard settings.sensitivityMode == .auto, let nightStore,
              let state = settings.autoSensitivity else { return }
        let nights = nightStore.all().map(NightFacts.init)
        let (next, action) = AutoSensitivity.evaluate(state, nights: nights, now: now())

        var updated = settings
        updated.autoSensitivity = next
        if action == .stepUp {
            updated.sensitivityValue = AutoSensitivity.ladder[next.step]
        }
        settings = updated
        if action == .ask {
            sensitivityQuestionPending = true
        }
    }

    /// How many nights auto is reading at its current step, for technical details
    var autoSensitivityNightsCounted: Int {
        guard let state = settings.autoSensitivity, let nightStore else { return 0 }
        return AutoSensitivity.countedEvidence(state, nights: nightStore.all().map(NightFacts.init)).count
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
