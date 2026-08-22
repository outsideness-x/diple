import SwiftUI
import UniformTypeIdentifiers

public struct LibraryView: View {
    /// One book is visible in the hero and in the shelf at the same time, and a zoom
    /// transition needs an unambiguous source — so the placement is part of the id.
    private enum BookPlacement: String, Hashable {
        case continueReading
        case grid
        case list
    }

    /// Covers or rows. Persisted, like Notes' own layout choice, because it is a working
    /// preference rather than a navigation state.
    ///
    /// Rows are the default. The grid shows a cover, a title, a byline and a bar; the row shows
    /// all of that plus what kind of source it is, how long is left in it and what it was tagged
    /// with — and it can be filed with a thumb. Opening the library is far more often "what do I
    /// read next, and is there time" than "which spine am I looking for", and the answer to the
    /// first question is the one the shelf could not give. The grid stays a tap away, and stays
    /// the better view for recognising a book by its colour.
    private enum LibraryLayout: String {
        case grid
        case list
    }

    private struct BookRoute: Hashable {
        let book: Book
        let placement: BookPlacement

        var sourceID: String { "\(placement.rawValue):\(book.id)" }
    }

    @StateObject private var viewModel = LibraryViewModel()
    @State private var isFileImporterPresented = false
    @State private var isLinkImporterPresented = false

