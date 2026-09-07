import Foundation
import SwiftUI
import Combine

/// The board of everything made from reading: notes and saved passages under one set of
/// controls.
///
/// It does not replace `NotesViewModel`, which is still the notes data source for Home and for
/// the desktop's own list. What lives only here is the *narrowing* — scope, lenses, facets,
/// query, order, grouping — because that is the part the two collections had to start sharing:
/// a tag written on a passage was unreachable by any control in the app before this, while the
/// identical word on a note had a chip.
@MainActor
public final class MarginaliaViewModel: ObservableObject {
    // MARK: - Data

    @Published public private(set) var entries: [MarginaliaEntry] = []
    @Published public private(set) var books: [Book] = []
    /// The notes vocabulary and the passages vocabulary, kept apart — see `HighlightTag` for
    /// why they are three tables — and merged only for the filter row, which narrows over both
    /// collections at once and so has to offer every word either of them uses.
    @Published public private(set) var noteTagVocabulary: [String] = []
    @Published public private(set) var passageTagVocabulary: [String] = []

    // MARK: - Narrowing

    @Published public var scope: MarginaliaScope = .all
    @Published public var lenses: Set<MarginaliaLens> = []
    @Published public var facets = MarginaliaFacets()
    /// The raw contents of the search field, `#` and `@` operators included. Parsed rather than
    /// matched directly; see `MarginaliaQuery`.
    @Published public var rawQuery: String = ""
    @Published public var sort: MarginaliaSort = .recent
    @Published public var grouping: MarginaliaGrouping = .none

    // MARK: - Errors and confirmations

    @Published public var errorMessage: String? = nil
    @Published public var showErrorAlert: Bool = false
    @Published public var entryToDelete: MarginaliaEntry? = nil
    @Published public var showDeleteConfirmation: Bool = false
    /// The tag the rename prompt is open for, or `nil`.
    @Published public var tagToRename: String? = nil
    /// A rename that turned out to be a merge, waiting to be confirmed.
    @Published public var pendingMerge: PendingMerge? = nil

    /// Renaming onto a word that already exists is a merge, and a merge cannot be undone:
    /// renaming back afterwards returns one word, not the two sets that went into it. So it is
    /// asked about, and the question carries the number that makes it a real question.
    public struct PendingMerge: Identifiable, Equatable {
        public let from: String
        public let to: String
        public let existing: Int

        public var id: String { "\(from)>\(to)" }
    }

    private var syncObserver: AnyCancellable?
    /// Bumped on every load, so the derived snapshot below knows the rows underneath it moved
    /// even when not one control changed.
    private var dataVersion = 0
    private var cached: (signature: Signature, snapshot: MarginaliaBoard.Snapshot)?

