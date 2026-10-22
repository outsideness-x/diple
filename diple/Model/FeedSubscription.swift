import CryptoKit
import Foundation
import GRDB

/// A followed source as the library keeps it and iCloud carries it (`DipleFeedSource`): what the
/// source is. How this device last fared asking it — its validators, when it answered, why it
/// did not — is not here; that stays in `FeedStore`'s file with the pieces, because every device
/// asks for itself.
public nonisolated struct FeedSubscription: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Hashable, Sendable {
    public static let databaseTableName = "feedSource"

    public var id: String
    public var feedURL: String
    public var siteURL: String?
    public var title: String
    public var summary: String?
    public var seal: String?
    /// The arXiv fields followed, space-separated (`cs.AI cs.LG`); `nil` for an ordinary feed.
    /// One string rather than a list: a list field is typed by the first value CloudKit ever
    /// sees, and a string has no such first time.
    public var arxivFields: String?
    public var addedAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        feedURL: String,
        siteURL: String? = nil,
        title: String,
        summary: String? = nil,
        seal: String? = nil,
        arxivFields: String? = nil,
        addedAt: Date,
        updatedAt: Date
    ) {
        self.id = id
        self.feedURL = feedURL
        self.siteURL = siteURL
        self.title = title
        self.summary = summary
        self.seal = seal
        self.arxivFields = arxivFields
        self.addedAt = addedAt
        self.updatedAt = updatedAt
    }

    public init(source: FeedSource, updatedAt: Date = Date()) {
        self.init(
            id: source.id,
            feedURL: source.feedURL.absoluteString,
            siteURL: source.siteURL?.absoluteString,
            title: source.title,
            summary: source.summary,
            seal: source.seal,
            arxivFields: source.arxivFields.map { $0.joined(separator: " ") },
            addedAt: source.addedAt,
            updatedAt: updatedAt
        )
    }

    public var fields: [String]? {
        arxivFields.map { $0.split(separator: " ").map(String.init) }
    }

    /// One id per feed, and the same one on every device.
    ///
    /// A random id would make Quanta, followed on the phone and on the Mac before either had
    /// synced, two sources on both of them — every piece twice. Derived from the address
    /// instead, the second follow is the same record arriving again, and the newer of the two
    /// simply wins. arXiv is followed once whatever its fields, so it has one fixed id and the
    /// fields are what the record carries.
    public static func id(forFeedURL url: URL, isArxiv: Bool) -> String {
        if isArxiv { return "arxiv" }
        let digest = SHA256.hash(data: Data(FeedAddress.key(for: url).utf8))
        return "feed-" + digest.prefix(12).map { String(format: "%02x", $0) }.joined()
    }
}

/// An address reduced to what identifies the feed behind it.
public nonisolated enum FeedAddress {
    /// No scheme, no `www.`, no trailing slash: `http://www.aeon.co/essays/feed.rss/` and
    /// `https://aeon.co/essays/feed.rss` are one feed.
    public static func key(for url: URL) -> String {
        var host = url.host?.lowercased() ?? ""
        if host.hasPrefix("www.") { host.removeFirst(4) }
        var path = url.path
        while path.hasSuffix("/") { path.removeLast() }
        let query = url.query.map { "?" + $0 } ?? ""
        return host + path + query
    }
}

public extension FeedSource {
    /// A source as the library has it, with what this device knows from asking it: the
    /// validators, the time and the outcome of its last check. `local` is `nil` for a source
    /// that has just arrived from another device and has not been asked yet.
    init?(subscription: FeedSubscription, local: FeedSource?) {
        guard let feedURL = URL(string: subscription.feedURL) else { return nil }
        self.init(
            id: subscription.id,
            feedURL: feedURL,
            siteURL: subscription.siteURL.flatMap(URL.init(string:)),
            title: subscription.title,
            summary: subscription.summary,
            seal: subscription.seal,
            arxivFields: subscription.fields,
            addedAt: subscription.addedAt
        )
        // Validators belong to the address they were given for: when the fields of arXiv changed
        // on another device, the old ones would answer "not modified" for a different query.
        guard let local, local.feedURL == feedURL else { return }
        checkedAt = local.checkedAt
        etag = local.etag
        lastModified = local.lastModified
        failure = local.failure
    }
}
