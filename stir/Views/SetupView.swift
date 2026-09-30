import SwiftUI
import AVFoundation
import os

struct SetupView: View {
    @EnvironmentObject var appState: AppState
    @State private var showingSettings = false
    @State private var showingStartWarning = false
    @State private var systemVolumePercent = 0
    @State private var batteryPercent = 0
    @State private var startWarnings: NightStartCheck.Warnings = []

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
            .accessibilityIdentifier("setup.start")

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
            .accessibilityIdentifier("setup.settings")
            }
            .padding()
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
                .presentationDragIndicator(.visible)
        }
        .alert(startWarningTitle, isPresented: $showingStartWarning) {
            Button("start anyway") { startNight(force: true) }
            Button("not yet", role: .cancel) { }
        } message: {
            Text(startWarningMessage)
        }
    }

    private var startWarningTitle: String {
        if startWarnings.contains(.lowBattery) && startWarnings.contains(.lowVolume) {
            return "before you start"
        }
        return startWarnings.contains(.lowBattery) ? "your battery is low" : "your volume is low"
    }

    private var startWarningMessage: String {
        var lines: [String] = []
        if startWarnings.contains(.lowBattery) {
            lines.append("your phone is at \(batteryPercent)% and isn't charging. if it dies overnight, neither the alarm nor the backup alarm can wake you. plug it in, then start again.")
        }
        if startWarnings.contains(.lowVolume) {
            lines.append("your volume is at \(systemVolumePercent)% — the alarm may not be loud enough to wake you. raise it with the volume buttons, then start again.")
        }
        return lines.joined(separator: "\n\n")
    }

    // The last moment you're awake and holding the phone is the only moment a
    // low media volume can still be fixed. Checked here rather than at "up by",
    // when you're asleep and nothing can be done about it.
    private func startNight(force: Bool) {
        if !force {
            UIDevice.current.isBatteryMonitoringEnabled = true
            let level = UIDevice.current.batteryLevel
            let state = UIDevice.current.batteryState
            let volume = currentSystemVolume()
            let warnings = NightStartCheck.warnings(
                alarmEnabled: appState.settings.alarmEnabled,
                whiteNoiseEnabled: appState.settings.whiteNoiseEnabled,
                volume: volume,
                batteryLevel: level,
                isCharging: state == .charging || state == .full
            )
            if !warnings.isEmpty {
                systemVolumePercent = Int(((volume ?? 0) * 100).rounded())
                batteryPercent = Int((level * 100).rounded())
                startWarnings = warnings
                showingStartWarning = true
                return
            }
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
            Logger.session.error("⚠️ Could not read system volume: \(String(describing: error), privacy: .public)")
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
