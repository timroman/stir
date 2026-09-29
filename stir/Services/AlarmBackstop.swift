import Foundation
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
import os
#endif

// Guaranteed can't-oversleep net behind the gentle in-app alarm. On iOS 26+
// this schedules a system alarm (AlarmKit) shortly after "up by" — it fires
// through Silent mode, Focus, and even if the app is killed overnight. The
// in-app alarm remains primary; a normal night cancels the backstop before
// it ever fires. On earlier iOS versions these calls are no-ops.
enum AlarmBackstop {
    // Fire slightly after "up by" so the gentle alarm always goes first
    private static let graceSeconds: TimeInterval = 120

    private static let alarmIdKey = "backstopAlarmId"
    // Written the instant a night ends, before the cancel is even attempted.
    // Cancelling is asynchronous, and stir can die before it lands — which is
    // how a system alarm fired for a night that had already ended. The next
    // launch reads this and finishes the job.
    private static let nightEndedKey = "backstopNightEnded"

    /// The rule the next launch follows. A backstop is only ever cancelled for
    /// a night that ended: one whose night never ended is the net doing its job
    /// after stir died, and must be left alone.
    static func shouldCancelAtLaunch(hasScheduledBackstop: Bool, nightEnded: Bool) -> Bool {
        hasScheduledBackstop && nightEnded
    }

    static func schedule(upBy: Date, tagline: String) {
        #if DEBUG
        // Screenshot/test sessions aren't real nights
        if ProcessInfo.processInfo.arguments.contains("-noBackstop") { return }
        #endif
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            Task {
                do {
                    let manager = AlarmManager.shared

                    switch manager.authorizationState {
                    case .notDetermined:
                        let state = try await manager.requestAuthorization()
                        guard state == .authorized else {
                            Logger.alarm.notice("⏰ Backstop not authorized")
                            return
                        }
                    case .denied:
                        Logger.alarm.error("⏰ Backstop authorization denied")
                        return
                    case .authorized:
                        break
                    @unknown default:
                        return
                    }

                    await cancel()

                    let id = UUID()
                    let alert = AlarmPresentation.Alert(
                        title: LocalizedStringResource(stringLiteral: tagline),
                        stopButton: AlarmButton(
                            text: "stop",
                            textColor: .white,
                            systemImageName: "stop.circle"
                        )
                    )
                    let attributes = AlarmAttributes<BackstopMetadata>(
                        presentation: AlarmPresentation(alert: alert),
                        tintColor: NightSky.dawnAmber
                    )
                    let configuration = AlarmManager.AlarmConfiguration(
                        schedule: .fixed(upBy.addingTimeInterval(graceSeconds)),
                        attributes: attributes
                    )

                    _ = try await manager.schedule(id: id, configuration: configuration)
                    UserDefaults.standard.set(id.uuidString, forKey: alarmIdKey)
                    UserDefaults.standard.removeObject(forKey: nightEndedKey)
                    Logger.alarm.notice("⏰ Backstop scheduled for \(String(describing: upBy.addingTimeInterval(graceSeconds)), privacy: .public)")
                } catch {
                    Logger.alarm.error("⏰ Backstop scheduling failed: \(String(describing: error), privacy: .public)")
                }
            }
        }
        #endif
    }

    static func cancelBackstop() {
        // Synchronous, and first: everything below can be cut short by stir
        // dying, but this survives into the next launch.
        UserDefaults.standard.set(true, forKey: nightEndedKey)
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            Task { await cancel() }
        }
        #endif
    }

    /// Called at launch, when no night can be running. Finishes a cancel that
    /// was interrupted, and leaves alone a backstop whose night never ended.
    static func clearIfNightEnded() {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            let defaults = UserDefaults.standard
            let hasBackstop = defaults.string(forKey: alarmIdKey) != nil
            let nightEnded = defaults.bool(forKey: nightEndedKey)
            guard shouldCancelAtLaunch(hasScheduledBackstop: hasBackstop, nightEnded: nightEnded) else {
                if hasBackstop {
                    Logger.alarm.notice("⏰ Backstop kept: its night never ended")
                }
                return
            }
            Logger.alarm.notice("⏰ Backstop left behind by a night that ended — cancelling now")
            Task { await cancel() }
        }
        #endif
    }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private static func cancel() async {
        let manager = AlarmManager.shared
        let defaults = UserDefaults.standard

        if let idString = defaults.string(forKey: alarmIdKey),
           let id = UUID(uuidString: idString) {
            do {
                try manager.cancel(id: id)
                Logger.alarm.notice("⏰ Backstop cancelled")
            } catch {
                Logger.alarm.error("⏰ Backstop cancel failed (may have already fired): \(String(describing: error), privacy: .public)")
            }
        }

        // Every alarm AlarmKit holds for stir is a backstop of ours. Cancelling
        // by stored id alone leaves anything whose id was lost — a crash before
        // the id was written — ringing with nothing able to reach it.
        do {
            for alarm in try manager.alarms {
                try? manager.cancel(id: alarm.id)
                Logger.alarm.notice("⏰ Stray backstop cancelled: \(String(describing: alarm.id), privacy: .public)")
            }
        } catch {
            Logger.alarm.error("⏰ Could not read scheduled alarms: \(String(describing: error), privacy: .public)")
        }

        defaults.removeObject(forKey: alarmIdKey)
        defaults.removeObject(forKey: nightEndedKey)
    }

    @available(iOS 26.0, *)
    private struct BackstopMetadata: AlarmMetadata {}
    #endif
}
