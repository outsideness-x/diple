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

/// Where a source sits in the reader's queue — an intention, not a fact.
///
/// Progress already answers "have I read this". What it cannot answer is "do I mean to". A
/// freshly saved article and a book abandoned two years ago are both at 0%, and the library
/// had no way to tell them apart: the default sort keyed off `lastOpenedAt`, so anything never
/// opened sank below everything already read and the newest save landed at the very bottom.
public enum BookLocation: String, Codable, CaseIterable, Sendable, Hashable {
    case inbox
    case later
    case archive

    public var title: String {
        switch self {
        case .inbox: return "Inbox"
        case .later: return "Later"
        case .archive: return "Archive"
        }
    }

    public var systemImage: String {
        switch self {
        case .inbox: return "tray"
        case .later: return "clock"
        case .archive: return "archivebox"
        }
    }

    /// Where a source belongs when nobody has said. Used by the v15 backfill and by CloudKit
    /// records saved before the column existed: both describe libraries that predate the
    /// concept, and calling an already-finished book "inbox" would be a lie about it.
    public static func inferred(progress: Double) -> Self {
        progress >= 0.995 ? .archive : .later
    }
}

/// A reader's own word attached to a source.
///
/// Deliberately a separate table from `noteTag` rather than one shared tag vocabulary: a note's
/// tags describe a thought, a source's tags describe where a text belongs on the shelf, and
/// merging them would make every tag typed on one side appear as a suggestion on the other.
/// What the two do share is `TagName.normalized`, so "are these the same tag" has one answer.
public struct BookTag: Codable, FetchableRecord, PersistableRecord, Equatable, Hashable, Sendable {
    public var bookId: String
    public var tag: String

    public init(bookId: String, tag: String) {
        self.bookId = bookId
        self.tag = tag
    }

    public static func normalized(_ raw: String) -> String? {
        TagName.normalized(raw)
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
    /// The high-water mark of `progress`: how far the reader has actually travelled through
    /// the book, distinct from `progress`'s "where the saved position currently sits". Scrolling
    /// back to reread a chapter moves `progress` backwards, but a library card showing that as
    /// lost ground reads as a bug, not a feature — see "Прогресс чтения: `furthestProgress` и
    /// live-позиция" in CLAUDE.md.
    public var furthestProgress: Double
    public var locator: String?
    /// The web page an imported article was read from; `nil` for a file the reader imported.
    /// It remains distinct from `sourceKind`: the kind drives presentation, while this value
    /// is the canonical address a reader can reopen or copy.
    public var sourceURL: String?
    public var sourceKind: PublicationKind
    /// Where this source sits in the queue. New saves arrive in `.inbox`; see `BookLocation`.
    public var location: BookLocation

    public init(
        id: String = UUID().uuidString,
        title: String,
        author: String? = nil,
        filePath: String,
        coverPath: String? = nil,
        addedAt: Date = Date(),
        lastOpenedAt: Date? = nil,
        progress: Double = 0.0,
        furthestProgress: Double? = nil,
        locator: String? = nil,
        sourceURL: String? = nil,
        sourceKind: PublicationKind? = nil,
        // Not optional-with-inference like `sourceKind`: a brand new save genuinely belongs in
        // the inbox, and only the CloudKit path — where a missing field means "saved before the
        // concept existed" — wants `BookLocation.inferred(progress:)`. Making that the default
        // here would quietly file every fresh import under Later instead.
        location: BookLocation = .inbox
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.filePath = filePath
        self.coverPath = coverPath
        self.addedAt = addedAt
        self.lastOpenedAt = lastOpenedAt
        self.progress = progress
        // A caller that does not know about the high-water mark — a CloudKit record saved
        // before this field existed, a test fixture, an importer — must never regress it to a
        // bare 0 and erase a synced reader's history. Falling back to `progress` keeps the
        // invariant `furthestProgress >= progress` true for every `Book` this initializer can
        // produce, not only ones built by `updateReadingProgress`.
        self.furthestProgress = max(progress, furthestProgress ?? 0)
        self.locator = locator
        self.sourceURL = sourceURL
        self.sourceKind = sourceKind ?? PublicationKind.inferred(filePath: filePath, sourceURL: sourceURL)
        self.location = location
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
