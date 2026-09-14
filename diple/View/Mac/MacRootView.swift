#if targetEnvironment(macCatalyst)
import SwiftUI
import UniformTypeIdentifiers
// Scoped on purpose. A plain `import ReadiumShared` brings its own `Content` into this file,
// and `ViewModifier.body(content: Content)` then resolves against that instead of the
// associated type — every `ViewModifier` in the file stops conforming, with an error that
// points at the modifier rather than at the import.
import struct ReadiumShared.Locator

/// The desktop shell keeps the phone's reading and persistence stack, but gives it a
/// Mac-shaped information architecture: persistent sources, a working collection and a
/// contextual detail pane. The reader remains a focused full-window destination.
///
/// Three rules hold the desktop together, and every screen below is built to them:
///
/// 1. **One column header.** Whatever the source, the middle column opens with the same block:
///    title, count, the field that narrows it, then the actions. The shelf used to be the only
///    source with a command bar while Highlights and Notes printed their heading inside the
///    scroll view, so switching sources moved the title, the count and the search field to
///    three different places.
/// 2. **Selection is visible where it was made.** Clicking a cover used to change only the far
///    right of the window; the grid gave no sign which of forty covers the inspector was
///    describing.
/// 3. **Every shortcut is in the menu bar.** See `DipleMacCommands`. Shortcuts declared on
///    buttons inside the window are invisible to a reader looking for them, and two of them
///    collided with bindings UIKit had already taken.
public struct MacRootView: View {
    private enum Source: String, CaseIterable, Identifiable {
        case library
        case unread
        case reading
        case articles
        case highlights
        case search

        var id: Self { self }

        var title: String {
            switch self {
            case .library: return "Library"
            case .unread: return "Unread"
            case .reading: return "Reading"
            case .articles: return "Articles"
            case .highlights: return "Highlights"
            case .search: return "Search"
            }
        }

        var icon: String {
            switch self {
            case .library: return "books.vertical"
            case .unread: return "circle"
            case .reading: return "bookmark"
            case .articles: return "doc.text"
            case .highlights: return "quote.opening"
            case .search: return "magnifyingglass"
            }
        }

        /// The menu-bar key that selects this shelf, printed beside its row so the sidebar
        /// teaches the shortcut instead of hiding it one menu away.
        var shortcut: Character? {
            switch self {
            case .library: return "1"
            case .unread: return "2"
            case .reading: return "3"
            case .articles: return "4"
            case .highlights: return "5"
            case .search: return "7"
            }
        }

        /// The sidebar's shelves are each a *pair* of the two filter axes, now that type and
        /// status are no longer alternatives to one another. `nil` means the shelf is not a
        /// library shelf at all.
        var filters: (type: LibraryTypeFilter, status: LibraryStatusFilter)? {
            switch self {
            case .library: return (.all, .any)
            case .unread: return (.all, .unread)
            case .reading: return (.all, .reading)
            case .articles: return (.articles, .any)
            case .highlights, .search: return nil
            }
        }

        static func forCommand(_ command: MacCommand) -> Source? {
            switch command {
            case .goLibrary: return .library
            case .goUnread: return .unread
            case .goReading: return .reading
            case .goArticles: return .articles
            case .goHighlights: return .highlights
            case .goSearch: return .search
            default: return nil
            }
        }
    }

    private enum Detail: Hashable {
        case welcome
        case book(Book)
        case passage(PassageItem)
        case search(GlobalSearchResult)

        /// What the collection has to draw a ring around. Every model behind a detail carries
        /// a `String` id, so one property answers for all four rather than each collection
        /// unwrapping the enum itself.
        ///
        /// A note and a passage answer with the **namespaced** id `MarginaliaEntry` uses, not
        /// the bare row id: the two tables are separate UUID spaces, and on one board a
        /// collision would ring the wrong card.
        var selectionID: String? {
            switch self {
            case .welcome: return nil
            case .book(let book): return book.id
            case .passage(let item): return "passage:\(item.id)"
            case .search(let result): return result.id
            }
        }
    }

    @StateObject private var library = LibraryViewModel()
    /// One model for notes and passages, the same one the phone's board uses. The desktop had
    /// its own pair — `HubViewModel` for a list of books and `NotesViewModel` for a grid of
    /// cards — which is the two-screen arrangement the phone stopped having; keeping it here
    /// would have meant a tag written on a passage staying unreachable on this platform alone.
    @StateObject private var marginalia = MarginaliaViewModel(scope: .saved)
    @StateObject private var search = GlobalSearchViewModel()
    /// The notes workshop's own model — the phone's, so the Inbox, the spaces and every count
    /// mean on the desk exactly what they mean in the hand.
    @StateObject private var notes = NotesWorkshopModel()
    /// The All notes board: the same board the phone embeds as All notes, with its own instance
    /// so its scope never fights Highlights' for one field.
    @StateObject private var notesBoard = MarginaliaViewModel(scope: .written)

    /// Which workshop the window is. See `MacMode`.
    @State private var mode: MacMode = MacRootView.openingMode
    @State private var notesPlace: MacNotesPlace? = .inbox
    /// The page in the editor column. It may be a draft the database has not seen yet — a new
    /// note, or a day's page — which exists from its first word, as on the phone.
    @State private var notesDetail: NoteItem?
    @State private var notesQuery = ""
    @State private var isCreatingSpace = false

    /// The shelf the window opens at. `DipleWindowCapture` can name a different one, so a
    /// screenshot of the board does not depend on a command arriving and two columns agreeing
    /// about it before the shutter opens; it is `nil` in every build that is not being
    /// photographed.
    @State private var source: Source? = MacRootView.openingSource

    private static let openingSource: Source = DipleWindowCapture.requestedSource
        .flatMap(Source.init(rawValue:)) ?? .library

    /// The mode the window opens in: the one it was left in, unless a capture asks for one.
    private static var openingMode: MacMode {
        if DipleWindowCapture.requestedSource == "notes" { return .notes }
        if DipleWindowCapture.requestedSource != nil { return .reading }
        return MacMode(rawValue: UserDefaults.standard.string(forKey: RootTabView.modeKey) ?? "") ?? .reading
    }
    @State private var detail: Detail = .welcome
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var readerRequest: MacReaderRequest?
    @State private var secondReadBook: Book?
    @State private var isImportingFile = false
    @State private var isImportingLink = false
    @State private var tagEditingBook: Book?
    /// The shelf's own filter text. It lives here rather than inside the collection so that
    /// switching to Unread and back does not silently keep a query the header has re-drawn
    /// empty, and so ⌘F can put the caret in a field the shell knows about.
    @State private var libraryQuery = ""
    @State private var librarySort: LibrarySort = .recentlyOpened
    @Environment(\.scenePhase) private var scenePhase
    /// A pending "put the caret in the search field of the column that is open". Plain state
    /// rather than `@FocusState`, because the field itself is two views down inside
    /// `DipleSearchField` and only the view that owns a `TextField` can own its focus.
    @State private var searchFocusRequest: MacSearchTarget?

    /// True while a book is open over the whole window. Navigation commands are ignored then:
    /// moving the shelf underneath the reader changes what closing the book returns to without
    /// the reader ever appearing to move.
    private var isReading: Bool { readerRequest != nil || secondReadBook != nil }

