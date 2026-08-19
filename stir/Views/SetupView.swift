import SwiftUI
import AVFoundation

struct SetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingSettings = false
    @State private var showingLowVolume = false
    @State private var systemVolumePercent = 0

    // Below this, a gentle alarm ramping up from silence has no chance of
    // being heard. Media volume is the one thing stir can read but not set.
    private let lowVolumeThreshold: Float = 0.3

    var body: some View {
        ZStack {
            SpaceBackground()

            VStack(spacing: 0) {
                // Wordmark + the one question
                VStack(spacing: 12) {
                    Text("stir")
                        .font(.system(size: 44, weight: .light))
                        .kerning(1.5)
                        .foregroundColor(NightSky.cream)
                    Text("when do you want to be up by?")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.55))
                }
                .padding(.top, 72)

                Spacer()

                DatePicker("", selection: $appState.settings.wakeUpBy, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .colorScheme(.dark)
                    .datePickerStyle(.wheel)
                    .frame(height: 130)

                Spacer()

            // Start button
            Button(action: {
                startNight(force: false)
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
            .padding(.bottom, 12)

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
        .alert("your volume is low", isPresented: $showingLowVolume) {
            Button("start anyway") { startNight(force: true) }
            Button("not yet", role: .cancel) { }
        } message: {
            Text("your phone is at \(systemVolumePercent)% — the alarm may not be loud enough to wake you. raise it with the volume buttons, then start again.")
        }
    }

    // The last moment you're awake and holding the phone is the only moment a
    // low media volume can still be fixed. Checked here rather than at "up by",
    // when you're asleep and nothing can be done about it.
    private func startNight(force: Bool) {
        if !force, appState.settings.alarmEnabled, let volume = currentSystemVolume(),
           volume < lowVolumeThreshold {
            systemVolumePercent = Int((volume * 100).rounded())
            showingLowVolume = true
            return
        }
        withAnimation(.easeInOut(duration: 0.3)) {
            appState.recalculateWakeUpBy()
            appState.startMonitoring()
        }
    }

    // outputVolume only reports meaningfully on an active session, so activate
    // one first — .mixWithOthers so this never interrupts whatever is playing
    private func currentSystemVolume() -> Float? {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
        } catch {
            print("⚠️ Could not read system volume: \(error)")
            return nil
        }
        return session.outputVolume
    }
}

#Preview {
    SetupView()
        .environmentObject(AppState())
        .preferredColorScheme(.dark)
}
