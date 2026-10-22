import Combine
import Foundation
import SwiftUI

/// The feed: the sources the reader follows and the newest few pieces of each.
///
/// **What a source is lives in the library and syncs; what it brought stays on this device.**
/// The followed sources are rows of `feedSource`, written through `AppDatabase` so that a change
/// and its iCloud outbox entry are one transaction, and carried to the reader's other devices as
/// `DipleFeedSource` (2026-10-22) — following on the phone is following on the Mac. The pieces,
/// and how each source last answered *this* device — its validators, when, why it did not — are
/// in `feed.json`: every device asks the source for itself, and a few days of other people's
/// headlines, most of which leave on their own, are not the reader's work to keep. What the
/// reader does keep from the feed becomes a book through `LinkImporter` and syncs as every saved
/// link does. See "Лента" in CLAUDE.md.
@MainActor
public final class FeedStore: ObservableObject {
    public static let shared = FeedStore(fileURL: FeedStore.defaultFileURL, database: .shared)

    @Published public private(set) var sources: [FeedSource] = []
    @Published public private(set) var items: [FeedItem] = []
    /// When the last full check finished.
    @Published public private(set) var checkedAt: Date?
    @Published public private(set) var isChecking = false
    /// Sources being followed right now, by recommendation id or address: their first check is
    /// in flight, and their row says so.
    @Published public private(set) var arriving: Set<String> = []
    /// Pieces being fetched into the library from the feed without being opened.
    @Published public private(set) var keeping: Set<String> = []

    private let fileURL: URL?
    private let database: AppDatabase
    private var observers: Set<AnyCancellable> = []

    /// A feed is looked at again when it is opened and the last look is older than this.
    /// Half an hour: nobody publishes faster than that and expects to be read the same minute.
    static let staleAfter: TimeInterval = 30 * 60

    /// Nothing here needs isolation to be torn down — values and cancellables — so it is declined
    /// rather than back-deployed (see `ReaderViewModel`): a store a test makes and lets go of on
    /// the synchronous main thread otherwise dies in the back-deploy shim.
    nonisolated deinit {}

