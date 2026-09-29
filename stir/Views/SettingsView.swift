import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import os

// Five calm rows; every knob lives one tap deeper
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("night") { NightSettingsView() }
                    NavigationLink("sounds") { SoundsSettingsView() }
                    NavigationLink("wake") { WakeSettingsView() }
                }

                Section {
                    NavigationLink("technical details") {
                        TechnicalDetailsView()
                    }
                } footer: {
                    Text("how the night, the listening, and the rings actually work")
                }

                // About Section
                Section {
                    Link(destination: URL(string: "https://timroman.github.io/stir/")!) {
                        HStack {
                            Text("open source — see how it's built")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                        }
                    }

                    Link(destination: URL(string: "https://timroman.github.io/stir/#privacy")!) {
                        HStack {
                            Text("privacy policy")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                        }
                    }

                    Link(destination: URL(string: "https://www.pureinference.com")!) {
                        HStack {
                            Text("a pure inference build")
                            Spacer()
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                        }
                    }
                } footer: {
                    Text("version \(appVersion)")
                }
            }
            .navigationTitle("settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Night: what plays, and how early stir may wake you

struct NightSettingsView: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        List {
            Section {
                Toggle("white noise", isOn: $appState.settings.whiteNoiseEnabled)
                    .onChange(of: appState.settings.whiteNoiseEnabled) { _, enabled in
                        // A session with neither white noise nor alarm is nothing
                        if !enabled {
                            appState.settings.alarmEnabled = true
                        }
                    }

                Toggle("gentle alarm", isOn: $appState.settings.alarmEnabled)
                    .disabled(!appState.settings.whiteNoiseEnabled)
            } footer: {
                if !appState.settings.alarmEnabled {
                    Text("alarm off: white noise fades to silence at your \"up by\" time — when you don't hear it, it's time. the microphone is never used.")
                } else if !appState.settings.whiteNoiseEnabled {
                    // The toggle above is on but greyed out, which reads as
                    // "unavailable" without this line
                    Text("with white noise off, the gentle alarm stays on — a night needs at least one of the two.")
                }
            }

            Section {
                timelineStepper("wake window", value: $appState.settings.wakeWindowMinutes, range: 10...90,
                                caption: "how early stir may wake you — it listens for this long before your \"up by\" time, and nothing can wake you before it")
            } header: {
                Text("night timeline")
            } footer: {
                Text(timelineExample)
            }
        }
        .navigationTitle("night")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func timelineStepper(_ title: String, value: Binding<Int>, range: ClosedRange<Int>, caption: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Stepper(value: value, in: range, step: 5) {
                HStack {
                    Text(title)
                    Spacer()
                    Text("\(value.wrappedValue) min")
                        .foregroundColor(.gray)
                }
            }
            Text(caption)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    // Tonight's schedule with the current settings, so the controls explain themselves
    private var timelineExample: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        let upBy = formatter.string(from: appState.settings.wakeUpBy).lowercased()
        let fadeStart = formatter.string(from: appState.fadeStartTime).lowercased()
        let fadeEnd = formatter.string(from: appState.whiteNoiseEndTime).lowercased()
        let windowStart = formatter.string(from: appState.windowStart).lowercased()

        if !appState.settings.alarmEnabled {
            return "tonight, with \"up by\" \(upBy): white noise fades from \(fadeStart) and ends at \(upBy) — the silence is your wake-up."
        }
        return "tonight, with \"up by\" \(upBy): white noise fades from \(fadeStart) to \(fadeEnd), the room stays quiet until \(windowStart), then stir listens and the alarm sounds at \(upBy) at the latest."
    }
}

// MARK: - Sounds: sleep + alarm sounds, volumes, import

