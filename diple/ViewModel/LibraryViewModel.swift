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
                    self.errorMessage = "Failed to import EPUB: \(error.localizedDescription)"
                    self.showErrorAlert = true
                    self.isImporting = false
                }
            }
        }
    }

    @Published public var bookToEdit: Book? = nil

    public func updateMetadata(for bookId: String, title: String, author: String?, coverData: Data? = nil) {
        do {
            var coverPath: String? = nil
            if let data = coverData {
                coverPath = try BookStorageService.shared.saveCoverData(data, bookId: bookId)
            }
            try AppDatabase.shared.updateBookMetadata(id: bookId, title: title, author: author, coverPath: coverPath)
            loadBooks()
        } catch {
            self.errorMessage = "Failed to update metadata: \(error.localizedDescription)"
            self.showErrorAlert = true
        }
    }

    public func confirmDelete(_ book: Book) {
        self.bookToDelete = book
        self.showDeleteConfirmation = true
    }

    public func deleteConfirmedBook() {
        guard let book = bookToDelete else { return }
        do {
            try BookStorageService.shared.deleteBookFolder(id: book.id)
            try AppDatabase.shared.deleteBook(id: book.id)
            loadBooks()
        } catch {
            self.errorMessage = "Failed to delete book: \(error.localizedDescription)"
            self.showErrorAlert = true
        }
        self.bookToDelete = nil
        self.showDeleteConfirmation = false
    }
}
