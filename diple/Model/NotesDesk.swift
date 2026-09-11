import Foundation

/// What the notes workshop shows, as a pure function of the notes and the spaces.
///
/// The same arrangement `MarginaliaBoard` makes for the board: the view model holds the rows and
/// the database, this says what they *mean* — which notes are in the Inbox, which are pinned,
/// how many stand in each space — so the rules can be tested without launching the app on a live
/// library, which is the one thing CLAUDE.md does not allow.
public nonisolated enum NotesDesk {

    // MARK: - Where a note stands

    /// A note filed by nothing: no space the reader can see, no source, and not a day's page.
    ///
    /// A space that has not arrived from iCloud yet counts as no space — the note waits here
    /// with its filing intact (see `NoteSpace`). A note written inside a book is filed by that
    /// book and stands in From reading instead; a day's page is filed by its date.
    public static func isInInbox(_ item: NoteItem, spaceIDs: Set<String>) -> Bool {
        let hasSpace = item.note.spaceId.map(spaceIDs.contains) ?? false
        return !hasSpace && item.note.bookId == nil && item.note.dailyDate == nil
    }

    public static func inbox(_ items: [NoteItem], spaces: [NoteSpace]) -> [NoteItem] {
        let ids = Set(spaces.map(\.id))
        return ordered(items.filter { isInInbox($0, spaceIDs: ids) })
    }

    public static func notes(in space: NoteSpace, from items: [NoteItem]) -> [NoteItem] {
        ordered(items.filter { $0.note.spaceId == space.id })
    }

    /// Everything written about one source, wherever else it has been filed: From reading is a
    /// view over the link to the book, not a folder, so a note moved into a space stays here too.
    public static func notes(about bookID: String, from items: [NoteItem]) -> [NoteItem] {
        ordered(items.filter { $0.note.bookId == bookID })
    }

    /// Pinned notes, in the order they were pinned.
    public static func pinned(_ items: [NoteItem]) -> [NoteItem] {
        items
            .filter(\.note.isPinned)
            .sorted { ($0.note.pinnedAt ?? .distantPast) < ($1.note.pinnedAt ?? .distantPast) }
    }

    /// The order every list in the workshop stands in: pinned first, in pin order, then the
    /// rest by when they were last touched. One rule everywhere, so a note is found in the same
    /// place relative to its neighbours on every page it appears on.
    public static func ordered(_ items: [NoteItem]) -> [NoteItem] {
        pinned(items) + items
            .filter { !$0.note.isPinned }
            .sorted { $0.note.updatedAt > $1.note.updatedAt }
    }

    // MARK: - The Desk's own rows

    /// A source with notes about it, for the From reading section.
    public struct SourceEntry: Identifiable, Equatable {
        public let book: Book
        public let count: Int
        public var id: String { book.id }
    }

    /// Sources that have notes, most recently written about first. A deleted book's notes lose
    /// their link when it goes (see `deleteBook`), so every entry here has a book behind it.
    public static func sources(_ items: [NoteItem]) -> [SourceEntry] {
        var latest: [String: Date] = [:]
        var counts: [String: Int] = [:]
        var books: [String: Book] = [:]
        for item in items {
            guard let book = item.book else { continue }
            counts[book.id, default: 0] += 1
            books[book.id] = book
            latest[book.id] = max(latest[book.id] ?? .distantPast, item.note.updatedAt)
        }
        return books.values
            .sorted { (latest[$0.id] ?? .distantPast) > (latest[$1.id] ?? .distantPast) }
            .map { SourceEntry(book: $0, count: counts[$0.id] ?? 0) }
    }

    /// How many living notes stand in each space.
    public static func counts(bySpace items: [NoteItem]) -> [String: Int] {
        items.reduce(into: [:]) { counts, item in
            if let space = item.note.spaceId { counts[space, default: 0] += 1 }
        }
    }

    /// The day's pages, newest day first.
    public static func journal(_ items: [NoteItem]) -> [NoteItem] {
        items
            .filter { $0.note.dailyDate != nil }
            .sorted { ($0.note.dailyDate ?? "") > ($1.note.dailyDate ?? "") }
    }

    /// The page for `key`, when it has been started: the earliest of them, if two devices each
    /// began one offline. The same answer `AppDatabase.fetchDailyNote(forKey:)` gives.
    public static func dailyPage(for key: String, in items: [NoteItem]) -> NoteItem? {
        items
            .filter { $0.note.dailyDate == key }
            .min { $0.note.createdAt < $1.note.createdAt }
    }

    // MARK: - Tasks

    /// One note's open tasks, for the Tasks list.
    public struct TaskGroup: Identifiable, Equatable {
        public let item: NoteItem
        public let tasks: [NoteTask]
        public var id: String { item.id }
    }

    /// Where one task lives, stable across the tick that completes it: the line does not move
    /// when its box is filled, so `lineIndex` still names it afterwards.
    public struct TaskKey: Hashable, Sendable {
        public let noteID: String
        public let lineIndex: Int

        public init(noteID: String, lineIndex: Int) {
            self.noteID = noteID
            self.lineIndex = lineIndex
        }
    }

    /// Every open `- [ ]` in every living note, grouped by note, in the workshop's order.
    ///
    /// `lingering` keeps a just-completed task on the list for the moment it takes the thumb
    /// to see it land — the way Things lets a ticked to-do stay put for a beat before it goes —
    /// rather than whipping the row away in the same frame the box fills.
    public static func openTasks(
        _ items: [NoteItem],
        lingering: Set<TaskKey> = []
    ) -> [TaskGroup] {
        ordered(items).compactMap { item in
            let tasks = NoteMarkdown.parse(item.note.body).flatMap { block -> [NoteTask] in
                if case .tasks(let tasks) = block { return tasks }
                return []
            }
            .filter { task in
                !task.isCompleted
                    || lingering.contains(TaskKey(noteID: item.id, lineIndex: task.lineIndex))
            }
            return tasks.isEmpty ? nil : TaskGroup(item: item, tasks: tasks)
        }
    }

    public static func openTaskCount(_ items: [NoteItem]) -> Int {
        openTasks(items).reduce(0) { $0 + $1.tasks.count }
    }

    // MARK: - Finding

    /// The Desk's quick find: every word of the query somewhere in the note — its title, its
    /// text, its tags or its source — in the workshop's order.
    public static func search(_ query: String, in items: [NoteItem]) -> [NoteItem] {
        let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !words.isEmpty else { return [] }
        return ordered(items.filter { item in
            let haystack = MarginaliaEntry.note(item).haystack
            return words.allSatisfy { haystack.localizedStandardContains($0) }
        })
    }
}
