import ActivityKit
import Foundation
import SwiftUI
import os

enum StirLiveActivity {
    private static var currentActivity: Activity<StirActivityAttributes>?
    private static let accentColor = NightSky.dawnAmberComponents
    private static var currentWakeWindow: String = ""

    static func start(wakeWindow: String) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            Logger.session.notice("Live Activities not enabled")
            return
        }

        let color = accentColor
        currentWakeWindow = wakeWindow

        let attributes = StirActivityAttributes(startTime: Date())
        let state = StirActivityAttributes.ContentState(
            wakeWindow: wakeWindow,
            isActive: true,
            isAlarming: false,
            message: "waiting...",
            accentColorRed: color.red,
            accentColorGreen: color.green,
            accentColorBlue: color.blue,
            audioLevel: 0.0
        )

        do {
            let activity = try Activity.request(
                attributes: attributes,
                content: .init(state: state, staleDate: nil),
                pushType: nil
            )
            currentActivity = activity
            Logger.session.notice("Started Live Activity: \(String(describing: activity.id), privacy: .public)")
        } catch {
            Logger.session.error("Failed to start Live Activity: \(String(describing: error), privacy: .public)")
        }
    }

    static func updateStatus(_ status: String) {
        guard let activity = currentActivity else { return }

        let state = StirActivityAttributes.ContentState(
            wakeWindow: activity.content.state.wakeWindow,
            isActive: true,
            isAlarming: false,
            message: status,
            accentColorRed: accentColor.red,
            accentColorGreen: accentColor.green,
            accentColorBlue: accentColor.blue,
            audioLevel: activity.content.state.audioLevel
        )

        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: nil)
            )
            Logger.session.notice("Live Activity status: \(String(describing: status), privacy: .public)")
        }
    }

    static func updateAudioLevel(_ level: Double, status: String) {
        guard let activity = currentActivity else { return }

        let state = StirActivityAttributes.ContentState(
            wakeWindow: currentWakeWindow,
            isActive: true,
            isAlarming: false,
            message: status,
            accentColorRed: accentColor.red,
            accentColorGreen: accentColor.green,
            accentColorBlue: accentColor.blue,
            audioLevel: level
        )

        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: nil)
            )
        }
    }

    static func triggerAlarm(message: String) {
        let state = StirActivityAttributes.ContentState(
            wakeWindow: "",
            isActive: true,
            isAlarming: true,
            message: message,
            accentColorRed: accentColor.red,
            accentColorGreen: accentColor.green,
            accentColorBlue: accentColor.blue,
            audioLevel: 1.0
        )

        Task {
            await currentActivity?.update(
                ActivityContent(state: state, staleDate: nil)
            )
            Logger.session.notice("Live Activity updated to alarm state")
        }
    }

    static func stop() {
        let state = StirActivityAttributes.ContentState(
            wakeWindow: "",
            isActive: false,
            isAlarming: false,
            message: "",
            accentColorRed: accentColor.red,
            accentColorGreen: accentColor.green,
            accentColorBlue: accentColor.blue,
            audioLevel: 0.0
        )

        Task {
            await currentActivity?.end(
                ActivityContent(state: state, staleDate: nil),
                dismissalPolicy: .immediate
            )
            currentActivity = nil
            Logger.session.notice("Live Activity stopped")
        }
    }
}
