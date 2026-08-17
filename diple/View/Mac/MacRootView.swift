#if targetEnvironment(macCatalyst)
import SwiftUI
import UniformTypeIdentifiers

/// The desktop shell keeps the phone's reading and persistence stack, but gives it a
/// Mac-shaped information architecture: persistent sources, a working collection and a
/// contextual detail pane. The reader remains a focused full-window destination.
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

        var filter: LibraryFilter? {
            switch self {
            case .library: return .all
            case .unread: return .unread
            case .reading: return .inProgress
            case .articles: return .articles
            case .highlights, .notes, .search: return nil
            }
        }
    }

    private enum Detail: Hashable {
        case welcome
        case book(Book)
        case quoteBook(BookQuoteSummary)
        case note(NoteItem)
        case search(GlobalSearchResult)
    }

    @StateObject private var library = LibraryViewModel()
    @StateObject private var highlights = HubViewModel()
    @StateObject private var notes = NotesViewModel()
    @StateObject private var search = GlobalSearchViewModel()

    @State private var source: Source? = .library
    @State private var detail: Detail = .welcome
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var readerBook: Book?
    @State private var isImportingFile = false
    @State private var isImportingLink = false
    @State private var isShowingSettings = false
    @State private var tagEditingBook: Book?

    public init() {}

    public var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            sidebar
                .navigationSplitViewColumnWidth(min: 180, ideal: 220, max: 260)
        } content: {
            collection
                .navigationSplitViewColumnWidth(min: 340, ideal: 620)
        } detail: {
            inspector
                .navigationSplitViewColumnWidth(min: 280, ideal: 340, max: 440)
        }
        .controlSize(.large)
        .background(DipleColor.canvas)
        .tint(DipleColor.accent)
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    isShowingSettings = true
                } label: {
                    Label("Settings", systemImage: "gearshape")
                }
                .keyboardShortcut(",", modifiers: .command)

                Menu {
                    Button {
                        isImportingLink = true
                    } label: {
                        Label("Save Link", systemImage: "link")
                    }
                    .keyboardShortcut("l", modifiers: [.command, .shift])

                    Button {
                        isImportingFile = true
                    } label: {
                        Label("Import File", systemImage: "folder")
                    }
                    .keyboardShortcut("o", modifiers: .command)

                    Divider()

                    Button {
                        createNewNote()
                    } label: {
                        Label("New Note", systemImage: "square.and.pencil")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                } label: {
                    Label("New", systemImage: "plus")
                }
            }
        }
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
        .sheet(isPresented: $isShowingSettings) {
            AppSettingsView()
        }
        .fullScreenCover(item: $readerBook, onDismiss: reloadAll) { book in
            NavigationStack {
                ReaderContainerView(book: book, onReadingUpdated: reloadAll)
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
        .onAppear {
            if DailyResurfacingService.shared.consumeOpenRequest() {
                source = .highlights
            }
        }
        .onAppear(perform: reloadAll)
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $source) {
            Section {
                sourceRow(.library, badge: library.books.count)
                sourceRow(.unread, badge: count(for: .unread))
                sourceRow(.reading, badge: count(for: .inProgress))
                sourceRow(.articles, badge: count(for: .articles))
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
                Button {
                    isShowingSettings = true
                } label: {
                    Image(systemName: "gearshape")
                        .dipleIcon(12)
                        .foregroundStyle(DipleColor.textTertiary)
                }
                .buttonStyle(.plain)
                .help("Settings (⌘,)")
            }
            .padding(.horizontal, DipleSpace.m)
            .padding(.vertical, DipleSpace.l)
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
                filter: source?.filter ?? .all,
                continueReading: source == .library ? library.continueReadingBook : nil,
                isImporting: library.isImporting,
                onSelect: { detail = .book($0) },
                onOpen: { readerBook = $0 },
                onEdit: { library.bookToEdit = $0 },
                onMarkAsFinished: { library.markAsFinished($0) },
                onMove: { library.move($0, to: $1) },
                onEditTags: { tagEditingBook = $0 },
                onDelete: { library.confirmDelete($0) },
                onImportFile: { isImportingFile = true },
                onImportLink: { isImportingLink = true }
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
            .alert("Delete Book?", isPresented: $library.showDeleteConfirmation) {
                Button("Delete", role: .destructive) { library.deleteConfirmedBook() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The publication and reading position will be removed. Its quotes will remain in Quotes, where you can delete them manually.")
            }

        case .highlights:
            MacHighlightsCollection(
                model: highlights,
                onSelect: { detail = .quoteBook($0) }
            )

        case .notes:
            MacNotesCollection(
                model: notes,
                onSelect: { detail = .note($0) },
                onCreate: createNewNote
            )

        case .search:
            MacSearchCollection(
                model: search,
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
            MacBookInspector(
                book: currentBook(matching: book) ?? book,
                onRead: { readerBook = book },
                onEdit: { library.bookToEdit = book }
            )

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

    private func count(for filter: LibraryFilter) -> Int {
        library.books.filter(filter.includes).count
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

// MARK: - Library

private struct MacLibraryCollection: View {
    let title: String
    let books: [Book]
    let filter: LibraryFilter
    let continueReading: Book?
    let isImporting: Bool
    let onSelect: (Book) -> Void
    let onOpen: (Book) -> Void
    let onEdit: (Book) -> Void
    let onMarkAsFinished: (Book) -> Void
    let onMove: (Book, BookLocation) -> Void
    let onEditTags: (Book) -> Void
    let onDelete: (Book) -> Void
    let onImportFile: () -> Void
    let onImportLink: () -> Void

    @State private var query = ""
    @State private var sort: LibrarySort = .recentlyOpened

    private let columns = [
        GridItem(
            .adaptive(minimum: 144, maximum: 184),
            spacing: DipleSpace.xl,
            alignment: .top
        )
    ]

    private var visibleBooks: [Book] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return books
            .filter { book in
                guard filter.includes(book) else { return false }
                guard !needle.isEmpty else { return true }
                return [book.title, book.author, book.sourceHost]
                    .compactMap { $0 }
                    .contains { $0.localizedStandardContains(needle) }
            }
            .sorted(by: sorter)
    }

    var body: some View {
        VStack(spacing: 0) {
            commandBar

            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                if visibleBooks.isEmpty && !isImporting {
                    MacEmptyCollection(
                        icon: query.isEmpty ? "books.vertical" : "magnifyingglass",
                        title: query.isEmpty ? "Nothing here yet" : "No results",
                        message: query.isEmpty
                            ? "Import an EPUB or PDF to start your library."
                            : "Try a different title, author or source.",
                        actionTitle: query.isEmpty ? "Import File" : nil,
                        actionIcon: "plus",
                        action: query.isEmpty ? onImportFile : nil
                    )
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: DipleSpace.xxxl) {
                            if let continueReading, filter == .all, query.isEmpty {
                                MacContinueReadingCard(book: continueReading) {
                                    onOpen(continueReading)
                                }
                            }

                            VStack(alignment: .leading, spacing: DipleSpace.l) {
                                HStack(alignment: .firstTextBaseline) {
                                    Text("\(visibleBooks.count) items")
                                        .dipleType(.micro)
                                        .foregroundStyle(DipleColor.textQuaternary)
                                        .monospacedDigit()
                                    Spacer()
                                    Menu {
                                        Picker("Sort", selection: $sort) {
                                            ForEach(LibrarySort.allCases) { option in
                                                Text(option.rawValue).tag(option)
                                            }
                                        }
                                    } label: {
                                        Label(sort.compactTitle, systemImage: "arrow.up.arrow.down")
                                            .dipleType(.micro)
                                    }
                                }

                                LazyVGrid(columns: columns, alignment: .leading, spacing: DipleSpace.xxl) {
                                    ForEach(visibleBooks) { book in
                                        MacBookTile(book: book) {
                                            onSelect(book)
                                        } onOpen: {
                                            onOpen(book)
                                        }
                                        .contextMenu {
                                            Button("Open") { onOpen(book) }
                                            if book.furthestProgress < 0.995 {
                                                Button("Mark as Finished") { onMarkAsFinished(book) }
                                            }
                                            Button("Tags…") { onEditTags(book) }
                                            Button("Edit Metadata") { onEdit(book) }
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
        }
        .searchable(text: $query, placement: .toolbar, prompt: "Title, author or source")
    }

    private var commandBar: some View {
        HStack(spacing: DipleSpace.m) {
            Text(title)
                .dipleType(.headline)
                .foregroundStyle(DipleColor.textPrimary)

            Spacer()

            Button(action: onImportLink) {
                Label("Save Link", systemImage: "link")
                    .dipleType(.footnote)
            }
            .buttonStyle(.plain)
            .foregroundStyle(DipleColor.textSecondary)

            Button(action: onImportFile) {
                Label("Import File", systemImage: "plus")
                    .dipleType(.footnote, weight: .semibold)
                    .foregroundStyle(DipleColor.textOnAccent)
                    .padding(.horizontal, DipleSpace.m)
                    .padding(.vertical, DipleSpace.s)
                    .background(DipleColor.accent, in: RoundedRectangle(cornerRadius: DipleRadius.s))
            }
            .buttonStyle(.plain)
            .keyboardShortcut("o", modifiers: .command)
        }
        .padding(.horizontal, DipleSpace.xl)
        .padding(.vertical, DipleSpace.m)
        .background(DipleColor.surface)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DipleColor.separator)
                .frame(height: DipleStroke.hairline)
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
                    .shadow(color: .black.opacity(0.24), radius: 12, y: 7)

                    if book.furthestProgress > 0.001 {
                        GeometryReader { proxy in
                            VStack {
                                Spacer()
                                ZStack(alignment: .leading) {
                                    Rectangle().fill(.black.opacity(0.5))
                                    Rectangle()
                                        .fill(DipleColor.accent)
                                        .frame(width: proxy.size.width * min(max(book.furthestProgress, 0), 1))
                                }
                                .frame(height: 3)
                            }
                        }
                        .clipShape(RoundedRectangle(cornerRadius: DipleRadius.s))
                    }
                }
                .scaleEffect(isHovering ? 1.015 : 1)

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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            withAnimation(DipleMotion.snappy) { isHovering = hovering }
        }
        .simultaneousGesture(TapGesture(count: 2).onEnded(onOpen))
        .accessibilityHint("Double-click to read")
    }
}

private struct MacContinueReadingCard: View {
    let book: Book
    let onOpen: () -> Void

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
                        .foregroundStyle(DipleColor.accent)
                    Text(book.title)
                        .dipleType(.headline)
                        .foregroundStyle(DipleColor.textPrimary)
                        .lineLimit(2)
                    Text(book.subtitle)
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)

                    ProgressView(value: book.furthestProgress)
                        .tint(DipleColor.accent)
                }

                Spacer()

                Text(book.furthestProgress.formatted(.percent.precision(.fractionLength(0))))
                    .dipleType(.micro)
                    .foregroundStyle(DipleColor.textTertiary)
                    .monospacedDigit()

                Image(systemName: "arrow.right")
                    .dipleIcon(14)
                    .foregroundStyle(DipleColor.accent)
            }
            .padding(DipleSpace.l)
            .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.l)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Highlights

private struct MacHighlightsCollection: View {
    @ObservedObject var model: HubViewModel
    let onSelect: (BookQuoteSummary) -> Void

    var body: some View {
        ZStack {
            DipleColor.canvas.ignoresSafeArea()
            if model.summaries.isEmpty {
                MacEmptyCollection(
                    icon: "quote.opening",
                    title: "No highlights yet",
                    message: "Passages you mark while reading will be collected here."
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DipleSpace.l) {
                        MacCollectionHeader(title: "Highlights", count: model.totalQuoteCount)
                        DailyResurfacingCard(onOpen: onSelect)
                        ForEach(model.summaries) { summary in
                            Button { onSelect(summary) } label: {
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
                                    }
                                    Spacer()
                                    Text("\(summary.quoteCount)")
                                        .dipleType(.footnote, weight: .semibold)
                                        .foregroundStyle(DipleColor.accent)
                                        .monospacedDigit()
                                    Image(systemName: "chevron.right")
                                        .dipleIcon(11)
                                        .foregroundStyle(DipleColor.textQuaternary)
                                }
                                .padding(DipleSpace.m)
                                .craftSurface()
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(DipleSpace.xxl)
                }
            }
        }
    }
}

// MARK: - Notes

private struct MacNotesCollection: View {
    @ObservedObject var model: NotesViewModel
    let onSelect: (NoteItem) -> Void
    let onCreate: () -> Void

    private let columns = [
        GridItem(.adaptive(minimum: 190, maximum: 280), spacing: DipleSpace.m, alignment: .top)
    ]

    var body: some View {
        ZStack {
            DipleColor.canvas.ignoresSafeArea()
            if model.items.isEmpty {
                MacEmptyCollection(
                    icon: "square.and.pencil",
                    title: "Start with a thought",
                    message: "Notes are quiet pages for ideas, summaries and connections.",
                    actionTitle: "New Note",
                    actionIcon: "plus",
                    action: onCreate
                )
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DipleSpace.l) {
                        HStack {
                            VStack(alignment: .leading, spacing: DipleSpace.xs) {
                                MacCollectionHeader(title: "Notes", count: model.filteredItems.count)
                                Text("\(model.totalWordCount.formatted()) words · \(model.linkedCount) linked to your library")
                                    .dipleType(.micro)
                                    .foregroundStyle(DipleColor.textQuaternary)
                            }
                            Spacer()
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
                            }
                            .menuStyle(.borderlessButton)

                            Button(action: onCreate) {
                                Label("New note", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(DipleColor.accent)
                            .foregroundStyle(DipleColor.textOnAccent)
                        }

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
                                    Button { onSelect(item) } label: {
                                        NoteCardView(item: item)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }
                    .padding(DipleSpace.xxl)
                }
            }
        }
        .searchable(text: $model.query, placement: .toolbar, prompt: "Search notes, tags and books")
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
            .foregroundStyle(selected ? DipleColor.textOnAccent : DipleColor.textTertiary)
            .diplePadding(.chip)
            .background(selected ? DipleColor.accent : DipleColor.surfaceOverlay, in: Capsule())
    }
}

// MARK: - Search

private struct MacSearchCollection: View {
    @ObservedObject var model: GlobalSearchViewModel
    let onSelect: (GlobalSearchResult) -> Void

    var body: some View {
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
                                        Button { onSelect(result) } label: {
                                            MacSearchResultRow(result: result)
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                        }
                    }
                    .padding(DipleSpace.xxl)
                }
            }
        }
        .searchable(text: $model.query, placement: .toolbar, prompt: "Notes, highlights and library")
        .onChange(of: model.query) { _, _ in model.search() }
    }
}

