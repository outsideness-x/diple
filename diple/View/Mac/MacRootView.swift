#if targetEnvironment(macCatalyst)
import SwiftUI
import UniformTypeIdentifiers

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
        case notes
        case search

        var id: Self { self }

        var title: String {
            switch self {
            case .library: return "Library"
            case .unread: return "Unread"
            case .reading: return "Reading"
            case .articles: return "Articles"
            case .highlights: return "Highlights"
            case .notes: return "Notes"
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
            case .notes: return "square.grid.2x2"
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
            case .notes: return "6"
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
            case .highlights, .notes, .search: return nil
            }
        }

        static func forCommand(_ command: MacCommand) -> Source? {
            switch command {
            case .goLibrary: return .library
            case .goUnread: return .unread
            case .goReading: return .reading
            case .goArticles: return .articles
            case .goHighlights: return .highlights
            case .goNotes: return .notes
            case .goSearch: return .search
            default: return nil
            }
        }
    }

    private enum Detail: Hashable {
        case welcome
        case book(Book)
        case quoteBook(BookQuoteSummary)
        case note(NoteItem)
        case search(GlobalSearchResult)

        /// What the collection has to draw a ring around. Every model behind a detail carries a
        /// `String` id, so one property answers for all four rather than each collection
        /// unwrapping the enum itself.
        var selectionID: String? {
            switch self {
            case .welcome: return nil
            case .book(let book): return book.id
            case .quoteBook(let summary): return summary.bookId
            case .note(let item): return item.id
            case .search(let result): return result.id
            }
        }
    }

    @StateObject private var library = LibraryViewModel()
    @StateObject private var highlights = HubViewModel()
    @StateObject private var notes = NotesViewModel()
    @StateObject private var search = GlobalSearchViewModel()

    @State private var source: Source? = .library
    @State private var detail: Detail = .welcome
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var readerBook: Book?
    @State private var secondReadBook: Book?
    @State private var isImportingFile = false
    @State private var isImportingLink = false
    @State private var tagEditingBook: Book?
    /// The shelf's own filter text. It lives here rather than inside the collection so that
    /// switching to Unread and back does not silently keep a query the header has re-drawn
    /// empty, and so ⌘F can put the caret in a field the shell knows about.
    @State private var libraryQuery = ""
    @State private var librarySort: LibrarySort = .recentlyOpened
    @State private var highlightsQuery = ""
    @Environment(\.scenePhase) private var scenePhase
    /// A pending "put the caret in the search field of the column that is open". Plain state
    /// rather than `@FocusState`, because the field itself is two views down inside
    /// `DipleSearchField` and only the view that owns a `TextField` can own its focus.
    @State private var searchFocusRequest: MacSearchTarget?

    /// True while a book is open over the whole window. Navigation commands are ignored then:
    /// moving the shelf underneath the reader changes what closing the book returns to without
    /// the reader ever appearing to move.
    private var isReading: Bool { readerBook != nil || secondReadBook != nil }

    public init() {}

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 196, ideal: 232, max: 300)
        } content: {
            collection
                .navigationSplitViewColumnWidth(min: 380, ideal: 640)
        } detail: {
            inspector
                // Narrower than it was. At the width the window opens at, an inspector allowed
                // 460 pt left the cover grid two tiles wide under a header that had to fold.
                .navigationSplitViewColumnWidth(min: 288, ideal: 330, max: 400)
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
        }
        .fullScreenCover(item: $readerBook, onDismiss: reloadAll) { book in
            NavigationStack {
                ReaderContainerView(book: book, onReadingUpdated: reloadAll)
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
            if newSource == .highlights { highlights.load() }
            if newSource == .notes { notes.load() }
            if newSource == .search { search.reloadContext() }
            if newSource == .notes, case .note = detail { return }
            detail = .welcome
        }
        .onReceive(NotificationCenter.default.publisher(for: .dipleOpenDailyResurfacing)) { _ in
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
                source = .highlights
            }
        }
        .onAppear(perform: reloadAll)
        .onAppear(perform: DipleMacWindow.configure)
    }

    // MARK: - Commands

    private func perform(_ command: MacCommand) {
        switch command {
        case .newNote:
            guard !isReading else { return }
            createNewNote()

        case .importFile:
            guard !isReading else { return }
            isImportingFile = true

        case .importLink:
            guard !isReading else { return }
            isImportingLink = true

        case .refresh:
            reloadAll()

        case .goLibrary, .goUnread, .goReading, .goArticles, .goHighlights, .goNotes, .goSearch:
            guard !isReading, let destination = Source.forCommand(command) else { return }
            source = destination
            if destination == .search { searchFocusRequest = .search }

        case .findInColumn:
            // Narrow what is open, rather than going somewhere. Every shelf has a field of its
            // own, so this never has to fall back to the global index — and must not, because
            // that would throw away the filter the reader was already typing into.
            guard !isReading else { return }
            switch source {
            case .library, .unread, .reading, .articles: searchFocusRequest = .library
            case .highlights: searchFocusRequest = .highlights
            case .notes: searchFocusRequest = .notes
            case .search, .none: searchFocusRequest = .search
            }

        case .findInBook:
            // Answered by the reader itself, which is presented above this view.
            break
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
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
                sourceRow(.highlights, badge: highlights.totalQuoteCount)
                sourceRow(.notes, badge: notes.items.count)
            } header: {
                Text("Workspace")
            }

            Section {
                sourceRow(.search)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(DipleColor.surface)
        .safeAreaInset(edge: .top, spacing: 0) {
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
            .padding(.horizontal, DipleSpace.m)
            .padding(.vertical, DipleSpace.l)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // The one action a reader arrives wanting to perform on an empty library, kept
            // where it can be reached from any shelf rather than only from the one that has an
            // Import button in its header.
            VStack(spacing: 0) {
                Rectangle()
                    .fill(DipleColor.separator)
                    .frame(height: DipleStroke.hairline)

                Button {
                    isImportingFile = true
                } label: {
                    HStack(spacing: DipleSpace.s) {
                        Image(systemName: "plus")
                            .dipleIcon(12, weight: .semibold)
                        Text("Import")
                            .dipleType(.footnote, weight: .medium)
                            .lineLimit(1)
                        Spacer(minLength: DipleSpace.s)
                        Text("⌘O")
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
                onOpen: { readerBook = $0 },
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
            }
            .sheet(item: $library.bookToEdit) { book in
                EditBookMetadataView(book: book) { title, author, coverData in
                    library.updateMetadata(for: book.id, title: title, author: author, coverData: coverData)
                }
            }
            .alert("Delete book?", isPresented: $library.showDeleteConfirmation) {
                Button("Delete", role: .destructive) { library.deleteConfirmedBook() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The file and your reading position are removed. Saved passages stay in Highlights.")
            }

        case .highlights:
            MacHighlightsCollection(
                model: highlights,
                query: $highlightsQuery,
                searchFocusRequest: $searchFocusRequest,
                selectedID: detail.selectionID,
                onSelect: { detail = .quoteBook($0) }
            )

        case .notes:
            MacNotesCollection(
                model: notes,
                searchFocusRequest: $searchFocusRequest,
                selectedID: detail.selectionID,
                onSelect: { detail = .note($0) },
                onCreate: createNewNote,
                onDelete: { notes.delete($0); detail = .welcome }
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
                fragmentCount: highlights.summaries.first { $0.bookId == current.id }?.quoteCount ?? 0,
                onRead: { readerBook = current },
                onSecondRead: { secondReadBook = current },
                onEdit: { library.bookToEdit = current },
                onEditTags: { tagEditingBook = current }
            )
            .id(current.id)

        case .quoteBook(let summary):
            MacQuotesInspector(summary: summary)
                .id(summary.bookId)

        case .note(let item):
            let currentItem = currentNote(matching: item) ?? item
            MacNoteInspector(
                item: currentItem,
                books: notes.books,
                suggestedTags: notes.allTags,
                allNotes: notes.items,
                onOpenNote: { detail = .note($0) },
                onSave: { note, tags in notes.save(note, tags: tags) },
                onDelete: {
                    notes.delete(currentItem)
                    detail = .welcome
                }
            )
            .id(currentItem.id)

        case .search(let result):
            MacSearchInspector(
                result: result,
                book: search.book(for: result),
                note: notes.items.first { $0.id == result.entityID },
                onRead: { book in readerBook = book },
                onOpenNote: { note in
                    source = .notes
                    detail = .note(note)
                }
            )
        }
    }

    private func createNewNote() {
        let note = Note(body: "")
        guard notes.save(note, tags: []) else { return }
        guard let item = notes.items.first(where: { $0.id == note.id }) else { return }
        source = .notes
        detail = .note(item)
    }

    private func count(type: LibraryTypeFilter = .all, status: LibraryStatusFilter = .any) -> Int {
        library.books.filter { type.includes($0) && status.includes($0) }.count
    }

    private func currentBook(matching book: Book) -> Book? {
        library.books.first { $0.id == book.id }
    }

    private func currentNote(matching item: NoteItem) -> NoteItem? {
        notes.items.first { $0.id == item.id }
    }

    private func reloadAll() {
        library.loadBooks()
        highlights.load()
        notes.load()
        search.reloadContext()
    }
}

// MARK: - Shared desktop chrome

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
private struct MacColumnHeader<Actions: View>: View {
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
private struct MacPrimaryButton: View {
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
private struct MacRowSurface: ViewModifier {
    let isSelected: Bool
    let isHovering: Bool
    var radius: CGFloat = DipleRadius.m

    func body(content: Content) -> some View {
        content
            .background(fill, in: RoundedRectangle(cornerRadius: radius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: radius, style: .continuous)
                    .strokeBorder(
                        isSelected ? DipleColor.accent : DipleColor.hairline,
                        lineWidth: isSelected ? DipleStroke.selection : DipleStroke.hairline
                    )
            }
    }

    private var fill: Color {
        if isSelected { return DipleColor.accentSoft }
        return isHovering ? DipleColor.surfaceRaised : DipleColor.surface
    }
}

private extension View {
    func macRow(isSelected: Bool, isHovering: Bool, radius: CGFloat = DipleRadius.m) -> some View {
        modifier(MacRowSurface(isSelected: isSelected, isHovering: isHovering, radius: radius))
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
private struct MacSelectableRow<Content: View>: View {
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
        .macRow(isSelected: isSelected, isHovering: isHovering, radius: radius)
        .onHover { hovering in
            withAnimation(DipleMotion.snappy) { isHovering = hovering }
        }
    }
}

/// A plain hover wash for controls that are not rows in a collection — the sidebar footer.
private struct MacHoverRowButtonStyle: ButtonStyle {
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

private extension ButtonStyle where Self == MacHoverRowButtonStyle {
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

// MARK: - Highlights

private struct MacHighlightsCollection: View {
    @ObservedObject var model: HubViewModel
    @Binding var query: String
    @Binding var searchFocusRequest: MacSearchTarget?
    let selectedID: String?
    let onSelect: (BookQuoteSummary) -> Void

    private var visibleSummaries: [BookQuoteSummary] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return model.summaries }
        return model.summaries.filter { summary in
            [summary.title, summary.author]
                .compactMap { $0 }
                .contains { $0.localizedStandardContains(needle) }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            MacColumnHeader(
                title: "Highlights",
                count: model.totalQuoteCount,
                context: model.summaries.isEmpty
                    ? nil
                    : "\(model.summaries.count) \(model.summaries.count == 1 ? "book" : "books")",
                query: model.summaries.isEmpty ? nil : $query,
                prompt: "Book or author",
                searchIdentifier: "mac.highlights.search",
                focusRequest: $searchFocusRequest,
                focusTarget: .highlights
            ) {
                EmptyView()
            }

            ZStack {
                DipleColor.canvas.ignoresSafeArea()
                if model.summaries.isEmpty {
                    MacEmptyCollection(
                        icon: "quote.opening",
                        title: "No highlights yet",
                        message: "Passages you mark while reading will be collected here."
                    )
                } else if visibleSummaries.isEmpty {
                    MacEmptyCollection(
                        icon: "text.magnifyingglass",
                        title: "No matching books",
                        message: "Try a different title or author."
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: DipleSpace.m) {
                            // The desktop shell has no reader route of its own for a passage —
                            // the reader opens as a full-window cover from a `Book`, not from a
                            // path — so here the quote selects its group, which is the
                            // inspector's job.
                            if query.isEmpty {
                                DailyResurfacingCard { onSelect($0.summary) }
                            }

                            ForEach(visibleSummaries) { summary in
                                MacSelectableRow(isSelected: selectedID == summary.bookId) {
                                    onSelect(summary)
                                } content: {
                                    HStack(spacing: DipleSpace.m) {
                                        BookCoverView(
                                            coverPath: summary.book?.coverPath,
                                            title: summary.title,
                                            author: summary.author,
                                            isCompact: true
                                        )
                                        .frame(width: 44, height: 66)
                                        VStack(alignment: .leading, spacing: DipleSpace.xs) {
                                            Text(summary.title)
                                                .dipleType(.body, weight: .semibold)
                                                .foregroundStyle(DipleColor.textPrimary)
                                                .lineLimit(2)
                                            Text(summary.subtitle)
                                                .dipleType(.caption)
                                                .foregroundStyle(DipleColor.textTertiary)
                                                .lineLimit(1)
                                        }
                                        Spacer(minLength: DipleSpace.s)
                                        Text("\(summary.quoteCount)")
                                            .dipleType(.footnote, weight: .semibold)
                                            .foregroundStyle(DipleColor.accentInk)
                                            .monospacedDigit()
                                        Image(systemName: "chevron.right")
                                            .dipleIcon(11)
                                            .foregroundStyle(DipleColor.textQuaternary)
                                    }
                                    .padding(DipleSpace.m)
                                }
                            }
                        }
                        .padding(DipleSpace.xxl)
                        .padding(.bottom, DipleSpace.xxxl)
                    }
                }
            }
        }
    }
}

// MARK: - Notes

private struct MacNotesCollection: View {
    @ObservedObject var model: NotesViewModel
    @Binding var searchFocusRequest: MacSearchTarget?
    let selectedID: String?
    let onSelect: (NoteItem) -> Void
    let onCreate: () -> Void
    let onDelete: (NoteItem) -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 200, maximum: 300), spacing: DipleSpace.m, alignment: .top)
    ]

    var body: some View {
        VStack(spacing: 0) {
            MacColumnHeader(
                title: "Notes",
                count: model.filteredItems.count,
                context: model.items.isEmpty
                    ? nil
                    : "\(model.totalWordCount.formatted()) words · \(model.linkedCount) linked to your library",
                query: model.items.isEmpty ? nil : $model.query,
                prompt: "Search notes, tags and books",
                searchIdentifier: "mac.notes.search",
                focusRequest: $searchFocusRequest,
                focusTarget: .notes
            ) {
                Menu {
                    ForEach(NoteSort.allCases) { sort in
                        Button {
                            model.sort = sort
                        } label: {
                            Label(sort.title, systemImage: sort.systemImage)
                        }
                    }
                } label: {
                    Label(model.sort.title, systemImage: "arrow.up.arrow.down")
                        .dipleType(.footnote)
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
                .help("Sort your notes")

                MacPrimaryButton(title: "New note", shortcutHint: "⌘N", action: onCreate)
            }

            ZStack {
                DipleColor.canvas.ignoresSafeArea()
                if model.items.isEmpty {
                    MacEmptyCollection(
                        icon: "square.and.pencil",
                        title: "Start with a thought",
                        message: "Notes are quiet pages for ideas, summaries and connections.",
                        actionTitle: "New note",
                        actionIcon: "plus",
                        action: onCreate
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: DipleSpace.l) {
                            macNoteFilters

                            if model.filteredItems.isEmpty {
                                MacEmptyCollection(
                                    icon: model.query.isEmpty ? "line.3.horizontal.decrease.circle" : "text.magnifyingglass",
                                    title: model.query.isEmpty ? "Nothing in this view" : "No matching notes",
                                    message: model.query.isEmpty ? "Choose another filter." : "Try a title, phrase, tag, author or book."
                                )
                                .frame(minHeight: 280)
                            } else {
                                LazyVGrid(columns: columns, alignment: .leading, spacing: DipleSpace.m) {
                                    ForEach(model.filteredItems) { item in
                                        MacSelectableCard(isSelected: selectedID == item.id) {
                                            onSelect(item)
                                        } content: {
                                            NoteCardView(item: item)
                                        }
                                        .contextMenu {
                                            Button("Open") { onSelect(item) }
                                            Divider()
                                            Button("Delete", role: .destructive) { onDelete(item) }
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
    }

    private var macNoteFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DipleSpace.s) {
                ForEach(model.availableFilters, id: \.self) { filter in
                    Button {
                        model.filter = filter
                    } label: {
                        macFilterChip(for: filter)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @ViewBuilder
    private func macFilterChip(for filter: NoteFilter) -> some View {
        let selected = model.filter == filter
        switch filter {
        case .all:
            macSmartChip("All", icon: "tray.full", selected: selected)
        case .recent:
            macSmartChip("This week", icon: "clock", selected: selected)
        case .linked:
            macSmartChip("From library", icon: "book.closed", selected: selected)
        case .untagged:
            macSmartChip("Unsorted", icon: "tray", selected: selected)
        case .tag(let tag):
            TagChipView(label: tag, kind: .text, isSelected: selected)
        case .book:
            TagChipView(label: model.title(for: filter), kind: .book, isSelected: selected)
        }
    }

    private func macSmartChip(_ title: String, icon: String, selected: Bool) -> some View {
        Label(title, systemImage: icon)
            .dipleType(.micro)
            .foregroundStyle(selected ? DipleColor.accentInk : DipleColor.textTertiary)
            .diplePadding(.chip)
            .dipleSelected(selected, in: Capsule())
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

private struct MacQuotesInspector: View {
    let summary: BookQuoteSummary
    @StateObject private var model: BookQuotesViewModel

    init(summary: BookQuoteSummary) {
        self.summary = summary
        _model = StateObject(wrappedValue: BookQuotesViewModel(bookId: summary.bookId))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DipleSpace.l) {
                VStack(alignment: .leading, spacing: DipleSpace.s) {
                    Text(summary.title)
                        .dipleType(.readingTitle)
                        .foregroundStyle(DipleColor.textPrimary)
                    if summary.isRemovedFromLibrary {
                        Text("Not in your library")
                            .dipleType(.caption)
                            .foregroundStyle(DipleColor.textQuaternary)
                    }
                    Text("\(model.quotes.count) saved passages")
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)
                }

                ForEach(model.quotes) { quote in
                    VStack(alignment: .leading, spacing: DipleSpace.m) {
                        RoundedRectangle(cornerRadius: 1)
                            .fill(DipleColor.Highlight.color(forHex: quote.colorHex))
                            .frame(width: 26, height: 3)
                        Text(quote.text)
                            .dipleType(.readingBody)
                            .foregroundStyle(DipleColor.textPrimary)
                            .textSelection(.enabled)
                        if let comment = quote.comment, !comment.isEmpty {
                            HStack(alignment: .top, spacing: DipleSpace.s) {
                                Image(systemName: "bubble.left")
                                    .dipleIcon(10, weight: .medium)
                                    .foregroundStyle(DipleColor.accentInk)
                                Text(comment)
                                    .dipleType(.caption)
                                    .foregroundStyle(DipleColor.textSecondary)
                                    .textSelection(.enabled)
                            }
                        }
                        Text(quote.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .dipleType(.nano)
                            .foregroundStyle(DipleColor.textQuaternary)
                    }
                    .padding(DipleSpace.l)
                    .craftSurface()
                    .contextMenu {
                        Button {
                            model.beginEditingComment(quote)
                        } label: {
                            Label(quote.comment == nil ? "Add comment" : "Edit comment", systemImage: "bubble.left")
                        }

                        Button(role: .destructive) {
                            model.confirmDelete(quote)
                        } label: {
                            Label("Delete passage", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(DipleSpace.xxl)
        }
        .background(DipleColor.surface)
        .alert("Delete passage?", isPresented: $model.showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                model.deleteConfirmedQuote()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This passage will be removed.")
        }
        .sheet(item: $model.quoteForComment) { quote in
            QuoteCommentEditorView(
                quote: quote,
                tags: model.tags(for: quote),
                suggestions: model.tagSuggestions,
                onSave: model.saveComment,
                onCancel: model.cancelCommentEditing
            )
        }
    }
}

private struct MacNoteInspector: View {
    let item: NoteItem
    let books: [Book]
    let suggestedTags: [String]
    /// Wiki links resolve against these, exactly as they do on the phone.
    let allNotes: [NoteItem]
    let onOpenNote: (NoteItem) -> Void
    let onSave: (Note, [String]) -> Bool
    let onDelete: () -> Void

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
    @State private var isFormulaComposerPresented = false
    @State private var formulaSeed = ""
    @State private var formulaMode: NoteFormulaMode = .inline
    @State private var formulaSessionID = UUID()

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
        books: [Book],
        suggestedTags: [String],
        allNotes: [NoteItem],
        onOpenNote: @escaping (NoteItem) -> Void,
        onSave: @escaping (Note, [String]) -> Bool,
        onDelete: @escaping () -> Void
    ) {
        self.item = item
        self.books = books
        self.suggestedTags = suggestedTags
        self.allNotes = allNotes
        self.onOpenNote = onOpenNote
        self.onSave = onSave
        self.onDelete = onDelete

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
                            onSlashChanged: { slashContext = $0 }
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
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .background(DipleColor.surface)
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
            .frame(minWidth: 520, minHeight: 560)
        }
        .sheet(isPresented: $isFormulaComposerPresented) {
            NoteFormulaComposer(initialLatex: formulaSeed, initialMode: formulaMode) { mode, latex in
                NoteEditing.insertFormula(latex, mode: mode, in: &bodyText, selection: selection)
                isBodyFocused = true
            }
            .id(formulaSessionID)
            .frame(minWidth: 620, minHeight: 680)
        }
        .alert("Delete note?", isPresented: $isShowingDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                isDeleting = true
                saveTask?.cancel()
                onDelete()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This note and its tags will be removed.")
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
        title != lastSavedTitle
            || bodyText != lastSavedBody
            || tags != lastSavedTags
            || selectedBookId != lastSavedBookId
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

        let tagsChanged = finalTags != lastSavedTags
        guard hasUnsavedChanges || tagsChanged else {
            saveState = .saved
            return
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let note = Note(
            id: item.note.id,
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            body: bodyText,
            bookId: selectedBookId,
            createdAt: item.note.createdAt
        )

        if onSave(note, finalTags) {
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

private struct MacEmptyCollection: View {
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