    @State private var overviewBook: Book?
    @State private var searchText = ""
    @State private var location: BookLocation = .inbox
    @State private var hasResolvedInitialLocation = false
    @State private var type: LibraryTypeFilter = .all
    @State private var status: LibraryStatusFilter = .any
    @State private var selectedTags: Set<String> = []
    @State private var tagEditingBook: Book?
    @State private var sort: LibrarySort = .recentlyOpened
    /// Rows push through this rather than through a `NavigationLink`. Inside a `List` a link
    /// draws a system disclosure chevron and reserves the gutter for it, which left the rows
    /// and the hero measurably narrower than the search field and chips above them — a right
    /// margin twice the left one. It is also the wrong texture: the card already reads as
    /// pressable, and the chevron is a second, louder claim to the same thing.
    @State private var path = NavigationPath()
    // Only the default moves. A reader who has already chosen a layout has that choice stored,
    // and a stored choice must outrank a changed default — otherwise shipping an opinion
    // silently overrides theirs.
    @AppStorage("diple_library_layout") private var layout: LibraryLayout = .list
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
            type: type,
            status: status,
            tags: selectedTags,
            sort: sort
        )
    }

    private var isDefaultBrowse: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && type == .all && status == .any && selectedTags.isEmpty
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

    /// Puts the just-imported source in front of the reader instead of only in a count.
    ///
    /// Reloading the library is not enough on its own, and that is the whole reason this exists:
    /// an import lands in the inbox, the shelf is standing wherever it was left — usually Later —
    /// and the only sign of the new book is the digit on a segment the reader is not looking at.
    /// From their side an import that cannot be seen is an import that failed, which is what was
    /// reported. Restarting the app appeared to fix it only because `selectInitialLocation
    /// IfNeeded` then picked the first non-empty location, and by then that was the inbox.
    ///
    /// Any narrowing that would hide it is dropped for the same reason: a shelf filtered to
    /// Finished, or to somebody else's tag, would show an empty page in answer to an import.
    /// `hasResolvedInitialLocation` is stamped so the first-appearance rule cannot immediately
    /// move the shelf somewhere else.
    private func reveal(_ book: Book) {
        hasResolvedInitialLocation = true
        location = book.location
        if !type.includes(book) { type = .all }
        if !status.includes(book) { status = .any }
        // A source arrives untagged, so any tag selected at all excludes it.
        selectedTags = []
        searchText = ""
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                if viewModel.books.isEmpty {
                    EmptyLibraryView(
                        onImportFile: { isFileImporterPresented = true },
                        onSaveLink: { isLinkImporterPresented = true }
                    )
                } else if layout == .grid {
                    gridBrowser
                } else {
                    listBrowser
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
                        NotificationCenter.default.post(name: .dipleOpenSettings, object: nil)
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
            // The shelf has to re-read the library every time the reader comes back to it: a
            // book imported from Home, or finished in the reader, changes what belongs here.
            .refreshesOnTabActivation { viewModel.loadBooks() }
            .onReceive(NotificationCenter.default.publisher(for: .dipleSourceDidImport)) { note in
                guard let book = note.dipleImportedBook else { return }
                reveal(book)
            }
            .onChange(of: viewModel.books.count) { _, _ in
                // The library loads asynchronously and can still be empty on first appearance,
                // in which case the initial choice has not been made yet.
                selectInitialLocationIfNeeded()
            }
        }
    }

    // MARK: - Browsers

    /// Covers. The default, because a library is recognised by its spines before its titles.
    private var gridBrowser: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DipleSpace.xxxl) {
                browseControls

                VStack(alignment: .leading, spacing: DipleSpace.m) {
                    shelfHeader

                    if visibleBooks.isEmpty {
                        emptyShelf
                    } else {
                        LazyVGrid(columns: columns, spacing: DipleSpace.xxl) {
                            ForEach(visibleBooks) { book in
                                let route = BookRoute(book: book, placement: .grid)
                                Button {
                                    path.append(route)
                                } label: {
                                    BookItemView(book: book)
                                        .bookActionsMenu(
                                            for: book,
                                            onShowOverview: { overviewBook = book },
                                            onMarkAsFinished: { viewModel.markAsFinished(book) },
                                            onMove: { viewModel.move(book, to: $0) },
                                            onEditTags: { tagEditingBook = book },
                                            onEdit: { viewModel.bookToEdit = book },
                                            onDelete: { viewModel.confirmDelete(book) }
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
        .tracksTabBarCollapse()
    }

    /// Rows, for triage rather than for browsing.
    ///
    /// This has to be a real `List`: `swipeActions` exists nowhere else, and filing a source
    /// with a thumb is the whole reason the layout exists. That is also why the hero and the
    /// control rows move *inside* it — a `List` nested in a `ScrollView` scrolls against
    /// itself — with their list chrome stripped off so they still read as part of the page
    /// rather than as rows of it.
    private var listBrowser: some View {
        List {
            Group {
                browseControls
                shelfHeader

                if visibleBooks.isEmpty {
                    emptyShelf
                }
            }
            .listRowInsets(EdgeInsets(
                top: DipleSpace.s,
                leading: DipleSpace.xl,
                bottom: DipleSpace.s,
                trailing: DipleSpace.xl
            ))
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)

            ForEach(visibleBooks) { book in
                let route = BookRoute(book: book, placement: .list)
                Button {
                    path.append(route)
                } label: {
                    LibraryRowView(
                        book: book,
                        tags: viewModel.tagsByBook[book.id] ?? [],
                        characters: viewModel.charactersByBook[book.id]
                    )
                    // The same menu the grid carries, on the same gesture. A row that answered
                    // a long press with three of the seven actions was the layout switch
                    // quietly taking Source Overview, Mark as Finished and Edit Metadata away;
                    // the swipes below stay the thumb-sized shortcut into this list, not a
                    // second, shorter version of it.
                    .bookActionsMenu(
                        for: book,
                        onShowOverview: { overviewBook = book },
                        onMarkAsFinished: { viewModel.markAsFinished(book) },
                        onMove: { viewModel.move(book, to: $0) },
                        onEditTags: { tagEditingBook = book },
                        onEdit: { viewModel.bookToEdit = book },
                        onDelete: { viewModel.confirmDelete(book) }
                    )
                }
                .buttonStyle(.bookCard)
                .matchedTransitionSource(id: route.sourceID, in: bookNamespace)
                // No vertical inset: the rows carry their own vertical padding and meet along
                // their rules, the way entries in a catalogue do. Spacing between cards would
                // reintroduce exactly the gaps the cards were removed to close.
                .listRowInsets(EdgeInsets(
                    top: 0,
                    leading: DipleSpace.xl,
                    bottom: 0,
                    trailing: DipleSpace.xl
                ))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .swipeActions(edge: .leading, allowsFullSwipe: true) {
                    ForEach(BookLocation.allCases.filter { $0 != book.location }, id: \.self) { destination in
                        Button {
                            viewModel.move(book, to: destination)
                        } label: {
                            Label(destination.title, systemImage: destination.systemImage)
                        }
                        .tint(destination == .archive ? DipleColor.textTertiary : DipleColor.accent)
                    }
                }
                .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                    // Routed through the confirmation the grid already uses. A full swipe that
                    // deleted a book and its file outright would be the one destructive action
                    // in the app without a second thought attached to it.
                    Button(role: .destructive) {
                        viewModel.confirmDelete(book)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }

                    Button {
                        tagEditingBook = book
                    } label: {
                        Label("Tags", systemImage: "number")
                    }
                    .tint(DipleColor.surfaceOverlay)
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, DipleSpace.scrollBottom, for: .scrollContent)
        .tracksTabBarCollapse()
    }

    /// The shelf no longer opens with the book you were reading.
    ///
    /// It did, and Home does too — the same lead, from the same `SourceLeadView`, one tab
    /// apart. Two screens answering "carry on from here" is one screen too many, and the cost
    /// fell on this one: between the search field, the lead, the location picker, the type
    /// chips, the tag row and the shelf heading, a reader met five rows of controls and a block
    /// about a book they were not looking for before the first cover appeared — nearly half the
    /// display. Home is where you carry on; the library is where you choose. It opens on the
    /// shelf now.
    ///
    /// `SourceLeadView` stays shared — Home still uses it, and the Mac shell has its own
    /// arrangement — so nothing is deleted, only this screen's use of it.

    @ViewBuilder
    private var browseControls: some View {
        VStack(alignment: .leading, spacing: DipleSpace.l) {
            locationPicker

            if viewModel.books.count > 1 {
                filterBar
            }

            if !viewModel.allTags.isEmpty {
                tagBar
            }
        }
    }

    private var shelfHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            sectionHeading(isDefaultBrowse ? location.title.uppercased() : "RESULTS")

            Spacer()

            Text("\(visibleBooks.count)")
                .dipleType(.micro)
                .foregroundStyle(DipleColor.textQuaternary)
                .monospacedDigit()

            layoutToggle
            filterMenu
        }
    }

    /// An empty shelf and a search that found nothing are different facts, and "Nothing Found"
    /// over a cleared inbox reads as a failure rather than as the goal.
    @ViewBuilder
    private var emptyShelf: some View {
        if isDefaultBrowse {
            emptyLocation
        } else {
            noResults
        }
    }

    private var layoutToggle: some View {
        Button {
            HapticManager.shared.selection()
            withAnimation(DipleMotion.standard) {
                layout = layout == .grid ? .list : .grid
            }
        } label: {
            Image(systemName: layout == .grid ? "list.bullet" : "square.grid.2x2")
                .dipleIcon(11, weight: .semibold)
                .foregroundStyle(DipleColor.textSecondary)
                .diplePadding(.chip)
                .background(DipleColor.surfaceOverlay, in: Capsule())
        }
        .buttonStyle(.readerControl)
        .accessibilityLabel(layout == .grid ? "Switch to list" : "Switch to covers")
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
                ForEach(LibraryTypeFilter.allCases) { option in
                    Button {
                        HapticManager.shared.selection()
                        withAnimation(DipleMotion.standard) {
                            type = option
                        }
                    } label: {
                        Text(option.rawValue)
                            .dipleType(.micro)
                            .foregroundStyle(type == option ? DipleColor.textOnAccent : DipleColor.textTertiary)
                            .diplePadding(.chip)
                            .background(type == option ? DipleColor.accent : DipleColor.surfaceOverlay)
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

    /// Status and sort in one menu, not two controls.
    ///
    /// Location, type and tags each already have a visible row; putting status and sort out as
    /// separate chips too would give the header four controls, and at accessibility text sizes
    /// the section heading and the count lose that fight long before the controls do. They pair
    /// naturally anyway — both answer "how should this shelf be presented" rather than "what is
    /// on it".
    ///
    /// The label prints the chosen status when there is one. A filter that is on but invisible
    /// is a library that looks broken.
    private var filterMenu: some View {
        Menu {
            Picker("Status", selection: $status) {
                ForEach(LibraryStatusFilter.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }

            Picker("Sort Library", selection: $sort) {
                ForEach(LibrarySort.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
        } label: {
            HStack(spacing: DipleSpace.xs) {
                Image(systemName: status == .any ? "arrow.up.arrow.down" : "line.3.horizontal.decrease")
                    .dipleIcon(10, weight: .semibold)
                Text(status.compactTitle ?? sort.compactTitle)
                    .dipleType(.micro, weight: .semibold)
            }
            .foregroundStyle(status == .any ? DipleColor.textSecondary : DipleColor.textOnAccent)
            .diplePadding(.chip)
            .background(status == .any ? DipleColor.surfaceOverlay : DipleColor.accent, in: Capsule())
        }
        .buttonStyle(.readerControl)
        .accessibilityLabel("Filter and sort")
        .accessibilityValue("\(status.rawValue), \(sort.rawValue)")
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
                type = .all
                status = .any
                selectedTags = []
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