    public init() {}

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 196, ideal: 232, max: 300)
        } content: {
            switch mode {
            case .reading:
                collection
                    .navigationSplitViewColumnWidth(min: 380, ideal: 640)
            case .notes:
                // Bear's proportions: the list is a list, and the page takes the room.
                notesCollection
                    .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 460)
            }
        } detail: {
            switch mode {
            case .reading:
                inspector
                    // Narrower than it was. At the width the window opens at, an inspector allowed
                    // 460 pt left the cover grid two tiles wide under a header that had to fold.
                    .navigationSplitViewColumnWidth(min: 288, ideal: 330, max: 400)
            case .notes:
                notesEditor
                    .navigationSplitViewColumnWidth(min: 420, ideal: 680)
            }
        }
        .controlSize(.large)
        .background(DipleColor.canvas)
        .tint(DipleColor.accent)
        // No SwiftUI `toolbar` here at all. Catalyst renders a toolbar group unreliably beside
        // a search field (see CLAUDE.md), and every action it used to hold now has two homes
        // that are always drawn: the column header, and the menu bar.
        .fileImporter(
            isPresented: $isImportingFile,
            allowedContentTypes: [.epub, .pdf],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    library.importBook(from: url)
                }
            case .failure(let error):
                library.errorMessage = "Import failed: \(error.localizedDescription)"
                library.showErrorAlert = true
            }
        }
        .sheet(isPresented: $isImportingLink) {
            ImportLinkSheetView { _ in
                reloadAll()
            }
            .dipleMacSheet(minWidth: 520, minHeight: 400)
        }
        .fullScreenCover(item: $readerRequest, onDismiss: reloadAll) { request in
            NavigationStack {
                ReaderContainerView(
                    book: request.book,
                    startingLocator: request.startingLocator,
                    onReadingUpdated: reloadAll
                )
            }
        }
        .fullScreenCover(item: $secondReadBook, onDismiss: reloadAll) { book in
            NavigationStack {
                SecondReadView(book: book, onReadingUpdated: reloadAll)
            }
        }
        .alert("Error", isPresented: $library.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(library.errorMessage ?? "An unknown error occurred.")
        }
        .onChange(of: source) { _, newSource in
            guard let newSource else { return }
            // The shelf sets what stands in the column and nothing else. Grouping and order
            // are the reader's, and re-clicking a sidebar row is not a request to undo them.
            if newSource == .highlights { marginalia.load() }
            if newSource == .search { search.reloadContext() }
            detail = .welcome
        }
        .onChange(of: mode) { _, newMode in
            UserDefaults.standard.set(newMode.rawValue, forKey: RootTabView.modeKey)
            if newMode == .notes {
                notes.load()
                notesBoard.load()
            }
        }
        .onChange(of: notesPlace) { _, newPlace in
            notesQuery = ""
            switch newPlace {
            case .today:
                openToday()
            case .allNotes:
                notesBoard.load()
            default:
                // A page standing in the place being left stays open only if it belongs to the
                // one arrived at; otherwise the editor would describe a list no longer shown.
                if let item = notesDetail, !stands(item, in: newPlace) {
                    notesDetail = nil
                }
            }
        }
        .sheet(isPresented: $isCreatingSpace) {
            NoteSpaceEditor { name, symbol in
                if let space = notes.createSpace(named: name, symbol: symbol) {
                    notesPlace = .space(space.id)
                }
            }
            .dipleMacSheet(minWidth: 480, minHeight: 520)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dipleOpenDailyResurfacing)) { _ in
            mode = .reading
            source = .highlights
        }
        .onReceive(NotificationCenter.default.publisher(for: .dipleMacCommand)) { note in
            guard let command = MacCommand(note) else { return }
            perform(command)
        }
        // A second window opened on the same library holds its own view models, and nothing
        // tells one about a book imported in the other. Reloading when a window is brought
        // forward is the cheap version of the sync that would otherwise need a shared store.
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            reloadAll()
        }
        .onAppear {
            if DailyResurfacingService.shared.consumeOpenRequest() {
                mode = .reading
                source = .highlights
            }
        }
        .onAppear(perform: reloadAll)
        .onAppear(perform: DipleMacWindow.configure)
        .onAppear(perform: standWhereTheCaptureAsks)
    }

    // MARK: - Commands

    private func perform(_ command: MacCommand) {
        switch command {
        case .newNote:
            guard !isReading else { return }
            createNote()

        case .importFile:
            guard !isReading else { return }
            isImportingFile = true

        case .importLink:
            guard !isReading else { return }
            isImportingLink = true

        case .refresh:
            reloadAll()

        case .goLibrary, .goUnread, .goReading, .goArticles, .goHighlights, .goSearch:
            guard !isReading, let destination = Source.forCommand(command) else { return }
            mode = .reading
            source = destination
            if destination == .search { searchFocusRequest = .search }

        case .goNotes:
            guard !isReading else { return }
            mode = .notes
            notesPlace = .inbox

        case .goToday:
            guard !isReading else { return }
            mode = .notes
            if notesPlace == .today { openToday() } else { notesPlace = .today }

        case .findInColumn:
            // Narrow what is open, rather than going somewhere. Every shelf has a field of its
            // own, so this never has to fall back to the global index — and must not, because
            // that would throw away the filter the reader was already typing into.
            guard !isReading else { return }
            if mode == .notes {
                searchFocusRequest = .notes
                return
            }
            switch source {
            case .library, .unread, .reading, .articles: searchFocusRequest = .library
            case .highlights: searchFocusRequest = .highlights
            case .search, .none: searchFocusRequest = .search
            }

        case .findInBook:
            // Answered by the reader itself, which is presented above this view.
            break
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        Group {
            switch mode {
            case .reading: readingSidebar
            case .notes:
                MacNotesSidebar(model: notes, place: $notesPlace) {
                    isCreatingSpace = true
                }
            }
        }
        .background(DipleColor.surface)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: DipleSpace.m) {
                HStack(spacing: DipleSpace.s) {
                    DipleMark(size: 22)
                    Text("diple.")
                        .dipleType(.headline, weight: .semibold)
                        .foregroundStyle(DipleColor.textPrimary)
                    Spacer()
                    MacIconButton(
                        systemImage: "gearshape",
                        help: "Settings (⌘,)",
                        accessibilityLabel: "Settings"
                    ) {
                        NotificationCenter.default.post(name: .dipleOpenSettings, object: nil)
                    }
                }
                // The phone's two workshops, at the head of the column they reshape. Above the
                // lists rather than inside one: it is not a place, it is which set of places.
                MacModeSwitch(mode: $mode)
            }
            .padding(.horizontal, DipleSpace.m)
            .padding(.vertical, DipleSpace.l)
            .background(DipleColor.surface)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // The one action a reader arrives wanting to perform, kept where it can be reached
            // from any place: a publication in Reading, a page in Notes.
            VStack(spacing: 0) {
                Rectangle()
                    .fill(DipleColor.separator)
                    .frame(height: DipleStroke.hairline)

                Button {
                    switch mode {
                    case .reading: isImportingFile = true
                    case .notes: createNote()
                    }
                } label: {
                    HStack(spacing: DipleSpace.s) {
                        Image(systemName: mode == .reading ? "plus" : "square.and.pencil")
                            .dipleIcon(12, weight: .semibold)
                        Text(mode == .reading ? "Import" : "New note")
                            .dipleType(.footnote, weight: .medium)
                            .lineLimit(1)
                        Spacer(minLength: DipleSpace.s)
                        Text(mode == .reading ? "⌘O" : "⌘N")
                            .dipleType(.nano)
                            .foregroundStyle(DipleColor.textQuaternary)
                    }
                    .foregroundStyle(DipleColor.textSecondary)
                    .padding(.horizontal, DipleSpace.m)
                    .padding(.vertical, DipleSpace.m)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.macHoverRow)
                .padding(DipleSpace.s)
            }
            .background(DipleColor.surface)
        }
    }

    private var readingSidebar: some View {
        List(selection: $source) {
            Section {
                sourceRow(.library, badge: library.books.count)
                sourceRow(.unread, badge: count(status: .unread))
                sourceRow(.reading, badge: count(status: .reading))
                sourceRow(.articles, badge: count(type: .articles))
            } header: {
                Text("Library")
            }

            Section {
                sourceRow(.highlights, badge: marginalia.totalSaved)
                sourceRow(.search)
            } header: {
                Text("Workspace")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private func sourceRow(_ item: Source, badge: Int? = nil) -> some View {
        HStack(spacing: DipleSpace.s) {
            Image(systemName: item.icon)
                .dipleIcon(13)
                .frame(width: 18)
            Text(item.title)
                .dipleType(.footnote)
            Spacer()
            if let badge, badge > 0 {
                Text("\(badge)")
                    .dipleType(.nano)
                    .foregroundStyle(DipleColor.textQuaternary)
                    .monospacedDigit()
            }
        }
        .foregroundStyle(source == item ? DipleColor.textPrimary : DipleColor.textSecondary)
        .help(item.shortcut.map { "\(item.title) (⌘\($0))" } ?? item.title)
        .tag(item)
    }

    // MARK: - Collection

    @ViewBuilder
    private var collection: some View {
        switch source ?? .library {
        case .library, .unread, .reading, .articles:
            MacLibraryCollection(
                title: source?.title ?? "Library",
                books: library.books,
                tagsByBook: library.tagsByBook,
                type: source?.filters?.type ?? .all,
                status: source?.filters?.status ?? .any,
                continueReading: source == .library ? library.continueReadingBook : nil,
                isImporting: library.isImporting,
                selectedID: detail.selectionID,
                query: $libraryQuery,
                sort: $librarySort,
                searchFocusRequest: $searchFocusRequest,
                onSelect: { detail = .book($0) },
                onOpen: { readerRequest = MacReaderRequest(book: $0) },
                onOpenSecondRead: { secondReadBook = $0 },
                onEdit: { library.bookToEdit = $0 },
                onMarkAsFinished: { library.markAsFinished($0) },
                onMove: { library.move($0, to: $1) },
                onEditTags: { tagEditingBook = $0 },
                onDelete: { library.confirmDelete($0) },
                onImportFile: { isImportingFile = true },
                onImportLink: { isImportingLink = true },
                onImportURL: { library.importBook(from: $0) }
            )
            .sheet(item: $tagEditingBook) { book in
                // Tags set on the phone have to be readable and editable here too, and the
                // desktop sidebar has no tag section yet — so the tile's menu is the only door.
                BookTagsSheetView(
                    book: book,
                    tags: library.tagsByBook[book.id] ?? [],
                    suggestions: library.allTags
                ) { tags in
                    library.setTags(tags, for: book)
                }
                .dipleMacSheet(minWidth: 520, minHeight: 560)
            }
            .sheet(item: $library.bookToEdit) { book in
                EditBookMetadataView(book: book) { title, author, coverData in
                    library.updateMetadata(for: book.id, title: title, author: author, coverData: coverData)
                }
                .dipleMacSheet(minWidth: 520, minHeight: 560)
            }
            .alert("Delete book?", isPresented: $library.showDeleteConfirmation) {
                Button("Delete", role: .destructive) { library.deleteConfirmedBook() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The file and your reading position are removed. Saved passages stay in Highlights.")
            }

        case .highlights:
            // The saved half of the board. Notes are no longer a shelf here: they are the other
            // workshop, one switch away, and a note gathered from passages opens there.
            MacMarginaliaCollection(
                title: "Highlights",
                model: marginalia,
                searchFocusRequest: $searchFocusRequest,
                focusTarget: .highlights,
                selectedID: detail.selectionID,
                onSelect: { entry in
                    switch entry {
                    case .note(let item): openInNotes(item)
                    case .passage(let item): detail = .passage(item)
                    }
                },
                onCreate: createNote,
                onOpenPassage: { openPassage($0) },
                onCollected: { note in openInNotes(note) }
            )

        case .search:
            MacSearchCollection(
                model: search,
                searchFocusRequest: $searchFocusRequest,
                selectedID: detail.selectionID,
                onSelect: { detail = .search($0) }
            )
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var inspector: some View {
        switch detail {
        case .welcome:
            MacInspectorPlaceholder(sourceTitle: source?.title ?? "Library")

        case .book(let book):
            let current = currentBook(matching: book) ?? book
            MacBookInspector(
                book: current,
                tags: library.tagsByBook[current.id] ?? [],
                fragmentCount: marginalia.entries.filter {
                    $0.kind == .saved && $0.bookId == current.id
                }.count,
                onRead: { readerRequest = MacReaderRequest(book: current) },
                onSecondRead: { secondReadBook = current },
                onEdit: { library.bookToEdit = current },
                onEditTags: { tagEditingBook = current }
            )
            .id(current.id)

        case .passage(let item):
            let currentPassage = currentPassage(matching: item) ?? item
            MacPassageInspector(
                passage: currentPassage,
                tagSuggestions: marginalia.passageTagVocabulary,
                onSave: { colorHex, comment, tags in
                    marginalia.savePassage(
                        currentPassage,
                        colorHex: colorHex,
                        comment: comment,
                        tags: tags
                    )
                },
                onOpenInSource: destination(of: currentPassage) == nil
                    ? nil
                    : { openPassage(currentPassage) },
                onExpandIntoNote: { expandIntoNote(currentPassage) },
                onDelete: {
                    marginalia.delete(.passage(currentPassage))
                    detail = .welcome
                }
            )
            .id(currentPassage.id)

        case .search(let result):
            MacSearchInspector(
                result: result,
                book: search.book(for: result),
                note: notes.items.first { $0.id == result.entityID },
                onRead: { book in readerRequest = MacReaderRequest(book: book) },
                onOpenNote: { note in openInNotes(note) }
            )
        }
    }

    // MARK: - Notes workshop

    @ViewBuilder
    private var notesCollection: some View {
        switch notesPlace ?? .inbox {
        case .allNotes:
            MacMarginaliaCollection(
                title: "All notes",
                model: notesBoard,
                searchFocusRequest: $searchFocusRequest,
                focusTarget: .notes,
                selectedID: notesDetail.map { "note:\($0.id)" },
                onSelect: { entry in
                    if case .note(let item) = entry { notesDetail = item }
                },
                onCreate: createNote,
                onOpenPassage: { openPassage($0) },
                onCollected: { note in notesDetail = note }
            )

        case let place:
            MacNotesList(
                title: title(of: place),
                notes: notesInPlace(place),
                selectedID: notesDetail?.id,
                empty: emptyState(of: place),
                query: $notesQuery,
                searchFocusRequest: $searchFocusRequest,
                onSelect: { notesDetail = $0 },
                onCreate: createNote
            )
        }
    }

    @ViewBuilder
    private var notesEditor: some View {
        if let draft = notesDetail {
            let current = notes.current(draft)
            MacNoteInspector(
                item: current ?? draft,
                isDraft: current == nil,
                books: notes.books,
                suggestedTags: notes.tagVocabulary,
                allNotes: notes.items,
                onOpenNote: { notesDetail = $0 },
                onSave: { note, tags in
                    let saved = notes.save(note, tags: tags)
                    if notesPlace == .allNotes { notesBoard.load() }
                    return saved
                },
                onDelete: {
                    if let current { notes.trash([current]) }
                    notesDetail = nil
                    if notesPlace == .allNotes { notesBoard.load() }
                }
            )
            .id(draft.id)
        } else {
            MacNotesPlaceholder()
        }
    }

    private func notesInPlace(_ place: MacNotesPlace?) -> [NoteItem] {
        switch place ?? .inbox {
        case .inbox: return notes.inbox
        case .today, .journal: return notes.journal
        case .space(let id):
            guard let space = notes.space(id: id) else { return notes.inbox }
            return NotesDesk.notes(in: space, from: notes.items)
        case .source(let id): return NotesDesk.notes(about: id, from: notes.items)
        case .allNotes: return NotesDesk.ordered(notes.items)
        }
    }

    /// Whether the page in the editor belongs to the list beside it. A draft is in no list yet —
    /// it stands where its first word will file it — and asking the lists about it would close the
    /// page ⌘N opened from Reading in the same update that moved the window to its place.
    private func stands(_ item: NoteItem, in place: MacNotesPlace?) -> Bool {
        guard notes.current(item) == nil else {
            return notesInPlace(place).contains { $0.id == item.id }
        }
        let note = item.note
        switch place ?? .inbox {
        case .space(let id): return note.spaceId == id
        case .source(let id): return note.bookId == id
        case .today, .journal: return note.dailyDate != nil
        case .inbox, .allNotes: return note.spaceId == nil && note.bookId == nil && note.dailyDate == nil
        }
    }

    private func title(of place: MacNotesPlace) -> String {
        switch place {
        case .inbox: return "Inbox"
        case .today: return "Today"
        case .journal: return "Journal"
        case .allNotes: return "All notes"
        case .space(let id): return notes.space(id: id)?.name ?? "Inbox"
        case .source(let id): return notes.book(id: id)?.title ?? "Notes"
        }
    }

    private func emptyState(of place: MacNotesPlace) -> (symbol: String, title: String, message: String) {
        switch place {
        case .inbox:
            return ("tray", "Inbox is clear", "A new note waits here until it has a place.")
        case .today, .journal:
            return ("sun.max", "No days written yet", "Today’s page stands on the right. It begins with its first word.")
        case .space(let id):
            let space = notes.space(id: id)
            return (space?.symbol ?? "folder", "Nothing here yet", "Press ⌘N to write a note in \(space?.name ?? "this space").")
        case .source:
            return ("book.closed", "No notes about this source", "A note written inside the book stands here.")
        case .allNotes:
            return ("rectangle.stack", "No notes yet", "Press ⌘N to write the first one.")
        }
    }

    /// A new page where the writer stands — the phone's contextual `+`, because the sidebar shows
    /// the desk exactly where that is: in a space it is filed there, on a source's notes it is
    /// written about that source with its name as a tag, on Today or the Journal it is today's
    /// page, and anywhere else it waits in the Inbox. From Reading it is an Inbox note.
    ///
    /// A draft, not a row: it exists from its first word, like every new page on the phone. The
    /// desktop used to save an empty note the moment ⌘N was pressed, and every abandoned one
    /// stayed behind as an Untitled row.
    private func createNote() {
        guard mode == .notes else {
            mode = .notes
            notesPlace = .inbox
            notesDetail = NoteItem(note: Note(body: ""), tags: [], book: nil)
            return
        }
        switch notesPlace ?? .inbox {
        case .space(let id):
            notesDetail = NoteItem(note: Note(body: "", spaceId: id), tags: [], book: nil)
        case .source(let id):
            let book = notes.book(id: id)
            let tags = book.flatMap { TagName.forSource(titled: $0.title) }.map { [$0] } ?? []
            notesDetail = NoteItem(note: Note(body: "", bookId: id), tags: tags, book: book)
        case .today, .journal:
            openToday()
        case .inbox, .allNotes:
            notesDetail = NoteItem(note: Note(body: ""), tags: [], book: nil)
        }
    }

    /// Today's page: the one begun, or a page for today that exists from its first word.
    private func openToday() {
        if let page = notes.todayPage() {
            notesDetail = page
            return
        }
        let key = Note.dailyKey(for: Date())
        notesDetail = NoteItem(
            note: Note(title: Note.dailyTitle(forKey: key), body: "", dailyDate: key),
            tags: [],
            book: nil
        )
    }

    /// The place and note `DipleWindowCapture` names, for a photograph of one screen. Nothing at
    /// all in a run that is not a capture.
    private func standWhereTheCaptureAsks() {
        guard let requested = DipleWindowCapture.requestedPlace else { return }
        notes.load()
        mode = .notes
        switch requested {
        case "today": notesPlace = .today
        case "journal": notesPlace = .journal
        case "allNotes": notesPlace = .allNotes
        default:
            if requested.hasPrefix("space:"),
               let space = notes.spaces.first(where: { $0.name == String(requested.dropFirst(6)) }) {
                notesPlace = .space(space.id)
            } else {
                notesPlace = .inbox
            }
        }
        if let start = DipleWindowCapture.requestedNote {
            notesDetail = notes.items.first { $0.displayTitle.hasPrefix(start) }
        }
    }

    /// A note reached from outside the workshop — search, a gathered set of passages, a passage
    /// grown into a note — opened in it, in the place it lives.
    private func openInNotes(_ item: NoteItem) {
        notes.load()
        let current = notes.current(item) ?? item
        mode = .notes
        if let space = current.note.spaceId, notes.space(id: space) != nil {
            notesPlace = .space(space)
        } else if let book = current.note.bookId {
            notesPlace = .source(book)
        } else if current.note.dailyDate != nil {
            notesPlace = .journal
        } else {
            notesPlace = .inbox
        }
        notesDetail = current
    }

    /// A note grown out of a passage. The seed is `NoteRoute.newFromPassage`'s, not a second
    /// definition of it: the quotation, the source link and the inherited tags have to be the
    /// same on both platforms or the same button would produce two different notes.
    private func expandIntoNote(_ passage: PassageItem) {
        let route = NoteRoute.newFromPassage(passage)
        let note = Note(body: route.initialBody, bookId: route.initialBookId)
        guard notes.save(note, tags: route.initialTags) else { return }
        guard let item = notes.items.first(where: { $0.id == note.id }) else { return }
        openInNotes(item)
    }

    /// Where a passage would open, or `nil` when there is nowhere to go — the book has been
    /// deleted, or the passage was imported for one that was never here. Pure, because the
    /// inspector asks it whether to draw the control at all.
    private func destination(of passage: PassageItem) -> Book? {
        guard passage.highlight.parsedLocator != nil else { return nil }
        return passage.book ?? library.books.first { $0.id == passage.highlight.bookId }
    }

    private func openPassage(_ passage: PassageItem) {
        guard let book = destination(of: passage) else { return }
        readerRequest = MacReaderRequest(book: book, locatorJSON: passage.highlight.locator)
    }

    private func count(type: LibraryTypeFilter = .all, status: LibraryStatusFilter = .any) -> Int {
        library.books.filter { type.includes($0) && status.includes($0) }.count
    }

    private func currentBook(matching book: Book) -> Book? {
        library.books.first { $0.id == book.id }
    }

    private func currentPassage(matching item: PassageItem) -> PassageItem? {
        marginalia.entries.compactMap(\.passageItem).first { $0.id == item.id }
    }

    private func reloadAll() {
        library.loadBooks()
        marginalia.load()
        search.reloadContext()
        notes.load()
        notesBoard.load()
    }
}

// MARK: - Shared desktop chrome

/// A book to open over the whole window, and optionally the passage to open it at.
///
/// `fullScreenCover(item:)` keys on one identifiable value, so the locator has to travel beside
/// the book rather than in state of its own — two pieces of state would let the cover come up
/// before the locator had been set and open the book at its saved place instead.
struct MacReaderRequest: Identifiable {
    let book: Book
    var locatorJSON: String? = nil

    /// Distinct per request rather than the book's id: opening the same book at two different
    /// passages in one session must be two presentations, not a no-op.
    let id = UUID()

    var startingLocator: Locator? {
        locatorJSON.flatMap { Locator.from(jsonString: $0) }
    }
}

/// Which column's field ⌘F should put the caret in. One enum for the whole window, because
/// only one column is on screen at a time and `FocusState` wants a single value type.
enum MacSearchTarget: Hashable {
    case library
    case highlights
    case notes
    case search
}

/// The block every collection opens with.
///
/// Title, count, an optional line of context, the field that narrows the collection, then the
/// actions — always in that order, always the same height, always pinned above the scroll. The
/// four sources used to disagree about all five of those things.
struct MacColumnHeader<Actions: View>: View {
    let title: String
    var count: Int? = nil
    var context: String? = nil
    var query: Binding<String>? = nil
    var prompt: String = ""
    var searchIdentifier: String = "mac.column.search"
    /// Cleared as soon as it has been honoured, so the same request cannot re-steal the caret
    /// the next time this header is rebuilt.
    var focusRequest: Binding<MacSearchTarget?>? = nil
    var focusTarget: MacSearchTarget? = nil
    @ViewBuilder var actions: () -> Actions

    @FocusState private var isFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            // The middle column is the one that gives up width first — the sidebar and the
            // inspector both have minimums — so this row has to survive being narrow. It used
            // to be one `HStack`, and at the width the window opens at SwiftUI compressed the
            // labels rather than the gaps: the screen title broke across two lines as "Libr /
            // ary" and the import button read "Im / po / rt". Every control is fixed to its own
            // ideal width now, and when the row no longer fits the actions drop to a line of
            // their own instead of the words breaking.
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .firstTextBaseline, spacing: DipleSpace.s) {
                    titleBlock
                    Spacer(minLength: DipleSpace.m)
                    actions()
                }

                VStack(alignment: .leading, spacing: DipleSpace.m) {
                    titleBlock
                    HStack(spacing: DipleSpace.s) {
                        Spacer(minLength: 0)
                        actions()
                    }
                }
            }

            if let context {
                Text(context)
                    .dipleType(.micro)
                    .foregroundStyle(DipleColor.textQuaternary)
                    .monospacedDigit()
            }

            if let query {
                searchField(query)
            }
        }
        .padding(.horizontal, DipleSpace.xxl)
        .padding(.top, DipleSpace.xl)
        .padding(.bottom, DipleSpace.l)
        .background(DipleColor.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DipleColor.separator)
                .frame(height: DipleStroke.hairline)
        }
    }

    private var titleBlock: some View {
        HStack(alignment: .firstTextBaseline, spacing: DipleSpace.s) {
            Text(title)
                // A bare screen title standing alone at the top of its column, sharing the
                // line with nothing but its own count. That is what `hero` is for.
                .dipleType(.hero)
                .foregroundStyle(DipleColor.textPrimary)
                .lineLimit(1)
                .fixedSize()

            if let count {
                Text("\(count)")
                    .dipleType(.micro)
                    .foregroundStyle(DipleColor.textQuaternary)
                    .monospacedDigit()
                    .fixedSize()
            }
        }
    }

    private func searchField(_ query: Binding<String>) -> some View {
        DipleSearchField(
            text: query,
            prompt: prompt,
            identifier: searchIdentifier,
            focus: $isFieldFocused
        )
        .onAppear(perform: honourPendingFocus)
        .onChange(of: focusRequest?.wrappedValue) { _, _ in honourPendingFocus() }
    }

    private func honourPendingFocus() {
        guard let focusRequest, let focusTarget else { return }
        guard focusRequest.wrappedValue == focusTarget else { return }
        isFieldFocused = true
        focusRequest.wrappedValue = nil
    }
}

