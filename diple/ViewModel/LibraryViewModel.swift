import Foundation
import SwiftUI
import Combine

public enum LibraryFilter: String, CaseIterable, Identifiable, Sendable, Equatable, Hashable {
    case all = "All"
    case books = "Books"
    case pdfs = "PDFs"
    case articles = "Articles"
    case unread = "Unread"
    case inProgress = "In Progress"
    case finished = "Finished"

    public var id: Self { self }

    public func includes(_ book: Book) -> Bool {
        switch self {
        case .all: return true
        case .books: return book.sourceKind == .epub
        case .pdfs: return book.sourceKind == .pdf
        case .articles: return book.isArticle
        case .unread: return book.furthestProgress <= 0.001
        case .inProgress: return book.furthestProgress > 0.001 && book.furthestProgress < 0.995
        case .finished: return book.furthestProgress >= 0.995
        }
    }
}

public enum LibrarySort: String, CaseIterable, Identifiable, Sendable, Equatable, Hashable {
    case recentlyOpened = "Recently Opened"
    case recentlyAdded = "Recently Added"
    case title = "Title"
    case author = "Author"
    case source = "Source"

    public var id: Self { self }

    public var compactTitle: String {
        switch self {
        case .recentlyOpened: return "Recent"
        case .recentlyAdded: return "Added"
        case .title: return "Title"
        case .author: return "Author"
        case .source: return "Source"
        }
    }
}

@MainActor
public final class LibraryViewModel: ObservableObject {
    @Published public private(set) var books: [Book] = []
    @Published public var isImporting: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var showErrorAlert: Bool = false
    @Published public var bookToDelete: Book? = nil
    @Published public var showDeleteConfirmation: Bool = false
    private var syncObserver: AnyCancellable?

    public init() {
        loadBooks()
        syncObserver = NotificationCenter.default.publisher(for: .dipleRemoteDataDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.loadBooks() }
    }

    /// The unfinished book the reader touched most recently. The library remains the source of
    /// truth; this is a presentation over the same rows rather than a second persisted shelf.
    public var continueReadingBook: Book? {
        books
            .filter { $0.lastOpenedAt != nil && $0.furthestProgress > 0.001 && $0.furthestProgress < 0.995 }
            .max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }
    }

    /// Search, filtering and ordering are projections over the in-memory library. Opening the
    /// screen still costs one database read, and typing never issues a query per keystroke.
    public func visibleBooks(query: String, filter: LibraryFilter, sort: LibrarySort) -> [Book] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = books.filter { book in
            guard filter.includes(book) else { return false }
            guard !needle.isEmpty else { return true }
            return [book.title, book.author, book.sourceHost, book.sourceURL]
                .compactMap { $0 }
                .contains { $0.localizedStandardContains(needle) }
        }

        return matching.sorted { lhs, rhs in
            switch sort {
            case .recentlyOpened:
                let left = lhs.lastOpenedAt ?? .distantPast
                let right = rhs.lastOpenedAt ?? .distantPast
                return left == right ? lhs.addedAt > rhs.addedAt : left > right
            case .recentlyAdded:
                return lhs.addedAt > rhs.addedAt
            case .title:
                return ordered(lhs.title, before: rhs.title, fallback: lhs.addedAt > rhs.addedAt)
            case .author:
                return ordered(lhs.author ?? "", before: rhs.author ?? "", fallback: lhs.title < rhs.title)
            case .source:
                return ordered(lhs.sourceHost ?? "", before: rhs.sourceHost ?? "", fallback: lhs.title < rhs.title)
            }
        }
    }

    private func ordered(_ lhs: String, before rhs: String, fallback: Bool) -> Bool {
        let result = lhs.localizedCaseInsensitiveCompare(rhs)
        return result == .orderedSame ? fallback : result == .orderedAscending
    }

    public func loadBooks() {
        do {
            self.books = try AppDatabase.shared.fetchAllBooks()
        } catch {
            self.errorMessage = "Failed to load library: \(error.localizedDescription)"
            self.showErrorAlert = true
        }
    }

    public func importBook(from url: URL) {
        isImporting = true
        Task {
            do {
                _ = try await EPUBImporter.shared.importEPUB(from: url)
                await MainActor.run {
                    self.loadBooks()
                    self.isImporting = false
                }
            } catch {
                await MainActor.run {
                    self.errorMessage = "Failed to import book: \(error.localizedDescription)"
                    self.showErrorAlert = true
                    self.isImporting = false
                }
            }
        }
    }

    @Published public var bookToEdit: Book? = nil

    /// Updates metadata and reports whether the editor can be dismissed.
    @discardableResult
    public func updateMetadata(for bookId: String, title: String, author: String?, coverData: Data? = nil) -> Bool {
        do {
            var coverPath: String? = nil
            if let data = coverData {
                coverPath = try BookStorageService.shared.saveCoverData(data, bookId: bookId)
                if let coverPath {
                    // The path is stable across replacements, so the old artwork would
                    // otherwise stay cached.
                    CoverImageCache.shared.invalidate(relativePath: coverPath)
                }
            }
            try AppDatabase.shared.updateBookMetadata(id: bookId, title: title, author: author, coverPath: coverPath)
            loadBooks()
            return true
        } catch {
            self.errorMessage = "Failed to update metadata: \(error.localizedDescription)"
            self.showErrorAlert = true
            return false
        }
    }

    public func confirmDelete(_ book: Book) {
        self.bookToDelete = book
        self.showDeleteConfirmation = true
    }

    /// Marks the publication complete without disturbing its saved reading location. The
    /// locator is retained so a reader can still reopen the last passage if they choose.
    public func markAsFinished(_ book: Book) {
        guard book.furthestProgress < 0.995 else { return }

        do {
            try AppDatabase.shared.updateReadingProgress(
                id: book.id,
                progress: 1,
                locator: book.locator
            )
            loadBooks()
            HapticManager.shared.notification(.success)
        } catch {
            self.errorMessage = "Failed to mark book as finished: \(error.localizedDescription)"
            self.showErrorAlert = true
        }
    }

    public func deleteConfirmedBook() {
        guard let book = bookToDelete else { return }
        do {
            // Commit the database transaction first. If file cleanup then fails, the result is
            // an unreachable folder that can be retried safely, never a visible book whose file
            // has already disappeared.
            try AppDatabase.shared.deleteBook(id: book.id)
            loadBooks()

            do {
                try BookStorageService.shared.deleteBookFolder(id: book.id)
            } catch {
                self.errorMessage = "The book was removed, but its files could not be cleaned up: \(error.localizedDescription)"
                self.showErrorAlert = true
            }
        } catch {
            self.errorMessage = "Failed to delete book: \(error.localizedDescription)"
            self.showErrorAlert = true
        }
        self.bookToDelete = nil
        self.showDeleteConfirmation = false
    }
}
