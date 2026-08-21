import Foundation
import SwiftUI

/// Which script a piece of text is set in, for the purpose of vertical metrics.
///
/// Hangul, kana and han glyphs are visually far denser than Latin ones and they fill their em
/// box: at the leading Latin is comfortable at, consecutive lines close up and the block turns
/// into a grey slab that is slow to read. The fix is vertical, not horizontal — more leading,
/// and more air between paragraphs.
public enum ReaderScript: String {
    // Raw values are a persisted key — `ReadingSpeed` files each measured pace under one — so
    // they are written out rather than left to follow the case names.
    case latin = "latin"
    case cjk = "cjk"

    /// Leading for the reader's page. Sent to Readium for both scripts — see
    /// `ReaderSettings.epubPreferences(for:)` for why Latin now gets a value here too, not only
    /// CJK.
    ///
    /// 1.50 for Latin is a book leading, not a screen-default one: the value a browser or an
    /// unstyled web view ships (~1.2) is set for short UI strings, not a page a reader's eye
    /// travels down for an hour. 1.70 for CJK stays ~13% over that Latin baseline — Hangul/kana/
    /// han glyphs fill their em box far more than Latin ones, so consecutive lines close up into
    /// a grey slab at Latin leading (see the type's own doc comment above).
    public var lineHeight: Double {
        switch self {
        case .latin: return 1.50
        case .cjk: return 1.70
        }
    }

    /// Space between paragraphs, in rem. Sent to Readium for both scripts, for the same reason
    /// as `lineHeight`.
    public var paragraphSpacing: Double {
        switch self {
        case .latin: return 0.60
        case .cjk: return 0.85
        }
    }

    /// Reading-system CSS the page needs before any user preference is applied.
    ///
    /// Korean is written with spaces between 어절, and Korean typesetting breaks lines at those
    /// spaces. A web view does not: its default `word-break` treats every Hangul syllable as a
    /// break opportunity, so a paragraph breaks mid-word — `계단을 세었다. 조` / `수는 천천히` —
    /// which no Korean book does. `keep-all` restores the convention.
    ///
    /// Readium's own `cjk-horizontal` stylesheet does not cover this: it sets `line-break:
    /// strict`, which governs where breaks are *forbidden* around kana and small signs, not
    /// whether Hangul may break between syllables at all. It is also selected from publication
    /// metadata alone, and CLAUDE.md already records how often that metadata is wrong.
    ///
    /// `overflow-wrap: break-word` rides along because `keep-all` on its own has no escape
    /// hatch: an unspaced run longer than the measure — a URL, a long compound — would push
    /// past the page edge rather than break.
    ///
    /// Applied to Latin text this is a no-op in practice: Latin already breaks at spaces, and
    /// `keep-all` only additionally suppresses breaks inside hyphenated words.
    public var cssOverrides: [String: String?] {
        switch self {
        case .latin: return [:]
        case .cjk: return ["word-break": "keep-all", "overflow-wrap": "break-word"]
        }
    }

    /// Extra leading for text drawn by SwiftUI rather than the web view — quotes, note bodies.
    public var swiftUILineSpacing: CGFloat {
        switch self {
        case .latin: return DipleSpace.s
        case .cjk: return DipleSpace.s + DipleSpace.xs
        }
    }

    // MARK: - Detection

    /// Publication metadata is the reliable signal, so it is consulted first. It is also
    /// routinely wrong or absent in the wild, so a sample of the actual text is the fallback:
    /// a book whose title is in Hangul is a Korean book whatever its OPF claims.
    public static func detect(languages: [String], sample: String) -> ReaderScript {
        for tag in languages {
            let code = tag.lowercased().prefix(2)
            if code == "ko" || code == "ja" || code == "zh" {
                return .cjk
            }
        }
        return detect(in: sample)
    }

    /// A tenth of the letters being CJK is enough: mixed text still reads at the denser
    /// script's leading, and the cost of the extra air on the Latin runs is nil.
    public static func detect(in text: String) -> ReaderScript {
        var cjk = 0
        var letters = 0
        for scalar in text.unicodeScalars {
            guard CharacterSet.alphanumerics.contains(scalar) else { continue }
            letters += 1
            if isCJK(scalar) { cjk += 1 }
        }
        guard letters > 0 else { return .latin }
        return Double(cjk) / Double(letters) >= 0.1 ? .cjk : .latin
    }

    private static func isCJK(_ scalar: Unicode.Scalar) -> Bool {
        switch scalar.value {
        case 0xAC00...0xD7AF,   // Hangul syllables
             0x1100...0x11FF,   // Hangul jamo
             0x3130...0x318F,   // Hangul compatibility jamo
             0x3040...0x30FF,   // Hiragana and katakana
             0x4E00...0x9FFF,   // CJK unified ideographs
             0x3400...0x4DBF:   // CJK extension A
            return true
        default:
            return false
        }
    }
}

public extension View {
    /// Leading for a block of the reader's own words, set from the script it is written in.
    func readingLineSpacing(for text: String) -> some View {
        lineSpacing(ReaderScript.detect(in: text).swiftUILineSpacing)
    }
}

public extension Book {
    /// Which script this source is set in, as far as the library can tell without opening it.
    ///
    /// The reader has the publication's own metadata and uses it (`ReaderViewModel.script`);
    /// a shelf does not, and opening every book to lay out a list is not on the table. Title
    /// and byline are what the row has, and they are a good signal for the same reason the
    /// reader falls back to the title at all: a book called `해변의 카프카` is a Korean book
    /// whatever its OPF claims.
    ///
    /// **Everything that prints an estimate uses this one, including the reader's own bar.**
    /// The reader could do better for itself, and deliberately does not: the same book must not
    /// say "4 h left" on the shelf and "1 h 40 min left" once opened. What the more precise
    /// signal is used for is the measurement — see `ReadingSpeed` — where a sample filed under
    /// the wrong script corrupts the figure for the whole library rather than one row.
    var script: ReaderScript {
        ReaderScript.detect(in: author.map { "\(title) \($0)" } ?? title)
    }
}
