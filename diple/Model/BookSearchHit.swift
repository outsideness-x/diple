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
}
