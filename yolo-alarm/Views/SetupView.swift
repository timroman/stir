import SwiftUI

struct SetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingSettings = false

    var body: some View {
        ZStack {
            AppGradient.meshBackground(for: appState.settings.colorTheme)

            VStack(spacing: 40) {
                Spacer()

                // App logo
                VStack(spacing: 12) {
                    Image("yolo-logo")
                        .renderingMode(.template)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 70)
                        .foregroundColor(.white)
                    Text("make the most of today")
                        .font(.subheadline)
                        .foregroundColor(.gray)
                }

                Spacer()

            // The one nightly input: when do you need to be up?
            VStack(spacing: 20) {
                Text("up by")
                    .font(.headline)
                    .foregroundColor(.gray)

                DatePicker("", selection: $appState.settings.wakeUpBy, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .colorScheme(.dark)
                    .datePickerStyle(.wheel)
                    .frame(height: 120)

                VStack(spacing: 12) {
                    Toggle("white noise", isOn: $appState.settings.whiteNoiseEnabled)
                        .onChange(of: appState.settings.whiteNoiseEnabled) { _, enabled in
                            // A session with neither white noise nor alarm is nothing
                            if !enabled {
                                appState.settings.alarmEnabled = true
                            }
                        }

                    Toggle("gentle alarm", isOn: $appState.settings.alarmEnabled)
                        .disabled(!appState.settings.whiteNoiseEnabled)
                }
                .foregroundColor(.white.opacity(0.8))
                .tint(.white.opacity(0.4))

                Text(appState.timelinePreview)
                    .font(.caption)
                    .foregroundColor(.gray)
                    .multilineTextAlignment(.center)
            }
            .padding(24)
            .background(Color.white.opacity(0.05))
            .cornerRadius(16)

            Spacer()

            // Start button
            Button(action: {
                withAnimation(.easeInOut(duration: 0.3)) {
                    appState.recalculateWakeUpBy()
                    appState.startMonitoring()
                }
            }) {
                Text("start")
                    .font(.title2.bold())
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                    .background(Color.white)
                    .cornerRadius(16)
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
                .foregroundColor(.gray)
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
