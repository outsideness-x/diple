import Foundation

public nonisolated enum GlobalSearchKind: String, Codable, Sendable, Hashable, CaseIterable {
    case note
    case highlight
    case book
    case article

    public var title: String {
        switch self {
        case .note: return "Notes"
        case .highlight: return "Highlights"
        case .book: return "Library"
        case .article: return "Articles"
        }
    }

    public var systemImage: String {
        switch self {
        case .note: return "note.text"
        case .highlight: return "quote.opening"
        case .book: return "book.closed"
        case .article: return "doc.text"
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

    public var id: String { "\(kind.rawValue):\(entityID)" }

    public init(
        kind: GlobalSearchKind,
        entityID: String,
        bookID: String?,
        title: String,
        subtitle: String,
        snippet: String
    ) {
        self.kind = kind
        self.entityID = entityID
        self.bookID = bookID
        self.title = title
        self.subtitle = subtitle
        self.snippet = snippet
    }
}
