import Foundation
import ReadiumShared

/// The reading-order metadata already present in the local full-text index. It is derived from
/// the publication and never synced; Second Read uses it only to make old or partial locators
/// sortable when their own global progression is missing.
public nonisolated struct SecondReadSection: Equatable, Sendable {
    public let href: String
    public let title: String?
    public let ordinal: Int

    public init(href: String, title: String?, ordinal: Int) {
        self.href = href
        self.title = title
        self.ordinal = ordinal
    }
}

/// A deterministic position assembled from Readium's stable locator fields. The section index
/// is preferred when available because it is the publication's reading order; the remaining
/// fields keep highlights useful when the derived content index has not reached this book yet.
public nonisolated struct SecondReadPosition: Equatable, Sendable {
    public let sectionOrdinal: Int?
    public let totalProgression: Double?
    public let position: Int?
    public let progression: Double?
    public let href: String
    public let selector: String

    public init(
        sectionOrdinal: Int?,
        totalProgression: Double?,
        position: Int?,
        progression: Double?,
        href: String,
        selector: String
    ) {
        self.sectionOrdinal = sectionOrdinal
        self.totalProgression = totalProgression
        self.position = position
        self.progression = progression
        self.href = href
        self.selector = selector
    }

    public func isBefore(_ other: Self, id: String, otherID: String) -> Bool {
        if let comparison = Self.compare(sectionOrdinal, other.sectionOrdinal) {
            return comparison
        }
        if let comparison = Self.compare(totalProgression, other.totalProgression) {
            return comparison
        }
        if let comparison = Self.compare(position, other.position) {
            return comparison
        }
        if href != other.href {
            return href < other.href
        }
        if let comparison = Self.compare(progression, other.progression) {
            return comparison
        }
        if selector != other.selector {
            return selector < other.selector
        }
        return id < otherID
    }

    /// Known publication coordinates sort before missing coordinates. Applying that rule at
    /// every level produces a strict total order; pairwise "use whichever fields both happen
    /// to have" comparisons can form cycles when old and new locators are mixed.
    private static func compare<Value: Comparable>(_ lhs: Value?, _ rhs: Value?) -> Bool? {
        switch (lhs, rhs) {
        case let (lhs?, rhs?) where lhs != rhs: return lhs < rhs
        case (_?, nil): return true
        case (nil, _?): return false
        default: return nil
        }
    }
}

/// One lightweight page in the personal edition. Its identity is the highlight's identity;
/// there is no Second Read row to duplicate or synchronize.
public nonisolated struct SecondReadItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let bookID: String
    public let locatorJSON: String
    public let locator: Locator?
    public let chapterTitle: String?
    public let highlightedText: String
    public let noteText: String?
    public let position: SecondReadPosition
    public let showsChapterMarker: Bool
    public let isSourceAvailable: Bool

    public var canShowContext: Bool {
        guard let locator else { return false }
        return isSourceAvailable || locator.text.before != nil || locator.text.after != nil
    }

    public var canOpenInBook: Bool {
        locator != nil && isSourceAvailable
    }
}

/// Transient surrounding prose. Keeping the paragraph on either side distinct preserves the
/// publication's rhythm, while the target paragraph is split so the saved passage can remain a
/// visual and accessibility anchor inside it.
public nonisolated struct SecondReadContext: Equatable, Sendable {
    public let precedingParagraphs: [String]
    public let targetPrefix: String
    public let highlightedText: String
    public let targetSuffix: String
    public let followingParagraphs: [String]

    public init(
        precedingParagraphs: [String],
        targetPrefix: String,
        highlightedText: String,
        targetSuffix: String,
        followingParagraphs: [String]
    ) {
        self.precedingParagraphs = precedingParagraphs
        self.targetPrefix = targetPrefix
        self.highlightedText = highlightedText
        self.targetSuffix = targetSuffix
        self.followingParagraphs = followingParagraphs
    }
}

