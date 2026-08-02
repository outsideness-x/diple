import Foundation
import SwiftUI
import Combine

/// A library book together with how many quotes were saved from it.
public struct BookQuoteSummary: Identifiable, Equatable, Hashable {
    public let book: Book
    public let quoteCount: Int

    public var id: String { book.id }
}

@MainActor
public final class HubViewModel: ObservableObject {
    @Published public private(set) var summaries: [BookQuoteSummary] = []
    @Published public var errorMessage: String? = nil
    @Published public var showErrorAlert: Bool = false
    private var syncObserver: AnyCancellable?

    public var totalQuoteCount: Int {
        summaries.reduce(0) { $0 + $1.quoteCount }
    }

    public init() {
        load()
        syncObserver = NotificationCenter.default.publisher(for: .dipleRemoteDataDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.load() }
    }

    public func load() {
        do {
            let books = try AppDatabase.shared.fetchAllBooks()
            let counts = try AppDatabase.shared.fetchHighlightCountsByBook()
            summaries = books.compactMap { book in
                guard let count = counts[book.id], count > 0 else { return nil }
                return BookQuoteSummary(book: book, quoteCount: count)
            }
        } catch {
            errorMessage = "Failed to load quotes: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
}

@MainActor
public final class BookQuotesViewModel: ObservableObject {
    @Published public private(set) var quotes: [Highlight] = []
    @Published public var errorMessage: String? = nil
    @Published public var showErrorAlert: Bool = false

    private let bookId: String
    private var syncObserver: AnyCancellable?

    public init(bookId: String) {
        self.bookId = bookId
        load()
        syncObserver = NotificationCenter.default.publisher(for: .dipleRemoteDataDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.load() }
    }

    public func load() {
        do {
            quotes = try AppDatabase.shared.fetchHighlights(forBookId: bookId)
        } catch {
            errorMessage = "Failed to load quotes: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }
}
