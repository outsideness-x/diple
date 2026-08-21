import Foundation
import ReadiumNavigator

/// New York and San Francisco are real system faces now, not the CSS generics `serif`/
/// `sans-serif` these two options used to mean — those never resolved to Apple's own faces in
/// the web view (Times/Helvetica), so neither option was ever literally what its name claimed.
/// Reaching the real faces through their system keywords (`ui-serif`, `-apple-system`) used to
/// cost every Hangul glyph in the book; `ReaderFontDeclarations` now fronts each keyword with a
/// `unicode-range`-restricted guard family that claims Hangul and CJK before the keyword can
/// swallow the rest of the cascade. See "Шрифт читалки" in CLAUDE.md for the finding.

public enum ReaderFont: String, CaseIterable, Identifiable, Codable {
    // Raw values are the persisted representation and must not be renamed.
    case serif = "Serif"
    case sanFrancisco = "San Francisco"
    case atkinson = "Atkinson Hyperlegible"
    case openDyslexic = "OpenDyslexic"

    public var id: String { rawValue }

    /// What the picker shows. Kept apart from `rawValue` so the label can change without
    /// invalidating what is already stored on readers' devices.
    public var title: String {
        switch self {
        case .serif: return "New York"
        case .sanFrancisco: return "San Francisco"
        case .atkinson: return "Hyperlegible"
        case .openDyslexic: return "Dyslexic"
        }
    }

    /// The value handed to Readium as the `fontFamily` preference. For the two system faces
    /// this is not the face's own name — WebKit does not resolve `"New York"`/`"SF Pro"` by name
    /// at all (see CLAUDE.md) — it is the bare guard family declared for it in
    /// `ReaderFontDeclarations`, which is what actually carries Hangul and CJK in front of the
    /// system keyword.
    public var fontFamily: FontFamily {
        switch self {
        case .serif:
            return FontFamily(rawValue: "DipleNewYork")
        case .sanFrancisco:
            return FontFamily(rawValue: "DipleSanFrancisco")
        case .atkinson:
            return FontFamily(rawValue: "Atkinson Hyperlegible")
        case .openDyslexic:
            return FontFamily(rawValue: "OpenDyslexic")
        }
    }

    /// The system keyword a guard family stands in front of — non-`nil` exactly for the two
    /// faces `ReaderFontDeclarations` backs with a `ReaderSystemFontDeclaration` rather than
    /// bundled files. `ui-serif`/`-apple-system` are CSS keywords, not family names, which is
    /// why they are never quoted on the way to the page (`String.css()` in Readium's
    /// `CSSProperties.swift` only quotes a family containing a space or a quote) and why WebKit
    /// resolves them to the real New York / San Francisco instead of falling through.
    var systemFallbackKeyword: String? {
        switch self {
        case .serif: return "ui-serif"
        case .sanFrancisco: return "-apple-system"
        case .atkinson, .openDyslexic: return nil
        }
    }

    /// The family name UIKit knows this face by, for the picker's own label. `nil` for the two
    /// options that are CSS generics rather than shipped files — there is no app-side font to
    /// name, and the label falls back to a system face.
    public var registeredFamilyName: String? {
        switch self {
        case .serif, .sanFrancisco: return nil
        case .atkinson: return "Atkinson Hyperlegible"
        case .openDyslexic: return "OpenDyslexic"
        }
    }