/// The primary action of a column header: the one accent-filled control on the screen.
struct MacPrimaryButton: View {
    let title: String
    var systemImage: String = "plus"
    var shortcutHint: String? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .dipleType(.footnote, weight: .semibold)
                .foregroundStyle(DipleColor.textOnAccent)
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, DipleSpace.m)
                .padding(.vertical, DipleSpace.s)
                .background(
                    DipleColor.accent.opacity(isHovering ? 0.86 : 1),
                    in: RoundedRectangle(cornerRadius: DipleRadius.s, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DipleMotion.snappy) { isHovering = hovering }
        }
        .help(shortcutHint.map { "\(title) (\($0))" } ?? title)
    }
}

/// A quiet header action — a verb in text, not a filled control.
private struct MacSecondaryButton: View {
    let title: String
    var systemImage: String? = nil
    var shortcutHint: String? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Group {
                if let systemImage {
                    Label(title, systemImage: systemImage)
                } else {
                    Text(title)
                }
            }
            .dipleType(.footnote)
            .foregroundStyle(isHovering ? DipleColor.textPrimary : DipleColor.textSecondary)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, DipleSpace.s)
            .padding(.vertical, DipleSpace.s)
            .background(
                isHovering ? DipleColor.surfaceOverlay : Color.clear,
                in: RoundedRectangle(cornerRadius: DipleRadius.s, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DipleMotion.snappy) { isHovering = hovering }
        }
        .help(shortcutHint.map { "\(title) (\($0))" } ?? title)
    }
}

/// A glyph on its own, with the hit area and the hover wash a pointer expects.
private struct MacIconButton: View {
    let systemImage: String
    let help: String
    var accessibilityLabel: String? = nil
    let action: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .dipleIcon(12)
                .foregroundStyle(isHovering ? DipleColor.textPrimary : DipleColor.textTertiary)
                .frame(width: 26, height: 26)
                .background(
                    isHovering ? DipleColor.surfaceOverlay : Color.clear,
                    in: RoundedRectangle(cornerRadius: DipleRadius.xs, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DipleMotion.snappy) { isHovering = hovering }
        }
        .help(help)
        .accessibilityLabel(accessibilityLabel ?? help)
    }
}

/// What a desktop row looks like when the pointer is over it and when it is the selected one.
///
/// The pointer is the desktop's substitute for a finger that can be seen before it lands, and
/// an interface that does not answer it feels like a picture of an app. Selection is the accent
/// ring the design system already spends on a chosen state — never a flood of colour.
struct MacRowSurface: ViewModifier {
    let isSelected: Bool
    let isHovering: Bool
    var radius: CGFloat = DipleRadius.m
    /// A row that is already a catalogue entry — a note with its own rule underneath — draws no
    /// edge of its own at rest: a box around a ruled entry prints two edges for one object.
    var isBordered = true

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        isSelected ? DipleColor.accent : (isBordered ? DipleColor.hairline : Color.clear),
                        lineWidth: isSelected ? DipleStroke.selection : DipleStroke.hairline
                    )
            }
    }

    private var fill: Color {
        if isSelected { return DipleColor.accentSoft }
        if isHovering { return DipleColor.surfaceRaised }
        return isBordered ? DipleColor.surface : Color.clear
    }
}

extension View {
    func macRow(isSelected: Bool, isHovering: Bool, radius: CGFloat = DipleRadius.m, isBordered: Bool = true) -> some View {
        modifier(MacRowSurface(isSelected: isSelected, isHovering: isHovering, radius: radius, isBordered: isBordered))
    }
}

/// Selection and hover for something that already draws its own card — a note. Only the ring
/// and a lift; a second fill underneath a `craftSurface` would print two edges around one
/// object.
private struct MacSelectableCard<Content: View>: View {
    let isSelected: Bool
    var radius: CGFloat = DipleRadius.m
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            content()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(
                    isSelected ? DipleColor.accent : Color.clear,
                    lineWidth: DipleStroke.selection
                )
        }
        .shadow(
            color: .black.opacity(isHovering ? 0.22 : 0),
            radius: isHovering ? 12 : 0,
            y: isHovering ? 5 : 0
        )
        .onHover { hovering in
            withAnimation(DipleMotion.snappy) { isHovering = hovering }
        }
    }
}

/// A row that is a button: it tracks its own hover so the caller never has to hold that state.
struct MacSelectableRow<Content: View>: View {
    let isSelected: Bool
    var radius: CGFloat = DipleRadius.m
    var isBordered = true
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            content()
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .macRow(isSelected: isSelected, isHovering: isHovering, radius: radius, isBordered: isBordered)
        .onHover { hovering in
            withAnimation(DipleMotion.snappy) { isHovering = hovering }
        }
    }
}

/// A plain hover wash for controls that are not rows in a collection — the sidebar footer.
struct MacHoverRowButtonStyle: ButtonStyle {
    @State private var isHovering = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(
                isHovering || configuration.isPressed
                    ? DipleColor.surfaceOverlay
                    : Color.clear,
                in: RoundedRectangle(cornerRadius: DipleRadius.s, style: .continuous)
            )
            .onHover { hovering in
                withAnimation(DipleMotion.snappy) { isHovering = hovering }
            }
    }
}

