import Foundation

public enum HapticIntensity: String, CaseIterable, Identifiable, Codable {
    case light = "Light"
    case medium = "Medium"
    case heavy = "Heavy"

    public var id: String { rawValue }
}

public struct AppSettings: Codable, Equatable {
    public var isHapticsEnabled: Bool
    public var hapticIntensity: HapticIntensity
    public var chapterHapticsEnabled: Bool
    public var defaultScrollReadingMode: Bool
    public var readerSettings: ReaderSettings
    public var accent: DipleAccent
    public var appearance: DipleAppearance
    public var keepScreenAwakeWhileReading: Bool

    public init(
        isHapticsEnabled: Bool = true,
        hapticIntensity: HapticIntensity = .medium,
        chapterHapticsEnabled: Bool = true,
        defaultScrollReadingMode: Bool = false,
        readerSettings: ReaderSettings = ReaderSettings(),
        accent: DipleAccent = .lilac,
        appearance: DipleAppearance = .dark,
        keepScreenAwakeWhileReading: Bool = true
    ) {
        self.isHapticsEnabled = isHapticsEnabled
        self.hapticIntensity = hapticIntensity
        self.chapterHapticsEnabled = chapterHapticsEnabled
        self.defaultScrollReadingMode = defaultScrollReadingMode
        self.readerSettings = readerSettings
        self.accent = accent
        self.appearance = appearance
        self.keepScreenAwakeWhileReading = keepScreenAwakeWhileReading
    }

    enum CodingKeys: String, CodingKey {
        case isHapticsEnabled
        case hapticIntensity
        case chapterHapticsEnabled
        case defaultScrollReadingMode
        case readerSettings
        case accent
        case appearance
        case keepScreenAwakeWhileReading
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.isHapticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .isHapticsEnabled) ?? true
        self.hapticIntensity = try container.decodeIfPresent(HapticIntensity.self, forKey: .hapticIntensity) ?? .medium
        self.chapterHapticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .chapterHapticsEnabled) ?? true
        self.defaultScrollReadingMode = try container.decodeIfPresent(Bool.self, forKey: .defaultScrollReadingMode) ?? false
        var loadedReaderSettings = try container.decodeIfPresent(ReaderSettings.self, forKey: .readerSettings) ?? ReaderSettings()
        if container.contains(.defaultScrollReadingMode) && !container.contains(.readerSettings) {
            loadedReaderSettings.readingMode = self.defaultScrollReadingMode ? .scroll : .paginated
        }
        self.readerSettings = loadedReaderSettings
        self.accent = try container.decodeIfPresent(DipleAccent.self, forKey: .accent) ?? .lilac
        // Absent for everyone who installed before the light theme existed, and they chose an
        // app that was dark — so the default is `.dark`, not `.system`. Following the device
        // would have silently turned the interface white on the next launch.
        self.appearance = try container.decodeIfPresent(DipleAppearance.self, forKey: .appearance) ?? .dark
        self.keepScreenAwakeWhileReading = try container.decodeIfPresent(Bool.self, forKey: .keepScreenAwakeWhileReading) ?? true
    }
}
