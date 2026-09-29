import SwiftUI
import AVFoundation
import os

// Two rows, one per half of the night: what plays while you fall asleep, and
// how you are brought out of it. Settings used to be split by kind — a "sounds"
// screen holding both — which meant setting up your sleep sound took two
// screens and the only thing binding them was that both were sounds.
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink("night") { NightSettingsView() }
                    NavigationLink("wake") { WakeSettingsView() }
                } footer: {
                    // Belongs to neither half, and describes both
                    Text(timelineExample)
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

    // Tonight's schedule with the current settings, so the settings explain
    // themselves without anybody having to assemble the timeline in their head
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
        if !appState.settings.whiteNoiseEnabled {
            return "tonight, with \"up by\" \(upBy): stir listens from \(windowStart), and the alarm sounds at \(upBy) at the latest."
        }
        return "tonight, with \"up by\" \(upBy): white noise fades from \(fadeStart) to \(fadeEnd), the room stays quiet until \(windowStart), then stir listens and the alarm sounds at \(upBy) at the latest."
    }
}

// MARK: - Night: what plays while you fall asleep

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
            } footer: {
                if appState.settings.whiteNoiseEnabled {
                    Text("plays all night and fades to silence before stir starts listening.")
                } else {
                    // The constraint is easy to miss now that the two toggles
                    // live on different screens
                    Text("with white noise off, the gentle alarm stays on — a night needs at least one of the two.")
                }
            }

            if appState.settings.whiteNoiseEnabled {
                Section {
                    NavigationLink {
                        SoundListView(title: "sleep sound",
                                      footer: "preview plays at the volume it will use tonight.",
                                      options: WhiteNoiseSound.allCases.map { ($0.rawValue, $0.displayName) },
                                      selectedId: Binding(
                                        get: { appState.settings.whiteNoiseSound.rawValue },
                                        set: { id in
                                            if let sound = WhiteNoiseSound(rawValue: id) {
                                                appState.settings.whiteNoiseSound = sound
                                            }
                                        }),
                                      volume: $appState.settings.whiteNoiseVolume)
                    } label: {
                        LabeledContent("sleep sound", value: appState.settings.whiteNoiseSound.displayName)
                    }
                }
            }
        }
        .navigationTitle("night")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Wake: how stir brings you out of it

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

            if appState.settings.alarmEnabled {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        Stepper(value: $appState.settings.wakeWindowMinutes, in: 10...90, step: 5) {
                            HStack {
                                Text("wake window")
                                Spacer()
                                Text("\(appState.settings.wakeWindowMinutes) min")
                                    .foregroundColor(.gray)
                            }
                        }
                        Text("how early stir may wake you — it listens for this long before your \"up by\" time, and nothing can wake you before it")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("when")
                }

                Section {
                    NavigationLink {
                        SoundListView(title: "alarm sound",
                                      footer: "preview plays at the volume the alarm will use, through your phone's current volume — if it sounds quiet now, it will be quiet then.",
                                      options: AlarmSound.allCases.map { ($0.rawValue, $0.displayName) },
                                      selectedId: Binding(
                                        get: { appState.settings.selectedSound.rawValue },
                                        set: { id in
                                            if let sound = AlarmSound(rawValue: id) {
                                                appState.settings.selectedSound = sound
                                            }
                                        }),
                                      volume: $appState.settings.volume)
                    } label: {
                        LabeledContent("alarm sound", value: appState.settings.selectedSound.displayName)
                    }
                }

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
        }
        .navigationTitle("wake")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - One sound list and its volume, shared by both halves of the night
//
// A screen rather than a section: eleven wake tones inline pushed everything
// below them out of reach, and a lazy list does not even build what is off
// screen — which is how a UI test found this.

private struct SoundListView: View {
    let title: String
    let footer: String
    let options: [(id: String, name: String)]
    @Binding var selectedId: String
    @Binding var volume: Float

    @State private var previewPlayer: AVAudioPlayer?

    var body: some View {
        List {
            Section {
                HStack {
                    Image(systemName: "speaker.fill").foregroundColor(.gray)
                    Slider(value: $volume, in: 0.1...1.0, step: 0.05)
                    Image(systemName: "speaker.wave.3.fill").foregroundColor(.gray)
                }

                ForEach(options, id: \.id) { option in
                    HStack {
                        Button(action: { selectedId = option.id }) {
                            HStack {
                                Image(systemName: selectedId == option.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundColor(selectedId == option.id ? .blue : .gray)
                                Text(option.name)
                                    .foregroundColor(.primary)
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button(action: { preview(option.id) }) {
                            Image(systemName: "play.circle")
                                .font(.title2)
                                .foregroundColor(.blue)
                        }
                        .buttonStyle(.plain)
                    }
                }
            } footer: {
                Text(footer)
            }
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { stopPreview() }
    }

    // An honest preview: the slider's real value through the same .playback
    // session the night uses, so what you hear now is what will play then —
    // at whatever the phone's volume happens to be right now. A fixed 0.6
    // preview made every sound seem fine and taught the slider nothing.
    private func preview(_ name: String) {
        stopPreview()
        guard let url = bundledSoundURL(name) else { return }
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            previewPlayer = try AVAudioPlayer(contentsOf: url)
            previewPlayer?.volume = volume
            previewPlayer?.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) {
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

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