extension ButtonStyle where Self == MacHoverRowButtonStyle {
    static var macHoverRow: MacHoverRowButtonStyle { MacHoverRowButtonStyle() }
}

/// Accepts publications dropped on the window from the Finder.
///
/// A desktop app that can only be given a file through a picker is a phone app in a window;
/// dragging a book onto a library is the gesture the platform has taught for thirty years.
/// Anything that is not an EPUB or a PDF is refused at the drop rather than accepted and then
/// failed, so the cursor says no before the file is let go.
private struct MacPublicationDrop: ViewModifier {
    let onImport: (URL) -> Void

    @State private var isTargeted = false

    private static let acceptedExtensions: Set<String> = ["epub", "pdf"]

    func body(content: Content) -> some View {
        content
            .overlay {
                if isTargeted {
                    RoundedRectangle(cornerRadius: DipleRadius.l, style: .continuous)
                        .strokeBorder(DipleColor.accent, style: StrokeStyle(lineWidth: 2, dash: [6, 5]))
                        .background(
                            DipleColor.accentSoft,
                            in: RoundedRectangle(cornerRadius: DipleRadius.l, style: .continuous)
                        )
                        .overlay {
                            VStack(spacing: DipleSpace.s) {
                                Image(systemName: "arrow.down.doc")
                                    .dipleIcon(26, weight: .light)
                                Text("Drop to import")
                                    .dipleType(.callout, weight: .semibold)
                            }
                            .foregroundStyle(DipleColor.accentInk)
                        }
                        .padding(DipleSpace.m)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(DipleMotion.snappy, value: isTargeted)
            .dropDestination(for: URL.self) { urls, _ in
                let accepted = urls.filter {
                    Self.acceptedExtensions.contains($0.pathExtension.lowercased())
                }
                accepted.forEach(onImport)
                return !accepted.isEmpty
            } isTargeted: { targeted in
                isTargeted = targeted
            }
    }
}

private extension View {
    func macPublicationDrop(onImport: @escaping (URL) -> Void) -> some View {
        modifier(MacPublicationDrop(onImport: onImport))
    }
}

// MARK: - Library

private struct MacLibraryCollection: View {
    let title: String
    let books: [Book]
    let tagsByBook: [String: [String]]
    let type: LibraryTypeFilter
    let status: LibraryStatusFilter
    let continueReading: Book?
    let isImporting: Bool
    let selectedID: String?
    @Binding var query: String
    @Binding var sort: LibrarySort
    @Binding var searchFocusRequest: MacSearchTarget?
    let onSelect: (Book) -> Void
    let onOpen: (Book) -> Void
    let onOpenSecondRead: (Book) -> Void
    let onEdit: (Book) -> Void
    let onMarkAsFinished: (Book) -> Void
    let onMove: (Book, BookLocation) -> Void
    let onEditTags: (Book) -> Void
    let onDelete: (Book) -> Void
    let onImportFile: () -> Void
    let onImportLink: () -> Void
    let onImportURL: (URL) -> Void

    private let columns = [
        GridItem(
            .adaptive(minimum: 148, maximum: 188),
            spacing: DipleSpace.xl,
            alignment: .top
        )
    ]

    private var visibleBooks: [Book] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return books
            .filter { book in
                guard type.includes(book), status.includes(book) else { return false }
                guard !needle.isEmpty else { return true }
                let tags = tagsByBook[book.id] ?? []
                // Tags are searched here for the same reason they are on the phone: a shelf
                // filed by hand is unreachable if the only things the field matches are the
                // three fields the file happened to carry.
                return ([book.title, book.author, book.sourceHost].compactMap { $0 } + tags)
                    .contains { $0.localizedStandardContains(needle) }
            }
            .sorted(by: sorter)
    }

    var body: some View {
        VStack(spacing: 0) {
            MacColumnHeader(
                title: title,
                count: visibleBooks.count,
                query: $query,
                prompt: "Title, author, source or tag",
                searchIdentifier: "mac.library.search",
                focusRequest: $searchFocusRequest,
                focusTarget: .library
            ) {
                Menu {
                    Picker("Sort", selection: $sort) {
                        ForEach(LibrarySort.allCases) { option in
                            Text(option.rawValue).tag(option)
                        }
                    }
                } label: {
                    Label(sort.compactTitle, systemImage: "arrow.up.arrow.down")
                        .dipleType(.footnote)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Sort the shelf")

                MacSecondaryButton(title: "Save link", systemImage: "link", shortcutHint: "⇧⌘L", action: onImportLink)
                MacPrimaryButton(title: "Import", shortcutHint: "⌘O", action: onImportFile)
            }

            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                if visibleBooks.isEmpty && !isImporting {
                    MacEmptyCollection(
                        icon: query.isEmpty ? "books.vertical" : "magnifyingglass",
                        title: query.isEmpty ? "Nothing here yet" : "No results",
                        message: query.isEmpty
                            ? "Import an EPUB or PDF, or drag one onto this window."
                            : "Try a different title, author, source or tag.",
                        actionTitle: query.isEmpty ? "Import file" : nil,
                        actionIcon: "plus",
                        action: query.isEmpty ? onImportFile : nil
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: DipleSpace.xxxl) {
                            if let continueReading, type == .all, status == .any, query.isEmpty {
                                MacContinueReadingCard(book: continueReading) {
                                    onOpen(continueReading)
                                }
                            }

                            LazyVGrid(columns: columns, alignment: .leading, spacing: DipleSpace.xxl) {
                                ForEach(visibleBooks) { book in
                                    MacBookTile(
                                        book: book,
                                        isSelected: selectedID == book.id
                                    ) {
                                        onSelect(book)
                                    } onOpen: {
                                        onOpen(book)
                                    }
                                    .contextMenu {
                                        Button("Open") { onOpen(book) }
                                        if LibraryStatusFilter.finished.includes(book) {
                                            Button("Second Read") { onOpenSecondRead(book) }
                                        }
                                        if book.progress < 0.995 {
                                            Button("Mark as Finished") { onMarkAsFinished(book) }
                                        }
                                        Button("Tags…") { onEditTags(book) }
                                        Button("Edit metadata") { onEdit(book) }
                                        Divider()
                                        // The desktop sidebar does not split by location
                                        // yet, so this is the only place on the Mac where
                                        // the queue can be sorted at all — and a source
                                        // filed on the phone has to be reachable here.
                                        ForEach(
                                            BookLocation.allCases.filter { $0 != book.location },
                                            id: \.self
                                        ) { destination in
                                            Button("Move to \(destination.title)") {
                                                onMove(book, destination)
                                            }
                                        }
                                        Divider()
                                        Button("Delete", role: .destructive) { onDelete(book) }
                                    }
                                }
                            }
                        }
                        .padding(DipleSpace.xxl)
                        .padding(.bottom, DipleSpace.xxxl)
                    }
                }

                if isImporting {
                    VStack(spacing: DipleSpace.m) {
                        ProgressView()
                            .tint(DipleColor.accent)
                        Text("Importing publication…")
                            .dipleType(.callout, weight: .medium)
                            .foregroundStyle(DipleColor.textSecondary)
                    }
                    .padding(DipleSpace.xxl)
                    .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.l)
                }
            }
            .macPublicationDrop(onImport: onImportURL)
        }
    }

    private func sorter(_ lhs: Book, _ rhs: Book) -> Bool {
        switch sort {
        case .recentlyOpened:
            let left = lhs.lastOpenedAt ?? .distantPast
            let right = rhs.lastOpenedAt ?? .distantPast
            return left == right ? lhs.addedAt > rhs.addedAt : left > right
        case .recentlyAdded:
            return lhs.addedAt > rhs.addedAt
        case .title:
            return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
        case .author:
            return (lhs.author ?? "").localizedCaseInsensitiveCompare(rhs.author ?? "") == .orderedAscending
        case .source:
            return (lhs.sourceHost ?? "").localizedCaseInsensitiveCompare(rhs.sourceHost ?? "") == .orderedAscending
        }
    }
}

private struct MacBookTile: View {
    let book: Book
    let isSelected: Bool
    let onSelect: () -> Void
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: DipleSpace.s) {
                ZStack(alignment: .bottom) {
                    BookCoverView(
                        coverPath: book.coverPath,
                        title: book.title,
                        author: book.author
                    )
                    .shadow(color: .black.opacity(isHovering ? 0.34 : 0.24), radius: isHovering ? 16 : 12, y: isHovering ? 9 : 7)

                    if book.progress > 0.001 {
                        GeometryReader { proxy in
                            VStack {
                                Spacer()
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(.black.opacity(0.5))
                                    Rectangle()
                                        .fill(DipleColor.accent)
                                        .frame(width: proxy.size.width * min(max(book.progress, 0), 1))
                                }
                                .frame(height: DipleStroke.progressLine)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: DipleRadius.s))
                    }

                    // Appears only under the pointer, and only on a cover that can be opened
                    // by double-click — the affordance the accessibility hint used to be the
                    // only trace of.
                    if isHovering {
                        Button(action: onOpen) {
                            Label("Read", systemImage: "book")
                                .dipleType(.nano, weight: .semibold)
                                .foregroundStyle(DipleColor.textOnAccent)
                                .padding(.horizontal, DipleSpace.s)
                                .padding(.vertical, DipleSpace.xs)
                                .background(DipleColor.accent, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .padding(.bottom, DipleSpace.s)
                        .transition(.opacity)
                    }
                }

                Text(book.title)
                    .dipleType(.footnote, weight: .semibold)
                    .foregroundStyle(DipleColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(book.subtitle)
                    .dipleType(.caption)
                    .foregroundStyle(DipleColor.textQuaternary)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(DipleSpace.s)
            .background(
                selectionFill,
                in: RoundedRectangle(cornerRadius: DipleRadius.m, style: .continuous)
            )
            .overlay {
                RoundedRectangle(cornerRadius: DipleRadius.m, style: .continuous)
                    .strokeBorder(
                        isSelected ? DipleColor.accent : Color.clear,
                        lineWidth: DipleStroke.selection
                    )
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DipleMotion.snappy) { isHovering = hovering }
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded(onOpen))
        .accessibilityHint("Double-click to read")
    }

    private var selectionFill: Color {
        if isSelected { return DipleColor.accentSoft }
        return isHovering ? DipleColor.surface : Color.clear
    }
}

/// The reading measure, drawn rather than asked for. See the note at its call sites.
private struct MacProgressLine: View {
    let progress: Double

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(DipleColor.surfaceOverlay)
                Capsule()
                    .fill(DipleColor.accent)
                    .frame(width: proxy.size.width * min(max(progress, 0), 1))
            }
        }
        .frame(height: DipleStroke.progressLine)
    }
}

private struct MacContinueReadingCard: View {
    let book: Book
    let onOpen: () -> Void

    @State private var isHovering = false

    var body: some View {
        Button(action: onOpen) {
            HStack(spacing: DipleSpace.l) {
                BookCoverView(
                    coverPath: book.coverPath,
                    title: book.title,
                    author: book.author,
                    isCompact: true
                )
                .frame(width: 58, height: 87)
                .shadow(color: .black.opacity(0.28), radius: 10, y: 5)

                VStack(alignment: .leading, spacing: DipleSpace.s) {
                    Text("CONTINUE READING")
                        .dipleType(.nano)
                        .foregroundStyle(DipleColor.accentInk)
                    Text(book.title)
                        .dipleType(.headline)
                        .foregroundStyle(DipleColor.textPrimary)
                        .lineLimit(2)
                    Text(book.subtitle)
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)

                    // Not `ProgressView`. Catalyst draws the linear style in the system's own
                    // grey and ignores `tint`, so the one line on this card that says how far
                    // the reader has come was the only element on the screen carrying no colour
                    // from the app at all — while the same measure is already drawn in the
                    // accent across the foot of every cover in the grid below it.
                    MacProgressLine(progress: book.progress)
                }

                Spacer()

                Text(book.progress.formatted(.percent.precision(.fractionLength(0))))
                    .dipleType(.micro)
                    .foregroundStyle(DipleColor.textTertiary)
                    .monospacedDigit()

                Image(systemName: "arrow.right")
                    .dipleIcon(14)
                    .foregroundStyle(DipleColor.accentInk)
                    .offset(x: isHovering ? 3 : 0)
            }
            .padding(DipleSpace.l)
            .craftSurface(
                isHovering ? DipleColor.surfaceOverlay : DipleColor.surfaceRaised,
                radius: DipleRadius.l
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DipleMotion.snappy) { isHovering = hovering }
        }
    }
}

// MARK: - The board

