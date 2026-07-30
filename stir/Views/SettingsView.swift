import SwiftUI
import AVFoundation
import UniformTypeIdentifiers
import CoreHaptics

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) var dismiss
    @StateObject private var soundManager = CustomSoundManager.shared
    @State private var previewPlayer: AVAudioPlayer?
    @State private var showingFilePicker = false
    @State private var importError: String?
    @State private var showingImportError = false
    @State private var hapticEngine: CHHapticEngine?
    @State private var hapticPlayer: CHHapticPatternPlayer?

    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

    var body: some View {
        NavigationStack {
            List {
                // Wake message Section - moved to top
                Section {
                    TextField("your motivation", text: $appState.settings.tagline)
                } header: {
                    Text("how do you want to start the day?")
                }

                // Night Section
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
                } header: {
                    Text("night")
                } footer: {
                    if !appState.settings.alarmEnabled {
                        Text("alarm off: white noise fades to silence at your \"up by\" time — when you don't hear it, it's time. the microphone is never used.")
                    }
                }

                // Night timeline Section
                Section {
                    Stepper(value: $appState.settings.wakeWindowMinutes, in: 10...90, step: 5) {
                        HStack {
                            Text("wake window")
                            Spacer()
                            Text("\(appState.settings.wakeWindowMinutes) min")
                                .foregroundColor(.gray)
                        }
                    }

                    Stepper(value: $appState.settings.quietGapMinutes, in: 0...120, step: 5) {
                        HStack {
                            Text("quiet gap")
                            Spacer()
                            Text("\(appState.settings.quietGapMinutes) min")
                                .foregroundColor(.gray)
                        }
                    }

                    Stepper(value: $appState.settings.fadeOutMinutes, in: 5...60, step: 5) {
                        HStack {
                            Text("fade-out")
                            Spacer()
                            Text("\(appState.settings.fadeOutMinutes) min")
                                .foregroundColor(.gray)
                        }
                    }
                } header: {
                    Text("night timeline")
                } footer: {
                    Text("listening starts a wake window before your \"up by\" time. white noise fades out over the fade-out duration, finishing a quiet gap before listening begins.")
                }

                // Sensitivity Section
                Section {
                    HStack {
                        Text("less")
                            .font(.caption)
                            .foregroundColor(.gray)
                        Slider(value: $appState.settings.sensitivityValue, in: 0.0...1.0, step: 0.05)
                        Text("more")
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

                    Toggle("motion detection", isOn: $appState.settings.motionDetectionEnabled)
                } header: {
                    Text("sensitivity")
                } footer: {
                    if appState.settings.motionDetectionEnabled {
                        Text("alarm triggers when you move your phone")
                    }
                }

                // Volume Section
                Section {
                    HStack {
                        Image(systemName: "speaker.fill")
                            .foregroundColor(.gray)
                        Slider(value: $appState.settings.volume, in: 0.1...1.0, step: 0.05)
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundColor(.gray)
                    }
                } header: {
                    Text("volume")
                }

                // Sound Selection Section
                Section {
                    // Built-in sounds
                    ForEach(AlarmSound.SoundCategory.allCases, id: \.self) { category in
                        let sounds = AlarmSound.allCases.filter { $0.category == category }
                        if !sounds.isEmpty {
                            DisclosureGroup(category.rawValue) {
                                ForEach(sounds) { sound in
                                    SoundRowView(
                                        sound: sound,
                                        isSelected: !appState.settings.isUsingCustomSound && appState.settings.selectedSound == sound,
                                        onSelect: {
                                            appState.settings.selectedSound = sound
                                            appState.settings.customSoundId = nil
                                        },
                                        onPreview: {
                                            previewSound(sound)
                                        }
                                    )
                                }
                            }
                        }
                    }

                    // Custom sounds section
                    DisclosureGroup("custom") {
                        // Import button
                        Button(action: { showingFilePicker = true }) {
                            HStack {
                                Image(systemName: "plus.circle.fill")
                                    .foregroundColor(.blue)
                                Text("import sound")
                                    .foregroundColor(.blue)
                            }
                        }

                        // List custom sounds
                        ForEach(soundManager.customSounds) { sound in
                            CustomSoundRowView(
                                sound: sound,
                                isSelected: appState.settings.customSoundId == sound.id,
                                onSelect: {
                                    appState.settings.customSoundId = sound.id
                                },
                                onPreview: {
                                    previewCustomSound(sound)
                                },
                                onDelete: {
                                    if appState.settings.customSoundId == sound.id {
                                        appState.settings.customSoundId = nil
                                    }
                                    soundManager.deleteSound(sound)
                                }
                            )
                        }
                    }
                } header: {
                    Text("alarm sound")
                }

                // White Noise Section
                Section {
                    HStack {
                        Image(systemName: "speaker.fill")
                            .foregroundColor(.gray)
                        Slider(value: $appState.settings.whiteNoiseVolume, in: 0.1...1.0, step: 0.05)
                        Image(systemName: "speaker.wave.3.fill")
                            .foregroundColor(.gray)
                    }

                    ForEach(WhiteNoiseSound.SoundCategory.allCases, id: \.self) { category in
                        let sounds = WhiteNoiseSound.allCases.filter { $0.category == category }
                        if !sounds.isEmpty {
                            DisclosureGroup(category.rawValue) {
                                ForEach(sounds) { sound in
                                    WhiteNoiseRowView(
                                        sound: sound,
                                        isSelected: !appState.settings.isUsingCustomWhiteNoise && appState.settings.whiteNoiseSound == sound,
                                        onSelect: {
                                            appState.settings.whiteNoiseSound = sound
                                            appState.settings.whiteNoiseCustomSoundId = nil
                                        },
                                        onPreview: {
                                            previewWhiteNoise(sound)
                                        }
                                    )
                                }
                            }
                        }
                    }

                    DisclosureGroup("custom") {
                        ForEach(soundManager.customSounds) { sound in
                            CustomSoundRowView(
                                sound: sound,
                                isSelected: appState.settings.whiteNoiseCustomSoundId == sound.id,
                                onSelect: {
                                    appState.settings.whiteNoiseCustomSoundId = sound.id
                                },
                                onPreview: {
                                    previewCustomSound(sound)
                                },
                                onDelete: {
                                    if appState.settings.whiteNoiseCustomSoundId == sound.id {
                                        appState.settings.whiteNoiseCustomSoundId = nil
                                    }
                                    if appState.settings.customSoundId == sound.id {
                                        appState.settings.customSoundId = nil
                                    }
                                    soundManager.deleteSound(sound)
                                }
                            )
                        }
                    }
                } header: {
                    Text("white noise")
                } footer: {
                    Text("imported sounds are shared between alarm and white noise")
                }

                // Haptic Section
                Section {
                    Toggle("haptics", isOn: $appState.settings.hapticEnabled)

                    if appState.settings.hapticEnabled {
                        HStack {
                            Text("low")
                                .font(.caption)
                                .foregroundColor(.gray)
                            Slider(value: $appState.settings.hapticIntensity, in: 0.2...1.0, step: 0.1)
                            Text("high")
                                .font(.caption)
                                .foregroundColor(.gray)
                        }

                        ForEach(HapticType.allCases) { type in
                            HapticRowView(
                                type: type,
                                isSelected: appState.settings.hapticType == type,
                                onSelect: {
                                    appState.settings.hapticType = type
                                },
                                onPreview: {
                                    previewHaptic(type, intensity: appState.settings.hapticIntensity)
                                }
                            )
                        }
                    }
                } header: {
                    Text("haptics")
                }

                // Technical details
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
                    Button("done") {
                        stopPreview()
                        dismiss()
                    }
                }
            }
        }
        .onDisappear {
            stopPreview()
        }
        .fileImporter(
            isPresented: $showingFilePicker,
            allowedContentTypes: CustomSoundManager.supportedTypes,
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    do {
                        let sound = try soundManager.importSound(from: url)
                        appState.settings.customSoundId = sound.id
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

    private func previewSound(_ sound: AlarmSound) {
        stopPreview()

        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "mp3") else {
            print("Sound file not found: \(sound.rawValue).mp3")
            return
        }

        playPreviewWithFade(url: url)
    }

    private func previewWhiteNoise(_ sound: WhiteNoiseSound) {
        stopPreview()

        guard let url = Bundle.main.url(forResource: sound.rawValue, withExtension: "mp3") else {
            print("Sound file not found: \(sound.rawValue).mp3")
            return
        }

        playPreviewWithFade(url: url)
    }

    private func previewCustomSound(_ sound: CustomSound) {
        stopPreview()

        guard let url = sound.fileURL else { return }

        playPreviewWithFade(url: url)
    }

    private func playPreviewWithFade(url: URL) {
        do {
            // Configure audio session for playback
            try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
            try AVAudioSession.sharedInstance().setActive(true)

            previewPlayer = try AVAudioPlayer(contentsOf: url)
            previewPlayer?.numberOfLoops = -1 // Loop in case sound is shorter than 10s
            previewPlayer?.volume = 0
            previewPlayer?.play()

            let targetVolume = appState.settings.volume
            let fadeDuration: TimeInterval = 1.5
            let playDuration: TimeInterval = 10.0

            // Fade in
            fadeVolume(to: targetVolume, duration: fadeDuration)

            // Schedule fade out
            DispatchQueue.main.asyncAfter(deadline: .now() + playDuration - fadeDuration) { [self] in
                fadeVolume(to: 0, duration: fadeDuration)
            }

            // Stop after total duration
            DispatchQueue.main.asyncAfter(deadline: .now() + playDuration) { [self] in
                stopPreview()
            }
        } catch {
            print("Failed to preview sound: \(error)")
        }
    }

    private func fadeVolume(to targetVolume: Float, duration: TimeInterval) {
        guard let player = previewPlayer else { return }

        let steps = 30
        let stepDuration = duration / Double(steps)
        let startVolume = player.volume
        let volumeDelta = targetVolume - startVolume
        var currentStep = 0

        Timer.scheduledTimer(withTimeInterval: stepDuration, repeats: true) { timer in
            currentStep += 1
            let progress = Float(currentStep) / Float(steps)
            self.previewPlayer?.volume = startVolume + (volumeDelta * progress)

            if currentStep >= steps {
                timer.invalidate()
                self.previewPlayer?.volume = targetVolume
            }
        }
    }

    private func stopPreview() {
        previewPlayer?.stop()
        previewPlayer = nil
    }

    private func previewHaptic(_ type: HapticType, intensity: Float) {
        stopHapticPreview()

        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }

        do {
            hapticEngine = try CHHapticEngine()
            try hapticEngine?.start()

            let events = createHapticPreviewEvents(for: type, intensity: intensity)
            let pattern = try CHHapticPattern(events: events, parameters: [])
            hapticPlayer = try hapticEngine?.makePlayer(with: pattern)
            try hapticPlayer?.start(atTime: 0)

            // Stop after 3 seconds
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [self] in
                stopHapticPreview()
            }
        } catch {
            print("Haptic preview error: \(error)")
        }
    }

    private func createHapticPreviewEvents(for type: HapticType, intensity: Float) -> [CHHapticEvent] {
        var events: [CHHapticEvent] = []

        switch type {
        case .heartbeat:
            for i in 0..<2 {
                let baseTime = Double(i) * 1.5
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                    ],
                    relativeTime: baseTime
                ))
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.7),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
                    ],
                    relativeTime: baseTime + 0.2
                ))
            }

        case .pulse:
            for i in 0..<3 {
                events.append(CHHapticEvent(
                    eventType: .hapticContinuous,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.6),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.2)
                    ],
                    relativeTime: Double(i) * 1.0,
                    duration: 0.5
                ))
            }

        case .escalating:
            for i in 0..<4 {
                let escalatingIntensity = min(intensity, 0.2 + (intensity * Float(i) / 4.0))
                events.append(CHHapticEvent(
                    eventType: .hapticTransient,
                    parameters: [
                        CHHapticEventParameter(parameterID: .hapticIntensity, value: escalatingIntensity),
                        CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
                    ],
                    relativeTime: Double(i) * 0.7
                ))
            }

        case .steady:
            events.append(CHHapticEvent(
                eventType: .hapticContinuous,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity * 0.85),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.4)
                ],
                relativeTime: 0,
                duration: 2.5
            ))
        }

        return events
    }

    private func stopHapticPreview() {
        try? hapticPlayer?.cancel()
        hapticPlayer = nil
        hapticEngine?.stop()
        hapticEngine = nil
    }
}

struct CustomSoundRowView: View {
    let sound: CustomSound
    let isSelected: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack {
            Button(action: onSelect) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .gray)
                    Text(sound.name)
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

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .font(.body)
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
            .padding(.leading, 8)
        }
        .padding(.vertical, 4)
    }
}

struct SoundRowView: View {
    let sound: AlarmSound
    let isSelected: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void

    var body: some View {
        HStack {
            Button(action: onSelect) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .gray)
                    Text(sound.displayName)
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
        .padding(.vertical, 4)
    }
}

struct WhiteNoiseRowView: View {
    let sound: WhiteNoiseSound
    let isSelected: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void

    var body: some View {
        HStack {
            Button(action: onSelect) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .gray)
                    Text(sound.displayName)
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
        .padding(.vertical, 4)
    }
}

struct HapticRowView: View {
    let type: HapticType
    let isSelected: Bool
    let onSelect: () -> Void
    let onPreview: () -> Void

    var body: some View {
        HStack {
            Button(action: onSelect) {
                HStack {
                    Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                        .foregroundColor(isSelected ? .blue : .gray)
                    Text(type.displayName)
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
        .padding(.vertical, 4)
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
