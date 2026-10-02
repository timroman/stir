import SwiftUI
import AVFoundation
import os

// Settings on stir's own ground: the night sky behind it, moonlight cream type,
// amber switches, and the app's own icon at the head of it. The depth — how a
// night runs, how the listening works — lives on the website; what stays here
// is what only the phone knows (stir.md decisions 77, 78, 79).
//
// Native List, controls and separators underneath the paint: the styling is
// ours, the behaviour and accessibility stay Apple's.
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
            .navigationTitle("stir")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.hidden, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - the icon, what stir does, and what it costs

    private var masthead: some View {
        Section {
            VStack(spacing: 14) {
                if let icon = Bundle.main.appIcon {
                    Image(uiImage: icon)
                        .resizable()
                        .frame(width: 68, height: 68)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 15, style: .continuous)
                                .stroke(NightSky.cream.opacity(0.12), lineWidth: 0.5)
                        )
                        .accessibilityHidden(true)
                }

                Text("you set one time: when you need to be up by. everything else counts back from it, and the wake window is how long stir listens for you before it.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(NightSky.cream.opacity(0.7))
                    .lineSpacing(2)

                Text("free, open source, no accounts, no analytics. built at [pure inference](https://www.pureinference.com): simple software should be good value without a subscription, and your data should never be the thing that pays for it.")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(NightSky.cream.opacity(0.5))
                    .tint(NightSky.dawnAmber)
                    .lineSpacing(2)

                // One Text rather than a row of links, so four of them wrap
                // instead of squeezing on a narrow phone
                Text("[how it works](https://timroman.github.io/stir/#how) · [source](https://github.com/timroman/stir) · [privacy](https://timroman.github.io/stir/#privacy) · [our other apps](https://www.pureinference.com)")
                    .font(.footnote)
                    .multilineTextAlignment(.center)
                    .tint(NightSky.dawnAmber)

                Text("version \(appVersion)")
                    .font(.caption2)
                    .foregroundStyle(NightSky.cream.opacity(0.28))
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 2)
            .padding(.bottom, 14)
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
        }
    }

    // MARK: - last night, the one thing only the phone knows

    @ViewBuilder
    private var lastNight: some View {
        if let last = SessionRecord.last {
            Section {
                ValueRow("started", value: last.startedText)
                ValueRow("alarm", value: last.alarmText)
                ValueRow("ended", value: last.endedText)
                ValueRow("ran", value: last.lengthText)
                ValueRow("how", value: last.ending.label)
            } header: {
                SectionHeader("last night")
            }
            .listRowBackground(NightSky.surface)
        }
    }

    // MARK: - night: what plays while you fall asleep

    private var nightSection: some View {
        Section {
            ToggleRow("white noise", isOn: $appState.settings.whiteNoiseEnabled)
                .onChange(of: appState.settings.whiteNoiseEnabled) { _, enabled in
                    // A night with neither white noise nor alarm is nothing
                    if !enabled {
                        appState.settings.alarmEnabled = true
                    }
                }

            if appState.settings.whiteNoiseEnabled {
                NavigationLink {
                    SoundListView(title: "sleep sound",
                                  note: "preview plays at the volume it will use tonight.",
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
                    ValueRow("sound", value: appState.settings.whiteNoiseSound.displayName)
                }
            } else {
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
            ToggleRow("alarm", isOn: $appState.settings.alarmEnabled)
                .disabled(!appState.settings.whiteNoiseEnabled)

            if appState.settings.alarmEnabled {
                HStack(spacing: 8) {
                    RowLabel("wake window", detail: Explanation(
                        title: "wake window",
                        body: "stir listens for this long before your \"up by\" time, and wakes you on the first stirring it hears.\n\nit is also the earliest you can be woken: nothing happens before the window opens."
                    ))
                    Spacer(minLength: 8)
                    Text("\(appState.settings.wakeWindowMinutes) min")
                        .foregroundStyle(NightSky.cream.opacity(0.5))
                        .monospacedDigit()
                    Stepper("", value: $appState.settings.wakeWindowMinutes, in: 10...90, step: 5)
                        .labelsHidden()
                        .accessibilityIdentifier("wake.window")
                }

                NavigationLink {
                    SoundListView(title: "alarm sound",
                                  note: "preview plays at the volume the alarm will use, through your phone's current volume — if it sounds quiet now, it will be quiet then.",
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
                    ValueRow("sound", value: appState.settings.selectedSound.displayName)
                }

                NavigationLink {
                    SensitivityView()
                } label: {
                    ValueRow("sensitivity", value: appState.settings.sensitivityLabel)
                }
                .accessibilityIdentifier("wake.sensitivity")

                ToggleRow("wake if the phone moves",
                          isOn: $appState.settings.motionDetectionEnabled,
                          detail: Explanation(
                            title: "wake if the phone moves",
                            // stir hears the room, not a person (decisions 57, 59)
                            body: "anyone moving the phone sets off the alarm, not just you. keeping it on the nightstand, on your side of the bed, avoids most of that."))

                ToggleRow("vibration",
                          isOn: $appState.settings.hapticEnabled,
                          detail: Explanation(
                            title: "vibration",
                            body: "the alarm vibrates as well as sounds, rising over the same minute. turn it off if the phone sleeps on something that rattles."))

                // Its own row: a message worth writing runs longer than the
                // space left beside a label
                VStack(alignment: .leading, spacing: 6) {
                    Text("wake message")
                        .foregroundStyle(NightSky.cream)
                    TextField("good morning", text: $appState.settings.tagline, axis: .vertical)
                        .lineLimit(1...3)
                        .foregroundStyle(NightSky.cream.opacity(0.65))
                        .textFieldStyle(.plain)
                }
                .padding(.vertical, 2)

                if appState.settings.whiteNoiseEnabled {
                    NoteRow(timelineExample)
                } else {
                    NoteRow("with white noise off, the alarm stays on — a night needs at least one of the two.")
                }
            } else {
                NoteRow("alarm off: white noise fades to silence at your \"up by\" time — when you don't hear it, it's time. the microphone is never used.")
            }
        } header: {
            SectionHeader("wake")
        }
        .listRowBackground(NightSky.surface)
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

extension Bundle {
    /// The app's own icon, for the head of settings. iOS keeps it in the bundle
    /// under the name the asset catalogue generated rather than as an asset you
    /// can name directly.
    var appIcon: UIImage? {
        guard let icons = infoDictionary?["CFBundleIcons"] as? [String: Any],
              let primary = icons["CFBundlePrimaryIcon"] as? [String: Any],
              let files = primary["CFBundleIconFiles"] as? [String],
              let name = files.last else { return nil }
        return UIImage(named: name)
    }
}

private struct SectionHeader: View {
    let title: String

    init(_ title: String) { self.title = title }

    var body: some View {
        Text(title)
            .font(.caption)
            .tracking(1.4)
            .textCase(nil)   // lowercase, like every other word stir shows
            .foregroundStyle(NightSky.cream.opacity(0.4))
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

/// A label with its explanation beside it, rather than in a column of its own —
/// most rows have nothing to explain, and an empty column down the left is a
/// column of nothing.
private struct RowLabel: View {
    let title: String
    let detail: Explanation?

    @State private var showingDetail = false

    init(_ title: String, detail: Explanation? = nil) {
        self.title = title
        self.detail = detail
    }

    var body: some View {
        HStack(spacing: 6) {
            Text(title)
                .foregroundStyle(NightSky.cream)

            if let detail {
                Button {
                    showingDetail = true
                } label: {
                    Image(systemName: "info.circle")
                        .font(.footnote)
                        .foregroundStyle(NightSky.dawnAmber)
                        // Wide enough to hit, short enough not to stretch the
                        // row past the ones with nothing to explain
                        .frame(width: 44, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("about \(title)")
                .alert(detail.title, isPresented: $showingDetail) {
                    Button("ok") { }
                } message: {
                    Text(detail.body)
                }
            }
        }
    }
}

private struct ToggleRow: View {
    let title: String
    @Binding var isOn: Bool
    let detail: Explanation?

    init(_ title: String, isOn: Binding<Bool>, detail: Explanation? = nil) {
        self.title = title
        self._isOn = isOn
        self.detail = detail
    }

    var body: some View {
        HStack(spacing: 8) {
            RowLabel(title, detail: detail)
            Spacer(minLength: 8)
            Toggle("", isOn: $isOn)
                .labelsHidden()
                .accessibilityLabel(title)
        }
    }
}

private struct ValueRow: View {
    let title: String
    let value: String

    init(_ title: String, value: String) {
        self.title = title
        self.value = value
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(title)
                .foregroundStyle(NightSky.cream)
            Spacer(minLength: 8)
            Text(value)
                .foregroundStyle(NightSky.cream.opacity(0.5))
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
    let note: String
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

                    NoteRow(note)
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