/// Notes and saved passages in one column, under the controls they now share.
///
/// It stands behind both the Highlights and the Notes shelf, showing one kind at a time: the
/// shelf says which, for as long as it is the shelf. Everything the phone's board does is here
/// because it is the same view model and the same `MarginaliaBoard` transform — what is
/// desktop-shaped is only the chrome around it.
struct MacMarginaliaCollection: View {
    let title: String
    @ObservedObject var model: MarginaliaViewModel
    @Binding var searchFocusRequest: MacSearchTarget?
    let focusTarget: MacSearchTarget
    let selectedID: String?
    let onSelect: (MarginaliaEntry) -> Void
    let onCreate: () -> Void
    let onOpenPassage: (PassageItem) -> Void
    let onCollected: (NoteItem) -> Void

    @State private var renameDraft = ""
    @State private var isFilterSheetPresented = false

    /// How many names the wrapped row prints before the rest go to the sheet. The desktop has
    /// the width to wrap rather than scroll, and that is exactly why it needs a cap: an
    /// unbounded wrap does not run off the edge, it pushes the catalogue off the bottom — with
    /// a real library the controls stood eight lines tall before the first card.
    private let visibleFacets = 8

    /// Two columns at the width the window opens at, one when the inspector takes the room.
    /// A quote card set in Literata below 260 pt is a column of broken lines.
    private let columns = [
        GridItem(.adaptive(minimum: 260), spacing: DipleSpace.m, alignment: .top)
    ]

    /// What this shelf holds, in its own kind only. The header printed both counts on both
    /// shelves while the scope bar could walk between them; over a column of passages, "4
    /// notes · 12 passages" names a collection the shelf does not show.
    private var contextLine: String? {
        let total = model.totalInScope
        guard total > 0 else { return nil }
        return model.scope == .written
            ? (total == 1 ? "1 note" : "\(total) notes")
            : (total == 1 ? "1 passage" : "\(total) passages")
    }

    var body: some View {
        VStack(spacing: 0) {
            MacColumnHeader(
                title: title,
                count: model.count(for: model.scope),
                context: contextLine,
                query: model.totalInScope == 0 ? nil : $model.rawQuery,
                prompt: "Search everything · #tag · @source",
                searchIdentifier: "mac.marginalia.search",
                focusRequest: $searchFocusRequest,
                focusTarget: focusTarget
            ) {
                arrangeMenu

                // No selection model on the desktop, and none needed: narrowing the board to a
                // word and pressing this is the same act as ticking every box the phone would
                // have shown, with the filter doing the choosing. It appears only when there is
                // more than one row, because collecting one row is copying it.
                if model.results.count > 1 {
                    MacSecondaryButton(
                        title: "Collect \(model.results.count)",
                        systemImage: "square.and.pencil"
                    ) {
                        if let note = model.collectAllVisible() { onCollected(note) }
                    }
                }

                MacPrimaryButton(title: "New note", shortcutHint: "⌘N", action: onCreate)
            }

            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                if model.totalInScope == 0 {
                    // The shelf's own emptiness, in the shelf's own words. Asked of the whole
                    // catalogue it answered for the other shelf: a library of marked passages
                    // and no notes drew a filter row over an empty Notes column, and a library
                    // of notes and no passages did the same in Highlights.
                    if model.scope == .saved {
                        MacEmptyCollection(
                            icon: "quote.opening",
                            title: "Nothing marked yet",
                            message: "Mark a passage while reading and it collects here, by source, by tag and by the colour you marked it with.",
                        )
                    } else {
                        MacEmptyCollection(
                            icon: "square.and.pencil",
                            title: "Start with a thought",
                            message: "Everything you write collects here, by source and by tag. Passages you keep while reading are in Highlights.",
                            actionTitle: "New note",
                            actionIcon: "plus",
                            action: onCreate
                        )
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: DipleSpace.l) {
                            controls

                            if model.results.isEmpty {
                                noResults
                            } else {
                                ForEach(model.groups) { group in
                                    if model.grouping != .none {
                                        groupHeader(group)
                                    }
                                    LazyVGrid(columns: columns, alignment: .leading, spacing: DipleSpace.m) {
                                        ForEach(group.entries) { entry in
                                            card(for: entry)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(DipleSpace.xxl)
                        .padding(.bottom, DipleSpace.xxxl)
                    }
                }
            }
        }
        .sheet(isPresented: $isFilterSheetPresented) {
            MarginaliaFilterSheet(model: model)
                .dipleMacSheet(minWidth: 520, minHeight: 620)
        }
        .alert(
            model.entryToDelete?.kind == .saved ? "Delete passage?" : "Delete note?",
            isPresented: $model.showDeleteConfirmation
        ) {
            Button("Delete", role: .destructive) { model.deleteConfirmedEntry() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                model.entryToDelete?.kind == .saved
                    ? "This passage and its comment will be removed."
                    : "It stays in Recently deleted for thirty days, where it can be restored from diple on iPhone."
            )
        }
        .alert(
            "Rename tag",
            isPresented: Binding(
                get: { model.tagToRename != nil },
                set: { if !$0 { model.tagToRename = nil } }
            ),
            presenting: model.tagToRename
        ) { tag in
            TextField("Tag", text: $renameDraft)
            Button("Rename") { model.rename(tag, to: renameDraft) }
            Button("Cancel", role: .cancel) { renameDraft = "" }
        } message: { tag in
            Text("#\(tag) will be renamed on every note and passage that carries it.")
        }
        .alert(
            "Merge tags?",
            isPresented: Binding(
                get: { model.pendingMerge != nil },
                set: { if !$0 { model.pendingMerge = nil } }
            ),
            presenting: model.pendingMerge
        ) { _ in
            Button("Merge", role: .destructive) { model.confirmPendingMerge() }
            Button("Cancel", role: .cancel) {}
        } message: { merge in
            Text("#\(merge.to) is already in use on \(merge.existing) \(merge.existing == 1 ? "item" : "items"). Merging cannot be undone.")
        }
    }

    private var arrangeMenu: some View {
        Menu {
            Picker("Sort", selection: $model.sort) {
                ForEach(MarginaliaSort.allCases) { option in
                    Label(option.title, systemImage: option.systemImage).tag(option)
                }
            }
            Picker("Group", selection: $model.grouping) {
                ForEach(MarginaliaGrouping.allCases) { option in
                    Label(option.title, systemImage: option.systemImage).tag(option)
                }
            }
        } label: {
            Label(model.sort.title, systemImage: "arrow.up.arrow.down")
                .dipleType(.footnote)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help("Sort and group the board")
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            if let token = MarginaliaQuery.activeToken(in: model.rawQuery) {
                tokenSuggestions(for: token)
            }

            chipRow
        }
    }

    @ViewBuilder
    private func tokenSuggestions(for token: MarginaliaQuery.Token) -> some View {
        let suggestions = Array(model.suggestions(for: token).prefix(8))
        if !suggestions.isEmpty {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DipleSpace.s) {
                    ForEach(suggestions) { option in
                        MarginaliaChip(
                            label: option.label,
                            kind: chipKind(for: option),
                            count: option.count,
                            isSelected: false
                        ) {
                            model.rawQuery = MarginaliaQuery.removingActiveToken(from: model.rawQuery)
                            model.toggle(option)
                        }
                    }
                }
            }
        }
    }

    /// The desktop wraps the chips instead of scrolling them sideways. It has the width, and a
    /// horizontal scroller inside a resizable column is a row whose end nobody finds.
    ///
    /// **One `FlowLayout` per run, stacked.** The chips arrive grouped — marks, then shelves,
    /// then words — and the phone rules between the runs because it has only one line to spend.
    /// Here the wrap can do it for free: a run of its own is a stronger seam than any hairline,
    /// and the desktop was the surface where a single ranking by size looked worst, because all
    /// of it is on screen at once with nothing to scroll past.
    ///
    /// The cap is per run for the same reason it is on the phone: `visibleFacets` over the
    /// whole row means a library with nine books wraps nine shelves and prints no words.
    private var chipRow: some View {
        VStack(alignment: .leading, spacing: DipleSpace.s) {
            if !model.lensOptions.isEmpty {
                FlowLayout(spacing: DipleSpace.s) {
                    ForEach(model.lensOptions) { option in
                        MarginaliaChip(
                            label: option.lens.title,
                            kind: .lens(option.lens.systemImage),
                            count: option.count,
                            isSelected: option.isSelected
                        ) {
                            model.toggle(option.lens)
                        }
                    }
                }
            }

            let runs = MarginaliaBoard.runs(of: model.facetOptions, limit: visibleFacets)

            ForEach(runs) { run in
                FlowLayout(spacing: DipleSpace.s) {
                    ForEach(run.options) { option in
                        MarginaliaChip(
                            label: option.label,
                            kind: chipKind(for: option),
                            count: option.count,
                            isSelected: option.isSelected
                        ) {
                            model.toggle(option)
                        }
                        .contextMenu { facetMenu(option) }
                    }

                    // The door to the rest sits at the end of the last run, where the row
                    // actually ends — usually the words, which is the run a library outgrows
                    // first.
                    if run.id == runs.last?.id {
                        allFiltersChip
                    }
                }
            }
        }
    }

    /// The count is what the wrap did **not** print, the same as on the phone: a row that is a
    /// fraction of the vocabulary has to say how big the fraction is, and that is the one fact
    /// it cannot show by showing chips.
    @ViewBuilder
    private var allFiltersChip: some View {
        let hidden = hiddenFacetCount
        if hidden > 0 || model.facets.count > 0 {
            MarginaliaChip(
                label: "All filters",
                kind: .lens("line.3.horizontal.decrease"),
                count: hidden,
                isSelected: false
            ) {
                isFilterSheetPresented = true
            }
        }
    }

    private var hiddenFacetCount: Int {
        let shown = MarginaliaBoard.runs(of: model.facetOptions, limit: visibleFacets)
            .reduce(0) { $0 + $1.options.count }
        return max(0, model.facetOptions.count - shown)
    }

    @ViewBuilder
    private func facetMenu(_ option: MarginaliaFacetOption) -> some View {
        Button {
            model.lenses = []
            model.facets = MarginaliaFacets()
            model.toggle(option)
        } label: {
            Label("Show only this", systemImage: "line.3.horizontal.decrease")
        }

        if case .tag(let tag) = option.kind {
            Button {
                renameDraft = tag
                model.beginRename(tag)
            } label: {
                Label("Rename tag…", systemImage: "pencil")
            }
        }
    }

    private func chipKind(for option: MarginaliaFacetOption) -> MarginaliaChip.Kind {
        switch option.kind {
        case .source: return .source
        case .tag: return .tag
        case .color(let hex): return .color(hex)
        }
    }

    private func groupHeader(_ group: MarginaliaGroup) -> some View {
        HStack(spacing: DipleSpace.s) {
            if let book = group.book {
                BookCoverView(
                    coverPath: book.coverPath,
                    title: book.title,
                    author: book.author,
                    isCompact: true
                )
                .frame(width: 20, height: 30)
            }

            Text(group.title.localizedUppercase)
                .dipleType(.nano)
                .foregroundStyle(DipleColor.accentInk)
                .lineLimit(1)

            Spacer(minLength: DipleSpace.s)

            Text("\(group.entries.count)")
                .dipleType(.nano)
                .monospacedDigit()
                .foregroundStyle(DipleColor.textQuaternary)
        }
        .padding(.top, DipleSpace.s)
    }

    @ViewBuilder
    private func card(for entry: MarginaliaEntry) -> some View {
        MacSelectableCard(isSelected: selectedID == entry.id) {
            onSelect(entry)
        } content: {
            switch entry {
            case .note(let item): NoteCardView(item: item)
            case .passage(let item): PassageRowView(passage: item, style: .card)
            }
        }
        .contextMenu { entryMenu(entry) }
    }

    @ViewBuilder
    private func entryMenu(_ entry: MarginaliaEntry) -> some View {
        Button("Open") { onSelect(entry) }

        if case .passage(let item) = entry {
            Button("Open in the book") { onOpenPassage(item) }
        }

        Button("Copy text") {
            switch entry {
            case .note(let item): UIPasteboard.general.string = item.note.body
            case .passage(let item): UIPasteboard.general.string = item.highlight.text
            }
        }

        Divider()

        Button("Delete", role: .destructive) { model.confirmDelete(entry) }
    }

    private var noResults: some View {
        MacEmptyCollection(
            icon: model.rawQuery.isEmpty ? "line.3.horizontal.decrease.circle" : "text.magnifyingglass",
            title: model.rawQuery.isEmpty ? "Nothing in this view" : "No matches",
            message: model.narrowingSummary ?? "Choose another filter.",
            actionTitle: model.isNarrowed ? "Clear the filters" : nil,
            actionIcon: model.isNarrowed ? "xmark" : nil,
            action: model.isNarrowed ? { model.clearNarrowing() } : nil
        )
        .frame(minHeight: 280)
    }
}

// MARK: - Search

private struct MacSearchCollection: View {
    @ObservedObject var model: GlobalSearchViewModel
    @Binding var searchFocusRequest: MacSearchTarget?
    let selectedID: String?
    let onSelect: (GlobalSearchResult) -> Void

