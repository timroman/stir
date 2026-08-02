import SwiftUI

struct SetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            SkyBackground(colors: NightSky.colors(NightSky.dusk))

            VStack(spacing: 40) {
                Spacer()

                // Wordmark
                VStack(spacing: 10) {
                    Text("stir")
                        .font(.system(size: 44, weight: .light))
                        .kerning(1.5)
                        .foregroundColor(NightSky.cream)
                    Text("the world's most gentle alarm")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.55))
                }

                Spacer()

            // The one nightly input: when do you need to be up?
            VStack(spacing: 52) {
                Text("up by")
                    .font(.system(size: 12, weight: .semibold))
                    .kerning(2.5)
                    .textCase(.uppercase)
                    .foregroundColor(.white.opacity(0.55))

                DatePicker("", selection: $appState.settings.wakeUpBy, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .colorScheme(.dark)
                    .datePickerStyle(.wheel)
                    .frame(height: 130)
            }

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
}

#Preview {
    SetupView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
