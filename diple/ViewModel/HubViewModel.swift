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
        syncObserver = Publishers.Merge(
            NotificationCenter.default.publisher(for: .dipleRemoteDataDidChange),
            NotificationCenter.default.publisher(for: .dipleDataDidRestore)
        )
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
    /// This book's tags by highlight id, loaded once per refresh so the list can draw a chip
    /// row on every card without a query per card.
    @Published public private(set) var tagsByQuote: [String: [String]] = [:]
    /// The whole library's passage vocabulary. The word this quote wants was very likely first
    /// typed in another book, so the menu offers all of them, not only this book's.
    @Published public private(set) var tagSuggestions: [String] = []
    @Published public var errorMessage: String? = nil
    @Published public var showErrorAlert: Bool = false
    @Published public var quoteToDelete: Highlight? = nil
    @Published public var showDeleteConfirmation: Bool = false
    @Published public var quoteForComment: Highlight? = nil

    private let bookId: String
    private var syncObserver: AnyCancellable?

    public init(bookId: String) {
        self.bookId = bookId
        load()
        syncObserver = Publishers.Merge(
            NotificationCenter.default.publisher(for: .dipleRemoteDataDidChange),
            NotificationCenter.default.publisher(for: .dipleDataDidRestore)
        )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.load() }
    }

    public func load() {
        do {
            quotes = try AppDatabase.shared.fetchHighlights(forBookId: bookId)
            tagsByQuote = try AppDatabase.shared.fetchTagsByHighlight(forBookId: bookId)
            tagSuggestions = try AppDatabase.shared.fetchAllHighlightTags()
        } catch {
            errorMessage = "Failed to load quotes: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    public func tags(for quote: Highlight) -> [String] {
        tagsByQuote[quote.id] ?? []
    }

    public func confirmDelete(_ quote: Highlight) {
        quoteToDelete = quote
        showDeleteConfirmation = true
    }

    public func beginEditingComment(_ quote: Highlight) {
        quoteForComment = quote
    }

    public func cancelCommentEditing() {
        quoteForComment = nil
    }

    /// The comment and the tags are written together because the editor collects them
    /// together: two calls would put two records in the CloudKit outbox and two rewrites of
    /// the same search document for one tap of Save.
    public func saveComment(_ comment: String, tags: [String]) {
        guard let quote = quoteForComment else { return }
        do {
            try AppDatabase.shared.updateHighlight(
                id: quote.id,
                colorHex: quote.colorHex,
                comment: comment,
                tags: tags
            )
            quoteForComment = nil
            load()
        } catch {
            errorMessage = "Failed to save passage: \(error.localizedDescription)"
            showErrorAlert = true
        }
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
