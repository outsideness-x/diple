import Foundation
import ReadiumShared
import ReadiumNavigator

/// The shipped reading faces, declared to Readium once when a navigator is created.
///
/// Readium reads `fontFamilyDeclarations` only at construction time — `submitPreferences`, the
/// path a live font switch takes, does not revisit them — so every family the picker can offer
/// has to be declared up front, not just the one currently selected.
///
/// Two different mechanisms live here, one per pair of `ReaderFont` cases:
///
/// - Atkinson Hyperlegible and OpenDyslexic are bundled OFL files, declared with `alternates:
///   [.sansSerif]`. Readium resolves that into a real CSS stack (`--USER__fontFamily:
///   "Atkinson Hyperlegible", sans-serif`), which is ordinary per-glyph fallback: neither face
///   carries Hangul or Cyrillic, so both scripts fall through to the same generic that a plain
///   sans-serif choice already resolves correctly.
/// - San Francisco is a real system face, declared through `ReaderSystemFontDeclaration`
///   instead — see that type for the cascade-order mechanism that makes it possible without
///   bundling an Apple font file.
/// - Literata (the "Serif" option since 2026-11-06) is bundled too, but set by
///   `ReaderLiterataDeclaration`: a variable upright, an italic in two subsets, and the New York
///   guard family behind it — `DipleLiterata, DipleNewYork, ui-serif` on the page.
public enum ReaderFontDeclarations {
    public static var all: [AnyHTMLFontFamilyDeclaration] {
        // A closure literal, not the bare `declaration(for:)` reference: passing the method as a
        // value strips the main-actor isolation it is declared with, and `compactMap` then calls
        // it from a nonisolated context. Written out, the closure inherits this property's own
        // isolation and the call is where it belongs.
        ReaderFont.allCases.compactMap { declaration(for: $0) } + [newYorkGuard]
    }

    /// The guard family Literata falls back to: Hangul to Apple SD Gothic Neo, kana and han to
    /// Hiragino, everything else to `ui-serif` — New York, which carries Greek, Vietnamese and
    /// whatever an italic subset leaves out. It is the guard New York had as an option of its
    /// own, unchanged, and it is declared whatever the reader picks: Readium resolves an
    /// alternate's stack through its declaration (`ReadiumCSS.resolveFontStack`).
    static let newYorkGuardFamily = FontFamily(rawValue: "DipleNewYork")

    private static var newYorkGuard: AnyHTMLFontFamilyDeclaration {
        ReaderSystemFontDeclaration(
            guardFamilyName: newYorkGuardFamily.rawValue,
            systemKeyword: "ui-serif",
            css: hangulAndHanGuardCSS(familyName: newYorkGuardFamily.rawValue)
        ).eraseToAnyHTMLFontFamilyDeclaration()
    }

    /// Literata's files. The italic is two subsets (Latin with Western European, Cyrillic) and
    /// says so in `unicode-range`; a character outside both — Greek, Vietnamese, Polish `ł` — set
    /// in italic falls through to New York's italic rather than a slanted upright.
    static let literataUpright = "Literata-Variable"
    static let literataItalics: [(file: String, unicodeRange: String)] = [
        ("Literata-Italic-Latin", "U+0000-00FF, U+0131, U+0152-0153, U+02BB-02BC, U+02C6, U+02DA, U+02DC, U+0304, U+0308, U+0329, U+2000-206F, U+20AC, U+2122, U+2191, U+2193, U+2212, U+2215, U+FEFF, U+FFFD"),
        ("Literata-Italic-Cyrillic", "U+0301, U+0400-045F, U+0490-0491, U+04B0-04B1, U+2116"),
    ]

    private static var literata: AnyHTMLFontFamilyDeclaration? {
        guard
            let url = Bundle.main.url(forResource: literataUpright, withExtension: "ttf"),
            let upright = FileURL(url: url)
        else { return nil }
        let italics = literataItalics.compactMap { face -> ReaderLiterataDeclaration.Italic? in
            guard
                let url = Bundle.main.url(forResource: face.file, withExtension: "woff2"),
                let file = FileURL(url: url)
            else { return nil }
            return ReaderLiterataDeclaration.Italic(file: file, unicodeRange: face.unicodeRange)
        }
        return ReaderLiterataDeclaration(
            fontFamily: ReaderFont.serif.fontFamily,
            fallback: newYorkGuardFamily,
            upright: upright,
            italics: italics
        ).eraseToAnyHTMLFontFamilyDeclaration()
    }