    init(fileURL: URL?, database: AppDatabase) {
        self.fileURL = fileURL
        self.database = database
        load()
        // A source followed, unfollowed or re-fielded on another device arrives with the rest of
        // an iCloud batch. Reading the table again is cheap; the pieces of a source new here are
        // fetched by `reloadSubscriptions` itself.
        NotificationCenter.default.publisher(for: .dipleRemoteDataDidChange)
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                Task { @MainActor in self?.reloadSubscriptions() }
            }
            .store(in: &observers)
    }

    private static var defaultFileURL: URL? {
        try? FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("feed.json")
    }

    // MARK: - Reading

    public func source(id: String) -> FeedSource? {
        sources.first { $0.id == id }
    }

    public func item(id: String) -> FeedItem? {
        items.first { $0.id == id }
    }

    /// The source a recommendation became, if it is followed. arXiv is followed once whatever the
    /// fields; an address matches however it is written.
    public func source(for recommendation: FeedRecommendation) -> FeedSource? {
        if recommendation.isArxiv { return sources.first(where: \.isArxiv) }
        let key = Self.key(for: recommendation.feedURL)
        return sources.first { Self.key(for: $0.feedURL) == key }
    }

    /// What the head of the feed says about it: when it last looked — the one thing about its
    /// freshness worth saying — and never how much it found. `nil` before anything is followed.
    public var statusLine: String? {
        guard !sources.isEmpty else { return nil }
        if isChecking { return String(localized: "Checking your sources…") }
        guard let checkedAt else { return nil }
        if Date().timeIntervalSince(checkedAt) < 60 { return String(localized: "Up to date") }
        return String(localized: "Checked \(checkedAt.formatted(.relative(presentation: .named)))")
    }

    /// The recommendations not followed yet, in their own order.
    public var unfollowedRecommendations: [FeedRecommendation] {
        FeedRecommendation.all.filter { source(for: $0) == nil }
    }

    // MARK: - Following

    /// Follows one of diple's own suggestions. arXiv takes the fields chosen on its row.
    public func follow(_ recommendation: FeedRecommendation, arxivFields: [String]? = nil) async throws {
        guard source(for: recommendation) == nil, !arriving.contains(recommendation.id) else { return }
        arriving.insert(recommendation.id)
        defer { arriving.remove(recommendation.id) }

        var source = recommendation.source()
        if recommendation.isArxiv {
            let fields = (arxivFields?.isEmpty == false ? arxivFields : nil) ?? ArxivField.suggested
            source.arxivFields = fields
            source.feedURL = ArxivField.feedURL(for: fields)
            source.title = ArxivField.title(for: fields)
        }

        let outcome = try await FeedFetcher.fetch(source.feedURL)
        guard case let .feed(feed, etag, lastModified) = outcome else { return }
        source.etag = etag
        source.lastModified = lastModified
        source.checkedAt = Date()
        try add(source, items: feed.items)
    }

    /// Follows what `FeedDiscovery` found at an address the reader typed.
    ///
    /// An arXiv listing when arXiv is already followed adds its field to the ones followed —
    /// there is one arXiv in the feed, as there is one in the recommendations.
    public func follow(_ found: FeedDiscovery.Found) {
        if let fields = found.arxivFields, let arxiv = sources.first(where: \.isArxiv) {
            let current = arxiv.arxivFields ?? []
            Task { await setArxivFields(current + fields.filter { !current.contains($0) }, for: arxiv.id) }
            return
        }
        let key = Self.key(for: found.feedURL)
        guard !sources.contains(where: { Self.key(for: $0.feedURL) == key }) else { return }

        var source = FeedSource(
            feedURL: found.feedURL,
            siteURL: found.feed.siteURL,
            title: found.feed.title.isEmpty ? (found.feedURL.host ?? "Untitled") : found.feed.title,
            summary: found.feed.summary
        )
        if let fields = found.arxivFields {
            source.arxivFields = fields
            source.title = ArxivField.title(for: fields)
            source.seal = "χ"
        }
        source.etag = found.etag
        source.lastModified = found.lastModified
        source.checkedAt = Date()
        try? add(source, items: found.feed.items)
    }

    /// Files the source in the library under the id every device derives for the same feed
    /// (`FeedSubscription.id`), so following it on two devices before either has synced is one
    /// source and not two.
    private func add(_ incoming: FeedSource, items fetched: [ParsedFeedItem]) throws {
        let source = incoming.renamed(to: FeedSubscription.id(forFeedURL: incoming.feedURL, isArxiv: incoming.isArxiv))
        try database.saveFeedSubscription(FeedSubscription(source: source))
        let arrived = FeedRack.merge(
            sourceID: source.id,
            fetched: fetched,
            existing: items.filter { $0.sourceID == source.id }
        )
        // The first source followed has just been looked at, which is every source there is.
        if sources.isEmpty { checkedAt = Date() }
        withAnimation(DipleMotion.gentle) {
            sources.removeAll { $0.id == source.id }
            sources.append(source)
            items.removeAll { $0.sourceID == source.id }
            items.append(contentsOf: arrived)
        }
        persist()
    }

    /// Takes a source and what it brought off the feed — here and, through iCloud, on the
    /// reader's other devices. What the reader kept from it stays in the library: nothing here
    /// deletes a book.
    public func unfollow(_ sourceID: String) {
        try? database.deleteFeedSubscription(id: sourceID)
        withAnimation(DipleMotion.gentle) {
            sources.removeAll { $0.id == sourceID }
            items.removeAll { $0.sourceID == sourceID }
        }
        persist()
    }

    /// Changes which arXiv fields a source follows, and reads it again at once.
    public func setArxivFields(_ fields: [String], for sourceID: String) async {
        guard !fields.isEmpty, let index = sources.firstIndex(where: { $0.id == sourceID }) else { return }
        sources[index].arxivFields = fields
        sources[index].feedURL = ArxivField.feedURL(for: fields)
        sources[index].title = ArxivField.title(for: fields)
        sources[index].etag = nil
        sources[index].lastModified = nil
        try? database.saveFeedSubscription(FeedSubscription(source: sources[index]))
        persist()
        await check(only: [sourceID])
    }

    /// What another device changed: a source followed there, one unfollowed, arXiv's fields
    /// moved. A source new here — or asking a different address than this device last asked —
    /// is asked at once, so its pieces arrive with it rather than half an hour later.
    private func reloadSubscriptions() {
        guard let subscriptions = try? database.fetchFeedSubscriptions() else { return }
        let previous = Dictionary(sources.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let next = subscriptions.compactMap { FeedSource(subscription: $0, local: previous[$0.id]) }
        guard next != sources else { return }

        let kept = Set(next.map(\.id))
        let toAsk = Set(next.filter { previous[$0.id]?.feedURL != $0.feedURL }.map(\.id))
        withAnimation(DipleMotion.gentle) {
            sources = next
            items.removeAll { !kept.contains($0.sourceID) }
        }
        persist()
        if !toAsk.isEmpty {
            Task { await check(only: toAsk) }
        }
    }

    // MARK: - Checking

    /// Looks again if the last look is old. What opening the feed does.
    ///
    /// A look that is not old still asks the sources this device has never asked — one followed
    /// on another device while this one was asleep has nothing to show until it is.
    public func checkIfStale(now: Date = Date()) async {
        if let checkedAt, now.timeIntervalSince(checkedAt) < Self.staleAfter {
            let unasked = Set(sources.filter { $0.checkedAt == nil }.map(\.id))
            if !unasked.isEmpty { await check(only: unasked) }
            return
        }
        await check()
    }

    /// Asks every source — or the ones named — for what is new. All at once: a dozen feeds is a
    /// dozen small requests, and a slow one must not hold up the rest. Only a full check says
    /// "checking" in the head of the feed and moves its "checked" time; asking one source that
    /// has just arrived is not looking at the feed.
    public func check(only ids: Set<String>? = nil) async {
        let isFull = ids == nil
        if isFull, isChecking { return }
        let targets = sources.filter { ids?.contains($0.id) ?? true }
        guard !targets.isEmpty else { return }
        if isFull { isChecking = true }

        let outcomes = await withTaskGroup(of: (String, Result<FeedFetcher.Outcome, Error>).self) { group in
            for source in targets {
                let url = source.feedURL
                let etag = source.etag
                let lastModified = source.lastModified
                let id = source.id
                group.addTask {
                    do {
                        return (id, .success(try await FeedFetcher.fetch(url, etag: etag, lastModified: lastModified)))
                    } catch {
                        return (id, .failure(error))
                    }
                }
            }
            var results: [String: Result<FeedFetcher.Outcome, Error>] = [:]
            for await (id, result) in group { results[id] = result }
            return results
        }

        let now = Date()
        withAnimation(DipleMotion.gentle) {
            for (id, result) in outcomes { apply(result, to: id, at: now) }
        }
        if isFull {
            checkedAt = now
            isChecking = false
        }
        persist()
    }

    private func apply(_ result: Result<FeedFetcher.Outcome, Error>, to id: String, at now: Date) {
        guard let index = sources.firstIndex(where: { $0.id == id }) else { return }
        switch result {
        case .success(.notModified):
            sources[index].checkedAt = now
            sources[index].failure = nil
        case let .success(.feed(feed, etag, lastModified)):
            sources[index].checkedAt = now
            sources[index].failure = nil
            sources[index].etag = etag
            sources[index].lastModified = lastModified
            if sources[index].siteURL == nil, let site = feed.siteURL {
                // Part of what the source is, so it goes to the library and on to the other
                // devices — which will find the same site and agree.
                sources[index].siteURL = site
                try? database.saveFeedSubscription(FeedSubscription(source: sources[index]))
            }
            // An empty answer is a hiccup on the publisher's side, not the news that everything
            // was withdrawn: what the source showed stays.
            guard !feed.items.isEmpty else { return }
            let existing = items.filter { $0.sourceID == id }
            let merged = FeedRack.merge(sourceID: id, fetched: feed.items, existing: existing, now: now)
            items.removeAll { $0.sourceID == id }
            items.append(contentsOf: merged)
        case let .failure(error):
            // Quiet on purpose: the source keeps what it had, and the sheet of sources says
            // which one did not answer. A feed is not worth an alert.
            if error is CancellationError { return }
            sources[index].failure = (error as? LocalizedError)?.errorDescription
                ?? "Didn’t answer the last time it was asked."
        }
    }

    // MARK: - Keeping

    public func markKept(_ itemID: String, bookID: String) {
        guard let index = items.firstIndex(where: { $0.id == itemID }), items[index].keptBookID != bookID else { return }
        items[index].keptBookID = bookID
        persist()
    }

    /// Files a piece in the library without opening it — Later, because "keep for later" is
    /// exactly what that place of the library is for. Runs here rather than in the view, so a
    /// reader who scrolls away while the essay downloads still gets it.
    public func keep(_ item: FeedItem, library: [Book]) {
        guard !keeping.contains(item.id) else { return }
        keeping.insert(item.id)
        Task {
            defer { keeping.remove(item.id) }
            do {
                let book = try await FeedReading.book(for: item, in: library) { _ in }
                if book.location != .later {
                    try? database.updateBookLocation(id: book.id, location: .later)
                }
                HapticManager.shared.notification(.success)
            } catch {
                HapticManager.shared.notification(.error)
            }
        }
    }

    // MARK: - Storage

    /// The file's shape. Version 1 (2026-10-21) held the sources themselves, under random ids;
    /// from version 2 the sources are the library's, and `sources` here is only this device's
    /// copy of them, kept for what it adds: how each last answered here.
    private struct Stored: Codable {
        var version = 2
        var sources: [FeedSource]
        var items: [FeedItem]
        var checkedAt: Date?
    }

    private func load() {
        let stored = fileURL
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? JSONDecoder.feed.decode(Stored.self, from: $0) }
        var local = stored?.sources ?? []
        var storedItems = stored?.items ?? []
        let isFromBeforeSync = (stored?.version ?? 2) < 2
        if isFromBeforeSync {
            (local, storedItems) = adoptIntoLibrary(local, items: storedItems)
        }

        let subscriptions = (try? database.fetchFeedSubscriptions()) ?? []
        let byID = Dictionary(local.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        sources = subscriptions.compactMap { FeedSource(subscription: $0, local: byID[$0.id]) }
        // A piece whose source is gone has nothing to be filed under.
        let ids = Set(sources.map(\.id))
        items = storedItems.filter { ids.contains($0.sourceID) }
        checkedAt = stored?.checkedAt
        if isFromBeforeSync { persist() }
    }

    /// The sources a version-1 file held, moved into the library under the ids every device
    /// derives for the same feed — and the pieces and the check state moved with them. A source
    /// the library already has (it came from another device first) is not written again.
    private func adoptIntoLibrary(_ sources: [FeedSource], items: [FeedItem]) -> ([FeedSource], [FeedItem]) {
        let existing = Set(((try? database.fetchFeedSubscriptions()) ?? []).map(\.id))
        var renamed: [String: String] = [:]
        var adopted: [FeedSource] = []
        for old in sources {
            let source = old.renamed(to: FeedSubscription.id(forFeedURL: old.feedURL, isArxiv: old.isArxiv))
            renamed[old.id] = source.id
            if !existing.contains(source.id) {
                try? database.saveFeedSubscription(FeedSubscription(source: source, updatedAt: source.addedAt))
            }
            adopted.append(source)
        }
        let moved = items.compactMap { item in renamed[item.sourceID].map { item.moved(to: $0) } }
        return (adopted, moved)
    }

    /// Written off the main actor, atomically: a feed file torn by a quit mid-write would be a
    /// feed that comes back empty.
    private func persist() {
        guard let fileURL else { return }
        let stored = Stored(sources: sources, items: items, checkedAt: checkedAt)
        guard let data = try? JSONEncoder.feed.encode(stored) else { return }
        Task.detached(priority: .utility) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    /// An address reduced to what identifies it. See `FeedAddress`.
    static func key(for url: URL) -> String {
        FeedAddress.key(for: url)
    }
}

private extension JSONEncoder {
    nonisolated static var feed: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    nonisolated static var feed: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

/// Which library row a piece of the feed already is.
///
/// By the row the feed made of it first; then by address, for a piece the reader had saved some
/// other way — shared from Safari, pasted into "Save a link"; for a paper, by its arXiv number,
/// which its abstract page, its HTML and its PDF all carry.
public struct FeedLibraryIndex {
    private let byID: [String: Book]
    private let byAddress: [String: Book]
    private let byArxivNumber: [String: Book]

    public init(_ books: [Book]) {
        var byID: [String: Book] = [:]
        var byAddress: [String: Book] = [:]
        var byArxivNumber: [String: Book] = [:]
        for book in books {
            byID[book.id] = book
            guard let source = book.sourceURL, let url = URL(string: source) else { continue }
            byAddress[FeedStore.key(for: url)] = book
            if let number = Self.arxivNumber(in: url) { byArxivNumber[number] = book }
        }
        self.byID = byID
        self.byAddress = byAddress
        self.byArxivNumber = byArxivNumber
    }

    public func book(for item: FeedItem) -> Book? {
        if let id = item.keptBookID, let book = byID[id] { return book }
        if let number = item.arxivNumber, let book = byArxivNumber[number] { return book }
        return byAddress[FeedStore.key(for: item.link)]
    }

    static func arxivNumber(in url: URL) -> String? {
        guard url.host?.lowercased().hasSuffix("arxiv.org") == true else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        guard parts.count >= 2, ["abs", "pdf", "html"].contains(parts[0]) else { return nil }
        var number = parts[1]
        if number.hasSuffix(".pdf") { number.removeLast(4) }
        return FeedRack.arxivNumber(number)
    }
}

/// Reading a piece of the feed: fetched, typeset and filed in the library like any saved link,
/// so it opens in the reader with everything the reader does — marks, notes, the place kept.
public enum FeedReading {
    public enum Format: Sendable {
        /// The piece as a page. For a paper, arXiv's HTML when the paper has one — reflowed into
        /// the reader's own measure, with its formulas as MathML — and the PDF when it has not.
        case best
        /// A paper as its authors typeset it.
        case pdf
    }

    public static func book(
        for item: FeedItem,
        format: Format = .best,
        in library: [Book],
        progress: @escaping @Sendable (LinkImporter.Stage) -> Void
    ) async throws -> Book {
        if let existing = FeedLibraryIndex(library).book(for: item),
           (try? AppDatabase.shared.fetchBook(id: existing.id)) != nil {
            FeedStore.shared.markKept(item.id, bookID: existing.id)
            return existing
        }

        let book: Book
        if let number = item.arxivNumber {
            let version = item.arxivID ?? number
            let pdf = item.pdfURL ?? URL(string: "https://arxiv.org/pdf/\(version)")
            if format == .pdf, let pdf {
                book = try await LinkImporter.shared.importLink(from: pdf, progress: progress)
            } else if let html = URL(string: "https://arxiv.org/html/\(version)") {
                do {
                    book = try await LinkImporter.shared.importLink(from: html, progress: progress)
                } catch {
                    // Most papers have an HTML version; the rest answer 404, and some have one
                    // the extractor cannot read. Either way the paper is still the PDF.
                    if error is CancellationError { throw error }
                    guard let pdf else { throw error }
                    book = try await LinkImporter.shared.importLink(from: pdf, progress: progress)
                }
            } else {
                throw FeedFetchError.notAnAddress
            }
            // A paper's page names it `[2610.28632] …` and its PDF often not at all; the feed
            // has the title and the authors exactly.
            try? AppDatabase.shared.updateBookMetadata(id: book.id, title: item.title, author: item.byline)
        } else {
            book = try await LinkImporter.shared.importLink(from: item.link, progress: progress)
        }

        FeedStore.shared.markKept(item.id, bookID: book.id)
        return (try? AppDatabase.shared.fetchBook(id: book.id)) ?? book
    }
}
