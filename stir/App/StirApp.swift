import SwiftUI
import SwiftData
import AVFoundation
import os

@main
struct StirApp: App {
    @StateObject private var appState: AppState

    init() {
        Logger.session.notice("🚀 stir app initializing...")
        // Night records stay on the phone (stir.md decision 40). If the store
        // can't open, nights still run; they just aren't kept.
        let nightStore: NightStore?
        do {
            nightStore = SwiftDataNightStore(container: try ModelContainer(for: NightRecord.self))
        } catch {
            Logger.session.error("❌ night records unavailable: \(String(describing: error), privacy: .public)")
            nightStore = nil
        }
        _appState = StateObject(wrappedValue: AppState(nightStore: nightStore))
        Logger.session.notice("🚀 stir app ready")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .onAppear {
                    Logger.session.notice("🚀 ContentView appeared")
                }
        }
    }
}
