import Foundation
import SwiftData
import os

// What set off the alarm — never who. stir hears the room, not a person
// (stir.md decision 57).
enum AlarmTrigger: String, Codable {
    case sound
    case motion
    case upBy
    case none    // ended by hand, or a no-alarm night
}

enum NightEnding: String, Codable {
    case stopped          // ended by hand on the night screen
    case alarmDismissed   // the alarm rang and was stopped
    case completed        // a no-alarm night reached silence
}

// One clean run: a night that ended the way stir is designed to end one
// (stir.md decisions 31–33). It holds what stir did and nothing it heard — no
// sound levels, no motion samples, no location, no time zone. A field added
// here is a decision in stir.md first; NightRecordTests fails on any other.
@Model
final class NightRecord {
    var startedAt: Date
    var endedAt: Date
    var upBy: Date
    // The wake window as it was that night; nil on a no-alarm night
    var windowStart: Date?
    // When room calibration finished and listening began; nil if it never did
    var listeningStartedAt: Date?
    var alarmFiredAt: Date?
    var triggeredBy: AlarmTrigger
    var ending: NightEnding
    // The sensitivityValue the night started with — a setting, not a measurement
    var sensitivity: Float
    // Media volume when the alarm started
    var alarmVolume: Float?
    // Minutes after local midnight, so a night reads in the time it happened
    // without storing where it happened
    var startedLocalMinute: Int
    var endedLocalMinute: Int

    init(startedAt: Date, endedAt: Date, upBy: Date, windowStart: Date?,
         listeningStartedAt: Date?, alarmFiredAt: Date?, triggeredBy: AlarmTrigger,
         ending: NightEnding, sensitivity: Float, alarmVolume: Float?,
         calendar: Calendar = .current) {
        self.startedAt = startedAt
        self.endedAt = endedAt
        self.upBy = upBy
        self.windowStart = windowStart
        self.listeningStartedAt = listeningStartedAt
        self.alarmFiredAt = alarmFiredAt
        self.triggeredBy = triggeredBy
        self.ending = ending
        self.sensitivity = sensitivity
        self.alarmVolume = alarmVolume
        self.startedLocalMinute = Self.localMinute(startedAt, calendar)
        self.endedLocalMinute = Self.localMinute(endedAt, calendar)
    }

    private static func localMinute(_ date: Date, _ calendar: Calendar) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }
}

// The one definition of a clean run, shared by everything that reads the
// record — auto sensitivity now, history and Health later.
enum CleanRun {
    // A session started minutes before "up by" is a test or a nap, not a night
    // (stir.md open 10)
    static let minimumNightLength: TimeInterval = 3 * 60 * 60

    static func isCleanRun(startedAt: Date, upBy: Date, windowStart: Date?,
                           endedAt: Date, alarmFiredAt: Date?, ending: NightEnding) -> Bool {
        guard upBy.timeIntervalSince(startedAt) >= minimumNightLength else { return false }
        switch ending {
        case .alarmDismissed, .completed:
            return true
        case .stopped:
            // Up before stir: ended by hand inside the window, before the alarm
            guard let windowStart else { return false }
            return endedAt >= windowStart && alarmFiredAt == nil
        }
    }
}

@MainActor
protocol NightStore: AnyObject {
    func add(_ record: NightRecord)
    /// Every record, oldest first.
    func all() -> [NightRecord]
}

@MainActor
final class SwiftDataNightStore: NightStore {
    private let context: ModelContext

    init(container: ModelContainer) {
        context = container.mainContext
    }

    func add(_ record: NightRecord) {
        context.insert(record)
        do {
            try context.save()
        } catch {
            Logger.session.error("❌ night record not saved: \(String(describing: error), privacy: .public)")
        }
    }

    func all() -> [NightRecord] {
        let oldestFirst = FetchDescriptor<NightRecord>(sortBy: [SortDescriptor(\.startedAt)])
        do {
            return try context.fetch(oldestFirst)
        } catch {
            Logger.session.error("❌ night records not read: \(String(describing: error), privacy: .public)")
            return []
        }
    }
}
