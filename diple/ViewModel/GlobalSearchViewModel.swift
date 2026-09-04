import Foundation
import Combine

@MainActor
public final class GlobalSearchViewModel: ObservableObject {
    @Published public var query = ""
    @Published public private(set) var results: [GlobalSearchResult] = []
    @Published public private(set) var books: [Book] = []
    @Published public private(set) var isIndexingArticles = false
    @Published public private(set) var isIndexingBookContent = false
    @Published public var errorMessage: String?

    private var indexingTask: Task<Void, Never>?
    private var bookContentIndexingTask: Task<Void, Never>?
    private var searchTask: Task<Void, Never>?

    public init() {
        reloadContext()
        indexLegacyArticles()
        indexBookContent()
    }

    public func reloadContext() {
        do {
            books = try AppDatabase.shared.fetchAllBooks()
        } catch {
            errorMessage = "Search is unavailable: \(error.localizedDescription)"
        }
        search()
    }

    /// Runs right away: used after a save/delete and on first appearance, where there is no
    /// keystroke to debounce and the caller wants the list current immediately.
    public func search() {
        runSearch(debounced: false)
    }

    /// Debounced (~120 ms) and off the main actor: called on every keystroke, so an unguarded
    /// synchronous query here would mean one FTS scan per character typed, blocking scrolling
    /// and typing alike as the library grows. Cancels any query already in flight so a slow
    /// response can never land after — and overwrite — a newer one.
    public func scheduleSearch() {
        runSearch(debounced: true)
    }

    private func runSearch(debounced: Bool) {
        searchTask?.cancel()
        let query = query
        searchTask = Task { [weak self] in
            if debounced {
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
            }
            let outcome = await Task.detached(priority: .userInitiated) {
                Result { try AppDatabase.shared.search(query) }
            }.value
            guard !Task.isCancelled, let self else { return }
            switch outcome {
            case let .success(results):
                self.results = results
                self.errorMessage = nil
            case let .failure(error):
                self.results = []
                self.errorMessage = "Search failed: \(error.localizedDescription)"
            }
        }
    }

    public func book(for result: GlobalSearchResult) -> Book? {
        let id = result.bookID ?? result.entityID
        return books.first { $0.id == id }
    }

    /// A highlight result stays reachable after its book is gone: `result.title`/`.subtitle`
    /// already carry the highlight's own snapshot (search indexes that, not a book join), so
    /// only the author needs a direct lookup when there is no live book left to read it from.
    public func quoteSummary(for result: GlobalSearchResult) -> BookQuoteSummary? {
        guard result.kind == .highlight, let bookId = result.bookID else { return nil }
        let book = books.first { $0.id == bookId }
        let author = book?.author ?? highlightBookAuthor(for: result.entityID)
        return BookQuoteSummary(bookId: bookId, title: result.title, author: author, book: book, quoteCount: 0)
    }

    private func highlightBookAuthor(for highlightID: String) -> String? {
        (try? AppDatabase.shared.fetchHighlight(id: highlightID))?.bookAuthor
    }

    private func indexLegacyArticles() {
        guard indexingTask == nil else { return }
        isIndexingArticles = true
        indexingTask = Task { [weak self] in
            _ = await ArticleSearchIndexer.shared.indexMissingArticles()
            guard let self else { return }
            self.isIndexingArticles = false
            self.indexingTask = nil
            self.reloadContext()
        }
    }

    private func indexBookContent() {
        guard bookContentIndexingTask == nil else { return }
        isIndexingBookContent = true
        bookContentIndexingTask = Task { [weak self] in
            _ = await BookContentIndexer.shared.indexMissingBooks()
            guard let self else { return }
            self.isIndexingBookContent = false
            self.bookContentIndexingTask = nil
            self.reloadContext()
        }
    }
}
