import Foundation
import GRDB

public struct Book: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Hashable {
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
    ///
    /// This single column is also what marks a row as an article — there is no companion
    /// `kind`, because two fields describing the same fact are two fields that can disagree.
    public var sourceURL: String?

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
        sourceURL: String? = nil
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
    }

    /// Whether this row came from the web rather than from a file.
    public var isArticle: Bool { sourceURL != nil }

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
