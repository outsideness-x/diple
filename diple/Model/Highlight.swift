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

/// One row per book id that still has quotes, grouped from `highlight` itself rather than
/// joined outward from `book` — a deleted book must still produce a group instead of quietly
/// dropping its quotes from the hub.
public struct HighlightGroup: Equatable, Sendable {
    public let bookId: String
    public let quoteCount: Int
    public let bookTitle: String?
    public let bookAuthor: String?
}
