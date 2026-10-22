import GRDB
import XCTest
@testable import diple

/// The feed's sources on every device: following and unfollowing travel through iCloud as
/// `DipleFeedSource`, one feed is one record wherever it was followed, and what a device
/// learned by asking a source stays on that device.
@MainActor
final class FeedSyncTests: XCTestCase {
    private func database() throws -> AppDatabase {
        try AppDatabase(DatabaseQueue(), syncEnabled: true)
    }

    private let past = Date(timeIntervalSince1970: 1_700_000_000)

    private func subscription(
        _ url: String = "https://www.quantamagazine.org/feed/",
        title: String = "Quanta Magazine",
        updatedAt: Date? = nil
    ) throws -> FeedSubscription {
        let feedURL = try XCTUnwrap(URL(string: url))
        return FeedSubscription(
            id: FeedSubscription.id(forFeedURL: feedURL, isArxiv: false),
            feedURL: url,
            siteURL: "https://www.quantamagazine.org",
            title: title,
            addedAt: past,
            updatedAt: updatedAt ?? past
        )
    }

    private func queued(_ id: String, in db: AppDatabase) throws -> SyncOperation? {
        try db.fetchSyncOutbox().first { $0.entity == .feedSource && $0.entityID == id }?.pendingOperation
    }

    // MARK: - Identity

