import Foundation
import UniformTypeIdentifiers

struct CustomSound: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    let filename: String
    let dateAdded: Date

    var fileURL: URL? {
        CustomSoundManager.soundsDirectory?.appendingPathComponent(filename)
    }
}

class CustomSoundManager: ObservableObject {
    static let shared = CustomSoundManager()

    @Published private(set) var customSounds: [CustomSound] = []

    private let soundsKey = "customSounds"

    static var soundsDirectory: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent("CustomSounds")
    }

    init() {
        createSoundsDirectoryIfNeeded()
        loadSounds()
    }

    private func createSoundsDirectoryIfNeeded() {
        guard let directory = Self.soundsDirectory else { return }
        if !FileManager.default.fileExists(atPath: directory.path) {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    private func loadSounds() {
        if let data = UserDefaults.standard.data(forKey: soundsKey),
           let sounds = try? JSONDecoder().decode([CustomSound].self, from: data) {
            // Filter out sounds whose files no longer exist
            customSounds = sounds.filter { sound in
                if let url = sound.fileURL {
                    return FileManager.default.fileExists(atPath: url.path)
                }
                return false
            }
        }
    }

    private func saveSounds() {
        if let data = try? JSONEncoder().encode(customSounds) {
            UserDefaults.standard.set(data, forKey: soundsKey)
        }
    }

    func importSound(from sourceURL: URL, name: String? = nil) throws -> CustomSound {
        guard sourceURL.startAccessingSecurityScopedResource() else {
            throw CustomSoundError.accessDenied
        }
        defer { sourceURL.stopAccessingSecurityScopedResource() }

        guard let directory = Self.soundsDirectory else {
            throw CustomSoundError.directoryNotFound
        }

        let soundName = name ?? sourceURL.deletingPathExtension().lastPathComponent
        let fileExtension = sourceURL.pathExtension
        let uniqueFilename = "\(UUID().uuidString).\(fileExtension)"
        let destinationURL = directory.appendingPathComponent(uniqueFilename)

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)

        let sound = CustomSound(
            id: UUID(),
            name: soundName,
            filename: uniqueFilename,
            dateAdded: Date()
        )

        customSounds.append(sound)
        saveSounds()

        print("Imported custom sound: \(sound.name)")
        return sound
    }

    func deleteSound(_ sound: CustomSound) {
        if let url = sound.fileURL {
            try? FileManager.default.removeItem(at: url)
        }
        customSounds.removeAll { $0.id == sound.id }
        saveSounds()
        print("Deleted custom sound: \(sound.name)")
    }

    func renameSound(_ sound: CustomSound, to newName: String) {
        if let index = customSounds.firstIndex(where: { $0.id == sound.id }) {
            customSounds[index].name = newName
            saveSounds()
        }
    }

    static var supportedTypes: [UTType] {
        [.audio, .mp3, .wav, .aiff, UTType(filenameExtension: "m4a") ?? .audio]
    }
}

enum CustomSoundError: LocalizedError {
    case accessDenied
    case directoryNotFound
    case copyFailed

    var errorDescription: String? {
        switch self {
        case .accessDenied:
            return "Could not access the selected file"
        case .directoryNotFound:
            return "Could not find sounds directory"
        case .copyFailed:
            return "Failed to copy the sound file"
        }
    }
}
