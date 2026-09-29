import SwiftUI
import AVFoundation
import os

// One screen. Everything that decides how a night goes is here, in the order a
// night happens: what plays while you fall asleep, then how you are brought out
// of it. Splitting that across two screens gave one of them two rows and the
// other eight, and asked for a tap to reach either. The only thing still a tap
// away is a sound list, because eleven tones inline push everything under them
// off the screen (stir.md decision 77).
struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

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
        NavigationStack {
            List {
                // MARK: night — what plays while you fall asleep
                Section {
                    Toggle("white noise", isOn: $appState.settings.whiteNoiseEnabled)
                        .onChange(of: appState.settings.whiteNoiseEnabled) { _, enabled in
                            // A night with neither white noise nor alarm is nothing
                            if !enabled {
                                appState.settings.alarmEnabled = true
                            }
                        }

                    if appState.settings.whiteNoiseEnabled {
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
                            LabeledContent("sound", value: appState.settings.whiteNoiseSound.displayName)
                        }
                    }
                } header: {
                    Text("night")
                } footer: {
                    if !appState.settings.whiteNoiseEnabled {
                        Text("with white noise off, the alarm stays on — a night needs at least one of the two.")
                    }
                }

                // MARK: wake — how stir brings you out of it
                Section {
                    Toggle("alarm", isOn: $appState.settings.alarmEnabled)
                        .disabled(!appState.settings.whiteNoiseEnabled)

                    if appState.settings.alarmEnabled {
                        VStack(alignment: .leading, spacing: 4) {
                            Stepper(value: $appState.settings.wakeWindowMinutes, in: 10...90, step: 5) {
                                HStack {
                                    Text("wake window")
                                    Spacer()
                                    Text("\(appState.settings.wakeWindowMinutes) min")
                                        .foregroundColor(.gray)
                                }
                            }
                            Text("how early stir may wake you")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

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
                            LabeledContent("sound", value: appState.settings.selectedSound.displayName)
                        }

                        Picker("sensitivity", selection: Binding(
                            get: { sensitivity },
                            set: { choice in appState.settings.chooseSensitivity(choice) }
                        )) {
                            Text("low").tag("low")
                            Text("medium").tag("medium")
                            Text("high").tag("high")
                        }
                        .pickerStyle(.segmented)
                        .accessibilityIdentifier("wake.sensitivity")

                        Text(sensitivityNote)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .accessibilityIdentifier("wake.sensitivityNote")

                        // stir hears the room, not a person (stir.md decisions 57, 59)
                        ExplainedToggle(label: "wake if the phone moves",
                                        isOn: $appState.settings.motionDetectionEnabled,
                                        detail: "anyone moving the phone sets off the alarm, not just you. keeping it on the nightstand, on your side of the bed, avoids most of that.")

                        ExplainedToggle(label: "vibration",
                                        isOn: $appState.settings.hapticEnabled,
                                        detail: "the alarm vibrates as well as sounds, rising over the same minute. turn it off if the phone sleeps on something that rattles.")

                        TextField("wake message", text: $appState.settings.tagline)
                    }
                } header: {
                    Text("wake")
                } footer: {
                    if !appState.settings.alarmEnabled {
                        Text("alarm off: white noise fades to silence at your \"up by\" time — when you don't hear it, it's time. the microphone is never used.")
                    } else if !appState.settings.whiteNoiseEnabled {
                        // The toggle above is on but greyed out, which reads as
                        // "unavailable" without this line
                        Text("with white noise off, the alarm stays on — a night needs at least one of the two.")
                    } else {
                        Text(timelineExample)
                    }
                }

                Section {
                    NavigationLink("technical details") {
                        TechnicalDetailsView()
                    }
                } footer: {
                    Text("how the night, the listening, and the rings actually work")
                }

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

        return "tonight, with \"up by\" \(upBy): white noise fades from \(fadeStart) to \(fadeEnd), the room stays quiet until \(windowStart), then stir listens and the alarm sounds at \(upBy) at the latest."
    }
}

// MARK: - A toggle whose explanation is one tap away, not under every row
//
// A paragraph under each switch turned the screen into a wall of prose. The
// label says what it does; the button says why you might care.

private struct ExplainedToggle: View {
    let label: String
    @Binding var isOn: Bool
    let detail: String

    @State private var showingDetail = false

    var body: some View {
        HStack(spacing: 8) {
            Toggle(label, isOn: $isOn)

            Button {
                showingDetail = true
            } label: {
                Image(systemName: "info.circle")
                    .foregroundColor(.blue)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("about \(label)")
        }
        .alert(label, isPresented: $showingDetail) {
            Button("ok") { }
        } message: {
            Text(detail)
        }
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
