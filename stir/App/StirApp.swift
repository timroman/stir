import SwiftUI
import AVFoundation
import os

@main
struct StirApp: App {
    @StateObject private var appState = AppState()

    init() {
        Logger.session.notice("🚀 stir app initializing...")
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
