import Foundation
import SwiftUI
import Combine

/// A group of quotes that once belonged to one book. The book may since have been deleted —
/// `book` is then nil, and `title`/`author` fall back to the snapshot carried by the quotes
/// themselves so the group still has a name to show.
public struct BookQuoteSummary: Identifiable, Equatable, Hashable {
    public let bookId: String
    public let title: String
    public let author: String?
    public let book: Book?
    public let quoteCount: Int

    public var id: String { bookId }
    public var isRemovedFromLibrary: Bool { book == nil }

    /// Mirrors `Book.subtitle`'s shape so a removed group's row reads the same way a live
    /// book's does, with the missing book spelled out instead of silently omitted.
    public var subtitle: String {
        guard let book else {
            return [author, "Removed from library"].compactMap { $0 }.joined(separator: " · ")
        }
        return book.subtitle
    }
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
            let groups = try AppDatabase.shared.fetchHighlightGroups()
            let booksById = Dictionary(
                uniqueKeysWithValues: try AppDatabase.shared.fetchAllBooks().map { ($0.id, $0) }
            )
            summaries = groups.map { group in
                let book = booksById[group.bookId]
                return BookQuoteSummary(
                    bookId: group.bookId,
                    title: book?.title ?? group.bookTitle ?? "Untitled",
                    author: book?.author ?? group.bookAuthor,
                    book: book,
                    quoteCount: group.quoteCount
                )
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
    @Published public var quoteToDelete: Highlight? = nil
    @Published public var showDeleteConfirmation: Bool = false

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

    public func confirmDelete(_ quote: Highlight) {
        quoteToDelete = quote
        showDeleteConfirmation = true
    }

    public func deleteConfirmedQuote() {
        guard let quote = quoteToDelete else { return }
        do {
            try AppDatabase.shared.deleteHighlight(id: quote.id)
            load()
        } catch {
            errorMessage = "Failed to delete quote: \(error.localizedDescription)"
            showErrorAlert = true
        }
        quoteToDelete = nil
        showDeleteConfirmation = false
    }
}
