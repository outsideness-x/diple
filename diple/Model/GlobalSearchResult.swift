import Foundation
import ReadiumShared

public nonisolated enum GlobalSearchKind: String, Codable, Sendable, Hashable, CaseIterable {
    case note
    case highlight
    case book
    case article
    case bookContent

    public var title: String {
        switch self {
        case .note: return "Notes"
        case .highlight: return "Highlights"
        case .book: return "Library"
        case .article: return "Articles"
        case .bookContent: return "In Books"
        }
    }

    public var systemImage: String {
        switch self {
        case .note: return "note.text"
        case .highlight: return "quote.opening"
        case .book: return "book.closed"
        case .article: return "doc.text"
        case .bookContent: return "doc.text.magnifyingglass"
        }
    }
}

/// A lightweight FTS hit. It carries stable identifiers rather than full records so the
/// destination always resolves the latest database state when the reader opens it.
public nonisolated struct GlobalSearchResult: Identifiable, Sendable, Hashable {
    public let kind: GlobalSearchKind
    public let entityID: String
    public let bookID: String?
    public let title: String
    public let subtitle: String
    public let snippet: String
    /// Only set for `.bookContent`: the passage's own locator, serialized. Metadata hits (note,
    /// highlight, book, article) already know how to reach their destination without one.
    public let locatorJSON: String?

    public var id: String { "\(kind.rawValue):\(entityID)" }

    public init(
        kind: GlobalSearchKind,
        entityID: String,
        bookID: String?,
        title: String,
        subtitle: String,
        snippet: String,
        locatorJSON: String? = nil
    ) {
        self.kind = kind
        self.entityID = entityID
        self.bookID = bookID
        self.title = title
        self.subtitle = subtitle
        self.snippet = snippet
        self.locatorJSON = locatorJSON
    }

    /// The reader's presentation-time starting locator for a content hit.
    public var parsedLocator: Locator? {
        Locator.from(jsonString: locatorJSON)
    }
}
