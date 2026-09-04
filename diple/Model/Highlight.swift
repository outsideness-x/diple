import Foundation
import GRDB
import ReadiumShared

public struct Highlight: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var bookId: String
    public var locator: String
    public var text: String
    /// The reader's own thought attached to this saved passage. `nil` means no comment;
    /// blank input is normalized to `nil` before persistence.
    public var comment: String?
    public var colorHex: String
    public var createdAt: Date
    /// A copy of the book's title/author taken when the highlight is saved and kept current
    /// whenever the book's metadata changes. `bookId` has no foreign key, so once the book is
    /// deleted this snapshot is the only place left to find what it was.
    public var bookTitle: String?
    public var bookAuthor: String?

    public init(
        id: String = UUID().uuidString,
        bookId: String,
        locator: String,
        text: String,
        comment: String? = nil,
        colorHex: String = "#FFD60A",
        createdAt: Date = Date(),
        bookTitle: String? = nil,
        bookAuthor: String? = nil
    ) {
        self.id = id
        self.bookId = bookId
        self.locator = locator
        self.text = text
        self.comment = comment
        self.colorHex = colorHex
        self.createdAt = createdAt
        self.bookTitle = bookTitle
        self.bookAuthor = bookAuthor
    }

    public var parsedLocator: Locator? {
        Locator.from(jsonString: locator)
    }
}

/// A reader's own word attached to one saved passage.
///
/// A third table beside `noteTag` and `bookTag`, and a third vocabulary — deliberately, on the
/// rule those two already set: a source's tags say where a text belongs on the shelf, a note's
/// tags describe a thought the reader wrote from nothing, and a passage's tags say what this
/// particular sentence *is* to them — `objection`, `definition`, `for the essay`. Pouring them
/// into one list would make every word typed on one side a suggestion on the other, and the
/// suggestion menu is the whole value of a vocabulary. What all three share is `TagName`, so
/// "are these the same tag" keeps exactly one answer everywhere.
public struct HighlightTag: Codable, FetchableRecord, PersistableRecord, Equatable, Hashable, Sendable {
    public var highlightId: String
    public var tag: String

    public init(highlightId: String, tag: String) {
        self.highlightId = highlightId
        self.tag = tag
    }

    public static func normalized(_ raw: String) -> String? {
        TagName.normalized(raw)
    }
}

/// One row per book id that still has quotes, grouped from `highlight` itself rather than
/// joined outward from `book` — a deleted book must still produce a group instead of quietly
/// dropping its quotes from the hub.
public struct HighlightGroup: Equatable, Sendable {
    public let bookId: String
    public let quoteCount: Int
    public let bookTitle: String?
    public let bookAuthor: String?
}
