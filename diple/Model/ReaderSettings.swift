import Foundation
import ReadiumNavigator

/// Why the sans option is the CSS generic rather than San Francisco itself.
///
/// `FontFamily.sansSerif` resolves to Helvetica in the web view, so this option has never
/// literally been San Francisco. Routing it through the `-apple-system` / `system-ui`
/// keywords does select SF — and drops every Hangul glyph in the book to tofu. Declaring
/// alternates behind the keyword does not rescue them: an explicit `Apple SD Gothic Neo`
/// fallback was tried and the glyphs stayed missing, so Readium's alternates never reach the
/// effective stack. Korean has to render, so the generic stays until an SF-class face is
/// shipped as a real `fontFaces` declaration.

public enum ReaderFont: String, CaseIterable, Identifiable, Codable {
    // Raw values are the persisted representation and must not be renamed.
    case serif = "Serif"
    case sanFrancisco = "San Francisco"

    public var id: String { rawValue }

    /// What the picker shows. Kept apart from `rawValue` so the label can change without
    /// invalidating what is already stored on readers' devices.
    public var title: String {
        switch self {
        case .serif: return "Serif"
        case .sanFrancisco: return "Sans"
        }
    }

    public var fontFamily: FontFamily {
        switch self {
        case .serif:
            return .serif
        case .sanFrancisco:
            return .sansSerif
        }
    }
}

public enum ReadingMode: String, CaseIterable, Identifiable, Codable {
    case paginated = "Paginated"
    case scroll = "Continuous Scroll"

    public var id: String { rawValue }
}

public struct ReaderSettings: Codable, Equatable {
    /// The multiplier handed to Readium. Stored directly rather than as an index, so the
    /// ladder below can be retuned later without silently reinterpreting what readers have
    /// already chosen.
    public var fontSizeScale: Double = 1.0
    public var font: ReaderFont = .sanFrancisco
    public var theme: Theme = .dark
    public var readingMode: ReadingMode = .paginated

    /// Ten steps, closely spaced around 100% and opening up towards the extremes. Reading
    /// size is adjusted a nudge at a time — a ladder coarse enough that every press is a
    /// visible jump gives no comfortable resting place, which is the failure of the five
    /// steps this replaces.
    public static let fontSizes: [Double] = [0.8, 0.85, 0.9, 0.95, 1.0, 1.05, 1.1, 1.15, 1.25, 1.35]

    /// The ladder shipped previously. Retained solely to migrate stored indices.
    private static let legacyFontSizes: [Double] = [0.8, 0.9, 1.0, 1.15, 1.3]

    public static let defaultFontSizeScale: Double = 1.0

    public init(
        fontSizeScale: Double = ReaderSettings.defaultFontSizeScale,
        font: ReaderFont = .sanFrancisco,
        theme: Theme = .dark,
        readingMode: ReadingMode = .paginated
    ) {
        self.fontSizeScale = fontSizeScale
        self.font = font
        self.theme = theme
        self.readingMode = readingMode
    }

    // MARK: - Step interface

    /// Position on `fontSizes`. The stepper controls drive this; the scale is what persists.
    public var fontSizeStep: Int {
        get { Self.nearestStep(to: fontSizeScale) }
        set { fontSizeScale = Self.fontSizes[min(max(newValue, 0), Self.fontSizes.count - 1)] }
    }

    public static var maximumFontSizeStep: Int { fontSizes.count - 1 }

    public var canDecreaseFontSize: Bool { fontSizeStep > 0 }
    public var canIncreaseFontSize: Bool { fontSizeStep < Self.maximumFontSizeStep }

    /// Percentage shown beside the stepper.
    public var fontSizePercentage: Int { Int((fontSizeScale * 100).rounded()) }

    private static func nearestStep(to scale: Double) -> Int {
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, size) in fontSizes.enumerated() {
            let distance = abs(size - scale)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    public var currentFontSize: Double { fontSizeScale }

    // MARK: - Persistence

    enum CodingKeys: String, CodingKey {
        case fontSizeScale
        case fontSizeStep
        case font
        case theme
        case readingMode
    }

    /// Readers who set a size under the old five-step ladder keep it: the stored index is
    /// resolved against the ladder it was written for, and the resulting multiplier snaps to
    /// the nearest rung of the new one. Reading that index as if it pointed into the current
    /// array would move somebody's 130% down to 100% without them touching anything.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        if let scale = try container.decodeIfPresent(Double.self, forKey: .fontSizeScale) {
            self.fontSizeScale = scale
        } else if let legacyStep = try container.decodeIfPresent(Int.self, forKey: .fontSizeStep) {
            let clamped = min(max(legacyStep, 0), Self.legacyFontSizes.count - 1)
            let legacyScale = Self.legacyFontSizes[clamped]
            self.fontSizeScale = Self.fontSizes[Self.nearestStep(to: legacyScale)]
        } else {
            self.fontSizeScale = Self.defaultFontSizeScale
        }

        self.font = try container.decodeIfPresent(ReaderFont.self, forKey: .font) ?? .sanFrancisco
        self.theme = try container.decodeIfPresent(Theme.self, forKey: .theme) ?? .dark
        self.readingMode = try container.decodeIfPresent(ReadingMode.self, forKey: .readingMode) ?? .paginated
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fontSizeScale, forKey: .fontSizeScale)
        try container.encode(font, forKey: .font)
        try container.encode(theme, forKey: .theme)
        try container.encode(readingMode, forKey: .readingMode)
    }

    // MARK: - Readium

    /// Vertical metrics depend on the script the book is set in, which the settings struct
    /// cannot know on its own — the publication does. `ReaderViewModel` supplies it.
    ///
    /// Readium only honours `lineHeight` and `paragraphSpacing` when advanced settings are on,
    /// which is `publisherStyles == false`. Set the leading without clearing publisher styles
    /// and nothing happens at all. Publisher styles are therefore dropped only for CJK, where
    /// the publisher's own leading is the thing being corrected; a Latin book keeps the
    /// typography its designer chose.
    public func epubPreferences(for script: ReaderScript) -> EPUBPreferences {
        var prefs = EPUBPreferences()
        prefs.fontSize = currentFontSize
        prefs.fontFamily = font.fontFamily
        prefs.theme = theme
        prefs.scroll = (readingMode == .scroll)

        if script == .cjk {
            prefs.publisherStyles = false
            prefs.lineHeight = script.lineHeight
            prefs.paragraphSpacing = script.paragraphSpacing
        }

        return prefs
    }

    public var pdfPreferences: PDFPreferences {
        var prefs = PDFPreferences()
        prefs.scroll = (readingMode == .scroll)
        return prefs
    }
}
