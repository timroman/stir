import Foundation

// A short account of the night that just ended.
//
// Nothing about a running session was ever persisted: the app came back to the
// setup screen with no trace of what had happened, so "the animation was gone
// this morning" had no answer on the phone itself. This is the answer — when
// the night started, whether the alarm ever rang, and how it ended.
struct SessionRecord: Codable {
    enum Ending: String, Codable {
        case stopped         // the stop button on the night screen
        case alarmDismissed  // the alarm rang and was dismissed
        case completed       // a no-alarm night reached silence and was dismissed

        var label: String {
            switch self {
            case .stopped: return "stopped by hand"
            case .alarmDismissed: return "alarm dismissed"
            case .completed: return "finished"
            }
        }
    }

    var startedAt: Date
    var upBy: Date
    var alarmFiredAt: Date?
    var endedAt: Date
    var ending: Ending

    private static let key = "lastSessionRecord"

    static var last: SessionRecord? {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(SessionRecord.self, from: data) else { return nil }
        return decoded
    }

    func save() {
        guard let encoded = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(encoded, forKey: Self.key)
    }

    // MARK: - Display

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter
    }()

    private static func time(_ date: Date) -> String {
        timeFormatter.string(from: date).lowercased()
    }

    var startedText: String { Self.time(startedAt) }
    var endedText: String { Self.time(endedAt) }
    var alarmText: String { alarmFiredAt.map(Self.time) ?? "never rang" }

    var lengthText: String {
        let minutes = Int(endedAt.timeIntervalSince(startedAt) / 60)
        let hours = minutes / 60
        return hours > 0 ? "\(hours)h \(minutes % 60)m" : "\(minutes)m"
    }
}
