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

        // A stray from an earlier run must not sit beside tonight's
        endStrays(reason: "before starting a night")

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

    // Ends every activity stir has on screen, not just the one this launch
    // started. `currentActivity` lives in memory: a crash or a relaunch between
    // starting a night and ending it left it nil while the widget stayed on the
    // lock screen, with nothing able to clear it. ActivityKit knows what is
    // showing even when stir has forgotten.
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

        currentActivity = nil
        Task {
            for activity in Activity<StirActivityAttributes>.activities {
                await activity.end(
                    ActivityContent(state: state, staleDate: nil),
                    dismissalPolicy: .immediate
                )
                Logger.session.notice("Live Activity stopped: \(String(describing: activity.id), privacy: .public)")
            }
        }
    }

    /// Clears anything left on the lock screen by a run that never got to end it
    /// — a crash, or iOS restarting the app. Called at launch, when no night can
    /// possibly be running, and before a new night starts.
    static func endStrays(reason: String) {
        let strays = Activity<StirActivityAttributes>.activities
        guard !strays.isEmpty else { return }
        Logger.session.notice("clearing \(strays.count, privacy: .public) stray Live Activity(ies) \(reason, privacy: .public)")
        stop()
    }
}
