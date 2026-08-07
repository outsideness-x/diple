import Foundation
import Combine

/// Drives the reader's own "search inside this book" sheet, scoped to the one book already
/// open — a much smaller surface than `GlobalSearchViewModel`, but the same two lessons from
/// task 7 apply here too: debounce every keystroke and never block the main actor on FTS.
@MainActor
public final class ReaderSearchViewModel: ObservableObject {
    @Published public var query = ""
    @Published public private(set) var results: [BookSearchHit] = []
    /// `nil` until the first `isBookContentIndexed` check resolves, so the sheet does not flash
    /// "Indexing this book…" for a book that was in fact ready the whole time.
    @Published public private(set) var isIndexed: Bool?

    private let book: Book
    private var searchTask: Task<Void, Never>?
    private var indexingTask: Task<Void, Never>?

    public init(book: Book) {
        self.book = book
        ensureIndexed()
    }

    /// Groups results by the chapter they were found in, in the order they first appear —
    /// reading order, the same order `searchBookContent` already returns them in, not a
    /// re-sort by relevance.
    public var groupedResults: [ChapterGroup] {
        var order: [String] = []
        var titles: [String: String] = [:]
        var buckets: [String: [BookSearchHit]] = [:]
        for hit in results {
            let key = hit.href.isEmpty ? hit.chapterTitle : hit.href
            if buckets[key] == nil {
                order.append(key)
                titles[key] = hit.chapterTitle
            }
            buckets[key, default: []].append(hit)
        }
        return order.map { key in
            ChapterGroup(id: key, title: titles[key] ?? "", hits: buckets[key] ?? [])
        }
    }

    public struct ChapterGroup: Identifiable {
        public let id: String
        public let title: String
        public let hits: [BookSearchHit]
    }

    /// A book not yet in `bookContentIndex` starts indexing itself the moment its search sheet
    /// opens, rather than only ever getting swept when the user happens to visit the global
    /// Search tab — otherwise "Indexing this book…" would be a promise the app never keeps.
    private func ensureIndexed() {
        let bookID = book.id
        let book = book
        indexingTask = Task { [weak self] in
            let alreadyIndexed = (try? AppDatabase.shared.isBookContentIndexed(bookID: bookID)) ?? false
            guard let self else { return }
            if alreadyIndexed {
                self.isIndexed = true
                return
            }
            self.isIndexed = false
            _ = await BookContentIndexer.shared.indexBookAwaiting(book)
            guard !Task.isCancelled else { return }
            self.isIndexed = (try? AppDatabase.shared.isBookContentIndexed(bookID: bookID)) ?? false
            self.runSearch()
        }
    }

    /// Debounced (~120 ms) and off the main actor, mirroring `GlobalSearchViewModel.scheduleSearch()`
    /// — the corpus here is one book instead of the whole library, but a query per keystroke on
    /// the main actor is exactly the mistake task 7 already had to undo once.
    public func scheduleSearch() {
        runSearch(debounced: true)
    }

    private func runSearch(debounced: Bool = false) {
        searchTask?.cancel()
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            results = []
            return
        }
        let bookID = book.id
        searchTask = Task { [weak self] in
            if debounced {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
            }
            let outcome = await Task.detached(priority: .userInitiated) {
                (try? AppDatabase.shared.searchBookContent(bookID: bookID, query: trimmed)) ?? []
            }.value
            guard !Task.isCancelled, let self else { return }
            self.results = outcome
        }
    }
}