    var body: some View {
        VStack(spacing: 0) {
            MacColumnHeader(
                title: "Search",
                count: model.results.isEmpty ? nil : model.results.count,
                query: $model.query,
                prompt: "Notes, highlights and library",
                searchIdentifier: "mac.search.search",
                focusRequest: $searchFocusRequest,
                focusTarget: .search
            ) {
                EmptyView()
            }

            ZStack {
                DipleColor.canvas.ignoresSafeArea()
                if model.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    MacEmptyCollection(
                        icon: "magnifyingglass",
                        title: "Search your reading",
                        message: "Find books, article text, saved passages and your own notes."
                    )
                } else if model.results.isEmpty {
                    MacEmptyCollection(
                        icon: "text.magnifyingglass",
                        title: "No matches",
                        message: "Try fewer words or a different phrase."
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: DipleSpace.xxl) {
                            ForEach(GlobalSearchKind.allCases, id: \.self) { kind in
                                let results = model.results.filter { $0.kind == kind }
                                if !results.isEmpty {
                                    VStack(alignment: .leading, spacing: DipleSpace.s) {
                                        HStack {
                                            Text(kind.title.uppercased())
                                                .dipleType(.nano)
                                                .foregroundStyle(DipleColor.textTertiary)
                                            Spacer()
                                            Text("\(results.count)")
                                                .dipleType(.nano)
                                                .foregroundStyle(DipleColor.textQuaternary)
                                        }
                                        ForEach(results) { result in
                                            MacSelectableRow(isSelected: selectedID == result.id) {
                                                onSelect(result)
                                            } content: {
                                                MacSearchResultRow(result: result)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .padding(DipleSpace.xxl)
                        .padding(.bottom, DipleSpace.xxxl)
                    }
                }
            }
        }
        .onAppear { searchFocusRequest = .search }
        .onChange(of: model.query) { _, _ in model.search() }
    }
}

private struct MacSearchResultRow: View {
    let result: GlobalSearchResult

    var body: some View {
        HStack(alignment: .top, spacing: DipleSpace.m) {
            Image(systemName: result.kind.systemImage)
                .dipleIcon(13)
                .foregroundStyle(DipleColor.accentInk)
                .frame(width: 28, height: 28)
                .background(DipleColor.accentSoft, in: RoundedRectangle(cornerRadius: DipleRadius.s))

            VStack(alignment: .leading, spacing: DipleSpace.xs) {
                Text(result.title)
                    .dipleType(.footnote, weight: .semibold)
                    .foregroundStyle(DipleColor.textPrimary)
                    .lineLimit(1)

                if !result.snippet.isEmpty {
                    Text(result.snippet)
                        .dipleType(.readingCaption)
                        .foregroundStyle(DipleColor.textTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                } else if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textQuaternary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DipleSpace.s)
            Image(systemName: "chevron.right")
                .dipleIcon(10, weight: .semibold)
                .foregroundStyle(DipleColor.textQuaternary)
        }
        .padding(DipleSpace.m)
    }
}

// MARK: - Inspectors

private struct MacBookInspector: View {
    let book: Book
    let tags: [String]
    let fragmentCount: Int
    let onRead: () -> Void
    let onSecondRead: () -> Void
    let onEdit: () -> Void
    let onEditTags: () -> Void

    @State private var isReadHovering = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DipleSpace.xxl) {
                BookCoverView(
                    coverPath: book.coverPath,
                    title: book.title,
                    author: book.author
                )
                .frame(maxWidth: 190)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.32), radius: 18, y: 10)

                VStack(alignment: .leading, spacing: DipleSpace.s) {
                    Text(book.title)
                        .dipleType(.readingTitle)
                        .foregroundStyle(DipleColor.textPrimary)
                        .textSelection(.enabled)
                    Text(book.subtitle)
                        .dipleType(.callout)
                        .foregroundStyle(DipleColor.textTertiary)
                        .textSelection(.enabled)
                }

                Button(action: onRead) {
                    HStack {
                        Image(systemName: book.progress > 0.001 ? "book.pages" : "book")
                        Text(book.progress > 0.001 ? "Continue Reading" : "Start Reading")
                        Spacer()
                        Image(systemName: "arrow.right")
                            .offset(x: isReadHovering ? 3 : 0)
                    }
                    .dipleType(.footnote, weight: .semibold)
                    .foregroundStyle(DipleColor.textOnAccent)
                    .padding(.horizontal, DipleSpace.l)
                    .padding(.vertical, DipleSpace.m)
                    .background(
                        DipleColor.accent.opacity(isReadHovering ? 0.86 : 1),
                        in: RoundedRectangle(cornerRadius: DipleRadius.s)
                    )
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    withAnimation(DipleMotion.snappy) { isReadHovering = hovering }
                }
                // **⌘-Return, not bare Return.** Unmodified, this bound the Return key for the
                // whole window: every search field and the note editor's title lost it to the
                // reader the moment a book was selected, because a `keyboardShortcut` is
                // registered on the responder chain and not on the button it is written under.
                .keyboardShortcut(.return, modifiers: .command)
                .help(book.progress > 0.001 ? "Continue reading (⌘↩)" : "Start reading (⌘↩)")

                if LibraryStatusFilter.finished.includes(book) {
                    Button(action: onSecondRead) {
                        SecondReadEntryView(fragmentCount: fragmentCount)
                    }
                    .buttonStyle(.plain)
                }

                VStack(alignment: .leading, spacing: DipleSpace.m) {
                    MacMetadataRow(label: "Progress") {
                        HStack(spacing: DipleSpace.m) {
                            // `MacProgressLine`, for the reason given at its definition:
                            // Catalyst paints the linear `ProgressView` in the system grey and
                            // ignores `tint`, so this row reported the reader's own progress in
                            // a colour the app does not use anywhere else.
                            MacProgressLine(progress: book.progress)
                            Text(book.progress.formatted(.percent.precision(.fractionLength(0))))
                                .monospacedDigit()
                                .fixedSize()
                        }
                    }
                    MacMetadataRow(label: "Added") {
                        Text(book.addedAt.formatted(date: .abbreviated, time: .omitted))
                    }
                    if let lastOpenedAt = book.lastOpenedAt {
                        MacMetadataRow(label: "Last read") {
                            Text(lastOpenedAt.formatted(date: .abbreviated, time: .shortened))
                        }
                    }
                    if let source = book.sourceHost {
                        MacMetadataRow(label: "Source") { Text(source) }
                    }
                    MacMetadataRow(label: "Tags") {
                        if tags.isEmpty {
                            Text("None")
                                .foregroundStyle(DipleColor.textQuaternary)
                        } else {
                            FlowLayout(spacing: DipleSpace.xs) {
                                ForEach(tags, id: \.self) { tag in
                                    TagChipView(label: tag, kind: .text)
                                }
                            }
                        }
                    }
                }

                HStack(spacing: DipleSpace.l) {
                    Button("Edit metadata", action: onEdit)
                        .dipleType(.footnote)
                        .foregroundStyle(DipleColor.textSecondary)
                    Button("Tags…", action: onEditTags)
                        .dipleType(.footnote)
                        .foregroundStyle(DipleColor.textSecondary)
                }
            }
            .padding(DipleSpace.xxl)
        }
        .background(DipleColor.surface)
    }

}

/// One saved passage, as the desktop's detail pane.
///
/// The phone raises `HighlightEditorView` as a sheet; a Catalyst window has a third column
/// standing empty, and putting the same fields in a sheet over it would be the phone's shape
/// worn on a desk. What is *not* re-decided here is any of the rules: the colours, the
/// optionality of a comment, the tag vocabulary and the order the fields stand in are the
/// sheet's, so the same passage edited on either platform is the same object.
private struct MacPassageInspector: View {
    let passage: PassageItem
    let tagSuggestions: [String]
    let onSave: (String, String?, [String]) -> Void
    /// `nil` when there is nowhere to go — the book is gone, or the passage was imported.
    let onOpenInSource: (() -> Void)?
    let onExpandIntoNote: () -> Void
    let onDelete: () -> Void

    @State private var colorHex: String
    @State private var comment: String
    @State private var tags: [String]
    @State private var lastSavedComment: String
    @State private var lastSavedTags: [String]
    @State private var lastSavedColorHex: String
    @State private var saveTask: Task<Void, Never>?
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var didCopy = false

    init(
        passage: PassageItem,
        tagSuggestions: [String],
        onSave: @escaping (String, String?, [String]) -> Void,
        onOpenInSource: (() -> Void)?,
        onExpandIntoNote: @escaping () -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.passage = passage
        self.tagSuggestions = tagSuggestions
        self.onSave = onSave
        self.onOpenInSource = onOpenInSource
        self.onExpandIntoNote = onExpandIntoNote
        self.onDelete = onDelete

        let comment = passage.comment ?? ""
        _colorHex = State(initialValue: passage.highlight.colorHex)
        _comment = State(initialValue: comment)
        _tags = State(initialValue: passage.tags)
        _lastSavedComment = State(initialValue: comment)
        _lastSavedTags = State(initialValue: passage.tags)
        _lastSavedColorHex = State(initialValue: passage.highlight.colorHex)
    }

    private var hasUnsavedChanges: Bool {
        comment != lastSavedComment || tags != lastSavedTags || colorHex != lastSavedColorHex
    }

    private var sourceTitle: String? {
        passage.book?.title ?? passage.highlight.bookTitle
    }

    var body: some View {
        ZStack {
            DipleColor.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DipleSpace.xxl) {
                    quote
                    source
                    colors
                    commentField
                    tagField
                    actions
                }
                .padding(DipleSpace.xxl)
                .padding(.bottom, DipleSpace.xxxl)
            }
        }
        .onChange(of: comment) { _, _ in scheduleSave() }
        .onChange(of: tags) { _, _ in scheduleSave() }
        .onChange(of: colorHex) { _, _ in scheduleSave() }
        .onDisappear {
            saveTask?.cancel()
            if !isDeleting { saveNow() }
        }
        .alert("Delete passage?", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                isDeleting = true
                saveTask?.cancel()
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This passage and its comment will be removed.")
        }
    }

    private var quote: some View {
        HStack(alignment: .top, spacing: DipleSpace.m) {
            Capsule()
                .fill(Color(hex: colorHex))
                .frame(width: 4)
                .animation(DipleMotion.snappy, value: colorHex)

            VStack(alignment: .leading, spacing: DipleSpace.s) {
                Text("SAVED PASSAGE")
                    .dipleType(.micro, weight: .semibold)
                    .foregroundStyle(DipleColor.textTertiary)

                Text(passage.highlight.text)
                    .dipleType(.editorialQuote)
                    .readingLineSpacing(for: passage.highlight.text)
                    .foregroundStyle(DipleColor.textPrimary)
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DipleSpace.l)
        .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.l)
    }

    @ViewBuilder
    private var source: some View {
        if let sourceTitle {
            HStack(spacing: DipleSpace.s) {
                Image(systemName: "book.closed")
                    .dipleIcon(11)
                    .foregroundStyle(DipleColor.accentInk)

                VStack(alignment: .leading, spacing: 2) {
                    Text(sourceTitle)
                        .dipleType(.caption, weight: .medium)
                        .foregroundStyle(DipleColor.textSecondary)
                        .lineLimit(2)
                    Text(passage.highlight.createdAt.formatted(date: .abbreviated, time: .omitted))
                        .dipleType(.nano)
                        .foregroundStyle(DipleColor.textQuaternary)
                }

                Spacer(minLength: DipleSpace.s)

                if let onOpenInSource {
                    MacSecondaryButton(
                        title: "Open in the book",
                        systemImage: "book",
                        action: onOpenInSource
                    )
                }
            }
        }
    }

    private var colors: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            Text("COLOR")
                .dipleType(.micro, weight: .semibold)
                .foregroundStyle(DipleColor.textTertiary)

            HStack(spacing: DipleSpace.m) {
                ForEach(DipleColor.Highlight.selectable, id: \.hex) { item in
                    Button {
                        withAnimation(DipleMotion.snappy) { colorHex = item.hex }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(DipleColor.Highlight.color(forHex: item.hex))
                                .frame(width: 26, height: 26)
                            if colorHex == item.hex {
                                Circle()
                                    .stroke(DipleColor.textPrimary, lineWidth: 2)
                                    .frame(width: 34, height: 34)
                            }
                        }
                        .frame(width: 38, height: 38)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(item.name)
                }
                Spacer(minLength: 0)
            }
        }
    }

    private var commentField: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("COMMENT")
                    .dipleType(.micro, weight: .semibold)
                    .foregroundStyle(DipleColor.textTertiary)
                Spacer()
                Text("OPTIONAL")
                    .dipleType(.nano)
                    .foregroundStyle(DipleColor.textQuaternary)
            }

            TextField("Add context or your own thought…", text: $comment, axis: .vertical)
                .textFieldStyle(.plain)
                .lineLimit(4...12)
                .dipleType(.body)
                .foregroundStyle(DipleColor.textPrimary)
                .padding(DipleSpace.m)
                .frame(minHeight: 96, alignment: .topLeading)
                .background(DipleColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DipleRadius.m))
                .overlay {
                    RoundedRectangle(cornerRadius: DipleRadius.m)
                        .stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline)
                }
        }
    }

    private var tagField: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            Text("TAGS")
                .dipleType(.micro, weight: .semibold)
                .foregroundStyle(DipleColor.textTertiary)

            TagField(tags: $tags, suggestions: tagSuggestions, emptyPrompt: "File this passage")
        }
    }

    private var actions: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            Rectangle()
                .fill(DipleColor.separator)
                .frame(height: DipleStroke.hairline)

            HStack(spacing: DipleSpace.s) {
                MacSecondaryButton(
                    title: "Expand into a note",
                    systemImage: "square.and.pencil"
                ) {
                    saveNow()
                    onExpandIntoNote()
                }

                MacSecondaryButton(
                    title: didCopy ? "Copied" : "Copy",
                    systemImage: didCopy ? "checkmark" : "doc.on.doc"
                ) {
                    UIPasteboard.general.string = passage.highlight.text
                    withAnimation(DipleMotion.snappy) { didCopy = true }
                    Task { @MainActor in
                        try? await Task.sleep(for: .milliseconds(1_200))
                        withAnimation(DipleMotion.snappy) { didCopy = false }
                    }
                }

                Spacer(minLength: 0)

                MacIconButton(systemImage: "trash", help: "Delete passage") {
                    isShowingDeleteConfirmation = true
                }
            }
        }
    }

    /// The same rhythm as the desktop's note inspector: a debounce while typing, and a
    /// guaranteed write on the way out. A detail pane has no Save button because there is
    /// nothing to dismiss — the edit is finished when the reader looks somewhere else.
    private func scheduleSave() {
        saveTask?.cancel()
        guard !isDeleting, hasUnsavedChanges else { return }
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            saveNow()
        }
    }

    private func saveNow() {
        guard hasUnsavedChanges else { return }
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        onSave(colorHex, trimmed.isEmpty ? nil : trimmed, tags)
        lastSavedComment = comment
        lastSavedTags = tags
        lastSavedColorHex = colorHex
    }
}

