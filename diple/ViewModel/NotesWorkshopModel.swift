import Foundation
import SwiftUI
import Combine

/// The notes workshop's one source of truth: every living note, the spaces, Recently deleted,
/// and what a note page needs beside them — the books a note can be linked to, the passages its
/// Connections can see, the vocabulary its tag menu offers.
///
/// Every page of the workshop reads this one model, so a note moved on the space page is already
/// out of the Inbox when the reader goes back to it. What the rows *mean* — which notes are in
/// the Inbox, what is pinned, what each space holds — is `NotesDesk`, a pure function; this holds
/// the rows and writes to the database. The All notes board keeps its own `MarginaliaViewModel`,
/// as Highlights does, because the board's narrowing is its own state; both read `AppDatabase`,
/// and the board reloads whenever it is shown.
@MainActor
public final class NotesWorkshopModel: ObservableObject {
    @Published public private(set) var items: [NoteItem] = []
    @Published public private(set) var trashed: [NoteItem] = []
    @Published public private(set) var spaces: [NoteSpace] = []
    @Published public private(set) var books: [Book] = []
    @Published public private(set) var passages: [PassageItem] = []
    @Published public private(set) var tagVocabulary: [String] = []
    /// The passages' own words, for the passage editor a note's Connections can open. A separate
    /// vocabulary on purpose — see `HighlightTag`.
    @Published public private(set) var passageTagVocabulary: [String] = []

    @Published public var errorMessage: String?
    @Published public var showErrorAlert = false

    private var observer: AnyCancellable?

