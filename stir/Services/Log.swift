import os

// Diagnostics for a night that already happened.
//
// print() writes to stderr, which only an attached debugger ever sees — so an
// overnight failure left nothing behind to read the next morning. These go to
// the unified log, which persists on the device for days and can be pulled off
// it afterwards:
//
//   sudo log collect --device-udid <udid> --last 18h --output stir.logarchive
//   log show stir.logarchive --predicate 'subsystem == "com.pureinference.stir"'
//
// Levels are chosen for survival, not chattiness: .notice and .error are
// written to disk, while .debug and .info can be dropped before anyone looks.
// Anything needed to reconstruct a night is .notice or higher.
//
// Values are interpolated with privacy: .public. The default redacts them to
// <private>, which would leave timestamps and no substance.
extension Logger {
    private static let subsystem = "com.pureinference.stir"

    /// App and session lifecycle: launch, start, phase changes, Live Activity.
    static let session = Logger(subsystem: subsystem, category: "session")
    /// White noise playback, fades, and audio session configuration.
    static let audio = Logger(subsystem: subsystem, category: "audio")
    /// Microphone monitoring, calibration, and triggers.
    static let monitor = Logger(subsystem: subsystem, category: "monitor")
    /// The wake alarm and its AlarmKit backstop.
    static let alarm = Logger(subsystem: subsystem, category: "alarm")
    /// Haptic engine and patterns.
    static let haptics = Logger(subsystem: subsystem, category: "haptics")
    /// Sound library: bundled lookup, custom import, preview.
    static let sounds = Logger(subsystem: subsystem, category: "sounds")
}