struct MacNoteInspector: View {
    let item: NoteItem
    /// A page the database has not seen yet — a new note, or a day's page. It is written from its
    /// first word, never on opening, so a page opened and left leaves nothing behind.
    let isDraft: Bool
    let books: [Book]
    let suggestedTags: [String]
    /// Wiki links resolve against these, exactly as they do on the phone.
    let allNotes: [NoteItem]
    let onOpenNote: (NoteItem) -> Void
    let onSave: (Note, [String]) -> Bool
    let onDelete: () -> Void
    /// What `[[` completes to, settled once: the menu is asked on every keystroke inside a link.
    private let linkTitles: [String]

    @State private var title: String
    @State private var bodyText: String
    @State private var tags: [String]
    @State private var tagDraft = ""
    @State private var selectedBookId: String?
    @State private var lastSavedTitle: String
    @State private var lastSavedBody: String
    @State private var lastSavedTags: [String]
    @State private var lastSavedBookId: String?
    @State private var saveState: SaveState = .saved
    @State private var saveTask: Task<Void, Never>?
    @State private var isBookPickerPresented = false
    @State private var isShowingDeleteConfirmation = false
    @State private var isDeleting = false
    @State private var isClosing = false
    @State private var selection = NoteSelectionBox()
    @State private var isBodyFocused = false
    @State private var isPreviewing = false
    @State private var slashContext: NoteSlashContext?
    @State private var completionContext: NoteCompletionContext?
    @State private var isFormulaComposerPresented = false
    @State private var formulaSeed = ""
    @State private var formulaMode: NoteFormulaMode = .inline
    @State private var formulaSessionID = UUID()
    /// Set by the first save of a draft. The view is not rebuilt when the draft becomes a row —
    /// its identity is the note's id either way — so it has to learn that for itself.
    @State private var hasBeenWritten = false
    @FocusState private var isTitleFocused: Bool

    private enum SaveState {
        case saved
        case saving
        case failed

        var label: String {
            switch self {
            case .saved: return "Saved"
            case .saving: return "Saving…"
            case .failed: return "Not saved"
            }
        }

        var color: SwiftUI.Color {
            switch self {
            case .saved: return DipleColor.textQuaternary
            case .saving: return DipleColor.accent
            case .failed: return DipleColor.destructive
            }
        }
    }

    init(
        item: NoteItem,
        isDraft: Bool = false,
        books: [Book],
        suggestedTags: [String],
        allNotes: [NoteItem],
        onOpenNote: @escaping (NoteItem) -> Void,
        onSave: @escaping (Note, [String]) -> Bool,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.isDraft = isDraft
        self.books = books
        self.suggestedTags = suggestedTags
        self.allNotes = allNotes
        self.onOpenNote = onOpenNote
        self.onSave = onSave
        self.onDelete = onDelete
        self.linkTitles = allNotes.filter { $0.id != item.id }.map(\.displayTitle)

        let initialTitle = item.note.title ?? ""
        _title = State(initialValue: initialTitle)
        _bodyText = State(initialValue: item.note.body)
        _tags = State(initialValue: item.tags)
        _selectedBookId = State(initialValue: item.note.bookId)
        _lastSavedTitle = State(initialValue: initialTitle)
        _lastSavedBody = State(initialValue: item.note.body)
        _lastSavedTags = State(initialValue: item.tags)
        _lastSavedBookId = State(initialValue: item.note.bookId)
    }

    private var selectedBook: Book? {
        books.first { $0.id == selectedBookId }
    }

