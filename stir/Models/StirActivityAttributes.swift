import ActivityKit
import Foundation
import SwiftUI

struct StirActivityAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        var wakeWindow: String
        var isActive: Bool
        var isAlarming: Bool
        var message: String
        var accentColorRed: Double
        var accentColorGreen: Double
        var accentColorBlue: Double
        var audioLevel: Double // 0.0 to 1.0, representing level relative to threshold

        var accentColor: Color {
            Color(red: accentColorRed, green: accentColorGreen, blue: accentColorBlue)
        }
    }

    var startTime: Date
}
