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

    public var displayTitle: String {
        let explicit = note.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !explicit.isEmpty { return explicit }
        return NoteMarkdown.parse(note.body).compactMap { block in
            if case .heading(_, let text) = block { return text }
            return nil
        }.first ?? "Untitled"
    }
}

/// What the board is currently narrowed down to.
public enum NoteFilter: Equatable, Hashable {
    case all
    case recent
    case linked
    case untagged
    case tag(String)
    case book(String)
}

/// The sort is intentionally small and predictable. Notes are a thinking space, not a
/// spreadsheet; the three orders cover returning to work, browsing history and scanning
/// an alphabetical reference shelf without turning the toolbar into a query builder.
public enum NoteSort: String, CaseIterable, Identifiable {
    case updated
    case created
    case title

    public var id: Self { self }

    public var title: String {
        switch self {
        case .updated: return "Last edited"
        case .created: return "Date created"
        case .title: return "Title"
        }
    }

    public var systemImage: String {
        switch self {
        case .updated: return "clock.arrow.circlepath"
        case .created: return "calendar"
        case .title: return "textformat.abc"
        }
    }
}

@MainActor
public final class NotesViewModel: ObservableObject {
    @Published public private(set) var items: [NoteItem] = []
    @Published public private(set) var books: [Book] = []
    /// Every tag already in use, offered as suggestions in the editor.
    @Published public private(set) var allTags: [String] = []
    @Published public var filter: NoteFilter = .all
    @Published public var query: String = ""
    @Published public var sort: NoteSort = .updated
    @Published public var noteToDelete: NoteItem? = nil
    @Published public var showDeleteConfirmation: Bool = false
    @Published public var errorMessage: String? = nil
    @Published public var showErrorAlert: Bool = false
    private var syncObserver: AnyCancellable?

    public init() {
        load()
        syncObserver = NotificationCenter.default.publisher(for: .dipleRemoteDataDidChange)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.load() }
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
        var smart: [NoteFilter] = [.all]
        if items.contains(where: { Calendar.current.isDate($0.note.updatedAt, equalTo: Date(), toGranularity: .weekOfYear) }) {
            smart.append(.recent)
        }
        if items.contains(where: { $0.book != nil }) {
            smart.append(.linked)
        }
        if items.contains(where: { $0.tags.isEmpty && $0.book == nil }) {
            smart.append(.untagged)
        }
        let tags = Set(items.flatMap(\.tags)).sorted().map(NoteFilter.tag)
        let bookIds = items.compactMap(\.book).map(\.id)
        let uniqueBookIds = Array(NSOrderedSet(array: bookIds)).compactMap { $0 as? String }
        return smart + tags + uniqueBookIds.map(NoteFilter.book)
    }

    public var filteredItems: [NoteItem] {
        let scoped: [NoteItem]
        switch filter {
        case .all:
            scoped = items
        case .recent:
            scoped = items.filter {
                Calendar.current.isDate($0.note.updatedAt, equalTo: Date(), toGranularity: .weekOfYear)
            }
        case .linked:
            scoped = items.filter { $0.book != nil }
        case .untagged:
            scoped = items.filter { $0.tags.isEmpty && $0.book == nil }
        case .tag(let tag):
            scoped = items.filter { $0.tags.contains(tag) }
        case .book(let bookId):
            scoped = items.filter { $0.book?.id == bookId }
        }

        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let matching = needle.isEmpty ? scoped : scoped.filter { item in
            let haystack = [
                item.note.title ?? "",
                item.note.body,
                item.tags.joined(separator: " "),
                item.book?.title ?? "",
                item.book?.author ?? ""
            ].joined(separator: "\n")
            return haystack.localizedStandardContains(needle)
        }

        switch sort {
        case .updated:
            return matching.sorted { $0.note.updatedAt > $1.note.updatedAt }
        case .created:
            return matching.sorted { $0.note.createdAt > $1.note.createdAt }
        case .title:
            return matching.sorted {
                displayTitle(for: $0).localizedStandardCompare(displayTitle(for: $1)) == .orderedAscending
            }
        }
    }

    public func title(for filter: NoteFilter) -> String {
        switch filter {
        case .all:
            return "All"
        case .recent:
            return "This week"
        case .linked:
            return "From library"
        case .untagged:
            return "Unsorted"
        case .tag(let tag):
            return "#\(tag)"
        case .book(let bookId):
            return books.first { $0.id == bookId }?.title ?? "Book"
        }
    }

    public var totalWordCount: Int {
        items.reduce(0) { result, item in
            result + item.note.body.split { $0.isWhitespace || $0.isNewline }.count
        }
    }

    public var linkedCount: Int { items.filter { $0.book != nil }.count }

    private func displayTitle(for item: NoteItem) -> String {
        let title = item.note.title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !title.isEmpty { return title }
        return item.note.body
            .split(whereSeparator: \Character.isNewline)
            .first
            .map(String.init) ?? "Untitled"
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
