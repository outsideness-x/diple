import Foundation
import ReadiumShared

/// One in-book search hit: a `bookContent` chunk (see `AppDatabase.searchBookContent`) scoped
/// to a single book, with its own locator to jump straight to the passage.
///
/// Deliberately a separate type from `GlobalSearchResult`: that one carries the shape of the
/// library-wide search (kind, subtitle, an optional locator for four different entity types),
/// while every hit here is always a book-content chunk with a mandatory locator and a chapter
/// to group by.
public nonisolated struct BookSearchHit: Identifiable, Sendable, Hashable {
    /// Sentinel control characters `AppDatabase.searchBookContent` wraps a match in via FTS5's
    /// `snippet()`. Chosen because real prose never contains them, so the search sheet can
    /// split on them to bold the hit inline instead of parsing a second markup syntax out of
    /// the snippet text.
    public static let matchMarkerStart = "\u{0001}"
    public static let matchMarkerEnd = "\u{0002}"

    public let id: String
    public let chapterTitle: String
    public let href: String
    public let snippet: String
    public let locatorJSON: String

    public init(id: String, chapterTitle: String, href: String, snippet: String, locatorJSON: String) {
        self.id = id
        self.chapterTitle = chapterTitle
        self.href = href
        self.snippet = snippet
        self.locatorJSON = locatorJSON
    }

    public var parsedLocator: Locator? {
        Locator.from(jsonString: locatorJSON)
    }

    /// Alternating prose and matched runs from the FTS5 snippet. This is the single definition
    /// of the sentinel format for both the concordance and its wrapping fallback.
    var segments: [SnippetSegment] {
        var result: [SnippetSegment] = []
        var remainder = snippet[...]

        while let startRange = remainder.range(of: Self.matchMarkerStart) {
            let afterStart = remainder[startRange.upperBound...]
            guard let endRange = afterStart.range(of: Self.matchMarkerEnd) else {
                appendPlain(String(remainder), to: &result)
                return result
            }

            appendPlain(String(remainder[..<startRange.lowerBound]), to: &result)
            result.append(SnippetSegment(
                text: String(afterStart[..<endRange.lowerBound]),
                isMatch: true
            ))
            remainder = afterStart[endRange.upperBound...]
        }

        appendPlain(String(remainder), to: &result)
        return result
    }

    /// The first match set on a fixed axis, with every later match folded back into context.
    public nonisolated var concordance: (before: String, match: String, after: String)? {
        let segments = segments
        guard let matchIndex = segments.firstIndex(where: \.isMatch) else { return nil }

        let before = segments[..<matchIndex].map(\.text).joined()
        let match = segments[matchIndex].text
        let after = segments[segments.index(after: matchIndex)...].map(\.text).joined()

        return (
            before: Self.trimLeadingSpace(from: Self.collapsingWhitespace(in: before)),
            match: Self.collapsingWhitespace(in: match),
            after: Self.trimTrailingSpace(from: Self.collapsingWhitespace(in: after))
        )
    }

    private nonisolated func appendPlain(_ text: String, to segments: inout [SnippetSegment]) {
        let markerFree = text
            .replacingOccurrences(of: Self.matchMarkerStart, with: "")
            .replacingOccurrences(of: Self.matchMarkerEnd, with: "")
        guard !markerFree.isEmpty else { return }

        if let last = segments.last, !last.isMatch {
            segments[segments.index(before: segments.endIndex)] = SnippetSegment(
                text: last.text + markerFree,
                isMatch: false
            )
        } else {
            segments.append(SnippetSegment(text: markerFree, isMatch: false))
        }
    }

    private nonisolated static func collapsingWhitespace(in text: String) -> String {
        var result = ""
        var isInWhitespace = false

        for character in text {
            if character.isWhitespace {
                if !isInWhitespace {
                    result.append(" ")
                    isInWhitespace = true
                }
            } else {
                result.append(character)
                isInWhitespace = false
            }
        }
        return result
    }

    /// The left edge of `before` is external; its right edge touches the match and keeps its
    /// collapsed space. `after` applies the mirror rule below.
    private nonisolated static func trimLeadingSpace(from text: String) -> String {
        String(text.drop(while: { $0 == " " }))
    }

    private nonisolated static func trimTrailingSpace(from text: String) -> String {
        String(text.reversed().drop(while: { $0 == " " }).reversed())
    }
}

struct SnippetSegment: Sendable, Hashable {
    let text: String
    let isMatch: Bool
}
