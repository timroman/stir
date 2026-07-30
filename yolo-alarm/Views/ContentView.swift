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
        #endif
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
