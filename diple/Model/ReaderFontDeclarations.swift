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
/// - New York and San Francisco are real system faces, declared through
///   `ReaderSystemFontDeclaration` instead — see that type for the cascade-order mechanism that
///   makes them possible without bundling an Apple font file.
public enum ReaderFontDeclarations {
    public static var all: [AnyHTMLFontFamilyDeclaration] {
        // A closure literal, not the bare `declaration(for:)` reference: passing the method as a
        // value strips the main-actor isolation it is declared with, and `compactMap` then calls
        // it from a nonisolated context. Written out, the closure inherits this property's own
        // isolation and the call is where it belongs.
        ReaderFont.allCases.compactMap { declaration(for: $0) }
    }

    private static func declaration(for font: ReaderFont) -> AnyHTMLFontFamilyDeclaration? {
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
    /// a third guard bucket. No Cyrillic guard either: both New York and San Francisco carry
    /// Cyrillic themselves, confirmed live on a Russian paragraph in each.
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