    private static func declaration(for font: ReaderFont) -> AnyHTMLFontFamilyDeclaration? {
        // An upright that failed to resolve leaves "Serif" undeclared, like any bundled family
        // whose files are missing — see the guard at the end of this method.
        if font == .serif { return literata }

        if let systemKeyword = font.systemFallbackKeyword {
            // A system face legitimately has no files behind it — `local()` is the point — so
            // this branch never touches `bundledFaces` and always produces a declaration. The
            // guard below, in the other branch, is what still catches a *bundled* family whose
            // files failed to resolve; that guard is not needed here because there is nothing
            // to fail to resolve.
            return ReaderSystemFontDeclaration(
                guardFamilyName: font.fontFamily.rawValue,
                systemKeyword: systemKeyword,
                css: Self.hangulAndHanGuardCSS(familyName: font.fontFamily.rawValue)
            ).eraseToAnyHTMLFontFamilyDeclaration()
        }

        let faces = font.bundledFaces.compactMap { face -> CSSFontFace? in
            guard
                let url = Bundle.main.url(forResource: face.file, withExtension: "otf"),
                let fileURL = FileURL(url: url)
            else { return nil }

            return CSSFontFace(
                file: fileURL,
                // Only the upright regular is preloaded. The other three are wanted by a
                // minority of paragraphs, and preloading all four would have the web view fetch
                // ~1 MB of OpenDyslexic before the first page of a book that may never use bold.
                preload: !face.isBold && !face.isItalic,
                style: face.isItalic ? .italic : .normal,
                weight: .standard(face.isBold ? .bold : .normal)
            )
        }

        // A generic has no files, and a family whose files somehow failed to resolve must not be
        // declared at all: an empty declaration would name a family with nothing behind it, and
        // the page would silently render in the fallback while the picker claimed otherwise.
        guard !faces.isEmpty else { return nil }

        return CSSFontFamilyDeclaration(
            fontFamily: font.fontFamily,
            alternates: [.sansSerif],
            fontFaces: faces
        ).eraseToAnyHTMLFontFamilyDeclaration()
    }

    /// Hangul goes to Apple SD Gothic Neo; kana and han go to Hiragino Sans — both ship on every
    /// iOS device, so `local()` always resolves. Chinese text gets Japanese glyph variants for
    /// shared ideographs as a result; that is a known, accepted limitation, not a reason to add
    /// a third guard bucket. No Cyrillic guard either: New York, San Francisco and Literata all
    /// carry Cyrillic themselves, confirmed live on a Russian paragraph in each.
    ///
    /// Neither rule carries a `font-style`/`font-weight` descriptor. Leaving them off lets one
    /// rule serve upright, italic and bold at once, with the web view synthesizing whichever two
    /// it does not have — confirmed live, including synthesized Hangul italic.
    private static func hangulAndHanGuardCSS(familyName: String) -> String {
        """
        @font-face { font-family: "\(familyName)"; src: local("Apple SD Gothic Neo"); unicode-range: U+1100-11FF, U+3130-318F, U+A960-A97F, U+AC00-D7AF, U+D7B0-D7FF; }
        @font-face { font-family: "\(familyName)"; src: local("Hiragino Sans"); unicode-range: U+2E80-2FDF, U+3000-303F, U+3040-30FF, U+31F0-31FF, U+3400-4DBF, U+4E00-9FFF, U+F900-FAFF, U+FF00-FFEF; }
        """
    }
}

/// A guard font family that reserves Hangul and CJK glyphs in front of a system-font keyword.
///
/// `ui-serif` and `-apple-system` resolve to the real New York and San Francisco — but WebKit
/// treats either keyword as an opaque unit: once one is in the font stack, it swallows every
/// family that follows it, alternates included. An explicit `"Apple SD Gothic Neo"` alternate
/// declared *behind* the keyword was tried and does nothing; Readium's own alternate-resolution
/// never reaches the effective stack once the keyword owns it (see "Шрифт читалки" in
/// CLAUDE.md for that dead end). What the keyword cannot do is take glyphs away from a family
/// placed *before* it: a `unicode-range`-restricted family claims exactly the code points it
/// lists and leaves the rest of the cascade — including the keyword sitting right behind it —
/// untouched.
///
/// That is what `fontFamily` is here: a bare, unquoted guard name that exists only to carry the
/// `unicode-range`. The system keyword goes in `alternates`, and Readium's own
/// `ReadiumCSS.resolveFontStack` (`[fontFamily.rawValue] + alternates.flatMap(resolveFontStack)`)
/// turns the pair into exactly `GuardName, keyword` on the page. The guard name has to stay a
/// bare identifier — no space, no quote — because `String.css()` in Readium's own
/// `CSSProperties.swift` only quotes a family that contains one; an unquoted `ui-serif` reaching
/// the page as a keyword rather than a literal family name is the entire reason this approach
/// is possible, and the guard name riding in front of it has to reach the page the same way.
///
/// `CSSFontFamilyDeclaration`/`CSSFontFace` cannot express any of this: they only know how to
/// serve a bundled *file*, and the guard's whole point is `src: local(...)` — naming a face
/// already on the device, so no Apple font ships in the bundle. `inject` therefore writes the
/// `<style>` tag itself instead of going through `CSSFontFamilyDeclaration.inject`'s
/// `HTMLInjection.style(_:)`: that type is `internal` to the Readium module and unreachable from
/// a declaration conformed in the app module.
public struct ReaderSystemFontDeclaration: HTMLFontFamilyDeclaration {
    public let fontFamily: FontFamily
    public let alternates: [FontFamily]

