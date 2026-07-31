import Foundation

// Bundled sounds ship as synthesized .m4a (noise family, surf) or legacy .mp3
// (short alarm tones); resolve either
func bundledSoundURL(_ name: String) -> URL? {
    Bundle.main.url(forResource: name, withExtension: "m4a")
        ?? Bundle.main.url(forResource: name, withExtension: "mp3")
}

struct AlarmSettings: Codable {
    var wakeUpBy: Date           // The one nightly input: fallback alarm fires at this time
    var wakeWindowMinutes: Int   // Listening window length; windowStart = wakeUpBy - this (10-90)
    var alarmEnabled: Bool       // Off = no-alarm mode: white noise fades to silence, mic never activates
    var sensitivityValue: Float  // 0.0 (less sensitive) to 1.0 (more sensitive)
    var volume: Float            // 0.0 to 1.0
    var selectedSound: AlarmSound
    var customSoundId: UUID?     // If set, use custom sound instead of built-in
    var tagline: String          // Customizable wake message
    var hapticEnabled: Bool
    var hapticType: HapticType
    var hapticIntensity: Float
    var motionDetectionEnabled: Bool  // Trigger alarm on device movement

    var whiteNoiseEnabled: Bool
    var whiteNoiseSound: WhiteNoiseSound
    var whiteNoiseVolume: Float
    var whiteNoiseCustomSoundId: UUID?  // Points into the shared custom sound library
    var fadeOutMinutes: Int      // How long the fade-out takes (5-60 minutes)
    var quietGapMinutes: Int     // Silence between fade complete and listening start (0-120)

    var isUsingCustomSound: Bool {
        customSoundId != nil
    }

    var isUsingCustomWhiteNoise: Bool {
        whiteNoiseCustomSoundId != nil
    }

    var fadeOutSeconds: TimeInterval {
        TimeInterval(fadeOutMinutes * 60)
    }

    var quietGapSeconds: TimeInterval {
        TimeInterval(quietGapMinutes * 60)
    }

    var wakeWindowSeconds: TimeInterval {
        TimeInterval(wakeWindowMinutes * 60)
    }

    // Convert sensitivity slider (0-1) to standard deviation multiplier
    // Uses statistical threshold: baseline + (multiplier × stdDev)
    // 0.0 = 5.0× stdDev (needs significant deviation from baseline - less sensitive)
    // 1.0 = 2.0× stdDev (triggers on smaller deviations - more sensitive)
    var sensitivityMultiplier: Float {
        return 5.0 - (sensitivityValue * 3.0)
    }

    var sensitivityLabel: String {
        switch sensitivityValue {
        case 0.0..<0.33: return "low"
        case 0.33..<0.66: return "medium"
        default: return "high"
        }
    }

    static var `default`: AlarmSettings {
        let calendar = Calendar.current
        let now = Date()
        let upByComponents = DateComponents(hour: 7, minute: 0)

        return AlarmSettings(
            wakeUpBy: calendar.nextDate(after: now, matching: upByComponents, matchingPolicy: .nextTime) ?? now,
            wakeWindowMinutes: 30,
            alarmEnabled: true,
            sensitivityValue: 0.5,  // Medium by default
            volume: 0.7,
            selectedSound: .gentleChime,
            customSoundId: nil,
            tagline: "good morning",
            hapticEnabled: true,
            hapticType: .heartbeat,
            hapticIntensity: 0.7,
            motionDetectionEnabled: true,
            whiteNoiseEnabled: true,
            whiteNoiseSound: .oceanWaves,
            whiteNoiseVolume: 0.7,
            whiteNoiseCustomSoundId: nil,
            fadeOutMinutes: 10,
            quietGapMinutes: 30
        )
    }

    // MARK: - Codable with migration from the wake-window format

    private enum CodingKeys: String, CodingKey {
        case wakeUpBy, wakeWindowMinutes, alarmEnabled
        case sensitivityValue, volume, selectedSound, customSoundId, tagline
        case hapticEnabled, hapticType, hapticIntensity, motionDetectionEnabled
        case whiteNoiseEnabled, whiteNoiseSound, whiteNoiseVolume, whiteNoiseCustomSoundId
        case fadeOutMinutes, quietGapMinutes
        // Legacy keys (pre-merge stir), read-only
        case wakeWindowStart, wakeWindowEnd
    }

