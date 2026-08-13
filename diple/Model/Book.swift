import Foundation
import GRDB

/// The durable identity of a saved source. Articles are packaged as EPUB files on disk, so
/// the filename alone cannot tell the UI whether it came from the web. Keeping this value on
/// the source gives every screen one stable vocabulary without changing how publications are
/// opened by Readium.
public enum PublicationKind: String, Codable, CaseIterable, Sendable, Hashable {
    case epub
    case pdf
    case article

    public var title: String {
        switch self {
        case .epub: return "Book"
        case .pdf: return "PDF"
        case .article: return "Article"
        }
    }

    public var systemImage: String {
        switch self {
        case .epub: return "book.closed"
        case .pdf: return "doc.richtext"
        case .article: return "link"
        }
    }

    fileprivate static func inferred(filePath: String, sourceURL: String?) -> Self {
        if sourceURL != nil { return .article }
        if filePath.lowercased().hasSuffix(".pdf") { return .pdf }
        return .epub
    }
}

public struct Book: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var title: String
    public var author: String?
    public var filePath: String
    public var coverPath: String?
    public var addedAt: Date
    public var lastOpenedAt: Date?
    public var progress: Double
    public var locator: String?
    /// The web page an imported article was read from; `nil` for a file the reader imported.
    /// It remains distinct from `sourceKind`: the kind drives presentation, while this value
    /// is the canonical address a reader can reopen or copy.
    public var sourceURL: String?
    public var sourceKind: PublicationKind

    public init(
        id: String = UUID().uuidString,
        title: String,
        author: String? = nil,
        filePath: String,
        coverPath: String? = nil,
        addedAt: Date = Date(),
        lastOpenedAt: Date? = nil,
        progress: Double = 0.0,
        locator: String? = nil,
        sourceURL: String? = nil,
        sourceKind: PublicationKind? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.filePath = filePath
        self.coverPath = coverPath
        self.addedAt = addedAt
        self.lastOpenedAt = lastOpenedAt
        self.progress = progress
        self.locator = locator
        self.sourceURL = sourceURL
        self.sourceKind = sourceKind ?? PublicationKind.inferred(filePath: filePath, sourceURL: sourceURL)
    }

    /// Whether this row came from the web rather than from a file.
    public var isArticle: Bool { sourceKind == .article }
    public var isPDF: Bool { sourceKind == .pdf }

    /// The publication a web article came from, as it should be shown to a reader:
    /// `towardsdatascience.com`, not `https://www.towardsdatascience.com/…`. `www.` is
    /// dropped because it is noise nobody reads, and the chip has little room.
    public var sourceHost: String? {
        guard let sourceURL, let host = URL(string: sourceURL)?.host else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The single line of metadata printed under a title in the library and the hub.
    ///
    /// For an article the site is part of the identity — two saved links with similar
    /// headlines are told apart by where they came from — so it is always present, after the
    /// byline when the page named one.
    public var subtitle: String {
        guard let sourceHost else { return author ?? "Unknown Author" }
        return [author, sourceHost].compactMap { $0 }.joined(separator: " · ")
    }
}
