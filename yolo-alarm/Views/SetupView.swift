import SwiftUI

struct SetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            SkyBackground(colors: NightSky.colors(NightSky.dusk))

            VStack(spacing: 32) {
                Spacer()

                // App logo
                VStack(spacing: 12) {
                    Image("yolo-logo")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 56)
                        .foregroundColor(NightSky.cream)
                    Text("make the most of today")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.55))
                }

                Spacer()

            // The one nightly input: when do you need to be up?
            VStack(spacing: 18) {
                Text("up by")
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(2.5)
                    .textCase(.uppercase)
                    .foregroundColor(.white.opacity(0.55))

                DatePicker("", selection: $appState.settings.wakeUpBy, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .colorScheme(.dark)
                    .datePickerStyle(.wheel)
                    .frame(height: 110)

                HorizonArc(
                    fadeFraction: fadeFraction,
                    startLabel: "tonight",
                    fadeLabel: fadeLabel,
                    endLabel: upByLabel
                )
                .padding(.horizontal, 4)

                HStack(spacing: 10) {
                    TogglePill(title: "white noise", isOn: $appState.settings.whiteNoiseEnabled)
                        .onChange(of: appState.settings.whiteNoiseEnabled) { _, enabled in
                            // A session with neither white noise nor alarm is nothing
                            if !enabled {
                                appState.settings.alarmEnabled = true
                            }
                        }
                    TogglePill(title: "gentle alarm", isOn: $appState.settings.alarmEnabled)
                        .disabled(!appState.settings.whiteNoiseEnabled)
                        .opacity(appState.settings.whiteNoiseEnabled ? 1 : 0.5)
                }
            }
            .padding(22)
            .background(Color.black.opacity(0.18))
            .cornerRadius(20)

            Spacer()

            // Start button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    appState.recalculateWakeUpBy()
                    appState.startMonitoring()
                }
            }) {
                Text("start the night")
                    .font(.headline)
                    .foregroundColor(Color(red: 0.09, green: 0.13, blue: 0.27))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                    .background(NightSky.cream)
                    .cornerRadius(999)
            }
            .padding(.horizontal, 40)

            // Settings button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    showingSettings = true
                }
            }) {
                HStack {
                    Image(systemName: "gearshape")
                    Text("settings")
                }
                .foregroundColor(.white.opacity(0.55))
            }
            .padding(.bottom, 20)
            }
            .padding()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .presentationDragIndicator(.visible)
        }
    }

    // Fade start as a fraction of tonight (now → up by), for the arc marker
    private var fadeFraction: Double? {
        guard appState.settings.whiteNoiseEnabled else { return nil }
        let night = appState.settings.wakeUpBy.timeIntervalSince(Date())
        guard night > 0 else { return nil }
        let untilFade = appState.fadeStartTime.timeIntervalSince(Date())
        return min(max(untilFade / night, 0.05), 0.95)
    }

    private var fadeLabel: String? {
        guard appState.settings.whiteNoiseEnabled else { return nil }
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm"
        return "fade \(formatter.string(from: appState.fadeStartTime))"
    }

    private var upByLabel: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: appState.settings.wakeUpBy).lowercased()
    }
}

struct TogglePill: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        Button(action: { isOn.toggle() }) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(isOn ? Color(red: 0.09, green: 0.13, blue: 0.27) : .white.opacity(0.55))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(isOn ? NightSky.cream.opacity(0.9) : Color.white.opacity(0.08))
                )
                .overlay(
                    Capsule().stroke(Color.white.opacity(isOn ? 0 : 0.22), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    SetupView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