    init(wakeUpBy: Date, wakeWindowMinutes: Int, alarmEnabled: Bool, sensitivityValue: Float,
         volume: Float, selectedSound: AlarmSound, customSoundId: UUID?, tagline: String,
         hapticEnabled: Bool, hapticType: HapticType, hapticIntensity: Float,
         motionDetectionEnabled: Bool, whiteNoiseEnabled: Bool, whiteNoiseSound: WhiteNoiseSound,
         whiteNoiseVolume: Float, whiteNoiseCustomSoundId: UUID?, fadeOutMinutes: Int, quietGapMinutes: Int) {
        self.wakeUpBy = wakeUpBy
        self.wakeWindowMinutes = wakeWindowMinutes
        self.alarmEnabled = alarmEnabled
        self.sensitivityValue = sensitivityValue
        self.volume = volume
        self.selectedSound = selectedSound
        self.customSoundId = customSoundId
        self.tagline = tagline
        self.hapticEnabled = hapticEnabled
        self.hapticType = hapticType
        self.hapticIntensity = hapticIntensity
        self.motionDetectionEnabled = motionDetectionEnabled
        self.whiteNoiseEnabled = whiteNoiseEnabled
        self.whiteNoiseSound = whiteNoiseSound
        self.whiteNoiseVolume = whiteNoiseVolume
        self.whiteNoiseCustomSoundId = whiteNoiseCustomSoundId
        self.fadeOutMinutes = fadeOutMinutes
        self.quietGapMinutes = quietGapMinutes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = AlarmSettings.default

        let legacyStart = try container.decodeIfPresent(Date.self, forKey: .wakeWindowStart)
        let legacyEnd = try container.decodeIfPresent(Date.self, forKey: .wakeWindowEnd)

        // "Up by" is the old window end; the old window length seeds the duration config
        wakeUpBy = try container.decodeIfPresent(Date.self, forKey: .wakeUpBy)
            ?? legacyEnd
            ?? defaults.wakeUpBy
        if let minutes = try container.decodeIfPresent(Int.self, forKey: .wakeWindowMinutes) {
            wakeWindowMinutes = minutes
        } else if let start = legacyStart, let end = legacyEnd, end > start {
            wakeWindowMinutes = min(max(Int(end.timeIntervalSince(start) / 60), 10), 90)
        } else {
            wakeWindowMinutes = defaults.wakeWindowMinutes
        }

        alarmEnabled = try container.decodeIfPresent(Bool.self, forKey: .alarmEnabled) ?? true
        sensitivityValue = try container.decodeIfPresent(Float.self, forKey: .sensitivityValue) ?? defaults.sensitivityValue
        volume = try container.decodeIfPresent(Float.self, forKey: .volume) ?? defaults.volume
        selectedSound = try container.decodeIfPresent(AlarmSound.self, forKey: .selectedSound) ?? defaults.selectedSound
        customSoundId = try container.decodeIfPresent(UUID.self, forKey: .customSoundId)
        tagline = try container.decodeIfPresent(String.self, forKey: .tagline) ?? defaults.tagline
        hapticEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticEnabled) ?? defaults.hapticEnabled
        hapticType = try container.decodeIfPresent(HapticType.self, forKey: .hapticType) ?? defaults.hapticType
        hapticIntensity = try container.decodeIfPresent(Float.self, forKey: .hapticIntensity) ?? defaults.hapticIntensity
        motionDetectionEnabled = try container.decodeIfPresent(Bool.self, forKey: .motionDetectionEnabled) ?? defaults.motionDetectionEnabled
        whiteNoiseEnabled = try container.decodeIfPresent(Bool.self, forKey: .whiteNoiseEnabled) ?? defaults.whiteNoiseEnabled
        whiteNoiseSound = try container.decodeIfPresent(WhiteNoiseSound.self, forKey: .whiteNoiseSound) ?? defaults.whiteNoiseSound
        whiteNoiseVolume = try container.decodeIfPresent(Float.self, forKey: .whiteNoiseVolume) ?? defaults.whiteNoiseVolume
        whiteNoiseCustomSoundId = try container.decodeIfPresent(UUID.self, forKey: .whiteNoiseCustomSoundId)
        fadeOutMinutes = try container.decodeIfPresent(Int.self, forKey: .fadeOutMinutes) ?? defaults.fadeOutMinutes
        quietGapMinutes = try container.decodeIfPresent(Int.self, forKey: .quietGapMinutes) ?? defaults.quietGapMinutes
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(wakeUpBy, forKey: .wakeUpBy)
        try container.encode(wakeWindowMinutes, forKey: .wakeWindowMinutes)
        try container.encode(alarmEnabled, forKey: .alarmEnabled)
        try container.encode(sensitivityValue, forKey: .sensitivityValue)
        try container.encode(volume, forKey: .volume)
        try container.encode(selectedSound, forKey: .selectedSound)
        try container.encodeIfPresent(customSoundId, forKey: .customSoundId)
        try container.encode(tagline, forKey: .tagline)
        try container.encode(hapticEnabled, forKey: .hapticEnabled)
        try container.encode(hapticType, forKey: .hapticType)
        try container.encode(hapticIntensity, forKey: .hapticIntensity)
        try container.encode(motionDetectionEnabled, forKey: .motionDetectionEnabled)
        try container.encode(whiteNoiseEnabled, forKey: .whiteNoiseEnabled)
        try container.encode(whiteNoiseSound, forKey: .whiteNoiseSound)
        try container.encode(whiteNoiseVolume, forKey: .whiteNoiseVolume)
        try container.encodeIfPresent(whiteNoiseCustomSoundId, forKey: .whiteNoiseCustomSoundId)
        try container.encode(fadeOutMinutes, forKey: .fadeOutMinutes)
        try container.encode(quietGapMinutes, forKey: .quietGapMinutes)
    }
}

