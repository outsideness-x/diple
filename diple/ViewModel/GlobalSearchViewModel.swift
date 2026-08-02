import Foundation
import Combine

@MainActor
public final class GlobalSearchViewModel: ObservableObject {
    @Published public var query = ""
    @Published public private(set) var results: [GlobalSearchResult] = []
    @Published public private(set) var books: [Book] = []
    @Published public private(set) var isIndexingArticles = false
    @Published public var errorMessage: String?

    private var indexingTask: Task<Void, Never>?

    public init() {
        reloadContext()
        indexLegacyArticles()
    }

    public func reloadContext() {
        do {
            books = try AppDatabase.shared.fetchAllBooks()
            search()
        } catch {
            errorMessage = "Search is unavailable: \(error.localizedDescription)"
        }
    }

    public func search() {
        do {
            results = try AppDatabase.shared.search(query)
            errorMessage = nil
        } catch {
            results = []
            errorMessage = "Search failed: \(error.localizedDescription)"
        }
    }

    public func book(for result: GlobalSearchResult) -> Book? {
        let id = result.bookID ?? result.entityID
        return books.first { $0.id == id }
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
}
