import SwiftUI
import AVFoundation
import os

// Settings on stir's own ground: the night sky behind it, moonlight cream type,
// amber switches. It opens by saying what stir does — the wake window is the
// whole idea, and this is the only screen with room to explain it — and closes
// with who built it and why it costs nothing.
//
// Native List, controls and separators underneath the paint: the styling is
// ours, the behaviour and accessibility stay Apple's (stir.md decisions 77, 78).
struct SettingsView: View {
    @EnvironmentObject var appState: AppState

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    var body: some View {
        NavigationStack {
            ZStack {
                SkyBackground(colors: NightSky.colors(NightSky.deepNight))
                    .ignoresSafeArea()

                List {
                    masthead
                    lastNight
                    nightSection
                    wakeSection
                }
                .scrollContentBackground(.hidden)
                .listRowSeparatorTint(NightSky.cream.opacity(0.1))
                .tint(NightSky.dawnAmber)
            }
            .navigationTitle("settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - who it is, what it does, what it costs — all at the top

    private var masthead: some View {
        Section {
            VStack(spacing: 14) {
                Text("stir")
                    .font(.title3)
                    .tracking(6)
                    .foregroundStyle(NightSky.cream.opacity(0.85))

                Text("you set one time: when you need to be up by. everything else counts back from it, and the wake window is how long stir listens for you before it.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(NightSky.cream.opacity(0.7))
                    .lineSpacing(2)

                Text("free, open source, no accounts, no analytics. built at pure inference, where we think software this small should cost nothing.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(NightSky.cream.opacity(0.5))
                    .lineSpacing(2)

                HStack(spacing: 14) {
                    Link("how it works", destination: URL(string: "https://timroman.github.io/stir/#how")!)
                    Link("source", destination: URL(string: "https://github.com/timroman/stir")!)
                    Link("privacy", destination: URL(string: "https://timroman.github.io/stir/#privacy")!)
                }
                .font(.footnote)
                .foregroundStyle(NightSky.dawnAmber)

                Text("version \(appVersion) · pureinference.com")
                    .font(.caption2)
                    .foregroundStyle(NightSky.cream.opacity(0.28))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    // MARK: - night: what plays while you fall asleep

    private var nightSection: some View {
        Section {
            SettingRow {
                Toggle("white noise", isOn: $appState.settings.whiteNoiseEnabled)
                    .onChange(of: appState.settings.whiteNoiseEnabled) { _, enabled in
                        // A night with neither white noise nor alarm is nothing
                        if !enabled {
                            appState.settings.alarmEnabled = true
                        }
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
                    SettingRow {
                        LabeledContent("sound", value: appState.settings.whiteNoiseSound.displayName)
                    }
                }
            }
            if !appState.settings.whiteNoiseEnabled {
                NoteRow("with white noise off, the alarm stays on — a night needs at least one of the two.")
            }
        } header: {
            SectionHeader("night")
        }
        .listRowBackground(NightSky.surface)
    }

    // MARK: - wake: how stir brings you out of it

    private var wakeSection: some View {
        Section {
            SettingRow {
                Toggle("alarm", isOn: $appState.settings.alarmEnabled)
                    .disabled(!appState.settings.whiteNoiseEnabled)
            }

            if appState.settings.alarmEnabled {
                SettingRow(detail: Explanation(
                    title: "wake window",
                    body: "stir listens for this long before your \"up by\" time, and wakes you on the first stirring it hears.\n\nit is also the earliest you can be woken: nothing happens before the window opens."
                )) {
                    Stepper(value: $appState.settings.wakeWindowMinutes, in: 10...90, step: 5) {
                        LabeledContent("wake window", value: "\(appState.settings.wakeWindowMinutes) min")
                    }
                    .accessibilityIdentifier("wake.window")
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
                    SettingRow {
                        LabeledContent("sound", value: appState.settings.selectedSound.displayName)
                    }
                }

                NavigationLink {
                    SensitivityView()
                } label: {
                    SettingRow {
                        LabeledContent("sensitivity", value: appState.settings.sensitivityLabel)
                    }
                }
                .accessibilityIdentifier("wake.sensitivity")

                SettingRow(detail: Explanation(
                    title: "wake if the phone moves",
                    // stir hears the room, not a person (stir.md decisions 57, 59)
                    body: "anyone moving the phone sets off the alarm, not just you. keeping it on the nightstand, on your side of the bed, avoids most of that."
                )) {
                    Toggle("wake if the phone moves", isOn: $appState.settings.motionDetectionEnabled)
                }

                SettingRow(detail: Explanation(
                    title: "vibration",
                    body: "the alarm vibrates as well as sounds, rising over the same minute. turn it off if the phone sleeps on something that rattles."
                )) {
                    Toggle("vibration", isOn: $appState.settings.hapticEnabled)
                }

                SettingRow {
                    LabeledContent("wake message") {
                        TextField("good morning", text: $appState.settings.tagline)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(NightSky.cream.opacity(0.6))
                    }
                }
            }
            if !appState.settings.alarmEnabled {
                NoteRow("alarm off: white noise fades to silence at your \"up by\" time — when you don't hear it, it's time. the microphone is never used.")
            } else if !appState.settings.whiteNoiseEnabled {
                NoteRow("with white noise off, the alarm stays on — a night needs at least one of the two.")
            } else {
                NoteRow(timelineExample)
            }
        } header: {
            SectionHeader("wake")
        }
        .listRowBackground(NightSky.surface)
    }

    // MARK: - last night, the one thing only the phone knows

    @ViewBuilder
    private var lastNight: some View {
        if let last = SessionRecord.last {
            Section {
                NoteRow("the night ran \(last.lengthText).")
                SettingRow { LabeledContent("started", value: last.startedText) }
                SettingRow { LabeledContent("alarm", value: last.alarmText) }
                SettingRow { LabeledContent("ended", value: last.endedText) }
                SettingRow { LabeledContent("how", value: last.ending.label) }
            } header: {
                SectionHeader("last night")
            }
            .listRowBackground(NightSky.surface)
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

        return "tonight, up by \(upBy) — white noise fades \(fadeStart) to \(fadeEnd), the room stays quiet until \(windowStart), then stir listens."
    }
}

// MARK: - The pieces every row is built from

private struct SectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.caption)
            .tracking(1.6)
            .textCase(.uppercase)
            .foregroundStyle(NightSky.cream.opacity(0.38))
    }
}

/// A line of explanation that belongs to the rows around it, so it sits on the
/// same card rather than floating on the sky underneath.
private struct NoteRow: View {
    let text: String

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(NightSky.cream.opacity(0.5))
            .lineSpacing(1)
            .padding(.vertical, 2)
            .listRowSeparator(.hidden)
    }
}

/// What an information button says when tapped.
struct Explanation {
    let title: String
    let body: String
}

/// A row in stir's colours, with its explanation on the left where a thumb can
/// reach it — beside the label, not jammed against the switch.
private struct SettingRow<Content: View>: View {
    let detail: Explanation?
    let content: Content

    @State private var showingDetail = false

    init(detail: Explanation? = nil, @ViewBuilder content: () -> Content) {
        self.detail = detail
        self.content = content()
    }

    var body: some View {
        HStack(spacing: 12) {
            if let detail {
                Button {
                    showingDetail = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.body)
                        .foregroundStyle(NightSky.dawnAmber)
                        .frame(width: 30, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("about \(detail.title)")
            } else {
                // Keeps every label on the same line, explained or not
                Color.clear.frame(width: 30, height: 1)
            }

            content
                .foregroundStyle(NightSky.cream)
        }
        .alert(detail?.title ?? "", isPresented: $showingDetail) {
            Button("ok") { }
        } message: {
            Text(detail?.body ?? "")
        }
    }
}

// MARK: - Sensitivity, with all three described in one place

struct SensitivityView: View {
    @EnvironmentObject var appState: AppState

    // Sorted by how much of the room's sound comes and goes, not how loud it
    // is: steady sound calibrates into the baseline, and what sets stir off by
    // mistake is sound that arrives and leaves (stir.md decision 59)
    private let choices: [(id: String, note: String)] = [
        ("low", "for a shared bed, pets, or children nearby. it takes a bigger sound to wake you."),
        ("medium", "for a room with some sound that comes and goes, like occasional traffic or a partner who sleeps still."),
        ("high", "for sleeping alone in a quiet room, or one with steady sound like a fan. it hears you roll over or move the covers.")
    ]

    var body: some View {
        ZStack {
            SkyBackground(colors: NightSky.colors(NightSky.deepNight))
                .ignoresSafeArea()

            List {
                Section {
                    ForEach(choices, id: \.id) { choice in
                        Button {
                            appState.settings.chooseSensitivity(choice.id)
                        } label: {
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Image(systemName: appState.settings.sensitivityLabel == choice.id ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(appState.settings.sensitivityLabel == choice.id ? NightSky.dawnAmber : NightSky.cream.opacity(0.3))
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(choice.id)
                                        .foregroundStyle(NightSky.cream)
                                    Text(choice.note)
                                        .font(.caption)
                                        .foregroundStyle(NightSky.cream.opacity(0.5))
                                        .accessibilityIdentifier("sensitivity.note.\(choice.id)")
                                }
                            }
                            .padding(.vertical, 4)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("sensitivity.\(choice.id)")
                    }
                    NoteRow("stir measures your room when the window opens and listens for sound above it. sensitivity is how far above.")
                }
                .listRowBackground(NightSky.surface)
            }
            .scrollContentBackground(.hidden)
            .listRowSeparatorTint(NightSky.cream.opacity(0.1))
        }
        .navigationTitle("sensitivity")
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
        ZStack {
            SkyBackground(colors: NightSky.colors(NightSky.deepNight))
                .ignoresSafeArea()

            List {
                Section {
                    HStack {
                        Image(systemName: "speaker.fill").foregroundStyle(NightSky.cream.opacity(0.4))
                        Slider(value: $volume, in: 0.1...1.0, step: 0.05)
                        Image(systemName: "speaker.wave.3.fill").foregroundStyle(NightSky.cream.opacity(0.4))
                    }

                    ForEach(options, id: \.id) { option in
                        HStack {
                            Button(action: { selectedId = option.id }) {
                                HStack {
                                    Image(systemName: selectedId == option.id ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(selectedId == option.id ? NightSky.dawnAmber : NightSky.cream.opacity(0.3))
                                    Text(option.name)
                                        .foregroundStyle(NightSky.cream)
                                }
                            }
                            .buttonStyle(.plain)

                            Spacer()

                            Button(action: { preview(option.id) }) {
                                Image(systemName: "play.circle")
                                    .font(.title2)
                                    .foregroundStyle(NightSky.dawnAmber)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    NoteRow(footer)
                }
                .listRowBackground(NightSky.surface)
            }
            .scrollContentBackground(.hidden)
            .listRowSeparatorTint(NightSky.cream.opacity(0.1))
            .tint(NightSky.dawnAmber)
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