    public init() {
        load()
        syncObserver = Publishers.Merge(
            NotificationCenter.default.publisher(for: .dipleRemoteDataDidChange),
            NotificationCenter.default.publisher(for: .dipleDataDidRestore)
        )
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in self?.load() }
    }

    // MARK: - Loading

    public func load() {
        do {
            let notes = try AppDatabase.shared.fetchAllNotes()
            let tagsByNote = try AppDatabase.shared.fetchTagsByNote()
            let highlights = try AppDatabase.shared.fetchAllHighlights()
            let tagsByHighlight = try AppDatabase.shared.fetchTagsByHighlight()
            let books = try AppDatabase.shared.fetchAllBooks()
            let booksById = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })

            self.books = books
            self.noteTagVocabulary = try AppDatabase.shared.fetchAllTags()
            self.passageTagVocabulary = try AppDatabase.shared.fetchAllHighlightTags()

            let noteEntries = notes.map { note in
                MarginaliaEntry.note(
                    NoteItem(
                        note: note,
                        tags: tagsByNote[note.id] ?? [],
                        book: note.bookId.flatMap { booksById[$0] }
                    )
                )
            }
            let passageEntries = highlights.map { highlight in
                MarginaliaEntry.passage(
                    PassageItem(
                        highlight: highlight,
                        tags: tagsByHighlight[highlight.id] ?? [],
                        book: booksById[highlight.bookId]
                    )
                )
            }

            self.entries = noteEntries + passageEntries
            self.dataVersion += 1
            pruneNarrowing()
        } catch {
            present(error, doing: "load your notes")
        }
    }

    /// Drops any part of the narrowing that the rows can no longer satisfy.
    ///
    /// A tag deleted off its last note, or a source removed from the library, would otherwise
    /// leave the board filtered to nothing by a chip that is no longer drawn anywhere — an
    /// empty screen with no visible cause and no way back except relaunching.
    private func pruneNarrowing() {
        selection.formIntersection(Set(entries.map(\.id)))
        if selection.isEmpty && isSelecting && entries.isEmpty { isSelecting = false }
        let liveTags = Set(entries.flatMap(\.tags))
        let liveSources = Set(entries.compactMap(\.bookId))
        facets.tags.formIntersection(liveTags)
        facets.bookIds.formIntersection(liveSources)
    }

    // MARK: - Derived

    /// Everything the board draws, computed once per change of input rather than once per
    /// `body`. SwiftUI reads these several times a frame and the facet tallies walk the whole
    /// catalogue, so recomputing them per read made a keystroke cost as much as a reload. The
    /// signature carries `dataVersion` as well as the controls, because rows can move under a
    /// board nobody touched — a CloudKit push, a restore, a note saved on another screen.
    private struct Signature: Equatable {
        let dataVersion: Int
        let controls: MarginaliaBoard.Controls
    }

    public var controls: MarginaliaBoard.Controls {
        MarginaliaBoard.Controls(
            scope: scope,
            lenses: lenses,
            facets: facets,
            rawQuery: rawQuery,
            sort: sort,
            grouping: grouping
        )
    }

    private var snapshot: MarginaliaBoard.Snapshot {
        let signature = Signature(dataVersion: dataVersion, controls: controls)
        if let cached, cached.signature == signature { return cached.snapshot }
        let fresh = MarginaliaBoard.snapshot(entries: entries, books: books, controls: controls)
        cached = (signature, fresh)
        return fresh
    }

    public var results: [MarginaliaEntry] { snapshot.results }
    public var groups: [MarginaliaGroup] { snapshot.groups }
    /// The chips, in the order the row prints them: what is already chosen first, then what
    /// would narrow the most.
    public var facetOptions: [MarginaliaFacetOption] { snapshot.facetOptions }
    public var sourceOptions: [MarginaliaFacetOption] { snapshot.sourceOptions }
    public var tagOptions: [MarginaliaFacetOption] { snapshot.tagOptions }
    public var lensOptions: [MarginaliaBoard.LensOption] { snapshot.lensOptions }

    public func count(for scope: MarginaliaScope) -> Int {
        switch scope {
        case .all: return snapshot.totalCount
        case .written: return snapshot.writtenCount
        case .saved: return snapshot.savedCount
        }
    }

    public var totalWritten: Int { entries.filter { $0.kind == .written }.count }
    public var totalSaved: Int { entries.filter { $0.kind == .saved }.count }
    public var isNarrowed: Bool { !facets.isEmpty || !lenses.isEmpty || !rawQuery.isEmpty }

    // MARK: - Suggestions

    /// What the search field offers while a `#` or `@` token is still being typed.
    public func suggestions(for token: MarginaliaQuery.Token) -> [MarginaliaFacetOption] {
        switch token {
        case .tag(let prefix):
            let pool = tagOptions.isEmpty ? allTagOptions() : tagOptions
            return pool.filter { prefix.isEmpty || $0.label.hasPrefix(prefix) }
        case .source(let prefix):
            let pool = sourceOptions
            return pool.filter { prefix.isEmpty || $0.label.lowercased().contains(prefix) }
        }
    }

    /// Every tag in either vocabulary, for the moments the current narrowing offers none —
    /// a reader typing `#` on an empty result should still be shown the words that exist.
    private func allTagOptions() -> [MarginaliaFacetOption] {
        Set(noteTagVocabulary + passageTagVocabulary)
            .sorted()
            .map {
                MarginaliaFacetOption(
                    kind: .tag($0),
                    label: $0,
                    count: 0,
                    isSelected: facets.tags.contains($0)
                )
            }
    }

    // MARK: - Narrowing controls

    public func toggle(_ option: MarginaliaFacetOption) {
        switch option.kind {
        case .source(let bookId): facets.toggleSource(bookId)
        case .tag(let tag): facets.toggleTag(tag)
        }
    }

    public func toggle(_ lens: MarginaliaLens) {
        if lenses.contains(lens) { lenses.remove(lens) } else { lenses.insert(lens) }
    }

    // MARK: - Renaming a tag

    public func beginRename(_ tag: String) {
        tagToRename = tag
    }

    /// Applies a rename, or asks first when it would merge.
    public func rename(_ tag: String, to newName: String) {
        guard let target = TagName.normalized(newName), target != tag else { return }
        do {
            let existing = try AppDatabase.shared.tagUsage(target)
            if existing > 0 {
                pendingMerge = PendingMerge(from: tag, to: target, existing: existing)
                return
            }
            try AppDatabase.shared.renameTag(tag, to: target)
            followRename(from: tag, to: target)
        } catch {
            present(error, doing: "rename this tag")
        }
    }

    public func confirmPendingMerge() {
        guard let merge = pendingMerge else { return }
        pendingMerge = nil
        do {
            try AppDatabase.shared.renameTag(merge.from, to: merge.to)
            followRename(from: merge.from, to: merge.to)
        } catch {
            present(error, doing: "merge these tags")
        }
    }

    /// A board narrowed by the word being renamed follows it rather than losing it.
    ///
    /// `pruneNarrowing` would otherwise drop the chip on the next load — the old word no longer
    /// exists — and the reader would watch their filter disappear as a side effect of fixing a
    /// typo in its name.
    private func followRename(from oldTag: String, to newTag: String) {
        if facets.tags.remove(oldTag) != nil {
            facets.tags.insert(newTag)
        }
        load()
    }

    public func clearNarrowing() {
        facets = MarginaliaFacets()
        lenses = []
        rawQuery = ""
    }

    /// The line printed over the results when the board is showing a subset: what it was
    /// narrowed by, in the order the reader chose it, so the cause of a short list is on screen
    /// beside the list itself.
    public var narrowingSummary: String? {
        guard isNarrowed else { return nil }
        var parts: [String] = []
        let booksById = Dictionary(uniqueKeysWithValues: books.map { ($0.id, $0) })
        parts.append(contentsOf: facets.bookIds
            .map { booksById[$0]?.title ?? "Untitled" }
            .sorted())
        parts.append(contentsOf: facets.tags.sorted().map { "#\($0)" })
        parts.append(contentsOf: lenses.map(\.title).sorted())
        let query = MarginaliaQuery.parse(rawQuery)
        if !query.text.isEmpty { parts.append("“\(query.text)”") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: - The workbench

    /// The rows the reader has picked out, by id rather than by value: a row can be rewritten
    /// underneath the selection by an edit or a sync, and holding the value would keep the one
    /// that no longer exists.
    ///
    /// A chosen row that the narrowing then hides stays chosen but stops counting: every action
    /// reads `selectedEntries`, which is the intersection with what is on screen, and the
    /// number in the bar comes from the same place. So the count visibly falls when the board
    /// narrows and comes back when it widens, and what the bar says is always what the button
    /// will do — rather than an action quietly reaching rows the reader cannot see.
    @Published public private(set) var selection: Set<String> = []
    @Published public private(set) var isSelecting = false

    /// The chosen rows **in the order the board is showing them**, not in the order they were
    /// tapped. A compilation is a document, and its order has to be one the reader can see and
    /// change — that is what the sort control is for. Tap order is invisible and unrepeatable.
    public var selectedEntries: [MarginaliaEntry] {
        results.filter { selection.contains($0.id) }
    }

    public func beginSelecting(with entry: MarginaliaEntry? = nil) {
        isSelecting = true
        if let entry { selection = [entry.id] }
    }

    public func endSelecting() {
        isSelecting = false
        selection = []
    }

    public func toggleSelection(_ entry: MarginaliaEntry) {
        if selection.contains(entry.id) {
            selection.remove(entry.id)
        } else {
            selection.insert(entry.id)
        }
    }

    public func isSelected(_ entry: MarginaliaEntry) -> Bool {
        selection.contains(entry.id)
    }

    /// Everything currently on the board, which is not the same as everything there is — the
    /// narrowing is part of what the reader chose, and a Select all that reached past it would
    /// gather rows they cannot see.
    public func selectAllVisible() {
        let visible = Set(results.map(\.id))
        selection = selection.isSuperset(of: visible) ? [] : visible
    }

    /// The chosen rows as one note. Returns it so the caller can open what it just made — a
    /// document that appears somewhere in a list is a document you have to go and find.
    public func collect() -> NoteItem? {
        let entries = selectedEntries
        guard !entries.isEmpty else { return nil }

        let compilation = MarginaliaBoard.compile(entries, narrowedBy: facets, books: books)
        let note = Note(
            title: compilation.title,
            body: compilation.body,
            bookId: compilation.bookId
        )
        guard save(note, tags: compilation.tags) else { return nil }
        endSelecting()
        return self.entries.compactMap(\.noteItem).first { $0.id == note.id }
    }

    /// Everything the board is currently showing, gathered into one note.
    ///
    /// The desktop's way in, and it needs no selection model at all: narrowing to `#objection`
    /// and pressing Collect is the same act as ticking twelve boxes, with the filter doing the
    /// choosing. The phone keeps the boxes because a chip is not always the shape of what you
    /// want — three passages out of nine share no word — and both end in the same call.
    public func collectAllVisible() -> NoteItem? {
        selection = Set(results.map(\.id))
        return collect()
    }

    /// Files every chosen row under one more word.
    ///
    /// Additive, never a replacement: the reader is saying "these are also that", and a bulk
    /// operation that silently dropped whatever each row already carried would be the most
    /// expensive undo in the app.
    public func tagSelection(_ rawTag: String) {
        guard let tag = TagName.normalized(rawTag) else { return }
        let entries = selectedEntries
        guard !entries.isEmpty else { return }
        do {
            for entry in entries where !entry.tags.contains(tag) {
                let tags = entry.tags + [tag]
                switch entry {
                case .note(let item):
                    try AppDatabase.shared.setTags(tags, forNoteID: item.id)
                case .passage(let item):
                    try AppDatabase.shared.setTags(tags, forHighlightId: item.id)
                }
            }
            load()
        } catch {
            present(error, doing: "file these")
        }
    }

    public func deleteSelection() {
        let entries = selectedEntries
        guard !entries.isEmpty else { return }
        do {
            for entry in entries {
                switch entry {
                case .note(let item): try AppDatabase.shared.deleteNote(id: item.id)
                case .passage(let item): try AppDatabase.shared.deleteHighlight(id: item.id)
                }
            }
            endSelecting()
            load()
        } catch {
            present(error, doing: "delete these")
        }
    }

    /// The chosen rows as text, for the clipboard. The same bytes `collect` would write, so
    /// what is pasted into another app and what is kept in diple are one document.
    public var selectedText: String {
        MarginaliaBoard.compile(selectedEntries, narrowedBy: facets, books: books).body
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

    /// A passage's comment and tags travel together because the row collects them together:
    /// two calls would put two records in the CloudKit outbox and two rewrites of the same
    /// search document for one edit.
    public func savePassage(
        _ passage: PassageItem,
        colorHex: String,
        comment: String?,
        tags: [String]
    ) {
        do {
            try AppDatabase.shared.updateHighlight(
                id: passage.id,
                colorHex: colorHex,
                comment: comment,
                tags: tags
            )
            load()
        } catch {
            present(error, doing: "save this passage")
        }
    }

    public func delete(_ entry: MarginaliaEntry) {
        do {
            switch entry {
            case .note(let item): try AppDatabase.shared.deleteNote(id: item.id)
            case .passage(let item): try AppDatabase.shared.deleteHighlight(id: item.id)
            }
            load()
        } catch {
            present(error, doing: "delete this")
        }
    }

    public func confirmDelete(_ entry: MarginaliaEntry) {
        entryToDelete = entry
        showDeleteConfirmation = true
    }

    public func deleteConfirmedEntry() {
        guard let entry = entryToDelete else { return }
        delete(entry)
        entryToDelete = nil
        showDeleteConfirmation = false
    }

    private func present(_ error: Error, doing action: String) {
        errorMessage = "Failed to \(action): \(error.localizedDescription)"
        showErrorAlert = true
    }
}
