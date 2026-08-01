import Foundation
import SwiftUI

/// Which script a piece of text is set in, for the purpose of vertical metrics.
///
/// Hangul, kana and han glyphs are visually far denser than Latin ones and they fill their em
/// box: at the leading Latin is comfortable at, consecutive lines close up and the block turns
/// into a grey slab that is slow to read. The fix is vertical, not horizontal — more leading,
/// and more air between paragraphs.
public enum ReaderScript {
    case latin
    case cjk

    /// Leading for the reader's page. Only sent to Readium for CJK, which is the case where
    /// the publisher's own value is the problem.
    public var lineHeight: Double {
        switch self {
        case .latin: return 1.4
        case .cjk: return 1.6 // ~15% over the Latin baseline
        }
    }

    /// Space between paragraphs, in rem.
    public var paragraphSpacing: Double {
        switch self {
        case .latin: return 0.5
        case .cjk: return 0.75
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