    private var unusedSuggestions: [String] {
        suggestedTags.filter { !tags.contains($0) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: DipleSpace.s) {
                Circle()
                    .fill(saveState.color)
                    .frame(width: 6, height: 6)
                    // Matches the phone: the dot swells while a write is pending so saving is
                    // caught at the edge of vision rather than read.
                    .scaleEffect(saveState == .saving ? 1.5 : 1)
                Text(saveState.label)
                    .dipleType(.micro)
                    .foregroundStyle(saveState.color)
                    .contentTransition(.opacity)

                Spacer()

                Menu {
                    ShareLink(item: exportMarkdown) {
                        Label("Share Markdown", systemImage: "square.and.arrow.up")
                    }
                    Button {
                        UIPasteboard.general.string = exportMarkdown
                    } label: {
                        Label("Copy Markdown", systemImage: "doc.on.doc")
                    }
                    Divider()
                    Button(role: .destructive) {
                        isShowingDeleteConfirmation = true
                    } label: {
                        Label("Delete note", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .dipleIcon(15)
                        .foregroundStyle(DipleColor.textSecondary)
                }
                .menuStyle(.borderlessButton)

                Button {
                    withAnimation(DipleMotion.snappy) { isPreviewing.toggle() }
                } label: {
                    Image(systemName: isPreviewing ? "square.and.pencil" : "eye")
                        .dipleIcon(14)
                        .foregroundStyle(isPreviewing ? DipleColor.accentInk : DipleColor.textSecondary)
                }
                .buttonStyle(.plain)
                .help(isPreviewing ? "Edit note" : "Preview rendered note")
            }
            .padding(.horizontal, DipleSpace.xxl)
            .padding(.vertical, DipleSpace.m)

            Rectangle()
                .fill(DipleColor.separator)
                .frame(height: DipleStroke.hairline)

            VStack(alignment: .leading, spacing: DipleSpace.l) {
                TextField("Untitled", text: $title, axis: .vertical)
                    .textFieldStyle(.plain)
                    .dipleType(.noteTitle)
                    .foregroundStyle(DipleColor.textPrimary)
                    .focused($isTitleFocused)

                HStack(spacing: DipleSpace.s) {
                    Text(item.note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    Text("·")
                    Text(wordCountLabel)
                }
                .dipleType(.micro)
                .foregroundStyle(DipleColor.textQuaternary)
                .monospacedDigit()

                propertiesEditor

                Rectangle()
                    .fill(DipleColor.separator)
                    .frame(height: DipleStroke.hairline)

                if isPreviewing {
                    ScrollView {
                        NoteMarkdownView(markdown: bodyText) { task in
                            guard let updated = NoteMarkdown.togglingTask(
                                atLine: task.lineIndex,
                                in: bodyText
                            ) else { return }
                            bodyText = updated
                            saveImmediately()
                        }
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.bottom, DipleSpace.xxxl)
                    }
                    // Without this the private wiki-link scheme escapes to the system, which
                    // has nothing registered for it — the link would look live and do nothing,
                    // or worse, hand the URL to another app. Resolution matches the phone's.
                    .environment(\.openURL, OpenURLAction { url in
                        guard let title = NoteMarkdown.wikiLinkTitle(from: url) else { return .systemAction }
                        guard let target = note(titled: title) else { return .handled }
                        onOpenNote(target)
                        return .handled
                    })
                } else {
                    VStack(alignment: .leading, spacing: DipleSpace.s) {
                        macFormattingBar
                        NoteEditorView(
                            text: $bodyText,
                            selection: selection,
                            isFocused: $isBodyFocused,
                            onSlashChanged: { slashContext = $0 },
                            onOpenLink: { title in
                                guard let target = note(titled: title) else { return }
                                onOpenNote(target)
                            },
                            onTaskToggled: { saveImmediately() },
                            onCompletionChanged: { completionContext = $0 }
                        )
                        .noteCompletionMenu(
                            context: completionContext,
                            linkTitles: linkTitles,
                            tagVocabulary: tags + unusedSuggestions,
                            onPickLink: { pick, context in
                                NoteEditing.complete(context, with: pick.title, in: &bodyText, selection: selection)
                                completionContext = nil
                                isBodyFocused = true
                            },
                            onPickTag: { pick, context in
                                NoteEditing.complete(context, with: pick.tag, in: &bodyText, selection: selection)
                                if !tags.contains(pick.tag) {
                                    tags.append(pick.tag)
                                }
                                completionContext = nil
                                isBodyFocused = true
                            }
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .noteSlashMenu(context: slashContext) { command in
                            guard let context = slashContext else { return }
                            NoteEditing.applySlash(command, replacing: context.range, in: &bodyText, selection: selection)
                            slashContext = nil
                            isBodyFocused = true
                        }
                    }
                }
            }
            .padding(DipleSpace.xxl)
            // A page of prose stops being readable long before it stops being wide — the measure
            // the phone's page holds. Now that the note is the widest column on the desk, the
            // margins take the rest.
            .frame(maxWidth: 760, maxHeight: .infinity, alignment: .topLeading)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .background(DipleColor.surface)
        .task {
            // A new page opens ready to write: on its title, or — a day's page, whose title is
            // already the date — in its text.
            guard isDraft, !hasBeenWritten else { return }
            try? await Task.sleep(for: .milliseconds(150))
            if item.note.dailyDate != nil {
                isBodyFocused = true
            } else {
                isTitleFocused = true
            }
        }
        .onChange(of: title) { _, _ in scheduleSave() }
        .onChange(of: bodyText) { _, _ in scheduleSave() }
        .onChange(of: tags) { _, _ in scheduleSave() }
        .onChange(of: selectedBookId) { _, _ in scheduleSave() }
        .onDisappear {
            isClosing = true
            saveTask?.cancel()
            if !isDeleting { saveImmediately(includingPendingTag: true) }
        }
        .sheet(isPresented: $isBookPickerPresented) {
            BookTagPickerView(books: books, selectedBookId: selectedBookId) { bookId in
                selectedBookId = bookId
            }
            .dipleMacSheet(minWidth: 520, minHeight: 560)
        }
        .sheet(isPresented: $isFormulaComposerPresented) {
            NoteFormulaComposer(initialLatex: formulaSeed, initialMode: formulaMode) { mode, latex in
                NoteEditing.insertFormula(latex, mode: mode, in: &bodyText, selection: selection)
                isBodyFocused = true
            }
            .id(formulaSessionID)
            .dipleMacSheet(minWidth: 620, minHeight: 680)
        }
        .alert("Delete note?", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                isDeleting = true
                saveTask?.cancel()
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("It stays in Recently deleted for thirty days, where it can be restored from diple on iPhone.")
        }
    }

    private var propertiesEditor: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            HStack(spacing: DipleSpace.s) {
                Label("Tags", systemImage: "number")
                    .dipleType(.micro, weight: .semibold)
                    .foregroundStyle(DipleColor.textTertiary)
                    .frame(width: 70, alignment: .leading)

                TextField("Add tag", text: $tagDraft)
                    .textFieldStyle(.plain)
                    .dipleType(.callout)
                    .foregroundStyle(DipleColor.textPrimary)
                    .onSubmit(commitTagDraft)
                    .padding(.horizontal, DipleSpace.m)
                    .padding(.vertical, DipleSpace.s)
                    .background(
                        DipleColor.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: DipleRadius.s)
                    )

                Button(action: commitTagDraft) {
                    Image(systemName: "plus")
                        .dipleIcon(13, weight: .semibold)
                        .foregroundStyle(DipleColor.textOnAccent)
                        .frame(width: 30, height: 30)
                        .background(DipleColor.accent, in: Circle())
                }
                .buttonStyle(.plain)
                .disabled(NoteTag.normalized(tagDraft) == nil)
                .opacity(NoteTag.normalized(tagDraft) == nil ? 0.4 : 1)
                .help("Add tag")
            }

            if !tags.isEmpty {
                FlowLayout(spacing: DipleSpace.s) {
                    ForEach(tags, id: \.self) { tag in
                        Button {
                            tags.removeAll { $0 == tag }
                        } label: {
                            HStack(spacing: DipleSpace.xs) {
                                Text("#\(tag)")
                                    .dipleType(.caption, weight: .medium)
                                Image(systemName: "xmark")
                                    .dipleIcon(9, weight: .bold)
                            }
                            .foregroundStyle(DipleColor.textSecondary)
                            .diplePadding(.chip)
                            .background(DipleColor.surfaceOverlay, in: Capsule())
                        }
                        .buttonStyle(.plain)
                        .help("Remove #\(tag)")
                    }
                }
            }

            if !unusedSuggestions.isEmpty {
                Menu {
                    ForEach(unusedSuggestions, id: \.self) { tag in
                        Button("#\(tag)") {
                            tags.append(tag)
                        }
                    }
                } label: {
                    Label("Add existing tag", systemImage: "tag")
                        .dipleType(.micro)
                        .foregroundStyle(DipleColor.textTertiary)
                }
                .menuStyle(.borderlessButton)
            }

            HStack(spacing: DipleSpace.s) {
                Label("Book", systemImage: "book.closed")
                    .dipleType(.micro, weight: .semibold)
                    .foregroundStyle(DipleColor.textTertiary)
                    .frame(width: 70, alignment: .leading)

                Button {
                    isBookPickerPresented = true
                } label: {
                    HStack(spacing: DipleSpace.s) {
                        Text(selectedBook?.title ?? "Link a library item")
                            .dipleType(.callout)
                            .foregroundStyle(
                                selectedBook == nil
                                    ? DipleColor.textTertiary
                                    : DipleColor.textPrimary
                            )
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "chevron.right")
                            .dipleIcon(10, weight: .semibold)
                            .foregroundStyle(DipleColor.textQuaternary)
                    }
                    .padding(.horizontal, DipleSpace.m)
                    .padding(.vertical, DipleSpace.s)
                    .background(
                        DipleColor.surfaceRaised,
                        in: RoundedRectangle(cornerRadius: DipleRadius.s)
                    )
                }
                .buttonStyle(.plain)

                if selectedBookId != nil {
                    Button {
                        selectedBookId = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .dipleIcon(14)
                            .foregroundStyle(DipleColor.textQuaternary)
                    }
                    .buttonStyle(.plain)
                    .help("Remove book link")
                }
            }
        }
        .padding(DipleSpace.m)
        .background(DipleColor.surface, in: RoundedRectangle(cornerRadius: DipleRadius.m))
        .overlay {
            RoundedRectangle(cornerRadius: DipleRadius.m)
                .stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline)
        }
    }

    private var wordCountLabel: String {
        // Over the prose, not the notation — see `NoteDetailView.wordCount`.
        let count = NoteMarkdown.plainText(bodyText)
            .split { $0.isWhitespace || $0.isNewline }
            .count
        return count == 1 ? "1 word" : "\(count) words"
    }

    private var exportMarkdown: String {
        var sections: [String] = []
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append("# \(title.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        if !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            sections.append(bodyText.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !tags.isEmpty { sections.append(tags.map { "#\($0)" }.joined(separator: " ")) }
        return sections.joined(separator: "\n\n")
    }

    private var macFormattingBar: some View {
        HStack(spacing: DipleSpace.xs) {
            macFormatButton(label: "H1", help: "Heading") {
                applyMarkdown(prefix: "# ", placeholder: "Heading", line: true)
            }
            macFormatButton(icon: "bold", help: "Bold") {
                applyMarkdown(prefix: "**", suffix: "**", placeholder: "bold text")
            }
            .keyboardShortcut("b", modifiers: .command)
            macFormatButton(icon: "italic", help: "Italic") {
                applyMarkdown(prefix: "*", suffix: "*", placeholder: "italic text")
            }
            .keyboardShortcut("i", modifiers: .command)
            macFormatButton(label: "ƒx", help: "Equation") {
                presentFormulaComposer()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            macFormatButton(icon: "checklist", help: "Task") {
                applyMarkdown(prefix: "- [ ] ", placeholder: "Task", line: true)
            }
            macFormatButton(icon: "list.bullet", help: "List") {
                applyMarkdown(prefix: "- ", placeholder: "List item", line: true)
            }
            macFormatButton(icon: "text.quote", help: "Quote") {
                applyMarkdown(prefix: "> ", placeholder: "Quote", line: true)
            }
            macFormatButton(icon: "link", help: "Link") {
                applyMarkdown(prefix: "[", suffix: "](https://)", placeholder: "link title")
            }
            Spacer()
        }
        .padding(DipleSpace.xs)
        .background(DipleColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DipleRadius.s))
        .overlay {
            RoundedRectangle(cornerRadius: DipleRadius.s)
                .stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline)
        }
    }

    private func macFormatButton(
        label: String? = nil,
        icon: String? = nil,
        help: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Group {
                if let icon {
                    Image(systemName: icon).dipleIcon(13, weight: .semibold)
                } else {
                    Text(label ?? "").dipleType(.footnote, weight: .semibold)
                }
            }
            .foregroundStyle(DipleColor.textSecondary)
            .frame(width: 30, height: 28)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    private func applyMarkdown(
        prefix: String,
        suffix: String = "",
        placeholder: String,
        line: Bool = false
    ) {
        NoteEditing.apply(
            to: &bodyText,
            selection: selection,
            prefix: prefix,
            suffix: suffix,
            placeholder: placeholder,
            isLineCommand: line
        )
        isBodyFocused = true
    }

    /// Resolved the same way `NoteKnowledge` builds the Connections list, so following a link
    /// and appearing under "Linked notes" cannot disagree about what a title matches.
    private func note(titled title: String) -> NoteItem? {
        let target = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return allNotes.first { candidate in
            candidate.id != item.id
                && candidate.displayTitle
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == target
        }
    }

    private func presentFormulaComposer() {
        let source = bodyText as NSString
        let location = min(selection.range.location, source.length)
        let length = min(selection.range.length, source.length - location)
        let selected = source.substring(with: NSRange(location: location, length: length))
        let formula = NoteMathParser.formulaSelection(from: selected)
        formulaSeed = formula.latex
        formulaMode = formula.mode
        formulaSessionID = UUID()
        isBodyFocused = false
        isFormulaComposerPresented = true
    }

    private var hasUnsavedChanges: Bool {
        let changed = title != lastSavedTitle
            || bodyText != lastSavedBody
            || tags != lastSavedTags
            || selectedBookId != lastSavedBookId
        guard changed else { return false }
        guard isDraft, !hasBeenWritten else { return true }
        // A draft becomes a note with its first word. A day's page arrives with its date already
        // for a title, so for it the first word has to be in the text.
        let hasBody = !bodyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasTitle = !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return item.note.dailyDate != nil ? hasBody : (hasBody || hasTitle)
    }

    private func commitTagDraft() {
        guard let tag = NoteTag.normalized(tagDraft) else { return }
        if !tags.contains(tag) {
            tags.append(tag)
        }
        tagDraft = ""
    }

    private func scheduleSave() {
        saveTask?.cancel()
        guard !isClosing, !isDeleting else { return }
        guard hasUnsavedChanges else {
            saveState = .saved
            return
        }

        saveState = .saving
        saveTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            guard !Task.isCancelled else { return }
            saveImmediately()
        }
    }

    private func saveImmediately(includingPendingTag: Bool = false) {
        var finalTags = tags
        if includingPendingTag,
           let pendingTag = NoteTag.normalized(tagDraft),
           !finalTags.contains(pendingTag) {
            finalTags.append(pendingTag)
        }

        let tagsChanged = finalTags != lastSavedTags && (!isDraft || hasBeenWritten)
        guard hasUnsavedChanges || tagsChanged else {
            saveState = .saved
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        // Where the note lives travels on its first write only; for a row that exists already
        // `saveNote` keeps the stored place, so a page left open never undoes a move.
        let note = Note(
            id: item.note.id,
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            body: bodyText,
            bookId: selectedBookId,
            createdAt: item.note.createdAt,
            spaceId: item.note.spaceId,
            dailyDate: item.note.dailyDate
        )

        if onSave(note, finalTags) {
            hasBeenWritten = true
            lastSavedTitle = title
            lastSavedBody = bodyText
            lastSavedTags = finalTags
            lastSavedBookId = selectedBookId
            saveState = .saved
        } else {
            saveState = .failed
        }
    }
}

private struct MacSearchInspector: View {
    let result: GlobalSearchResult
    let book: Book?
    let note: NoteItem?
    let onRead: (Book) -> Void
    let onOpenNote: (NoteItem) -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DipleSpace.xl) {
                Label(result.kind.title, systemImage: result.kind.systemImage)
                    .dipleType(.micro, weight: .semibold)
                    .foregroundStyle(DipleColor.accentInk)

                Text(result.title)
                    .dipleType(.readingTitle)
                    .foregroundStyle(DipleColor.textPrimary)
                    .textSelection(.enabled)

                if !result.subtitle.isEmpty {
                    Text(result.subtitle)
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)
                        .textSelection(.enabled)
                }

                if !result.snippet.isEmpty {
                    Text(result.snippet)
                        .dipleType(.readingBody)
                        .foregroundStyle(DipleColor.textSecondary)
                        .textSelection(.enabled)
                        .padding(DipleSpace.l)
                        .craftSurface()
                }

                if let note {
                    Button("Open note") { onOpenNote(note) }
                        .buttonStyle(.borderedProminent)
                } else if let book {
                    Button("Open publication") { onRead(book) }
                        .buttonStyle(.borderedProminent)
                }
            }
            .padding(DipleSpace.xxl)
        }
        .background(DipleColor.surface)
    }
}

private struct MacInspectorPlaceholder: View {
    let sourceTitle: String

    /// A short legend, not the whole menu bar. These five are the ones that change how the
    /// window is used rather than what it shows.
    private static let shortcuts: [(key: String, label: String)] = [
        ("⌘O", "Import a publication"),
        ("⌘N", "New note"),
        ("⌘F", "Search this column"),
        ("⌘1…7", "Move between shelves"),
        ("⌘↩", "Open the selected book")
    ]

    var body: some View {
        VStack(spacing: DipleSpace.l) {
            DipleMark(size: 34)
                .opacity(0.55)
            Text("Select an item")
                .dipleType(.headline)
                .foregroundStyle(DipleColor.textSecondary)
            Text("Details from \(sourceTitle.lowercased()) will appear here.")
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textQuaternary)
                .multilineTextAlignment(.center)

            VStack(alignment: .leading, spacing: DipleSpace.s) {
                ForEach(Self.shortcuts, id: \.key) { shortcut in
                    HStack(spacing: DipleSpace.m) {
                        Text(shortcut.key)
                            .dipleType(.nano, weight: .semibold)
                            .foregroundStyle(DipleColor.textTertiary)
                            .monospaced()
                            .frame(width: 44, alignment: .trailing)
                        Text(shortcut.label)
                            .dipleType(.micro)
                            .foregroundStyle(DipleColor.textQuaternary)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.top, DipleSpace.l)
            .frame(maxWidth: 260)
        }
        .padding(DipleSpace.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DipleColor.surface)
    }
}

struct MacEmptyCollection: View {
    let icon: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var actionIcon: String? = nil
    var action: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: DipleSpace.l) {
            Image(systemName: icon)
                .dipleIcon(28, weight: .light)
                .foregroundStyle(DipleColor.accentInk)
                .frame(width: 60, height: 60)
                .background(DipleColor.accentSoft, in: RoundedRectangle(cornerRadius: DipleRadius.l))
            Text(title)
                .dipleType(.headline)
                .foregroundStyle(DipleColor.textPrimary)
            Text(message)
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)

            if let actionTitle, let action {
                Button(action: action) {
                    Label(actionTitle, systemImage: actionIcon ?? "plus")
                        .dipleType(.footnote, weight: .semibold)
                        .foregroundStyle(DipleColor.textOnAccent)
                        .padding(.horizontal, DipleSpace.l)
                        .padding(.vertical, DipleSpace.m)
                        .background(DipleColor.accent, in: RoundedRectangle(cornerRadius: DipleRadius.s))
                }
                .buttonStyle(.plain)
                .padding(.top, DipleSpace.s)
            }
        }
        .padding(DipleSpace.xxxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct MacMetadataRow<Content: View>: View {
    let label: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: DipleSpace.xs) {
            Text(label.uppercased())
                .dipleType(.nano)
                .foregroundStyle(DipleColor.textQuaternary)
            content()
                .dipleType(.caption)
                .foregroundStyle(DipleColor.textSecondary)
        }
    }
}

#endif