    /// The four files that make up a shipped family, or none for a generic.
    ///
    /// Both faces are Latin-only for practical purposes — Atkinson carries no Cyrillic at all
    /// and neither carries Hangul — so every declaration lists `sansSerif` as its alternate.
    /// Readium turns that into a real CSS stack (`"Atkinson Hyperlegible", sans-serif`), and
    /// per-glyph fallback covers Russian and Korean exactly as the plain Sans option already
    /// does. This is a different situation from the `-apple-system` keyword recorded in
    /// CLAUDE.md, where the *first* family was resolved specially by the web view.
    var bundledFaces: [(file: String, isBold: Bool, isItalic: Bool)] {
        switch self {
        case .serif, .sanFrancisco:
            return []
        case .atkinson:
            return [
                ("AtkinsonHyperlegible-Regular", false, false),
                ("AtkinsonHyperlegible-Bold", true, false),
                ("AtkinsonHyperlegible-Italic", false, true),
                ("AtkinsonHyperlegible-BoldItalic", true, true),
            ]
        case .openDyslexic:
            return [
                ("OpenDyslexic-Regular", false, false),
                ("OpenDyslexic-Bold", true, false),
                ("OpenDyslexic-Italic", false, true),
                ("OpenDyslexic-BoldItalic", true, true),
            ]
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
    // A book set in a serif is the register the whole redesign is aiming at; San Francisco
    // stays one tap away in the picker.
    public var font: ReaderFont = .serif
    public var theme: Theme = .dark
    public var readingMode: ReadingMode = .paginated

    /// Factor Readium multiplies its horizontal gutter by. Stored as a multiplier, not an
    /// index, for the same reason as `fontSizeScale`: an index reinterprets itself the moment
    /// the ladder is retuned, silently moving a reader's chosen value to a different one.
    public var pageMargins: Double = 0.65

    /// Ten steps, closely spaced around 100% and opening up towards the extremes. Reading
    /// size is adjusted a nudge at a time — a ladder coarse enough that every press is a
    /// visible jump gives no comfortable resting place, which is the failure of the five
    /// steps this replaces.
    public static let fontSizes: [Double] = [0.8, 0.85, 0.9, 0.95, 1.0, 1.05, 1.1, 1.15, 1.25, 1.35]

    /// The ladder shipped previously. Retained solely to migrate stored indices.
    private static let legacyFontSizes: [Double] = [0.8, 0.9, 1.0, 1.15, 1.3]

    public static let defaultFontSizeScale: Double = 1.0

    /// Six steps from edge-to-edge to generous, spanning `EPUBPreferencesEditor.pageMargins`'s
    /// own accepted range (`0.0 ... 4.0` in the resolved swift-toolkit 3.11.0 checkout — see
    /// `Sources/Navigator/EPUB/Preferences/EPUBPreferencesEditor.swift`).
    public static let pageMarginsSteps: [Double] = [0.0, 0.35, 0.65, 1.0, 1.25, 1.5]

    public static let defaultPageMargins: Double = 1.0

    public init(
        fontSizeScale: Double = ReaderSettings.defaultFontSizeScale,
        font: ReaderFont = .serif,
        theme: Theme = .dark,
        readingMode: ReadingMode = .paginated,
        pageMargins: Double = ReaderSettings.defaultPageMargins
    ) {
        self.fontSizeScale = fontSizeScale
        self.font = font
        self.theme = theme
        self.readingMode = readingMode
        self.pageMargins = pageMargins
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

    /// Position on `pageMarginsSteps`. Mirrors `fontSizeStep`.
    public var pageMarginsStep: Int {
        get { Self.nearestPageMarginsStep(to: pageMargins) }
        set { pageMargins = Self.pageMarginsSteps[min(max(newValue, 0), Self.pageMarginsSteps.count - 1)] }
    }

    public static var maximumPageMarginsStep: Int { pageMarginsSteps.count - 1 }

    public var canDecreasePageMargins: Bool { pageMarginsStep > 0 }
    public var canIncreasePageMargins: Bool { pageMarginsStep < Self.maximumPageMarginsStep }

    /// Percentage shown beside the stepper, relative to Readium's own 1× gutter.
    public var pageMarginsPercentage: Int { Int((pageMargins * 100).rounded()) }

    private static func nearestPageMarginsStep(to factor: Double) -> Int {
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude
        for (index, step) in pageMarginsSteps.enumerated() {
            let distance = abs(step - factor)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    // MARK: - Persistence

    enum CodingKeys: String, CodingKey {
        case fontSizeScale
        case fontSizeStep
        case font
        case theme
        case readingMode
        case pageMargins
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

        self.font = try container.decodeIfPresent(ReaderFont.self, forKey: .font) ?? .serif
        self.theme = try container.decodeIfPresent(Theme.self, forKey: .theme) ?? .dark
        self.readingMode = try container.decodeIfPresent(ReadingMode.self, forKey: .readingMode) ?? .paginated
        self.pageMargins = try container.decodeIfPresent(Double.self, forKey: .pageMargins) ?? Self.defaultPageMargins
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(fontSizeScale, forKey: .fontSizeScale)
        try container.encode(font, forKey: .font)
        try container.encode(theme, forKey: .theme)
        try container.encode(readingMode, forKey: .readingMode)
        try container.encode(pageMargins, forKey: .pageMargins)
    }

    // MARK: - Readium

    /// Vertical metrics depend on the script the book is set in, which the settings struct
    /// cannot know on its own — the publication does. `ReaderViewModel` supplies it.
    ///
    /// **Publisher styles are off for every reflowable book, Latin included — this reverses what
    /// this comment used to say.** The previous position was that a Latin book keeps the
    /// typography its designer chose, and only CJK — where the publisher's leading is the thing
    /// being corrected — dropped it. That argument stopped holding once diple started choosing
    /// the *face* (New York/San Francisco, see "Шрифт читалки" in CLAUDE.md): honouring the
    /// publisher for alignment and leading while overriding the font underneath it is not
    /// deference, it produces a font the publisher never designed against, set with the
    /// publisher's own justification and no hyphenation — rivers of white on nearly every
    /// paragraph at a phone measure. Apple Books does the same thing the moment a reader touches
    /// the font. See "Шрифт читалки" in CLAUDE.md for the fuller record of this reversal.
    ///
    /// `publisherStyles == false` (Readium's "advanced settings") is the gate for `textAlign`,
    /// `lineHeight`, `paragraphSpacing` and `hyphens` — none of them do anything while publisher
    /// styles are on (`EPUBPreferencesEditor.swift`). `pageMargins` is the one exception: it only
    /// multiplies Readium's own gutter variable and is effective regardless, so it was already
    /// unconditional above this method's `if` before there was one.
    public func epubPreferences(for script: ReaderScript) -> EPUBPreferences {
        var prefs = EPUBPreferences()
        prefs.fontSize = currentFontSize
        prefs.fontFamily = font.fontFamily
        prefs.theme = theme
        prefs.scroll = (readingMode == .scroll)
        prefs.pageMargins = pageMargins

        prefs.publisherStyles = false
        // Ragged right, not justified: Matter's reference page reads as designed rather than
        // stretched, and it is what keeps rivers of white out of a narrow measure. `.start`
        // rather than `.left` respects RTL publications if one is ever opened.
        prefs.textAlign = .start
        // Hyphenation stays on with ragged-right, not just with justify: Russian and German
        // compounds at a phone measure produce an ugly rag without it (verified live —
        // `hyphens: auto` correctly hyphenated "in-ternationalization" in a WKWebView test). It
        // needs the document to carry a `lang`, which EPUBs normally do.
        prefs.hyphens = true
        prefs.lineHeight = script.lineHeight
        prefs.paragraphSpacing = script.paragraphSpacing

        return prefs
    }

    public var pdfPreferences: PDFPreferences {
        var prefs = PDFPreferences()
        prefs.scroll = (readingMode == .scroll)
        return prefs
    }
}