enum AlarmSound: String, Codable, CaseIterable, Identifiable {
    // Gentle Tones
    case gentleChime = "gentle_chime"
    case softBells = "soft_bells"
    case singingBowl = "singing_bowl"
    case dawn = "dawn"

    // Nature Sounds
    case oceanWaves = "ocean_waves"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gentleChime: return "gentle chime"
        case .softBells: return "soft bells"
        case .singingBowl: return "singing bowl"
        case .dawn: return "dawn"
        case .oceanWaves: return "ocean waves"
        }
    }

    var category: SoundCategory {
        switch self {
        case .gentleChime, .softBells, .singingBowl, .dawn:
            return .gentle
        case .oceanWaves:
            return .nature
        }
    }

    enum SoundCategory: String, CaseIterable {
        case gentle = "gentle"
        case nature = "nature"
    }
}

enum WhiteNoiseSound: String, Codable, CaseIterable, Identifiable {
    // Pure Noise
    case whiteNoise = "white_noise"
    case pinkNoise = "pink_noise"
    case brownNoise = "brown_noise"
    case fan = "fan"

    // Nature Sounds
    case oceanWaves = "ocean_waves"
    case rain = "rain"
    case wind = "wind"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .whiteNoise: return "white noise"
        case .pinkNoise: return "pink noise"
        case .brownNoise: return "brown noise"
        case .fan: return "fan"
        case .oceanWaves: return "ocean waves"
        case .rain: return "rain"
        case .wind: return "wind"
        }
    }

    var category: SoundCategory {
        switch self {
        case .whiteNoise, .pinkNoise, .brownNoise, .fan:
            return .noise
        case .oceanWaves, .rain, .wind:
            return .nature
        }
    }

    enum SoundCategory: String, CaseIterable {
        case noise = "noise"
        case nature = "nature"
    }
}

enum HapticType: String, Codable, CaseIterable, Identifiable {
    case heartbeat = "heartbeat"
    case pulse = "pulse"
    case escalating = "escalating"
    case steady = "steady"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .heartbeat: return "heartbeat"
        case .pulse: return "pulse"
        case .escalating: return "escalating"
        case .steady: return "steady"
        }
    }

    var description: String {
        switch self {
        case .heartbeat: return "rhythmic double-tap pattern"
        case .pulse: return "gentle pulsing vibration"
        case .escalating: return "gradually intensifying"
        case .steady: return "continuous vibration"
        }
    }
}
