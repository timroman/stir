import SwiftUI
import AVFoundation
import UniformTypeIdentifiers

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

// MARK: - Night: toggles + timeline presets

private enum TimelinePreset: String, CaseIterable, Identifiable {
    case gentle, quick, custom
    var id: String { rawValue }

    // (fade, gap, window)
    static let gentleValues = (10, 30, 30)
    static let quickValues = (5, 5, 15)

    static func match(fade: Int, gap: Int, window: Int) -> TimelinePreset {
        if (fade, gap, window) == gentleValues { return .gentle }
        if (fade, gap, window) == quickValues { return .quick }
        return .custom
    }
}

struct NightSettingsView: View {
    @EnvironmentObject var appState: AppState
    // "custom" changes no values, so it must be sticky state — a purely
    // derived selection would snap back to whichever preset the values match
    @State private var forcedCustom = false

    private var preset: TimelinePreset {
        if forcedCustom { return .custom }
        return TimelinePreset.match(fade: appState.settings.fadeOutMinutes,
                                    gap: appState.settings.quietGapMinutes,
                                    window: appState.settings.wakeWindowMinutes)
    }

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
                Picker("timeline", selection: Binding(
                    get: { preset },
                    set: { newValue in
                        let values: (Int, Int, Int)
                        switch newValue {
                        case .gentle: values = TimelinePreset.gentleValues
                        case .quick: values = TimelinePreset.quickValues
                        case .custom:
                            forcedCustom = true
                            return   // custom keeps current values; steppers appear below
                        }
                        forcedCustom = false
                        appState.settings.fadeOutMinutes = values.0
                        appState.settings.quietGapMinutes = values.1
                        appState.settings.wakeWindowMinutes = values.2
                    }
                )) {
                    ForEach(TimelinePreset.allCases) { p in
                        Text(p.rawValue).tag(p)
                    }
                }
                .pickerStyle(.segmented)

                if preset == .custom {
                    timelineStepper("fade-out", value: $appState.settings.fadeOutMinutes, range: 5...60,
                                    caption: "how long the white noise takes to fade to silence")
                    timelineStepper("quiet gap", value: $appState.settings.quietGapMinutes, range: 0...120,
                                    caption: "silence between the fade ending and listening starting — keeps the room quiet so stir can learn its baseline")
                    timelineStepper("wake window", value: $appState.settings.wakeWindowMinutes, range: 10...90,
                                    caption: "how long stir listens for you stirring before your \"up by\" time")
                }
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
    @StateObject private var soundManager = CustomSoundManager.shared
    @State private var previewPlayer: AVAudioPlayer?
    @State private var showingFilePicker = false
    @State private var importError: String?
    @State private var showingImportError = false

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
                                  isSelected: !appState.settings.isUsingCustomWhiteNoise && appState.settings.whiteNoiseSound == sound,
                                  onSelect: {
                                      appState.settings.whiteNoiseSound = sound
                                      appState.settings.whiteNoiseCustomSoundId = nil
                                  },
                                  onPreview: { previewBundled(sound.rawValue) })
                }
                ForEach(soundManager.customSounds) { sound in
                    selectableRow(sound.name,
                                  isSelected: appState.settings.whiteNoiseCustomSoundId == sound.id,
                                  onSelect: { appState.settings.whiteNoiseCustomSoundId = sound.id },
                                  onPreview: { previewCustom(sound) })
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
                                  isSelected: !appState.settings.isUsingCustomSound && appState.settings.selectedSound == sound,
                                  onSelect: {
                                      appState.settings.selectedSound = sound
                                      appState.settings.customSoundId = nil
                                  },
                                  onPreview: { previewBundled(sound.rawValue) })
                }
                ForEach(soundManager.customSounds) { sound in
                    selectableRow(sound.name,
                                  isSelected: appState.settings.customSoundId == sound.id,
                                  onSelect: { appState.settings.customSoundId = sound.id },
                                  onPreview: { previewCustom(sound) })
                }
            } header: {
                Text("alarm sound")
            }

            Section {
                Button(action: { showingFilePicker = true }) {
                    HStack {
                        Image(systemName: "plus.circle.fill")
                        Text("import your own")
                    }
                }
            } footer: {
                Text("imported sounds appear in both lists")
            }
        }
        .navigationTitle("sounds")
        .navigationBarTitleDisplayMode(.inline)
        .onDisappear { stopPreview() }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: CustomSoundManager.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    do {
                        _ = try soundManager.importSound(from: url)
                    } catch {
                        importError = error.localizedDescription
                        showingImportError = true
                    }
                }
            case .failure(let error):
                importError = error.localizedDescription
                showingImportError = true
            }
        }
        .alert("import error", isPresented: $showingImportError) {
            Button("ok") { }
        } message: {
            Text(importError ?? "unknown error")
        }
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

    private func previewBundled(_ name: String) {
        stopPreview()
        guard let url = bundledSoundURL(name) else { return }
        playPreview(url: url)
    }

    private func previewCustom(_ sound: CustomSound) {
        stopPreview()
        guard let url = sound.fileURL else { return }
        playPreview(url: url)
    }

    private func playPreview(url: URL) {
        do {
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)
            previewPlayer = try AVAudioPlayer(contentsOf: url)
            previewPlayer?.volume = 0.6
            previewPlayer?.play()
            DispatchQueue.main.asyncAfter(deadline: .now() + 8.0) { [self] in
                stopPreview()
            }
        } catch {
            print("Failed to preview sound: \(error)")
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

    var body: some View {
        List {
            Section {
                Picker("sensitivity", selection: Binding(
                    get: { sensitivity },
                    set: { label in
                        switch label {
                        case "low": appState.settings.sensitivityValue = 0.15
                        case "high": appState.settings.sensitivityValue = 0.85
                        default: appState.settings.sensitivityValue = 0.5
                        }
                    }
                )) {
                    Text("low").tag("low")
                    Text("medium").tag("medium")
                    Text("high").tag("high")
                }
                .pickerStyle(.segmented)

                Toggle("motion detection", isOn: $appState.settings.motionDetectionEnabled)
            } header: {
                Text("listening")
            } footer: {
                Text("higher sensitivity wakes you on smaller sounds. motion detection also wakes you if the phone is picked up or bumped.")
            }

            Section {
                Toggle("haptics", isOn: $appState.settings.hapticEnabled)
                if appState.settings.hapticEnabled {
                    HStack {
                        Text("low").font(.caption).foregroundColor(.gray)
                        Slider(value: $appState.settings.hapticIntensity, in: 0.2...1.0, step: 0.1)
                        Text("high").font(.caption).foregroundColor(.gray)
                    }
                }
            } header: {
                Text("haptics")
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
