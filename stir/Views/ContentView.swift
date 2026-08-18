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
        // One owner for the display sleep timer. Screens must not each set it
        // in onAppear/onDisappear: SwiftUI runs the incoming view's onAppear
        // before the outgoing view's onDisappear, so the screen being left
        // always wins — which is how a ringing alarm ended up handed back to
        // the system timer and fell through to the lock screen.
        .onAppear {
            UIDevice.current.isBatteryMonitoringEnabled = true
            updateIdleTimer()
        }
        .onChange(of: appState.currentScreen) { _, _ in
            updateIdleTimer()
        }
        .onReceive(NotificationCenter.default.publisher(for: UIDevice.batteryStateDidChangeNotification)) { _ in
            updateIdleTimer()
        }
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

    // The alarm holds the display no matter what — it is the one moment the
    // screen must survive. The night screen holds it only while charging, so a
    // phone left off the charger doesn't drain until morning.
    private func updateIdleTimer() {
        let keepAwake: Bool
        switch appState.currentScreen {
        case .alarm:
            keepAwake = true
        case .monitoring:
            let state = UIDevice.current.batteryState
            keepAwake = (state == .charging || state == .full)
        case .setup, .onboarding:
            keepAwake = false
        }
        UIApplication.shared.isIdleTimerDisabled = keepAwake
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState())
}