private struct MacSearchResultRow: View {
    let result: GlobalSearchResult

    var body: some View {
        HStack(alignment: .top, spacing: DipleSpace.m) {
            Image(systemName: result.kind.systemImage)
                .dipleIcon(13)
                .foregroundStyle(DipleColor.accent)
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
        .craftSurface()
    }
}

// MARK: - Inspectors

private struct MacBookInspector: View {
    let book: Book
    let onRead: () -> Void
    let onEdit: () -> Void

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
                        Image(systemName: book.furthestProgress > 0.001 ? "book.pages" : "book")
                        Text(book.furthestProgress > 0.001 ? "Continue Reading" : "Start Reading")
                        Spacer()
                        Image(systemName: "arrow.right")
                    }
                    .dipleType(.footnote, weight: .semibold)
                    .foregroundStyle(DipleColor.textOnAccent)
                    .padding(.horizontal, DipleSpace.l)
                    .padding(.vertical, DipleSpace.m)
                    .background(DipleColor.accent, in: RoundedRectangle(cornerRadius: DipleRadius.s))
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.return, modifiers: [])

                VStack(alignment: .leading, spacing: DipleSpace.m) {
                    MacMetadataRow(label: "Progress") {
                        HStack(spacing: DipleSpace.s) {
                            ProgressView(value: book.furthestProgress)
                                .tint(DipleColor.accent)
                            Text(book.furthestProgress.formatted(.percent.precision(.fractionLength(0))))
                                .monospacedDigit()
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
                }

                Button("Edit Metadata", action: onEdit)
                    .dipleType(.footnote)
                    .foregroundStyle(DipleColor.textSecondary)
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
                        Text("Removed from library")
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
                                    .foregroundStyle(DipleColor.accent)
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
                            Label(quote.comment == nil ? "Add Comment" : "Edit Comment", systemImage: "bubble.left")
                        }

                        Button(role: .destructive) {
                            model.confirmDelete(quote)
                        } label: {
                            Label("Delete Quote", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(DipleSpace.xxl)
        }
        .background(DipleColor.surface)
        .alert("Delete Quote?", isPresented: $model.showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                model.deleteConfirmedQuote()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This quote will be removed.")
        }
        .sheet(item: $model.quoteForComment) { quote in
            QuoteCommentEditorView(
                quote: quote,
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
                        Label("Delete Note", systemImage: "trash")
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
                        .foregroundStyle(isPreviewing ? DipleColor.accent : DipleColor.textSecondary)
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
        .alert("Delete Note?", isPresented: $isShowingDeleteConfirmation) {
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
                    .foregroundStyle(DipleColor.accent)

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
                    Button("Open Note") { onOpenNote(note) }
                        .buttonStyle(.borderedProminent)
                } else if let book {
                    Button("Open Publication") { onRead(book) }
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
        }
        .padding(DipleSpace.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DipleColor.surface)
    }
}

private struct MacCollectionHeader: View {
    let title: String
    let count: Int

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: DipleSpace.s) {
            Text(title)
                .dipleType(.display)
                .foregroundStyle(DipleColor.textPrimary)
            Text("\(count)")
                .dipleType(.micro)
                .foregroundStyle(DipleColor.textQuaternary)
                .monospacedDigit()
        }
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
                .foregroundStyle(DipleColor.accent)
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
