import Foundation
import SwiftUI
#if canImport(AlarmKit)
import AlarmKit
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
                            print("⏰ Backstop not authorized")
                            return
                        }
                    case .denied:
                        print("⏰ Backstop authorization denied")
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
                    print("⏰ Backstop scheduled for \(upBy.addingTimeInterval(graceSeconds))")
                } catch {
                    print("⏰ Backstop scheduling failed: \(error)")
                }
            }
        }
        #endif
    }

    static func cancelBackstop() {
        #if canImport(AlarmKit)
        if #available(iOS 26.0, *) {
            Task { await cancel() }
        }
        #endif
    }

    #if canImport(AlarmKit)
    @available(iOS 26.0, *)
    private static func cancel() async {
        guard let idString = UserDefaults.standard.string(forKey: alarmIdKey),
              let id = UUID(uuidString: idString) else { return }
        do {
            try AlarmManager.shared.cancel(id: id)
            print("⏰ Backstop cancelled")
        } catch {
            print("⏰ Backstop cancel failed (may have already fired): \(error)")
        }
        UserDefaults.standard.removeObject(forKey: alarmIdKey)
    }

    @available(iOS 26.0, *)
    private struct BackstopMetadata: AlarmMetadata {}
    #endif
}
