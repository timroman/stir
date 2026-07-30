import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    #if DEBUG
    @State private var debugShowDetails = ProcessInfo.processInfo.arguments.contains("-showDetails")
    #endif

    var body: some View {
        ZStack {
            switch appState.currentScreen {
            case .onboarding:
                OnboardingView()
                    .transition(.opacity)
            case .setup:
                SetupView()
                    .transition(.opacity)
            case .monitoring:
                MonitoringView()
                    .transition(.opacity)
            case .alarm:
                AlarmView()
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 1.0), value: appState.currentScreen)
        #if DEBUG
        .sheet(isPresented: $debugShowDetails) {
            NavigationStack {
                TechnicalDetailsView()
            }
        }
        // Screenshot/test driving without relaunching, e.g.
        //   xcrun simctl openurl booted "stir://screen/monitoring?upByMinutes=480"
        .onOpenURL { url in
            guard url.scheme == "stir", url.host == "screen" else { return }
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            if let minutes = components?.queryItems?.first(where: { $0.name == "upByMinutes" })?.value,
               let value = Double(minutes) {
                appState.settings.wakeUpBy = Date().addingTimeInterval(value * 60)
            }
            switch url.lastPathComponent {
            case "setup": appState.currentScreen = .setup
            case "monitoring":
                appState.currentScreen = .monitoring
                appState.isMonitoring = true
            case "alarm": appState.currentScreen = .alarm
            case "details": debugShowDetails = true
            default: break
            }
        }
        #endif
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
