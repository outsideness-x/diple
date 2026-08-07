import Foundation

/// Backfills full-text search over the books' own prose, one book at a time, modelled on
/// `ArticleSearchIndexer`. A freshly-imported book is indexed as soon as its row is saved
/// (`indexBook`); `indexMissingBooks` sweeps the rest of the library for books saved before
/// this feature existed, resuming from `bookContentIndex` so a finished book is never
/// re-parsed.
public nonisolated final class BookContentIndexer: Sendable {
    public static let shared = BookContentIndexer()

    /// Books that failed to parse earlier in this process. Retried on the next app launch (a
    /// new process), but not every time Search reappears in the same session — a damaged EPUB
    /// must not turn into a repeating cost every time the user opens the tab.
    private let failedBookIDs = LockedIDSet()

    private init() {}

    /// Indexes one freshly-imported book. Fire-and-forget: the caller (`EPUBImporter`) does
    /// not await this, so import never waits on a full pass over the book it just copied in.
    public func indexBook(_ book: Book) {
        guard book.sourceURL == nil else { return }
        Task.detached(priority: .utility) { [self] in
            await index(book)
        }
    }

    /// The same single-book path as `indexBook`, but awaited. The reader's own search sheet
    /// needs to know when the book it is showing becomes searchable — unlike a fresh import,
    /// it cannot fire into the void, because "Indexing this book…" has to actually resolve
    /// instead of only being true until the user happens to open the Search tab, which is what
    /// drives `indexMissingBooks` today.
    @discardableResult
    public func indexBookAwaiting(_ book: Book) async -> Bool {
        guard book.sourceURL == nil else { return false }
        return await Task.detached(priority: .userInitiated) { [self] in
            await index(book)
        }.value
    }

    /// Sweeps the library for books with no `bookContent` yet. Returns the number newly
    /// indexed, so callers (the Search tab's spinner) know whether anything changed.
    @discardableResult
    public func indexMissingBooks() async -> Int {
        await Task.detached(priority: .utility) { [self] in
            guard let books = try? AppDatabase.shared.fetchBooksMissingContentIndex() else { return 0 }
            var indexed = 0
            for book in books {
                guard !Task.isCancelled else { break }
                if await index(book) {
                    indexed += 1
                }
            }
            return indexed
        }.value
    }

    /// Extracts and stores one book's chunks in a single transaction (see
    /// `AppDatabase.indexBookContent`). A book that fails to open or parse is skipped, not
    /// thrown — one damaged EPUB must never stop the rest of the library from becoming
    /// searchable, and never take the backfill down with it.
    @discardableResult
    private func index(_ book: Book) async -> Bool {
        guard !failedBookIDs.contains(book.id) else { return false }
        do {
            let chunks = try await BookContentExtractor.extractChunks(from: book)
            try AppDatabase.shared.indexBookContent(book: book, chunks: chunks)
            return true
        } catch {
            failedBookIDs.insert(book.id)
            return false
        }
    }
}

/// `indexBook` (fired at import) and `indexMissingBooks` (the backfill sweep) can run
/// concurrently on different detached tasks, so the failure cache needs real synchronization —
/// unlike the module's plain `static var`s, which get away without a lock only because their
/// readers and writers all already live on the main actor (see `DipleAccent.current`).
private nonisolated final class LockedIDSet: @unchecked Sendable {
    private let lock = NSLock()
    private var ids = Set<String>()

    func contains(_ id: String) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return ids.contains(id)
    }

    func insert(_ id: String) {
        lock.lock()
        defer { lock.unlock() }
        ids.insert(id)
    }
}
