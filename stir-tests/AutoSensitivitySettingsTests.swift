import XCTest
import SwiftData
@testable import stir

// Auto sensitivity in settings and at the end of a night (stir.md decisions
// 60, 65, 69, 71).
@MainActor
final class AutoSensitivitySettingsTests: XCTestCase {

    private final class Clock {
        var date: Date
        init(_ date: Date) { self.date = date }
    }

    // Held for the whole test: a store keeps only the container's context, and
    // a context whose container is gone crashes on its first insert
    private var container: ModelContainer!
    private var store: SwiftDataNightStore!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var clock: Clock!
    private var app: AppState!

    private let base = Date(timeIntervalSince1970: 1_800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    override func setUp() async throws {
        container = try ModelContainer(for: NightRecord.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        store = SwiftDataNightStore(container: container)
        suiteName = "stir-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        clock = Clock(base)
        app = AppState(nightStore: store, defaults: defaults)
        app.now = { [clock] in clock!.date }
        app.settings.wakeWindowMinutes = 30
        app.settings.alarmEnabled = true
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    // MARK: - decoding and defaults

    func testSettingsSavedBeforeAutoStayManual() throws {
        var saved = AlarmSettings.default
        saved.chooseSensitivity("high", now: base)
        var blob = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(saved)) as? [String: Any])
        blob.removeValue(forKey: "sensitivityMode")
        blob.removeValue(forKey: "autoSensitivity")

        let decoded = try JSONDecoder().decode(AlarmSettings.self, from: JSONSerialization.data(withJSONObject: blob))
        XCTAssertEqual(decoded.sensitivityMode, .manual)
        XCTAssertEqual(decoded.sensitivityValue, 0.85)
        XCTAssertNil(decoded.autoSensitivity)
    }

    func testANewInstallStartsOnAutoAtMedium() {
        let fresh = AlarmSettings.default
        XCTAssertEqual(fresh.sensitivityMode, .auto)
        XCTAssertEqual(fresh.sensitivityValue, 0.5)
        XCTAssertEqual(fresh.autoSensitivity?.step, 2)
        XCTAssertEqual(fresh.autoSensitivity?.phase, .settling)
    }

    func testAutoSurvivesSavingAndLoading() throws {
        let fresh = AlarmSettings.default
        let decoded = try JSONDecoder().decode(AlarmSettings.self, from: JSONEncoder().encode(fresh))
        XCTAssertEqual(decoded.sensitivityMode, .auto)
        XCTAssertEqual(decoded.autoSensitivity, fresh.autoSensitivity)
    }

    // MARK: - the picker

    func testSwitchingFromHighToAutoStartsAtStepFour() {
        var settings = AlarmSettings.default
        settings.chooseSensitivity("high", now: base)
        settings.chooseSensitivity("auto", now: base)
        XCTAssertEqual(settings.sensitivityMode, .auto)
        XCTAssertEqual(settings.autoSensitivity?.step, 4)
        XCTAssertEqual(settings.autoSensitivity?.maxStep, 5)
        XCTAssertEqual(settings.sensitivityValue, 0.85)
    }

    func testSwitchingFromAutoToMediumClearsAuto() {
        var settings = AlarmSettings.default
        settings.chooseSensitivity("medium", now: base)
        XCTAssertEqual(settings.sensitivityMode, .manual)
        XCTAssertNil(settings.autoSensitivity)
        XCTAssertEqual(settings.sensitivityValue, 0.5)
    }

    func testChoosingAutoWhileOnAutoChangesNothing() {
        var settings = AlarmSettings.default
        let before = settings.autoSensitivity
        settings.chooseSensitivity("auto", now: base.addingTimeInterval(day))
        XCTAssertEqual(settings.autoSensitivity, before)
    }

    func testLabelsRoundToTheNearestNamedSettingWithTiesAtMedium() {
        var settings = AlarmSettings.default
        for (value, label) in [(Float(0.15), "low"), (0.325, "medium"), (0.5, "medium"),
                               (0.675, "medium"), (0.85, "high"), (1.0, "high"), (0.2, "low")] {
            settings.sensitivityValue = value
            XCTAssertEqual(settings.sensitivityLabel, label, "\(value)")
        }
    }

    // MARK: - at the end of a night

    /// A clean run already in the store, as night n after base
    private func storedNight(_ n: Int, sensitivity: Float, detectedAfterMinutes: Double?) {
        let startedAt = base.addingTimeInterval(Double(n + 1) * day)
        let listening = startedAt.addingTimeInterval(8 * 60 * 60)
        let upBy = listening.addingTimeInterval(30 * 60)
        let fired = detectedAfterMinutes.map { listening.addingTimeInterval($0 * 60) } ?? upBy
        store.add(NightRecord(startedAt: startedAt, endedAt: fired.addingTimeInterval(60), upBy: upBy,
                              windowStart: listening, listeningStartedAt: listening, alarmFiredAt: fired,
                              triggeredBy: detectedAfterMinutes == nil ? .upBy : .sound,
                              ending: .alarmDismissed, sensitivity: sensitivity, alarmVolume: 0.7))
    }

    /// Night n lived through AppState: start, listen, alarm, stop
    private func liveNight(_ n: Int, detectedAfterMinutes: Double?) {
        let startedAt = base.addingTimeInterval(Double(n + 1) * day)
        let listening = startedAt.addingTimeInterval(8 * 60 * 60)
        app.settings.wakeUpBy = listening.addingTimeInterval(30 * 60)
        clock.date = startedAt
        app.startMonitoring()
        clock.date = listening
        app.markListeningStarted()
        if let minutes = detectedAfterMinutes {
            clock.date = listening.addingTimeInterval(minutes * 60)
            app.triggerAlarm(.sound)
        } else {
            clock.date = app.settings.wakeUpBy
            app.triggerAlarm(.upBy)
        }
        clock.date = clock.date.addingTimeInterval(60)
        app.dismissAlarm()
    }

    private func useAuto(at step: Int) {
        app.settings.sensitivityMode = .auto
        app.settings.autoSensitivity = AutoSensitivity.starting(at: AutoSensitivity.ladder[step], now: base)
        app.settings.sensitivityValue = AutoSensitivity.ladder[step]
    }

    func testAStepUpChangesTheNextNightNotTheOneThatEnded() {
        useAuto(at: 2)
        for n in 0..<8 { storedNight(n, sensitivity: 0.5, detectedAfterMinutes: nil) }

        liveNight(8, detectedAfterMinutes: nil)
        XCTAssertEqual(app.settings.autoSensitivity?.step, 3)
        XCTAssertEqual(app.settings.sensitivityValue, 0.675)
        XCTAssertEqual(store.all().last?.sensitivity, 0.5, "the night that ended keeps its own value")

        liveNight(9, detectedAfterMinutes: 10)
        XCTAssertEqual(store.all().last?.sensitivity, 0.675, "the next night starts at the new step")
    }

    func testAskFlagsTheQuestion() {
        useAuto(at: 2)
        for n in 0..<5 { storedNight(n, sensitivity: 0.5, detectedAfterMinutes: 1) }

        liveNight(5, detectedAfterMinutes: 1)
        XCTAssertTrue(app.sensitivityQuestionPending)
        XCTAssertEqual(app.settings.autoSensitivity?.questionAsked, true)
        XCTAssertEqual(app.settings.sensitivityValue, 0.5)
    }

    func testAnUncleanNightOnAutoEvaluatesNothing() {
        useAuto(at: 2)
        for n in 0..<8 { storedNight(n, sensitivity: 0.5, detectedAfterMinutes: nil) }
        let before = app.settings.autoSensitivity

        let startedAt = base.addingTimeInterval(9 * day)
        app.settings.wakeUpBy = startedAt.addingTimeInterval(8.5 * 60 * 60)
        clock.date = startedAt
        app.startMonitoring()
        clock.date = startedAt.addingTimeInterval(60 * 60)   // ended long before the window
        app.stopMonitoring()

        XCTAssertEqual(app.settings.autoSensitivity, before)
        XCTAssertEqual(app.settings.sensitivityValue, 0.5)
    }

    func testANightOnManualEvaluatesNothing() {
        app.settings.chooseSensitivity("medium", now: base)
        for n in 0..<8 { storedNight(n, sensitivity: 0.5, detectedAfterMinutes: nil) }

        liveNight(8, detectedAfterMinutes: nil)
        XCTAssertEqual(app.settings.sensitivityMode, .manual)
        XCTAssertNil(app.settings.autoSensitivity)
        XCTAssertEqual(app.settings.sensitivityValue, 0.5)
        XCTAssertFalse(app.sensitivityQuestionPending)
    }
}