    public init() {
        load()
        observer = Publishers.Merge(
            NotificationCenter.default.publisher(for: .dipleRemoteDataDidChange),
            NotificationCenter.default.publisher(for: .dipleDataDidRestore)
        )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.load() }
    }

    // MARK: - Loading

    public func load() {
        do {
            let database = AppDatabase.shared
            let books = try database.fetchAllBooks()
            let booksByID = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })
            let tagsByNote = try database.fetchTagsByNote()
            func item(_ note: Note) -> NoteItem {
                NoteItem(note: note, tags: tagsByNote[note.id] ?? [], book: note.bookId.flatMap { booksByID[$0] })
            }

            let tagsByHighlight = try database.fetchTagsByHighlight()
            self.books = books
            self.items = try database.fetchAllNotes().map(item)
            self.trashed = try database.fetchTrashedNotes().map(item)
            self.spaces = try database.fetchSpaces()
            self.tagVocabulary = try database.fetchAllTags()
            self.passageTagVocabulary = try database.fetchAllHighlightTags()
            self.passages = try database.fetchAllHighlights().map {
                PassageItem(highlight: $0, tags: tagsByHighlight[$0.id] ?? [], book: booksByID[$0.bookId])
            }
        } catch {
            present(error, doing: "load your notes")
        }
    }

    // MARK: - Derived

    public var inbox: [NoteItem] { NotesDesk.inbox(items, spaces: spaces) }
    public var pinned: [NoteItem] { NotesDesk.pinned(items) }
    public var sources: [NotesDesk.SourceEntry] { NotesDesk.sources(items) }
    public var journal: [NoteItem] { NotesDesk.journal(items) }
    public var spaceCounts: [String: Int] { NotesDesk.counts(bySpace: items) }
    public var openTaskCount: Int { NotesDesk.openTaskCount(items) }

    public func space(id: String) -> NoteSpace? { spaces.first { $0.id == id } }
    public func book(id: String) -> Book? { books.first { $0.id == id } }

    /// The newest copy of a note the workshop holds — a row captured a moment ago may already be
    /// out of date by the time it is acted on.
    public func current(_ item: NoteItem) -> NoteItem? {
        items.first { $0.id == item.id }
    }

    /// Today's page, if it has been started.
    public func todayPage(now: Date = Date()) -> NoteItem? {
        NotesDesk.dailyPage(for: Note.dailyKey(for: now), in: items)
    }

    // MARK: - Writing

    @discardableResult
    public func save(_ note: Note, tags: [String]) -> Bool {
        do {
            var updated = note
            updated.updatedAt = Date()
            try AppDatabase.shared.saveNote(updated, tags: tags)
            load()
            return true
        } catch {
            present(error, doing: "save this note")
            return false
        }
    }

    /// Ticks or unticks one box, from a list that is not the note's own page. Ticking is
    /// writing — the note says something different afterwards — so it goes through `save`
    /// and moves the note's date, exactly as ticking the box on its page does.
    public func toggleTask(_ task: NoteTask, in item: NoteItem) {
        guard let body = NoteMarkdown.togglingTask(atLine: task.lineIndex, in: item.note.body) else { return }
        var note = item.note
        note.body = body
        save(note, tags: item.tags)
    }

    /// A passage opened from a note's Connections, edited in the reader's own sheet.
    public func savePassage(_ passage: PassageItem, colorHex: String, comment: String?, tags: [String]) {
        perform("save this passage") {
            try AppDatabase.shared.updateHighlight(id: passage.id, colorHex: colorHex, comment: comment, tags: tags)
        }
    }

    public func deletePassage(_ passage: PassageItem) {
        perform("delete this passage") {
            try AppDatabase.shared.deleteHighlight(id: passage.id)
        }
    }

    // MARK: - Where notes live

    /// `reload: false` is for the filing pass, which walks its own snapshot and reads the
    /// database once when it closes rather than once per note filed.
    public func move(_ items: [NoteItem], to space: NoteSpace?, reload: Bool = true) {
        do {
            try AppDatabase.shared.moveNotes(ids: items.map(\.id), toSpace: space?.id)
            if reload { load() }
        } catch {
            present(error, doing: "move this note")
        }
    }

    public func setPinned(_ pinned: Bool, _ item: NoteItem) {
        perform("pin this note") {
            try AppDatabase.shared.setPinned(pinned, noteID: item.id)
        }
    }

    /// To Recently deleted. Nothing asks first: it can be undone for thirty days, and a
    /// question in front of an undoable act is only a delay.
    public func trash(_ items: [NoteItem]) {
        perform("delete this note") {
            for item in items { try AppDatabase.shared.trashNote(id: item.id) }
        }
    }

    public func restore(_ item: NoteItem) {
        perform("restore this note") {
            try AppDatabase.shared.restoreNote(id: item.id)
        }
    }

    /// Gone for good, from Recently deleted — the one deletion in the workshop that asks,
    /// because it is the one that cannot be undone.
    public func deleteForever(_ items: [NoteItem]) {
        perform("delete this note") {
            for item in items { try AppDatabase.shared.deleteNote(id: item.id) }
        }
    }

    // MARK: - Spaces

    @discardableResult
    public func createSpace(named name: String, symbol: String) -> NoteSpace? {
        guard let name = Self.spaceName(name) else { return nil }
        do {
            let space = try AppDatabase.shared.createSpace(named: name, symbol: symbol)
            load()
            return space
        } catch {
            present(error, doing: "create this space")
            return nil
        }
    }

    public func update(_ space: NoteSpace, name: String, symbol: String) {
        guard let name = Self.spaceName(name) else { return }
        var changed = space
        changed.name = name
        changed.symbol = symbol
        changed.updatedAt = Date()
        perform("change this space") { try AppDatabase.shared.saveSpace(changed) }
    }

    /// Puts the spaces in a new order, writing only the one that moved: it takes the midpoint
    /// of its new neighbours, which is one synced record rather than a renumbering of the list.
    public func moveSpaces(from source: IndexSet, to destination: Int) {
        var reordered = spaces
        reordered.move(fromOffsets: source, toOffset: destination)
        guard let movedID = source.first.map({ spaces[$0].id }),
              let index = reordered.firstIndex(where: { $0.id == movedID })
        else { return }
        var moved = reordered[index]
        moved.sortIndex = NoteSpace.sortIndex(
            between: index > 0 ? reordered[index - 1].sortIndex : nil,
            and: index < reordered.count - 1 ? reordered[index + 1].sortIndex : nil
        )
        moved.updatedAt = Date()
        // Shown in its new place at once, before the write lands, so the row does not hop back
        // for a frame under the finger that just put it there.
        reordered[index] = moved
        spaces = reordered
        perform("reorder your spaces") { try AppDatabase.shared.saveSpace(moved) }
    }

    public func delete(_ space: NoteSpace) {
        perform("delete this space") { _ = try AppDatabase.shared.deleteSpace(id: space.id) }
    }

    /// A name worth keeping, or `nil`. Surrounding space is trimmed; an empty name is refused
    /// rather than stored as a space nobody can see.
    static func spaceName(_ raw: String) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    // MARK: - Plumbing

    private func perform(_ action: String, _ work: () throws -> Void) {
        do {
            try work()
            load()
        } catch {
            present(error, doing: action)
        }
    }

    private func present(_ error: Error, doing action: String) {
        errorMessage = "Failed to \(action): \(error.localizedDescription)"
        showErrorAlert = true
    }
}
