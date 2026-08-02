import Foundation
import SwiftUI
import Combine

@MainActor
public final class LibraryViewModel: ObservableObject {
    @Published public private(set) var books: [Book] = []
    @Published public var isImporting: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var showErrorAlert: Bool = false
    @Published public var bookToDelete: Book? = nil
    @Published public var showDeleteConfirmation: Bool = false

    public init() {
        loadBooks()
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
