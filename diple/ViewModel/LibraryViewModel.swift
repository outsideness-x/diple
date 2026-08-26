import Foundation
import SwiftUI
import Combine

/// What a source *is*. Exactly one of these is true of any given source.
///
/// Type and status used to be one enum, which made them alternatives to each other: choosing
/// "Articles" cleared "Unread" and there was no way to ask for unread articles. They are
/// orthogonal — one describes the file, the other describes the reader's history with it — so
/// they are two selections applied together.
public enum LibraryTypeFilter: String, CaseIterable, Identifiable, Sendable, Equatable, Hashable {
    case all = "All"
    case books = "Books"
    case pdfs = "PDFs"
    case articles = "Articles"

    public var id: Self { self }

    public func includes(_ book: Book) -> Bool {
        switch self {
        case .all: return true
        case .books: return book.sourceKind == .epub
        case .pdfs: return book.sourceKind == .pdf
        case .articles: return book.isArticle
        }
    }
}

/// How far the reader has got, measured against the saved position — the same number every
/// shelf prints and the reader's own bar shows. A row reading `12%` filed under Finished is the
/// shelf and the book disagreeing about the same fact. See "Прогресс чтения" in CLAUDE.md.
public enum LibraryStatusFilter: String, CaseIterable, Identifiable, Sendable, Equatable, Hashable {
    case any = "Any status"
    case unread = "Unread"
    case reading = "Reading"
    case finished = "Finished"

    public var id: Self { self }

    /// Shown on the filter menu's own label, where "Any status" would be noise but a chosen
    /// status has to be visible — a filter you cannot see is a library that looks broken.
    public var compactTitle: String? {
        self == .any ? nil : rawValue
    }

    public func includes(_ book: Book) -> Bool {
        switch self {
        case .any: return true
        case .unread: return book.progress <= 0.001
        case .reading: return book.progress > 0.001 && book.progress < 0.995
        case .finished: return book.progress >= 0.995
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
    /// Tags for every source, fetched once per load rather than per card.
    @Published public private(set) var tagsByBook: [String: [String]] = [:]
    /// Every tag in use across the library, for the filter row and for suggestions.
    @Published public private(set) var allTags: [String] = []
    /// Prose length per source, for the reading estimates on cards. Fetched with the library
    /// rather than per row: reading it inside a card's `body` would mean a query per scroll.
    @Published public private(set) var charactersByBook: [String: Int] = [:]
    @Published public var isImporting: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var showErrorAlert: Bool = false
    @Published public var bookToDelete: Book? = nil
    @Published public var showDeleteConfirmation: Bool = false
    private var observers: Set<AnyCancellable> = []

    public init() {
        loadBooks()
        NotificationCenter.default.publisher(for: .dipleRemoteDataDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.loadBooks() }
            .store(in: &observers)
        NotificationCenter.default.publisher(for: .dipleDataDidRestore)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.loadBooks() }
            .store(in: &observers)
        // An import started on Home has to reach the shelf, and the shelf is a *different*
        // instance of this class in a different tab. Without this, the second instance kept
        // whatever it read at launch until the app was quit and reopened — which is exactly
        // what a reader reported: a book imported and opened was invisible in the library.
        NotificationCenter.default.publisher(for: .dipleSourceDidImport)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.loadBooks() }
            .store(in: &observers)
    }

    /// The unfinished book the reader touched most recently. The library remains the source of
    /// truth; this is a presentation over the same rows rather than a second persisted shelf.
    ///
    /// Archived sources are excluded even when half-read: archiving is the reader saying they
    /// are done with it for now, and an app that keeps offering it back has not listened.
    ///
    /// Having opened it is the whole test. There used to be a `progress > 0.001` floor as well,
    /// and it made Continue lie in the one case where a reader watches it hardest: import a
    /// book, open it, come back, and Home still offered the *previous* book. A publication
    /// opened at its first page has `progress == 0`, and one page into a hundred-chapter book is
    /// still under a thousandth of it — so the floor did not exclude "never started", which
    /// `lastOpenedAt` already excludes on its own; it excluded "just started", which is exactly
    /// what Continue is for.
    public var continueReadingBook: Book? {
        books
            .filter {
                $0.location != .archive
                    && $0.lastOpenedAt != nil
                    && $0.progress < 0.995
            }
            .max { ($0.lastOpenedAt ?? .distantPast) < ($1.lastOpenedAt ?? .distantPast) }
    }

    /// How many sources sit in each location. Drives the counts on the library's location
    /// picker, which is the only place a reader can see an inbox filling up without opening it.
    public func count(in location: BookLocation) -> Int {
        books.lazy.filter { $0.location == location }.count
    }

    /// Search, filtering and ordering are projections over the in-memory library. Opening the
    /// screen still costs one database read, and typing never issues a query per keystroke.
    public func visibleBooks(
        query: String,
        location: BookLocation,
        type: LibraryTypeFilter = .all,
        status: LibraryStatusFilter = .any,
        tags selectedTags: Set<String> = [],
        sort: LibrarySort
    ) -> [Book] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = books.filter { book in
            // The location is navigation, not a filter, so it binds before everything else:
            // searching inside the inbox must not start returning archived results.
            guard book.location == location else { return false }
            guard type.includes(book), status.includes(book) else { return false }
            // Selecting two tags means both, not either: tags narrow, and an OR would make
            // each extra tag return *more*, which is the opposite of what picking one more
            // filter looks like it should do.
            if !selectedTags.isEmpty {
                guard selectedTags.isSubset(of: Set(tagsByBook[book.id] ?? [])) else { return false }
            }
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
            self.tagsByBook = try AppDatabase.shared.fetchTagsByBook()
            self.allTags = try AppDatabase.shared.fetchAllBookTags()
            self.charactersByBook = try AppDatabase.shared.contentCharacterCounts()
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

    public func move(_ book: Book, to location: BookLocation) {
        guard book.location != location else { return }

        do {
            try AppDatabase.shared.updateBookLocation(id: book.id, location: location)
            loadBooks()
            HapticManager.shared.notification(.success)
        } catch {
            self.errorMessage = "Failed to move this source: \(error.localizedDescription)"
            self.showErrorAlert = true
        }
    }

    public func setTags(_ tags: [String], for book: Book) {
        do {
            try AppDatabase.shared.setTags(tags, forBookId: book.id)
            loadBooks()
        } catch {
            self.errorMessage = "Failed to save tags: \(error.localizedDescription)"
            self.showErrorAlert = true
        }
    }

    public func confirmDelete(_ book: Book) {
        self.bookToDelete = book
        self.showDeleteConfirmation = true
    }

    /// Marks the publication complete without disturbing its saved reading location. The
    /// locator is retained so a reader can still reopen the last passage if they choose.
    public func markAsFinished(_ book: Book) {
        guard book.progress < 0.995 else { return }

        do {
            try AppDatabase.shared.markBookAsFinished(id: book.id)
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
