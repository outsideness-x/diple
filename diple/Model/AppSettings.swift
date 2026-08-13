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
    /// When each field was last changed, by whichever device changed it.
    ///
    /// Settings used to sync as one blob under last-writer-wins, so changing *different*
    /// settings on two devices lost one of them: pick an accent on the phone, a theme on the
    /// Mac, and whichever synced first was reverted wholesale. Carrying a stamp per field lets
    /// a merge keep both, because the question stops being "which device wrote last" and
    /// becomes "which device wrote *this field* last".
    ///
    /// Absent on payloads written before this existed; those fields read as `.distantPast` and
    /// therefore lose to anything stamped, which is the right direction — an unstamped value
    /// is one nobody is known to have chosen.
    public var fieldStamps: [String: Date]

    public init(
        isHapticsEnabled: Bool = true,
        hapticIntensity: HapticIntensity = .medium,
        chapterHapticsEnabled: Bool = true,
        defaultScrollReadingMode: Bool = false,
        readerSettings: ReaderSettings = ReaderSettings(),
        accent: DipleAccent = .lilac,
        appearance: DipleAppearance = .dark,
        keepScreenAwakeWhileReading: Bool = true,
        fieldStamps: [String: Date] = [:]
    ) {
        self.isHapticsEnabled = isHapticsEnabled
        self.hapticIntensity = hapticIntensity
        self.chapterHapticsEnabled = chapterHapticsEnabled
        self.defaultScrollReadingMode = defaultScrollReadingMode
        self.readerSettings = readerSettings
        self.accent = accent
        self.appearance = appearance
        self.keepScreenAwakeWhileReading = keepScreenAwakeWhileReading
        self.fieldStamps = fieldStamps
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
        case fieldStamps
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
        self.fieldStamps = try container.decodeIfPresent([String: Date].self, forKey: .fieldStamps) ?? [:]
    }

    // MARK: - Per-field merge

    /// Every field that merges independently.
    ///
    /// `readerSettings` is treated as one unit rather than being taken apart: its members are
    /// chosen together in one screen, in one sitting, and splitting them would let a font size
    /// from one device meet a margin from another in a combination neither reader ever saw.
    public enum Field: String, CaseIterable {
        case isHapticsEnabled
        case hapticIntensity
        case chapterHapticsEnabled
        case defaultScrollReadingMode
        case readerSettings
        case accent
        case appearance
        case keepScreenAwakeWhileReading
    }

    /// Whether two settings differ in a given field.
    func differs(_ field: Field, from other: AppSettings) -> Bool {
        switch field {
        case .isHapticsEnabled: return isHapticsEnabled != other.isHapticsEnabled
        case .hapticIntensity: return hapticIntensity != other.hapticIntensity
        case .chapterHapticsEnabled: return chapterHapticsEnabled != other.chapterHapticsEnabled
        case .defaultScrollReadingMode: return defaultScrollReadingMode != other.defaultScrollReadingMode
        case .readerSettings: return readerSettings != other.readerSettings
        case .accent: return accent != other.accent
        case .appearance: return appearance != other.appearance
        case .keepScreenAwakeWhileReading: return keepScreenAwakeWhileReading != other.keepScreenAwakeWhileReading
        }
    }

    private mutating func take(_ field: Field, from other: AppSettings) {
        switch field {
        case .isHapticsEnabled: isHapticsEnabled = other.isHapticsEnabled
        case .hapticIntensity: hapticIntensity = other.hapticIntensity
        case .chapterHapticsEnabled: chapterHapticsEnabled = other.chapterHapticsEnabled
        case .defaultScrollReadingMode: defaultScrollReadingMode = other.defaultScrollReadingMode
        case .readerSettings: readerSettings = other.readerSettings
        case .accent: accent = other.accent
        case .appearance: appearance = other.appearance
        case .keepScreenAwakeWhileReading: keepScreenAwakeWhileReading = other.keepScreenAwakeWhileReading
        }
    }

    /// Records that whatever changed between `previous` and this happened at `date`.
    public mutating func stampChanges(against previous: AppSettings, at date: Date = Date()) {
        for field in Field.allCases where differs(field, from: previous) {
            fieldStamps[field.rawValue] = date
        }
    }

    /// Takes each field from whichever side changed it more recently.
    ///
    /// A tie keeps the local value: the reader is looking at this device, and a field that
    /// changes under them for no visible reason is worse than one that lags by a sync.
    public func merging(remote: AppSettings) -> AppSettings {
        var result = self
        for field in Field.allCases {
            let mine = fieldStamps[field.rawValue] ?? .distantPast
            let theirs = remote.fieldStamps[field.rawValue] ?? .distantPast
            guard theirs > mine else { continue }
            result.take(field, from: remote)
            result.fieldStamps[field.rawValue] = theirs
        }
        return result
    }
}
