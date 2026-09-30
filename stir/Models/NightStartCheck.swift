import Foundation

// What stir says before a night starts, and nothing after it (stir.md
// principle 4, decisions 20 and 76). The last moment somebody is awake and
// holding the phone is the only moment either of these can still be fixed —
// at "up by" they are asleep and nothing can be done.
enum NightStartCheck {
    /// Media volume below this cannot be relied on to wake anybody
    static let lowVolume: Float = 0.3
    /// Below this, unplugged, a phone may not survive the night — and a phone
    /// that dies rings neither the alarm nor the backstop
    static let lowBattery: Float = 0.3

    struct Warnings: OptionSet {
        let rawValue: Int
        static let lowVolume = Warnings(rawValue: 1 << 0)
        static let lowBattery = Warnings(rawValue: 1 << 1)
    }

    /// `volume` and `batteryLevel` are nil when the phone will not say, in
    /// which case stir does not guess.
    static func warnings(alarmEnabled: Bool,
                         whiteNoiseEnabled: Bool,
                         volume: Float?,
                         batteryLevel: Float?,
                         isCharging: Bool) -> Warnings {
        var warnings: Warnings = []

        // Only worth asking about when nothing else will play: with white noise
        // on, the volume is set by ear after the night starts, so the number
        // read here is not the one the alarm will use (owner, 29 september)
        if alarmEnabled, !whiteNoiseEnabled, let volume, volume < lowVolume {
            warnings.insert(.lowVolume)
        }

        // Regardless of how the night is meant to end: a dead phone wakes
        // nobody, with or without an alarm
        if !isCharging, let batteryLevel, batteryLevel >= 0, batteryLevel < lowBattery {
            warnings.insert(.lowBattery)
        }

        return warnings
    }
}
