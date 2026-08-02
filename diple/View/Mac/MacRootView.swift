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
        case quoteBook(Book)
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
    @State private var editedNote: NoteItem?
    @State private var isCreatingNote = false
    @State private var isImportingFile = false
    @State private var isImportingLink = false
    @State private var isShowingSettings = false

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
                        isCreatingNote = true
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
        .sheet(isPresented: $isCreatingNote) {
            noteEditor(route: .new)
        }
        .sheet(item: $editedNote) { item in
            noteEditor(route: .existing(item))
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
            detail = .welcome
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
                Text("diple")
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
                onDelete: { library.confirmDelete($0) },
                onImportFile: { isImportingFile = true },
                onImportLink: { isImportingLink = true }
            )
            .sheet(item: $library.bookToEdit) { book in
                EditBookMetadataView(book: book) { title, author, coverData in
                    library.updateMetadata(for: book.id, title: title, author: author, coverData: coverData)
                }
            }
            .alert("Delete Book?", isPresented: $library.showDeleteConfirmation) {
                Button("Delete", role: .destructive) { library.deleteConfirmedBook() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The publication, reading position and highlights will be removed.")
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
                onCreate: { isCreatingNote = true }
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

        case .quoteBook(let book):
            MacQuotesInspector(book: book)
                .id(book.id)

        case .note(let item):
            MacNoteInspector(item: currentNote(matching: item) ?? item) {
                editedNote = item
            }

        case .search(let result):
            MacSearchInspector(
                result: result,
                book: search.book(for: result),
                note: notes.items.first { $0.id == result.entityID },
                onRead: { book in readerBook = book },
                onEditNote: { note in editedNote = note }
            )
        }
    }

    private func noteEditor(route: NoteRoute) -> some View {
        NavigationStack {
            NoteDetailView(
                route: route,
                books: notes.books,
                suggestedTags: notes.allTags,
                onSave: { note, tags in notes.save(note, tags: tags) },
                onDelete: { item in notes.delete(item) }
            )
        }
        .frame(minWidth: 620, minHeight: 620)
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
    let onDelete: (Book) -> Void
    let onImportFile: () -> Void
    let onImportLink: () -> Void

    @State private var query = ""
    @State private var sort: LibrarySort = .recentlyOpened

    private let columns = [GridItem(.adaptive(minimum: 144, maximum: 184), spacing: DipleSpace.xl)]

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
                                            Button("Edit Metadata") { onEdit(book) }
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

                    ProgressView(value: book.progress)
                        .tint(DipleColor.accent)
                }

                Spacer()

                Text(book.progress.formatted(.percent.precision(.fractionLength(0))))
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
    let onSelect: (Book) -> Void

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
                        ForEach(model.summaries) { summary in
                            Button { onSelect(summary.book) } label: {
                                HStack(spacing: DipleSpace.m) {
                                    BookCoverView(
                                        coverPath: summary.book.coverPath,
                                        title: summary.book.title,
                                        author: summary.book.author,
                                        isCompact: true
                                    )
                                    .frame(width: 44, height: 66)
                                    VStack(alignment: .leading, spacing: DipleSpace.xs) {
                                        Text(summary.book.title)
                                            .dipleType(.body, weight: .semibold)
                                            .foregroundStyle(DipleColor.textPrimary)
                                            .lineLimit(2)
                                        Text(summary.book.subtitle)
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

    private let columns = [GridItem(.adaptive(minimum: 190, maximum: 280), spacing: DipleSpace.m)]

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
                            MacCollectionHeader(title: "Notes", count: model.filteredItems.count)
                            Spacer()
                            Button(action: onCreate) {
                                Label("New note", systemImage: "plus")
                            }
                            .buttonStyle(.borderedProminent)
                            .tint(DipleColor.accent)
                            .foregroundStyle(DipleColor.textOnAccent)
                        }

                        LazyVGrid(columns: columns, alignment: .leading, spacing: DipleSpace.m) {
                            ForEach(model.filteredItems) { item in
                                Button { onSelect(item) } label: {
                                    NoteCardView(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(DipleSpace.xxl)
                }
            }
        }
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
                        Image(systemName: book.progress > 0.001 ? "book.pages" : "book")
                        Text(book.progress > 0.001 ? "Continue Reading" : "Start Reading")
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
                            ProgressView(value: book.progress)
                                .tint(DipleColor.accent)
                            Text(book.progress.formatted(.percent.precision(.fractionLength(0))))
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
    let book: Book
    @StateObject private var model: BookQuotesViewModel

    init(book: Book) {
        self.book = book
        _model = StateObject(wrappedValue: BookQuotesViewModel(bookId: book.id))
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DipleSpace.l) {
                VStack(alignment: .leading, spacing: DipleSpace.s) {
                    Text(book.title)
                        .dipleType(.readingTitle)
                        .foregroundStyle(DipleColor.textPrimary)
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
                        Text(quote.createdAt.formatted(date: .abbreviated, time: .omitted))
                            .dipleType(.nano)
                            .foregroundStyle(DipleColor.textQuaternary)
                    }
                    .padding(DipleSpace.l)
                    .craftSurface()
                }
            }
            .padding(DipleSpace.xxl)
        }
        .background(DipleColor.surface)
    }
}

private struct MacNoteInspector: View {
    let item: NoteItem
    let onEdit: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DipleSpace.xl) {
                VStack(alignment: .leading, spacing: DipleSpace.s) {
                    Text(item.note.title?.isEmpty == false ? item.note.title ?? "" : "Untitled")
                        .dipleType(.readingTitle)
                        .foregroundStyle(DipleColor.textPrimary)
                    Text(item.note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                        .dipleType(.nano)
                        .foregroundStyle(DipleColor.textQuaternary)
                }

                NoteMarkdownView(markdown: item.note.body)
                    .textSelection(.enabled)

                if !item.tags.isEmpty || item.book != nil {
                    Rectangle()
                        .fill(DipleColor.separator)
                        .frame(height: DipleStroke.hairline)
                    FlowLayout(spacing: DipleSpace.s) {
                        if let book = item.book {
                            TagChipView(label: book.title, kind: .book)
                        }
                        ForEach(item.tags, id: \.self) { tag in
                            TagChipView(label: tag, kind: .text)
                        }
                    }
                }

                Button("Edit Note", action: onEdit)
                    .buttonStyle(.borderedProminent)
                    .tint(DipleColor.accent)
                    .foregroundStyle(DipleColor.textOnAccent)
            }
            .padding(DipleSpace.xxl)
        }
        .background(DipleColor.surface)
    }
}

private struct MacSearchInspector: View {
    let result: GlobalSearchResult
    let book: Book?
    let note: NoteItem?
    let onRead: (Book) -> Void
    let onEditNote: (NoteItem) -> Void

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
                    Button("Open Note") { onEditNote(note) }
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
