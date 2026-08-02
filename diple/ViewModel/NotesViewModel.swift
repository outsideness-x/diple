import Foundation
import SwiftUI
import Combine

/// A note with everything the board needs to draw it: its tags and the library item it
/// points at, resolved once at load time.
public struct NoteItem: Identifiable, Equatable, Hashable {
    public let note: Note
    public let tags: [String]
    public let book: Book?

    public var id: String { note.id }
}

/// What the board is currently narrowed down to.
public enum NoteFilter: Equatable, Hashable {
    case all
    case tag(String)
    case book(String)
}

@MainActor
public final class NotesViewModel: ObservableObject {
    @Published public private(set) var items: [NoteItem] = []
    @Published public private(set) var books: [Book] = []
    /// Every tag already in use, offered as suggestions in the editor.
    @Published public private(set) var allTags: [String] = []
    @Published public var filter: NoteFilter = .all
    @Published public var noteToDelete: NoteItem? = nil
    @Published public var showDeleteConfirmation: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var showErrorAlert: Bool = false

    public init() {
        load()
    }

    public func load() {
        do {
            let notes = try AppDatabase.shared.fetchAllNotes()
            let tagsByNote = try AppDatabase.shared.fetchTagsByNote()
            let books = try AppDatabase.shared.fetchAllBooks()
            let booksById = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })

            self.books = books
            self.allTags = try AppDatabase.shared.fetchAllTags()
            self.items = notes.map { note in
                NoteItem(
                    note: note,
                    tags: tagsByNote[note.id] ?? [],
                    book: note.bookId.flatMap { booksById[$0] }
                )
            }
            if !availableFilters.contains(filter) {
                filter = .all
            }
        } catch {
            errorMessage = "Failed to load notes: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    /// Every filter the current notes can actually satisfy — an empty tag chip would be a
    /// dead end.
    public var availableFilters: [NoteFilter] {
        let tags = Set(items.flatMap(\.tags)).sorted().map(NoteFilter.tag)
        let bookIds = items.compactMap(\.book).map(\.id)
        let uniqueBookIds = Array(NSOrderedSet(array: bookIds)).compactMap { $0 as? String }
        return [.all] + tags + uniqueBookIds.map(NoteFilter.book)
    }

    public var filteredItems: [NoteItem] {
        switch filter {
        case .all:
            return items
        case .tag(let tag):
            return items.filter { $0.tags.contains(tag) }
        case .book(let bookId):
            return items.filter { $0.book?.id == bookId }
        }
    }

    public func title(for filter: NoteFilter) -> String {
        switch filter {
        case .all:
            return "All"
        case .tag(let tag):
            return "#\(tag)"
        case .book(let bookId):
            return books.first { $0.id == bookId }?.title ?? "Book"
        }
    }

    /// Saves a note and tells the editor whether it is safe to leave editing mode.
    /// Keeping the result explicit prevents a failed write from looking like a successful save.
    @discardableResult
    public func save(_ note: Note, tags: [String]) -> Bool {
        do {
            var updated = note
            updated.updatedAt = Date()
            try AppDatabase.shared.saveNote(updated, tags: tags)
            load()
            return true
        } catch {
            errorMessage = "Failed to save note: \(error.localizedDescription)"
            showErrorAlert = true
            return false
        }
    }

    /// Deletion from the note's own page, which has already asked for confirmation.
    public func delete(_ item: NoteItem) {
        do {
            try AppDatabase.shared.deleteNote(id: item.note.id)
            load()
        } catch {
            errorMessage = "Failed to delete note: \(error.localizedDescription)"
            showErrorAlert = true
        }
    }

    public func confirmDelete(_ item: NoteItem) {
        noteToDelete = item
        showDeleteConfirmation = true
    }

    public func deleteConfirmedNote() {
        guard let item = noteToDelete else { return }
        do {
            try AppDatabase.shared.deleteNote(id: item.note.id)
            load()
        } catch {
            errorMessage = "Failed to delete note: \(error.localizedDescription)"
            showErrorAlert = true
        }
        noteToDelete = nil
        showDeleteConfirmation = false
    }
}
