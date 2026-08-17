import SwiftUI
import UniformTypeIdentifiers

public struct LibraryView: View {
    private enum BookPlacement: String, Hashable {
        case continueReading
        case grid
    }

    private struct BookRoute: Hashable {
        let book: Book
        let placement: BookPlacement

        var sourceID: String { "\(placement.rawValue):\(book.id)" }
    }

    @StateObject private var viewModel = LibraryViewModel()
    @State private var isFileImporterPresented = false
    @State private var isLinkImporterPresented = false

    @State private var isAppSettingsPresented = false
    @State private var overviewBook: Book?
    @State private var searchText = ""
    @State private var location: BookLocation = .inbox
    @State private var hasResolvedInitialLocation = false
    @State private var filter: LibraryFilter = .all
    @State private var selectedTags: Set<String> = []
    @State private var tagEditingBook: Book?
    @State private var sort: LibrarySort = .recentlyOpened
    @Namespace private var bookNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// A 140–180 pt column holds a two-line title at normal sizes and about one word of it at
    /// accessibility sizes, where the grid kept its two columns and truncated instead —
    /// "A Simplified View of th…". The card gets a full measure there and the grid gives up a
    /// column, the same trade Notes already makes on a phone.
    /// `alignment: .top` is load-bearing. `GridItem` centres its cell by default, so a card
    /// whose title runs to one line sat lower than its neighbour whose title ran to two — the
    /// covers in a row started at different heights, which is the one thing a grid of covers
    /// must not do. It reads as a rendering fault rather than as a choice.
    private var columns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.adaptive(minimum: 260), spacing: 20, alignment: .top)]
            : [GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 20, alignment: .top)]
    }

    public init() {}

    private var visibleBooks: [Book] {
        viewModel.visibleBooks(
            query: searchText,
            location: location,
            filter: filter,
            tags: selectedTags,
            sort: sort
        )
    }

    private var isDefaultBrowse: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filter == .all && selectedTags.isEmpty
    }

    /// Opening the library on an empty inbox is the normal state of an upgraded install — the
    /// v15 backfill deliberately leaves the inbox empty — and it would look like the library
    /// had been wiped. So the first appearance lands on the first location that actually holds
    /// something. It runs once: after the reader has touched the picker, their choice stands
    /// even when they empty the shelf they are standing on.
    private func selectInitialLocationIfNeeded() {
        guard !hasResolvedInitialLocation, !viewModel.books.isEmpty else { return }
        hasResolvedInitialLocation = true
        if let first = BookLocation.allCases.first(where: { viewModel.count(in: $0) > 0 }) {
            location = first
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                if viewModel.books.isEmpty {
                    EmptyLibraryView(
                        onImportFile: { isFileImporterPresented = true },
                        onSaveLink: { isLinkImporterPresented = true }
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: DipleSpace.xxxl) {
                            if isDefaultBrowse, let book = viewModel.continueReadingBook {
                                VStack(alignment: .leading, spacing: DipleSpace.m) {
                                    sectionHeading("CONTINUE READING")

                                    let route = BookRoute(book: book, placement: .continueReading)
                                    NavigationLink(value: route) {
                                        ContinueReadingCard(book: book)
                                    }
                                    .buttonStyle(.bookCard)
                                    .matchedTransitionSource(id: route.sourceID, in: bookNamespace)
                                    .accessibilityHint("Opens at your last reading position")
                                }
                            }

                            locationPicker

                            if viewModel.books.count > 1 {
                                filterBar
                            }

                            if !viewModel.allTags.isEmpty {
                                tagBar
                            }

                            VStack(alignment: .leading, spacing: DipleSpace.m) {
                                HStack(alignment: .firstTextBaseline) {
                                    sectionHeading(isDefaultBrowse ? location.title.uppercased() : "RESULTS")

                                    Spacer()

                                    Text("\(visibleBooks.count)")
                                        .dipleType(.micro)
                                        .foregroundStyle(DipleColor.textQuaternary)
                                        .monospacedDigit()

                                    sortMenu
                                }

                                if visibleBooks.isEmpty {
                                    // An empty shelf and a search that found nothing are
                                    // different facts, and "Nothing Found" over a cleared inbox
                                    // reads as a failure rather than as the goal.
                                    if isDefaultBrowse {
                                        emptyLocation
                                    } else {
                                        noResults
                                    }
                                } else {
                                    LazyVGrid(columns: columns, spacing: DipleSpace.xxl) {
                                        ForEach(visibleBooks) { book in
                                            let route = BookRoute(book: book, placement: .grid)
                                            NavigationLink(value: route) {
                                                BookItemView(
                                                    book: book,
                                                    onMarkAsFinished: {
                                                        viewModel.markAsFinished(book)
                                                    },
                                                    onShowOverview: {
                                                        overviewBook = book
                                                    },
                                                    onMove: { destination in
                                                        viewModel.move(book, to: destination)
                                                    },
                                                    onEditTags: {
                                                        tagEditingBook = book
                                                    },
                                                    onEdit: {
                                                        viewModel.bookToEdit = book
                                                    },
                                                    onDelete: {
                                                        viewModel.confirmDelete(book)
                                                    }
                                                )
                                            }
                                            .buttonStyle(.bookCard)
                                            .matchedTransitionSource(id: route.sourceID, in: bookNamespace)
                                        }
                                    }
                                }
                            }
                        }
                        .padding(.horizontal, DipleSpace.xl)
                        .padding(.top, DipleSpace.l)
                        .padding(.bottom, DipleSpace.scrollBottom)
                    }
                }

                if viewModel.isImporting {
                    ZStack {
                        DipleColor.canvas.opacity(0.75).ignoresSafeArea()
                        VStack(spacing: DipleSpace.m) {
                            ProgressView()
                                .tint(DipleColor.accent)
                            Text("Importing book...")
                                .dipleType(.callout, weight: .medium)
                                .foregroundStyle(DipleColor.textPrimary)
                        }
                        .padding(DipleSpace.xxl)
                        .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.l)
                    }
                }
            }
            .navigationTitle("diple.")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Title, author or source"
            )
            // Titles and authors are matched, not written: sentence capitalisation and
            // autocorrect only get in the way of a filter typed a letter at a time.
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        HapticManager.shared.selection()
                        isAppSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                            .dipleIcon(16)
                            .foregroundStyle(DipleColor.textSecondary)
                    }
                    .buttonStyle(.readerControl)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Menu {
                        Button {
                            isLinkImporterPresented = true
                        } label: {
                            Label("Save a Link", systemImage: "link")
                        }

                        Button {
                            isFileImporterPresented = true
                        } label: {
                            Label("Import a File", systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .dipleIcon(16)
                            .foregroundStyle(DipleColor.accent)
                    }
                    .buttonStyle(.readerControl)
                    .simultaneousGesture(TapGesture().onEnded {
                        HapticManager.shared.selection()
                    })
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.epub, .pdf],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    viewModel.importBook(from: url)
                case .failure(let error):
                    viewModel.errorMessage = "Import failed: \(error.localizedDescription)"
                    viewModel.showErrorAlert = true
                }
            }
            .alert("Error", isPresented: $viewModel.showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred.")
            }
            .alert("Delete Book?", isPresented: $viewModel.showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    viewModel.deleteConfirmedBook()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let book = viewModel.bookToDelete {
                    Text("Are you sure you want to delete '\(book.title)'? This will remove the book file and metadata. Its quotes will remain in Quotes, where you can delete them manually.")
                }
            }
            .navigationDestination(for: BookRoute.self) { route in
                readerDestination(for: route)
            }
            .sheet(isPresented: $isAppSettingsPresented) {
                AppSettingsView()
            }
            .sheet(isPresented: $isLinkImporterPresented) {
                ImportLinkSheetView { _ in
                    viewModel.loadBooks()
                }
            }
            .sheet(item: $viewModel.bookToEdit) { book in
                EditBookMetadataView(book: book) { newTitle, newAuthor, coverData in
                    viewModel.updateMetadata(for: book.id, title: newTitle, author: newAuthor, coverData: coverData)
                }
            }
            .sheet(item: $overviewBook) { book in
                SourceOverviewView(book: book) {
                    viewModel.loadBooks()
                }
            }
            .sheet(item: $tagEditingBook) { book in
                BookTagsSheetView(
                    book: book,
                    tags: viewModel.tagsByBook[book.id] ?? [],
                    suggestions: viewModel.allTags
                ) { tags in
                    viewModel.setTags(tags, for: book)
                }
            }
            .onAppear(perform: selectInitialLocationIfNeeded)
            .onChange(of: viewModel.books.count) { _, _ in
                // The library loads asynchronously and can still be empty on first appearance,
                // in which case the initial choice has not been made yet.
                selectInitialLocationIfNeeded()
            }
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .dipleType(.micro, weight: .semibold)
            .foregroundStyle(DipleColor.textTertiary)
    }

    @ViewBuilder
    private func readerDestination(for route: BookRoute) -> some View {
        let reader = ReaderContainerView(book: route.book, onReadingUpdated: {
            viewModel.loadBooks()
        })

        if reduceMotion {
            reader
        } else {
            reader.navigationTransition(.zoom(sourceID: route.sourceID, in: bookNamespace))
        }
    }

    /// The queue, as three places rather than three filters.
    ///
    /// A segmented control rather than another chip row: location is where you *are*, and the
    /// chips below narrow what you see once you are there. Two rows of identical capsules would
    /// have flattened that difference into one undifferentiated wall of filters.
    ///
    /// The count rides inside the segment label instead of a badge beside it, because a badge
    /// would either be clipped by the segment or push the label out of it at large Dynamic Type.
    private var locationPicker: some View {
        Picker("Location", selection: $location) {
            ForEach(BookLocation.allCases, id: \.self) { option in
                let count = viewModel.count(in: option)
                Text(count > 0 ? "\(option.title) \(count)" : option.title)
                    .tag(option)
            }
        }
        .pickerStyle(.segmented)
        .onChange(of: location) { _, _ in
            HapticManager.shared.selection()
        }
        .accessibilityLabel("Reading queue")
    }

    private var emptyLocation: some View {
        VStack(spacing: DipleSpace.m) {
            Image(systemName: location.systemImage)
                .dipleIcon(24, weight: .light)
                .foregroundStyle(DipleColor.accent)

            Text(emptyLocationTitle)
                .dipleType(.headline)
                .foregroundStyle(DipleColor.textPrimary)

            Text(emptyLocationDetail)
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DipleSpace.xxxl)
    }

    private var emptyLocationTitle: String {
        switch location {
        case .inbox: return "Inbox is clear"
        case .later: return "Nothing saved for later"
        case .archive: return "Archive is empty"
        }
    }

    private var emptyLocationDetail: String {
        switch location {
        case .inbox: return "Everything you saved has been sorted. New links and files land here first."
        case .later: return "Move something here from the inbox and it will wait for you without nagging."
        case .archive: return "Finished with something? Archive it and the library stops offering it back."
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DipleSpace.s) {
                ForEach(LibraryFilter.allCases) { option in
                    Button {
                        HapticManager.shared.selection()
                        withAnimation(DipleMotion.standard) {
                            filter = option
                        }
                    } label: {
                        Text(option.rawValue)
                            .dipleType(.micro)
                            .foregroundStyle(filter == option ? DipleColor.textOnAccent : DipleColor.textTertiary)
                            .diplePadding(.chip)
                            .background(filter == option ? DipleColor.accent : DipleColor.surfaceOverlay)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .accessibilityLabel("Library filters")
    }

    /// Tags get a row of their own rather than joining the type chips above.
    ///
    /// They are a different axis: type asks what a source *is*, a tag is what the reader
    /// decided it is about, and a source has exactly one type but any number of tags. Mixing
    /// them into one strip of identical capsules would say they are alternatives to each other,
    /// and tapping two of them would then look like it should widen the result rather than
    /// narrow it. Multi-select and the outline treatment both come from that.
    private var tagBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DipleSpace.s) {
                ForEach(viewModel.allTags, id: \.self) { tag in
                    Button {
                        HapticManager.shared.selection()
                        withAnimation(DipleMotion.standard) {
                            if selectedTags.contains(tag) {
                                selectedTags.remove(tag)
                            } else {
                                selectedTags.insert(tag)
                            }
                        }
                    } label: {
                        TagChipView(label: tag, kind: .text, isSelected: selectedTags.contains(tag))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .accessibilityLabel("Tag filters")
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort Library", selection: $sort) {
                ForEach(LibrarySort.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
        } label: {
            HStack(spacing: DipleSpace.xs) {
                Image(systemName: "arrow.up.arrow.down")
                    .dipleIcon(10, weight: .semibold)
                Text(sort.compactTitle)
                    .dipleType(.micro, weight: .semibold)
            }
            .foregroundStyle(DipleColor.textSecondary)
            .diplePadding(.chip)
            .background(DipleColor.surfaceOverlay, in: Capsule())
        }
        .buttonStyle(.readerControl)
        .accessibilityLabel("Sort Library")
        .accessibilityValue(sort.rawValue)
    }

    private var noResults: some View {
        VStack(spacing: DipleSpace.m) {
            Image(systemName: "magnifyingglass")
                .dipleIcon(24, weight: .light)
                .foregroundStyle(DipleColor.textQuaternary)

            Text("Nothing Found")
                .dipleType(.headline)
                .foregroundStyle(DipleColor.textPrimary)

            Text("Try another title, author, source or reading status.")
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
                .multilineTextAlignment(.center)

            Button("Clear Search and Filters") {
                searchText = ""
                filter = .all
                HapticManager.shared.selection()
            }
            .dipleType(.footnote, weight: .semibold)
            .foregroundStyle(DipleColor.accent)
            .buttonStyle(.readerControl)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DipleSpace.xxxl)
    }
}

/// The one unfinished publication most likely to be opened next. Unlike a grid tile, this is
/// a reading state: cover, identity, progress and a single continuation affordance.
private struct ContinueReadingCard: View {
    let book: Book

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var coverWidth: CGFloat = 72

    /// The thumbnail scales with Dynamic Type so it stays in proportion to the title beside
    /// it, but only up to a point: this is a side-by-side card, and every point the cover
    /// takes comes out of the text's measure. Unclamped it reached ~140 pt at accessibility
    /// sizes, leaving the title barely a word per line — "A" over "Simplifie…" — and the
    /// byline truncated to "James O'…". Past about half again its size the cover has stopped
    /// helping anyone recognise the book and started hiding its name.
    private var clampedCoverWidth: CGFloat {
        min(coverWidth, 108)
    }

    // Furthest-read, not the live saved position — see "Прогресс чтения: `furthestProgress` и
    // live-позиция" in CLAUDE.md.
    private var clampedProgress: CGFloat {
        CGFloat(min(max(book.furthestProgress, 0), 1))
    }

    var body: some View {
        HStack(spacing: DipleSpace.l) {
            BookCoverView(
                coverPath: book.coverPath,
                title: book.title,
                author: book.author,
                isCompact: true
            )
            .frame(width: clampedCoverWidth, height: clampedCoverWidth * 1.5)

            VStack(alignment: .leading, spacing: DipleSpace.s) {
                VStack(alignment: .leading, spacing: DipleSpace.xs) {
                    Text(book.title)
                        .dipleType(.headline)
                        .foregroundStyle(DipleColor.textPrimary)
                        // Two lines hold a title at normal sizes and cut one in half at
                        // accessibility sizes; the card is free to grow taller instead.
                        .lineLimit(dynamicTypeSize.isAccessibilitySize ? 4 : 2)
                        .multilineTextAlignment(.leading)

                    BookSubtitleView(book: book)
                }

                Spacer(minLength: DipleSpace.xs)

                HStack(spacing: DipleSpace.s) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(DipleColor.surfaceOverlay)
                            Capsule()
                                .fill(DipleColor.accent)
                                .frame(width: geometry.size.width * clampedProgress)
                                .craftGlow(DipleColor.accent.opacity(0.5), radius: DipleSpace.xs)
                        }
                    }
                    .frame(height: DipleSpace.xs)

                    Text("\(Int((clampedProgress * 100).rounded()))%")
                        .dipleType(.micro, weight: .semibold)
                        .foregroundStyle(DipleColor.accent)
                        .monospacedDigit()
                }

                HStack(spacing: DipleSpace.xs) {
                    Text("Continue")
                        .dipleType(.footnote, weight: .semibold)
                    Image(systemName: "arrow.right")
                        .dipleIcon(11, weight: .semibold)
                }
                .foregroundStyle(DipleColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DipleSpace.m)
        .background(alignment: .topTrailing) {
            RadialGradient(
                colors: [DipleColor.accent.opacity(0.12), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 180
            )
        }
        .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.l)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(Int((clampedProgress * 100).rounded())) percent read")
    }
}
