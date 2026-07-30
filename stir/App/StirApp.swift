import SwiftUI
import AVFoundation

@main
struct StirApp: App {
    @StateObject private var appState = AppState()

    init() {
        print("🚀 stir app initializing...")
        print("🚀 stir app ready")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .preferredColorScheme(.dark)
                .onAppear {
                    print("🚀 ContentView appeared")
                }
        }
    }
}