    /// Quanta followed on the phone and on the Mac before either has synced is one source.
    func testOneFeedIsOneRecordWhereverItWasFollowed() throws {
        let a = FeedSubscription.id(forFeedURL: try XCTUnwrap(URL(string: "https://www.aeon.co/essays/feed.rss/")), isArxiv: false)
        let b = FeedSubscription.id(forFeedURL: try XCTUnwrap(URL(string: "http://aeon.co/essays/feed.rss")), isArxiv: false)
        let other = FeedSubscription.id(forFeedURL: try XCTUnwrap(URL(string: "https://aeon.co/feed.rss")), isArxiv: false)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, other)
        XCTAssertTrue(a.hasPrefix("feed-"))
        XCTAssertEqual(
            FeedSubscription.id(forFeedURL: ArxivField.feedURL(for: ["cs.CL"]), isArxiv: true),
            "arxiv",
            "arXiv is followed once, whatever its fields"
        )
    }

    func testArxivFieldsTravelAsOneString() throws {
        var source = FeedSource(
            feedURL: ArxivField.feedURL(for: ["cs.AI", "cs.LG"]),
            title: "arXiv · AI, Machine learning",
            seal: "χ",
            arxivFields: ["cs.AI", "cs.LG"],
            addedAt: past
        )
        source.etag = "this device's own"
        let record = FeedSubscription(source: source, updatedAt: past)
        XCTAssertEqual(record.arxivFields, "cs.AI cs.LG")
        XCTAssertEqual(record.fields, ["cs.AI", "cs.LG"])

        let back = try XCTUnwrap(FeedSource(subscription: record, local: source))
        XCTAssertEqual(back.arxivFields, ["cs.AI", "cs.LG"])
        XCTAssertEqual(back.etag, "this device's own", "what this device learned stays with it")

        // Fields changed on another device: the old validators answered for a different query.
        var moved = record
        moved.arxivFields = "cs.CL"
        moved.feedURL = ArxivField.feedURL(for: ["cs.CL"]).absoluteString
        XCTAssertNil(FeedSource(subscription: moved, local: source)?.etag)
    }

    // MARK: - The library and the outbox

    func testFollowingIsQueuedForICloudAndUnfollowingIsADeletion() throws {
        let db = try database()
        let quanta = try subscription()
        try db.saveFeedSubscription(quanta)
        XCTAssertEqual(try db.fetchFeedSubscriptions().map(\.id), [quanta.id])
        XCTAssertEqual(try queued(quanta.id, in: db), .save)

        try db.deleteFeedSubscription(id: quanta.id)
        XCTAssertTrue(try db.fetchFeedSubscriptions().isEmpty)
        XCTAssertEqual(try queued(quanta.id, in: db), .delete)
    }

    func testANewerRemoteSourceIsTakenAndAnOlderOneRefused() throws {
        let db = try database()
        let later = past.addingTimeInterval(3_600)
        try db.saveFeedSubscription(try subscription(title: "Quanta", updatedAt: later))

        let older = try subscription(title: "Quanta (from the other device)", updatedAt: past)
        XCTAssertFalse(try db.applyRemoteFeedSubscription(older, modifiedAt: past, systemFields: Data()))
        XCTAssertEqual(try db.fetchFeedSubscriptions().first?.title, "Quanta")

        let newer = try subscription(title: "Quanta Magazine", updatedAt: later.addingTimeInterval(60))
        XCTAssertTrue(try db.applyRemoteFeedSubscription(newer, modifiedAt: later.addingTimeInterval(60), systemFields: Data()))
        XCTAssertEqual(try db.fetchFeedSubscriptions().first?.title, "Quanta Magazine")
    }

    func testUnfollowingOnAnotherDeviceUnfollowsHere() throws {
        let db = try database()
        let quanta = try subscription()
        try db.applyRemoteFeedSubscription(quanta, modifiedAt: past, systemFields: Data())

        XCTAssertTrue(try db.applyRemoteDeletion(entity: .feedSource, id: quanta.id))
        XCTAssertTrue(try db.fetchFeedSubscriptions().isEmpty)
    }

    func testTheFirstUploadCarriesTheFeedsSources() throws {
        let db = try database()
        let quanta = try subscription()
        try db.saveFeedSubscription(quanta)
        for entry in try db.fetchSyncOutbox() {
            try db.acknowledgeSavedRecord(
                entity: try XCTUnwrap(entry.entity),
                id: entry.entityID,
                modifiedAt: entry.modifiedAt,
                systemFields: Data()
            )
        }
        XCTAssertTrue(try db.fetchSyncOutbox().isEmpty)

        try db.prepareInitialSync()
        XCTAssertEqual(try queued(quanta.id, in: db), .save)
    }

    // MARK: - The file from before sync

    /// What the feed file held on 2026-10-21, before its sources moved into the library.
    private struct VersionOneFile: Encodable {
        let version = 1
        let sources: [FeedSource]
        let items: [FeedItem]
        let checkedAt: Date?
    }

    /// A version-1 file's sources move into the library under the ids every device derives,
    /// and their pieces and check state move with them.
    func testSourcesFollowedBeforeSyncMoveIntoTheLibrary() throws {
        let db = try database()
        let feedURL = try XCTUnwrap(URL(string: "https://www.quantamagazine.org/feed/"))
        var old = FeedSource(id: "RANDOM-UUID", feedURL: feedURL, title: "Quanta Magazine", addedAt: past)
        old.etag = "W/\"abc\""
        let piece = FeedItem(
            id: "RANDOM-UUID|https://www.quantamagazine.org/?p=1", sourceID: "RANDOM-UUID",
            title: "A piece", link: try XCTUnwrap(URL(string: "https://www.quantamagazine.org/a")),
            publishedAt: past, authors: [], summary: "", characterCount: nil, categories: [],
            arxivID: nil, pdfURL: nil, firstSeenAt: past, rank: 0, keptBookID: "book-1"
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("feed-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        try encoder.encode(VersionOneFile(sources: [old], items: [piece], checkedAt: past)).write(to: file)

        let store = FeedStore(fileURL: file, database: db)

        let id = FeedSubscription.id(forFeedURL: feedURL, isArxiv: false)
        XCTAssertEqual(store.sources.map(\.id), [id])
        XCTAssertEqual(store.sources.first?.etag, "W/\"abc\"")
        XCTAssertEqual(store.items.map(\.id), ["\(id)|https://www.quantamagazine.org/?p=1"])
        XCTAssertEqual(store.items.first?.keptBookID, "book-1")
        XCTAssertEqual(try db.fetchFeedSubscriptions().map(\.id), [id])
        XCTAssertEqual(try queued(id, in: db), .save, "so the other devices follow it too")
    }

    func testASourceInTheLibraryIsTheFeedsWhateverTheFileSays() throws {
        let db = try database()
        let quanta = try subscription()
        try db.applyRemoteFeedSubscription(quanta, modifiedAt: past, systemFields: Data())
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("feed-\(UUID().uuidString).json")

        let store = FeedStore(fileURL: missing, database: db)
        XCTAssertEqual(store.sources.map(\.title), ["Quanta Magazine"])
        XCTAssertNil(store.sources.first?.checkedAt, "never asked here, so the next look asks it")
        try? FileManager.default.removeItem(at: missing)
    }
}