struct SoundsSettingsView: View {
    @EnvironmentObject var appState: AppState
    @State private var previewPlayer: AVAudioPlayer?

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "speaker.fill").foregroundColor(.gray)
                    Slider(value: $appState.settings.whiteNoiseVolume, in: 0.1...1.0, step: 0.05)
                    Image(systemName: "speaker.wave.3.fill").foregroundColor(.gray)
                }
                ForEach(WhiteNoiseSound.allCases) { sound in
                    selectableRow(sound.displayName,
                                  isSelected: appState.settings.whiteNoiseSound == sound,
                                  onSelect: { appState.settings.whiteNoiseSound = sound },
                                  onPreview: { previewBundled(sound.rawValue, volume: appState.settings.whiteNoiseVolume) })
                }
            } header: {
                Text("sleep sound")
            }

            Section {
                HStack {
                    Image(systemName: "speaker.fill").foregroundColor(.gray)
                    Slider(value: $appState.settings.volume, in: 0.1...1.0, step: 0.05)
                    Image(systemName: "speaker.wave.3.fill").foregroundColor(.gray)
                }
                ForEach(AlarmSound.allCases) { sound in
                    selectableRow(sound.displayName,
                                  isSelected: appState.settings.selectedSound == sound,
                                  onSelect: { appState.settings.selectedSound = sound },
                                  onPreview: { previewBundled(sound.rawValue, volume: appState.settings.volume) })
                }
            } header: {
                Text("alarm sound")
            } footer: {
                Text("preview plays at the volume the alarm will use, through your phone's current volume — if it sounds quiet now, it will be quiet then.")
            }
        }
        .navigationTitle("sounds")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { stopPreview() }
    }

    private func selectableRow(_ name: String, isSelected: Bool, onSelect: @escaping () -> Void, onPreview: @escaping () -> Void) -> some View {
        HStack {
            Button(action: onSelect) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .gray)
                    Text(name)
                        .foregroundColor(.primary)
                }
            }
            .buttonStyle(.plain)

            Spacer()

            Button(action: onPreview) {
                Image(systemName: "play.circle")
                    .font(.title2)
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
        }
    }

    private func previewBundled(_ name: String, volume: Float) {
        stopPreview()
        guard let url = bundledSoundURL(name) else { return }
        playPreview(url: url, volume: volume)
    }

    // An honest preview: the slider's real value through the same .playback
    // session the night uses, so what you hear now is what will play then —
    // at whatever the phone's volume happens to be right now. A fixed 0.6
    // preview made every sound seem fine and taught the slider nothing.
    private func playPreview(url: URL, volume: Float) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            previewPlayer = try AVAudioPlayer(contentsOf: url)
            previewPlayer?.volume = volume
            previewPlayer?.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [self] in
                stopPreview()
            }
        } catch {
            Logger.sounds.error("Failed to preview sound: \(String(describing: error), privacy: .public)")
        }
    }

    private func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
    }
}

// MARK: - Wake: sensitivity, motion, haptics, wake message

struct WakeSettingsView: View {
    @EnvironmentObject var appState: AppState

    private var sensitivity: String {
        appState.settings.sensitivityLabel
    }

    // Sorted by how much of the room's sound comes and goes, not how loud it
    // is: steady sound calibrates into the baseline, and what sets stir off by
    // mistake is sound that arrives and leaves (stir.md decision 59)
    private var sensitivityNote: String {
        switch sensitivity {
        case "low":
            return "for a shared bed, pets, or children nearby. it takes a bigger sound to wake you."
        case "high":
            return "for sleeping alone in a quiet room, or one with steady sound like a fan. it hears you roll over or move the covers."
        default:
            return "for a room with some sound that comes and goes, like occasional traffic or a partner who sleeps still."
        }
    }

    var body: some View {
        List {
            Section {
                Picker("sensitivity", selection: Binding(
                    get: { sensitivity },
                    set: { choice in
                        appState.settings.chooseSensitivity(choice)
                    }
                )) {
                    Text("low").tag("low")
                    Text("medium").tag("medium")
                    Text("high").tag("high")
                }
                .pickerStyle(.segmented)
                .accessibilityIdentifier("wake.sensitivity")
            } header: {
                Text("listening")
            } footer: {
                Text(sensitivityNote)
                    .accessibilityIdentifier("wake.sensitivityNote")
            }

            Section {
                Toggle("motion detection", isOn: $appState.settings.motionDetectionEnabled)
            } footer: {
                // stir hears the room, not a person (stir.md decisions 57, 59)
                Text("motion detection wakes you when the phone moves, whoever moves it. a phone on the nightstand on your side of the bed avoids most of that.")
            }

            Section {
                Toggle("haptics", isOn: $appState.settings.hapticEnabled)
            } header: {
                Text("haptics")
            } footer: {
                Text("the alarm vibrates as well as sounds, rising over the same minute. turn it off if the phone sleeps on something that rattles.")
            }

            Section {
                TextField("your motivation", text: $appState.settings.tagline)
            } header: {
                Text("wake message")
            } footer: {
                Text("shown on the alarm screen when it's time")
            }
        }
        .navigationTitle("wake")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
