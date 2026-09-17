import XCTest
import SwiftData
@testable import stir

// The night record is what auto sensitivity reads, and later history and
// Health. Only a clean run becomes one (stir.md decisions 31–33).
@MainActor
final class NightRecordTests: XCTestCase {

    private final class Clock {
        var date: Date
        init(_ date: Date) { self.date = date }
    }

    private var container: ModelContainer!
    private var store: SwiftDataNightStore!
    private var defaults: UserDefaults!
    private var suiteName: String!
    private var clock: Clock!
    private var app: AppState!

    // 07:00 "up by", a 30-minute window: listening can begin at 06:30
    private let upBy = Date(timeIntervalSince1970: 1_800_000_000)
    private var windowStart: Date { upBy.addingTimeInterval(-30 * 60) }

    override func setUp() async throws {
        container = try ModelContainer(for: NightRecord.self,
                                       configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        store = SwiftDataNightStore(container: container)
        suiteName = "stir-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
        clock = Clock(upBy.addingTimeInterval(-8 * 60 * 60))
        app = AppState(nightStore: store, defaults: defaults)
        app.now = { [clock] in clock!.date }
        app.settings.wakeUpBy = upBy
        app.settings.wakeWindowMinutes = 30
        app.settings.alarmEnabled = true
        app.settings.sensitivityValue = 0.5
    }

    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func at(_ date: Date) { clock.date = date }
    private func minutes(_ m: Double, after date: Date) -> Date { date.addingTimeInterval(m * 60) }

    // MARK: - what reaches the record

    func testEachTriggerReachesTheRecord() {
        for reason in [AlarmTrigger.sound, .motion, .upBy] {
            at(upBy.addingTimeInterval(-8 * 60 * 60))
            app.startMonitoring()
            at(minutes(1, after: windowStart))
            app.markListeningStarted()
            at(minutes(12, after: windowStart))
            app.triggerAlarm(reason)
            app.recordAlarmVolume(0.6)
            at(minutes(13, after: windowStart))
            app.dismissAlarm()

            let record = store.all().last
            XCTAssertEqual(record?.triggeredBy, reason)
            XCTAssertEqual(record?.ending, .alarmDismissed)
            XCTAssertEqual(record?.alarmFiredAt, minutes(12, after: windowStart))
            XCTAssertEqual(record?.alarmVolume, 0.6)
        }
        XCTAssertEqual(store.all().count, 3)
    }

    func testListeningStartedIsTheFirstTransition() {
        app.startMonitoring()
        at(minutes(1, after: windowStart))
        app.markListeningStarted()
        at(minutes(5, after: windowStart))
        app.markListeningStarted()
        at(minutes(10, after: windowStart))
        app.stopMonitoring()

        XCTAssertEqual(store.all().first?.listeningStartedAt, minutes(1, after: windowStart))
    }

    func testListeningThatNeverBeganIsNil() {
        app.startMonitoring()
        at(minutes(0.2, after: windowStart))   // ended during calibration
        app.stopMonitoring()

        XCTAssertEqual(store.all().count, 1)
        XCTAssertNil(store.all().first?.listeningStartedAt)
    }

    func testSensitivityIsTheValueTheNightStartedWith() {
        app.settings.sensitivityValue = 0.85
        app.startMonitoring()
        app.settings.sensitivityValue = 0.15
        at(minutes(5, after: windowStart))
        app.triggerAlarm(.sound)
        app.dismissAlarm()

        XCTAssertEqual(store.all().first?.sensitivity, 0.85)
    }

    // MARK: - which nights are clean runs

    func testFinishedNoAlarmNightRecordsCompleted() {
        app.settings.alarmEnabled = false
        app.startMonitoring()
        at(minutes(1, after: upBy))
        app.completeNight()

        let record = store.all().first
        XCTAssertEqual(record?.ending, .completed)
        XCTAssertEqual(record?.triggeredBy, AlarmTrigger.none)
        XCTAssertNil(record?.windowStart)
        XCTAssertNil(record?.listeningStartedAt)
        XCTAssertEqual(SessionRecord.last?.ending, .completed)
    }

    func testNightThatNeverEndsWritesNothing() {
        app.startMonitoring()
        at(minutes(10, after: windowStart))
        app.markListeningStarted()

        XCTAssertTrue(store.all().isEmpty)
    }

    func testEndedBeforeTheWindowIsNotKeptButStillShowsAsLastNight() {
        app.startMonitoring()
        let ended = minutes(-10, after: windowStart)
        at(ended)
        app.stopMonitoring()

        XCTAssertTrue(store.all().isEmpty)
        XCTAssertEqual(SessionRecord.last?.endedAt, ended)
        XCTAssertEqual(SessionRecord.last?.ending, .stopped)
    }

    func testEndedByHandInsideTheWindowBeforeTheAlarmIsClean() {
        app.startMonitoring()
        at(minutes(5, after: windowStart))
        app.stopMonitoring()

        let record = store.all().first
        XCTAssertEqual(record?.ending, .stopped)
        XCTAssertEqual(record?.triggeredBy, AlarmTrigger.none)
        XCTAssertEqual(record?.windowStart, windowStart)
    }

    func testANightMustStartThreeHoursBeforeUpBy() {
        at(upBy.addingTimeInterval(-CleanRun.minimumNightLength + 60))
        app.startMonitoring()
        at(minutes(5, after: windowStart))
        app.triggerAlarm(.sound)
        app.dismissAlarm()
        XCTAssertTrue(store.all().isEmpty, "2h59m before up by is a nap, not a night")

        at(upBy.addingTimeInterval(-CleanRun.minimumNightLength))
        app.startMonitoring()
        at(minutes(5, after: windowStart))
        app.triggerAlarm(.sound)
        app.dismissAlarm()
        XCTAssertEqual(store.all().count, 1, "exactly 3h before up by is a night")
    }

    func testLocalMinutesAreMinutesAfterLocalMidnight() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 9, day: 15, hour: 22, minute: 40))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 9, day: 16, hour: 6, minute: 55))!
        let record = NightRecord(startedAt: start, endedAt: end, upBy: end, windowStart: nil,
                                 listeningStartedAt: nil, alarmFiredAt: nil, triggeredBy: .none,
                                 ending: .completed, sensitivity: 0.5, alarmVolume: nil,
                                 calendar: calendar)
        XCTAssertEqual(record.startedLocalMinute, 22 * 60 + 40)
        XCTAssertEqual(record.endedLocalMinute, 6 * 60 + 55)
    }

    // MARK: - the store

    /// Builds a store the way StirApp does: from a container nothing else keeps.
    private func storeWithoutKeepingItsContainer() throws -> SwiftDataNightStore {
        SwiftDataNightStore(container: try ModelContainer(for: NightRecord.self,
                                                          configurations: ModelConfiguration(isStoredInMemoryOnly: true)))
    }

    // Build 7 crashed on every clean night, the moment the alarm was stopped: the
    // store kept only the container's context, a context does not keep its
    // container alive, and StirApp held the container nowhere else. Every other
    // test here keeps its container in a property, which is why none caught it.
    func testTheStoreKeepsItsOwnContainerAlive() throws {
        let store = try storeWithoutKeepingItsContainer()
        store.add(NightRecord(startedAt: upBy.addingTimeInterval(-8 * 60 * 60), endedAt: upBy, upBy: upBy,
                              windowStart: windowStart, listeningStartedAt: windowStart, alarmFiredAt: upBy,
                              triggeredBy: .upBy, ending: .alarmDismissed, sensitivity: 0.5, alarmVolume: 0.7))
        XCTAssertEqual(store.all().count, 1)
    }

    // MARK: - the line in decision 32, enforced by the build

    func testTheRecordHoldsTheSpecifiedFieldsAndNoOthers() {
        let specified: Set<String> = [
            "startedAt", "endedAt", "upBy", "windowStart", "listeningStartedAt", "alarmFiredAt",
            "triggeredBy", "ending", "sensitivity", "alarmVolume", "startedLocalMinute", "endedLocalMinute",
        ]
        let stored = Set(Schema([NightRecord.self]).entities.first?.properties.map(\.name) ?? [])
        XCTAssertEqual(stored, specified,
                       "NightRecord's fields changed — that is a decision in stir.md first (decision 32)")
    }
}
