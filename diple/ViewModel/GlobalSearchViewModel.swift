import Foundation
import Combine

@MainActor
public final class GlobalSearchViewModel: ObservableObject {
    @Published public var query = ""
    @Published public private(set) var results: [GlobalSearchResult] = []
    @Published public private(set) var books: [Book] = []
    @Published public var errorMessage: String?

    public init() {
        reloadContext()
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
}