/// Pure context shaping, kept separate from publication I/O so paragraph edges, long prose and
/// locator fallbacks are testable without opening a renderer or creating book fixtures.
public nonisolated enum SecondReadContextExtractor {
    private static let targetSideLimit = 560
    private static let neighbourLimit = 640

    public static func makeContext(
        paragraphs rawParagraphs: [String],
        highlightedText rawHighlight: String,
        approximateProgression: Double? = nil,
        preferredParagraphIndex: Int? = nil
    ) -> SecondReadContext? {
        let paragraphs = rawParagraphs.map(normalized).filter { !$0.isEmpty }
        let highlight = normalized(rawHighlight)
        guard !paragraphs.isEmpty, !highlight.isEmpty else { return nil }

        let approximateIndex = preferredParagraphIndex.map {
            min(max($0, 0), paragraphs.count - 1)
        } ?? approximateProgression.map {
            min(max(Int(($0 * Double(paragraphs.count)).rounded(.down)), 0), paragraphs.count - 1)
        } ?? 0

        var matches: [(start: Int, end: Int, text: String, range: Range<String.Index>)] = []
        for start in paragraphs.indices {
            for length in 1 ... min(3, paragraphs.count - start) {
                let end = start + length
                let candidate = paragraphs[start ..< end].joined(separator: " ")
                if let range = candidate.range(of: highlight) {
                    matches.append((start, end, candidate, range))
                }
            }
        }

        guard let match = matches.min(by: { lhs, rhs in
            let lhsSpan = lhs.end - lhs.start
            let rhsSpan = rhs.end - rhs.start
            if lhsSpan != rhsSpan { return lhsSpan < rhsSpan }
            let lhsDistance = abs(lhs.start - approximateIndex)
            let rhsDistance = abs(rhs.start - approximateIndex)
            if lhsDistance != rhsDistance { return lhsDistance < rhsDistance }
            return lhs.start < rhs.start
        }) else { return nil }

        let prefix = String(match.text[..<match.range.lowerBound])
        let exactHighlight = String(match.text[match.range])
        let suffix = String(match.text[match.range.upperBound...])

        let preceding: [String]
        if match.start > paragraphs.startIndex {
            preceding = [sentenceAwareSuffix(paragraphs[match.start - 1], limit: neighbourLimit)]
        } else {
            preceding = []
        }

        let following: [String]
        if match.end < paragraphs.endIndex {
            following = [sentenceAwarePrefix(paragraphs[match.end], limit: neighbourLimit)]
        } else {
            following = []
        }

        return SecondReadContext(
            precedingParagraphs: preceding.filter { !$0.isEmpty },
            targetPrefix: sentenceAwareSuffix(prefix, limit: targetSideLimit),
            highlightedText: exactHighlight,
            targetSuffix: sentenceAwarePrefix(suffix, limit: targetSideLimit),
            followingParagraphs: following.filter { !$0.isEmpty }
        )
    }

    /// Readium stores a small before/after sample with many selection locators. It is a useful
    /// final fallback when the publication file is temporarily missing, but is never persisted
    /// by Second Read itself.
    public static func locatorFallback(
        highlightedText: String,
        locatorText: Locator.Text
    ) -> SecondReadContext? {
        let text = locatorText.sanitized()
        let before = normalized(text.before ?? "")
        let after = normalized(text.after ?? "")
        let highlight = normalized(highlightedText)
        guard !highlight.isEmpty, !before.isEmpty || !after.isEmpty else { return nil }

        return SecondReadContext(
            precedingParagraphs: [],
            targetPrefix: sentenceAwareSuffix(before, limit: targetSideLimit),
            highlightedText: highlight,
            targetSuffix: sentenceAwarePrefix(after, limit: targetSideLimit),
            followingParagraphs: []
        )
    }

    private static func normalized(_ text: String) -> String {
        text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    private static func sentenceAwareSuffix(_ text: String, limit: Int) -> String {
        let text = normalized(text)
        guard text.count > limit else { return text }
        var result = String(text.suffix(limit))
        if let boundary = result.firstIndex(where: isSentenceBoundary) {
            result = String(result[result.index(after: boundary)...])
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }

    private static func sentenceAwarePrefix(_ text: String, limit: Int) -> String {
        let text = normalized(text)
        guard text.count > limit else { return text }
        var result = String(text.prefix(limit))
        if let boundary = result.lastIndex(where: isSentenceBoundary) {
            result = String(result[...boundary])
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func isSentenceBoundary(_ character: Character) -> Bool {
        ".!?。！？".contains(character)
    }
}

/// Navigation values carry stored JSON rather than a second location representation. The reader
/// parses it through the same compatibility helper used for saved progress and highlights.
public nonisolated struct SecondReadSourceRoute: Hashable, Sendable {
    public let book: Book
    public let locatorJSON: String?

    public init(book: Book, locatorJSON: String?) {
        self.book = book
        self.locatorJSON = locatorJSON
    }
}
