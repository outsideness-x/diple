import Foundation
import ReadiumShared
import ReadiumNavigator

/// The shipped reading faces, declared to Readium once when a navigator is created.
///
/// Readium reads `fontFamilyDeclarations` only at construction time — `submitPreferences`, the
/// path a live font switch takes, does not revisit them — so every family the picker can offer
/// has to be declared up front, not just the one currently selected.
///
/// Each declaration lists `sansSerif` as its alternate. Readium resolves that into a real CSS
/// stack (`--USER__fontFamily: "Atkinson Hyperlegible", sans-serif`), which is ordinary
/// per-glyph fallback: Atkinson carries no Cyrillic and neither face carries Hangul, so Russian
/// and Korean fall through to the same generic that the plain "Sans" option already resolves
/// correctly. This is not the trap recorded in CLAUDE.md under "Шрифт читалки" — there the
/// *first* entry was the `-apple-system` keyword, which the web view resolves specially.
public enum ReaderFontDeclarations {
    public static var all: [AnyHTMLFontFamilyDeclaration] {
        ReaderFont.allCases.compactMap(declaration(for:))
    }

    private static func declaration(for font: ReaderFont) -> AnyHTMLFontFamilyDeclaration? {
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
}