    /// The `@font-face` rules the guard family resolves to. Passed in fully formed rather than
    /// assembled here, so this type stays about the injection mechanism and the CSS content
    /// stays next to the `ReaderFontDeclarations` call site that has to keep it in sync with
    /// which faces ship on the OS.
    private let css: String

    public init(guardFamilyName: String, systemKeyword: String, css: String) {
        self.fontFamily = FontFamily(rawValue: guardFamilyName)
        self.alternates = [FontFamily(rawValue: systemKeyword)]
        self.css = css
    }

    public func inject(in html: String, servingFile: (FileURL) throws -> any AbsoluteURL) throws -> String {
        // Case-insensitive: XHTML capitalization of the tag is not guaranteed. A document with
        // no `</head>` at all is malformed but not impossible, and invariant #2 forbids
        // force-unwrapping the search result to find out — hand the page back untouched rather
        // than crash the reader over one bad chapter.
        guard let headCloseStart = html.range(of: "</head>", options: .caseInsensitive)?.lowerBound else {
            return html
        }

        var result = html
        result.insert(contentsOf: "<style type=\"text/css\">\(css)</style>", at: headCloseStart)
        return result
    }
}

/// Literata on the page: the bundled variable upright (weights 200–900, optical sizes following
/// the type size, since WebKit's `font-optical-sizing` is `auto`), the italic as two `woff2`
/// subsets, and the New York guard family behind them as the one alternate.
///
/// Written by hand rather than as a `CSSFontFamilyDeclaration`: `CSSFontFace` has no
/// `unicode-range`, and without it an italic subset would claim every character, so an italic
/// Greek word would come out in a font that has no Greek. The splice is the same plain
/// search for `</head>` that `ReaderSystemFontDeclaration` uses, for the same reason —
/// Readium's `HTMLInjection` is internal to its module.
///
/// The guard family stays out of this family on purpose. Its `local()` rules carry no style or
/// weight, which is what lets the web view synthesize Hangul italic and bold for New York; put
/// beside Literata's own italic faces, an italic Hangul run would be matched against those
/// first, find nothing, and skip the family.
public struct ReaderLiterataDeclaration: HTMLFontFamilyDeclaration {
    public struct Italic {
        public let file: FileURL
        public let unicodeRange: String
    }

    public let fontFamily: FontFamily
    public let alternates: [FontFamily]
    private let upright: FileURL
    private let italics: [Italic]

    public init(fontFamily: FontFamily, fallback: FontFamily, upright: FileURL, italics: [Italic]) {
        self.fontFamily = fontFamily
        self.alternates = [fallback]
        self.upright = upright
        self.italics = italics
    }

    public func inject(in html: String, servingFile: (FileURL) throws -> any AbsoluteURL) throws -> String {
        guard let headCloseStart = html.range(of: "</head>", options: .caseInsensitive)?.lowerBound else {
            return html
        }

        let family = fontFamily.rawValue
        let uprightURL = try servingFile(upright).string
        var rules = [
            "@font-face { font-family: \"\(family)\"; src: url(\"\(uprightURL)\") format(\"truetype\"); font-style: normal; font-weight: 200 900; }"
        ]
        for italic in italics {
            let url = try servingFile(italic.file).string
            rules.append(
                "@font-face { font-family: \"\(family)\"; src: url(\"\(url)\") format(\"woff2\"); font-style: italic; font-weight: 200 900; unicode-range: \(italic.unicodeRange); }"
            )
        }

        // Only the upright is preloaded: it sets every line of the first page, the italic a
        // word here and there. Self-closed: a chapter is XHTML, parsed as XML, and an unclosed
        // `<link>` turns the whole page into the parser's error report.
        let preload = "<link rel=\"preload\" href=\"\(uprightURL)\" as=\"font\" crossorigin=\"\"/>"
        var result = html
        result.insert(
            contentsOf: preload + "<style type=\"text/css\">" + rules.joined(separator: "\n") + "</style>",
            at: headCloseStart
        )
        return result
    }
}
