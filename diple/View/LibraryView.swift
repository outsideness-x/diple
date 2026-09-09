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

    private struct SecondReadRoute: Hashable {
        let book: Book
    }

    @StateObject private var viewModel = LibraryViewModel()
    @State private var isFileImporterPresented = false
    @State private var isLinkImporterPresented = false

    @State private var overviewBook: Book?
    @State private var searchText = ""
    /// Whether the field is on the page. It is not, at rest.
    ///
    /// A shelf is browsed far more often than it is searched, and a field resting on it
    /// costs ~56 pt of the page every time it is not being used — on this screen that was
    /// the difference between meeting the chrome budget and missing it. Summoned from the
    /// shelf heading, where the other two controls over "how this shelf is presented"
    /// already live, and it stays for as long as there is a query in it.
    @State private var isSearchFieldShown = false
    @FocusState private var isSearchFocused: Bool
    @State private var location: BookLocation = .inbox
    @State private var hasResolvedInitialLocation = false
    @State private var type: LibraryTypeFilter = .all
    @State private var status: LibraryStatusFilter = .any
    @State private var selectedTags: Set<String> = []
    @State private var tagEditingBook: Book?
    @State private var tagDraft = ""
    @State private var isAddingTagToSelection = false
    @State private var isConfirmingBulkDelete = false
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

    /// The chosen sources **that are also on the shelf as it currently stands**.
    ///
    /// Narrowing the shelf does not un-choose anything, but it does take it out of reach: every
    /// action reads this, and so does the count on the bar, so what the bar says is always what
    /// the button will do. The board's selection is written to the same rule.
    private var selectedBooks: [Book] {
        visibleBooks.filter { viewModel.isSelected($0) }
    }

    private var isEverythingSelected: Bool {
        !visibleBooks.isEmpty && selectedBooks.count == visibleBooks.count
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
                            Text("Adding to your library…")
                                .dipleType(.callout, weight: .medium)
                                .foregroundStyle(DipleColor.textPrimary)
                        }
                        .padding(DipleSpace.xxl)
                        .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.l)
                    }
                }
            }
            // Set but hidden: it is what a pushed screen labels its own back button with.
            // The shelf prints its own name in the masthead instead — the wordmark belongs on
            // the front page, not in the running head of every screen.
            .navigationTitle("Library")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
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
            .alert("Delete book?", isPresented: $viewModel.showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    viewModel.deleteConfirmedBook()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let book = viewModel.bookToDelete {
                    Text("The file and your reading position are removed. Saved passages stay in Highlights.")
                }
            }
            .navigationDestination(for: BookRoute.self) { route in
                readerDestination(for: route)
            }
            .navigationDestination(for: SecondReadRoute.self) { route in
                SecondReadView(book: route.book) {
                    viewModel.loadBooks()
                }
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
            .safeAreaInset(edge: .bottom, spacing: 0) {
                if viewModel.isSelecting {
                    selectionBar
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .modifier(HidesTabBarWhileSelecting(isSelecting: viewModel.isSelecting))
            .alert("Add a tag", isPresented: $isAddingTagToSelection) {
                TextField("Tag", text: $tagDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Add") {
                    viewModel.addTag(tagDraft, to: selectedBooks)
                    viewModel.endSelecting()
                    tagDraft = ""
                }
                Button("Cancel", role: .cancel) { tagDraft = "" }
            } message: {
                Text("The word is added to each chosen source. Nothing already there is replaced.")
            }
            .alert("Delete \(selectedBooks.count) sources?", isPresented: $isConfirmingBulkDelete) {
                Button("Delete", role: .destructive) {
                    viewModel.delete(selectedBooks)
                    viewModel.endSelecting()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The files and your reading positions are removed. Saved passages stay in Highlights.")
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
                masthead
                browseControls

                VStack(alignment: .leading, spacing: DipleSpace.m) {
                    shelfHeader

                    if visibleBooks.isEmpty {
                        emptyShelf
                    } else {
                        LazyVGrid(columns: columns, spacing: DipleSpace.xxl) {
                            ForEach(visibleBooks) { book in
                                gridTile(book)
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
                masthead
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
                listRow(book)
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
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .contentMargins(.bottom, DipleSpace.scrollBottom, for: .scrollContent)
        .tracksTabBarCollapse()
    }

    // MARK: - A source, chosen or opened

    /// The mark sits in a fixed leading column that every row gets, chosen or not, so the left
    /// edge of the shelf stays flush while choosing. A check that appears only on the chosen
    /// rows makes the column shuffle sideways under the thumb on every tap — written down once
    /// already on the board, and true here for the same reason.
    @ViewBuilder
    private func listRow(_ book: Book) -> some View {
        if viewModel.isSelecting {
            let isSelected = viewModel.isSelected(book)
            Button {
                HapticManager.shared.selection()
                withAnimation(DipleMotion.snappy) { viewModel.toggleSelection(book) }
            } label: {
                HStack(alignment: .top, spacing: DipleSpace.m) {
                    selectionMark(isSelected)
                        .padding(.top, DipleSpace.xl)

                    LibraryRowView(
                        book: book,
                        tags: viewModel.tagsByBook[book.id] ?? [],
                        characters: viewModel.charactersByBook[book.id]
                    )
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        } else {
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
                    onSelect: { beginSelecting(with: book) },
                    onShowOverview: { overviewBook = book },
                    onOpenSecondRead: { path.append(SecondReadRoute(book: book)) },
                    onMarkAsFinished: { viewModel.markAsFinished(book) },
                    onMove: { viewModel.move(book, to: $0) },
                    onEditTags: { tagEditingBook = book },
                    onEdit: { viewModel.bookToEdit = book },
                    onDelete: { viewModel.confirmDelete(book) }
                )
            }
            .buttonStyle(.bookCard)
            .matchedTransitionSource(id: route.sourceID, in: bookNamespace)
            // The swipes belong to the browsing row and not to the chosen one: while choosing,
            // the bar below already carries move, tag and delete for the whole stack, and a
            // thumb shortcut that reached one book in the middle of that would be a second
            // answer to a question the reader has already asked differently.
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

    /// On the shelf the mark cannot take a column of its own — a cover is the whole tile — so it
    /// sits on the corner of the cover, over a disc that keeps it legible against artwork of any
    /// colour. The unchosen tile still draws its ring, for the same reason the row keeps its
    /// column: nothing may move when it is tapped.
    @ViewBuilder
    private func gridTile(_ book: Book) -> some View {
        if viewModel.isSelecting {
            let isSelected = viewModel.isSelected(book)
            Button {
                HapticManager.shared.selection()
                withAnimation(DipleMotion.snappy) { viewModel.toggleSelection(book) }
            } label: {
                BookItemView(book: book)
                    .overlay(alignment: .topTrailing) {
                        selectionMark(isSelected)
                            .padding(DipleSpace.s)
                    }
                    .opacity(isSelected ? 1 : 0.72)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? [.isSelected] : [])
        } else {
            let route = BookRoute(book: book, placement: .grid)
            Button {
                path.append(route)
            } label: {
                BookItemView(book: book)
                    .bookActionsMenu(
                        for: book,
                        onSelect: { beginSelecting(with: book) },
                        onShowOverview: { overviewBook = book },
                        onOpenSecondRead: { path.append(SecondReadRoute(book: book)) },
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

    private func selectionMark(_ isSelected: Bool) -> some View {
        Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
            .dipleIcon(18, weight: .regular)
            .foregroundStyle(isSelected ? DipleColor.accentInk : DipleColor.textQuaternary)
            .frame(width: 22)
    }

    private func beginSelecting(with book: Book) {
        HapticManager.shared.selection()
        withAnimation(DipleMotion.standard) { viewModel.beginSelecting(with: book) }
    }

    // MARK: - The workbench

    /// What can be done to the sources that were chosen.
    ///
    /// It takes the tab bar's place rather than floating above it — choosing is a mode with one
    /// way out, and leaving navigation live underneath it would offer three ways to abandon a
    /// selection without saying that is what they do. The board's bar is built the same way,
    /// because it is the same mode.
    ///
    /// Move comes first and is the filled action: the shelf is a queue, and a stack of books is
    /// chosen in order to be *put somewhere*. Tag and delete are the two the board also carries.
    private var selectionBar: some View {
        let chosen = selectedBooks.count

        return HStack(spacing: DipleSpace.s) {
            Menu {
                ForEach(BookLocation.allCases, id: \.self) { destination in
                    Button {
                        viewModel.move(selectedBooks, to: destination)
                        viewModel.endSelecting()
                    } label: {
                        Label("Move to \(destination.title)", systemImage: destination.systemImage)
                    }
                }
            } label: {
                HStack(spacing: DipleSpace.s) {
                    Image(systemName: "tray.full")
                        .dipleIcon(14, weight: .semibold)
                    Text(chosen == 0 ? "Move" : "Move \(chosen)")
                        .dipleType(.footnote, weight: .semibold)
                }
                .foregroundStyle(DipleColor.textOnAccent)
                .frame(maxWidth: .infinity, minHeight: 46)
                .background(DipleColor.accent, in: Capsule())
            }
            .buttonStyle(.readerControl)

            selectionAction("number", label: "Add a tag to all") {
                tagDraft = ""
                isAddingTagToSelection = true
            }

            selectionAction("trash", label: "Delete all", isDestructive: true) {
                isConfirmingBulkDelete = true
            }
        }
        .disabled(chosen == 0)
        .opacity(chosen == 0 ? 0.5 : 1)
        .animation(DipleMotion.standard, value: chosen == 0)
        .padding(.horizontal, DipleSpace.xl)
        .padding(.vertical, DipleSpace.m)
        .background(.ultraThinMaterial)
    }

    private func selectionAction(
        _ systemImage: String,
        label: String,
        isDestructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .dipleIcon(15, weight: .semibold)
                .foregroundStyle(isDestructive ? DipleColor.destructive : DipleColor.textSecondary)
                .frame(width: 46, height: 46)
                .background(DipleColor.surfaceOverlay, in: Circle())
        }
        .buttonStyle(.readerControl)
        .accessibilityLabel(label)
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

    /// The head of the shelf.
    ///
    /// Scrolls with the page rather than sitting in a bar above it, which is why it is a row of
    /// the browser rather than a `toolbar`: a masthead is the top of the page, not furniture
    /// bolted over it.
    private var masthead: some View {
        DipleMasthead(
            title: "Library",
            strapline: viewModel.isSelecting ? selectionStrapline : strapline
        ) {
            if viewModel.isSelecting {
                selectionMastheadActions
            } else {
                browsingMastheadActions
            }
        }
    }

    @ViewBuilder
    private var browsingMastheadActions: some View {
        Menu {
            Button {
                isLinkImporterPresented = true
            } label: {
                Label("Save a link", systemImage: "link")
            }

            Button {
                isFileImporterPresented = true
            } label: {
                Label("Import a file", systemImage: "folder")
            }
        } label: {
            MastheadGlyph(systemImage: "plus")
        }
        .buttonStyle(.readerControl)
        .accessibilityLabel("Add to your library")
        .simultaneousGesture(TapGesture().onEnded {
            HapticManager.shared.selection()
        })

        MastheadButton(systemImage: "gearshape", label: "Settings") {
            NotificationCenter.default.post(name: .dipleOpenSettings, object: nil)
        }
    }

    /// The one way out of choosing, and the one shortcut into choosing everything. Both are
    /// words rather than glyphs: `All` and `Done` are what every list on this platform calls
    /// them, and a mode with an invented icon for its exit is a mode readers leave by force
    /// quitting.
    @ViewBuilder
    private var selectionMastheadActions: some View {
        Button {
            HapticManager.shared.selection()
            withAnimation(DipleMotion.snappy) {
                if isEverythingSelected {
                    viewModel.clearSelection()
                } else {
                    viewModel.select(visibleBooks)
                }
            }
        } label: {
            Text(isEverythingSelected ? "None" : "All")
                .dipleType(.footnote, weight: .semibold)
                .foregroundStyle(DipleColor.textSecondary)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.readerControl)
        .accessibilityLabel(isEverythingSelected ? "Deselect all" : "Select all")

        Button {
            HapticManager.shared.selection()
            withAnimation(DipleMotion.standard) { viewModel.endSelecting() }
        } label: {
            Text("Done")
                .dipleType(.footnote, weight: .semibold)
                .foregroundStyle(DipleColor.accentInk)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.readerControl)
    }

    /// While choosing, the count under the name is the count of what is chosen — the library
    /// total is not the question being asked.
    private var selectionStrapline: String {
        let chosen = selectedBooks.count
        return chosen == 1 ? "1 chosen" : "\(chosen) chosen"
    }

    /// What the whole library holds, not what the current shelf shows — the count under the
    /// name answers "how much is in here", and the shelf heading below already answers "how
    /// much of it is on this shelf".
    private var strapline: String {
        let total = viewModel.books.count
        let unread = viewModel.books.filter { LibraryStatusFilter.unread.includes($0) }.count
        let sources = total == 1 ? "1 source" : "\(total) sources"
        return unread > 0 ? "\(sources) · \(unread) unread" : sources
    }

    /// Two rows where there used to be four.
    ///
    /// The type chips and the tag row both moved into `filterMenu`. Neither is a frequent
    /// choice, and each was costing a permanent row of the page: with the search field, the
    /// location rule, the chips, the tags and the shelf heading, a reader met five rows of
    /// control before the first cover — measured at 326 pt of an 874 pt display, which is the
    /// same complaint that removed the lead from this screen and did not go away when it did.
    ///
    /// The field sits *under* the rubric rather than over it, because it narrows what is on
    /// the shelf below rather than leading anywhere; a field placed above the thing it searches
    /// reads as a way out of the screen, and there is a whole tab for that.
    @ViewBuilder
    private var browseControls: some View {
        VStack(alignment: .leading, spacing: DipleSpace.l) {
            locationPicker

            if isSearchFieldShown || !searchText.isEmpty {
                DipleSearchField(
                    text: $searchText,
                    prompt: "Title, author or source",
                    identifier: "library.search"
                )
                .focused($isSearchFocused)
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear { isSearchFocused = true }
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

            searchToggle
            layoutToggle
            filterMenu
        }
    }

    /// Puts the field on the page, or takes it off and clears what was in it — leaving a query
    /// behind on a field nobody can see is a shelf that looks broken for no visible reason.
    private var searchToggle: some View {
        Button {
            HapticManager.shared.selection()
            withAnimation(DipleMotion.standard) {
                if isSearchFieldShown || !searchText.isEmpty {
                    searchText = ""
                    isSearchFieldShown = false
                    isSearchFocused = false
                } else {
                    isSearchFieldShown = true
                }
            }
        } label: {
            Image(systemName: isSearchFieldShown || !searchText.isEmpty ? "xmark" : "magnifyingglass")
                .dipleIcon(11, weight: .semibold)
                .foregroundStyle(DipleColor.textSecondary)
                .diplePadding(.chip)
                .background(DipleColor.surfaceOverlay, in: Capsule())
        }
        .buttonStyle(.readerControl)
        .accessibilityLabel(isSearchFieldShown || !searchText.isEmpty ? "Close search" : "Search the library")
    }

    /// An empty shelf and a search that found nothing are different facts, and "Nothing found"
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
    /// Set as a rubric, not as a control. It was a system `Picker(.segmented)` — the only piece
    /// of stock UIKit on the screen, and it read as one: a settings widget where the page wanted
    /// a section head. A section is announced in type. The current place is set at full strength
    /// with a rule under it, the two you might go to are dimmed, and nothing is boxed.
    ///
    /// The distinction the segmented control was there to protect still holds and is now carried
    /// by the difference in kind rather than by the difference in shape: location is *where you
    /// are*, and everything in the filter menu narrows what you see once you are there.
    ///
    /// The count rides as a superior figure rather than in the label, because "Inbox 2" reads as
    /// a name containing a number and `Inbox²` reads as a name with a count attached.
    private var locationPicker: some View {
        HStack(alignment: .bottom, spacing: DipleSpace.xl) {
            ForEach(BookLocation.allCases, id: \.self) { option in
                locationSegment(option)
            }
            Spacer(minLength: 0)
        }
        .accessibilityLabel("Reading queue")
    }

    private func locationSegment(_ option: BookLocation) -> some View {
        let isSelected = location == option
        let count = viewModel.count(in: option)
        return Button {
            guard !isSelected else { return }
            HapticManager.shared.selection()
            withAnimation(DipleMotion.standard) { location = option }
        } label: {
            HStack(alignment: .top, spacing: DipleSpace.hair) {
                Text(option.title)
                    .dipleType(.headline, weight: isSelected ? .semibold : .regular)

                if count > 0 {
                    Text("\(count)")
                        .dipleType(.tag)
                        .monospacedDigit()
                        .baselineOffset(7)
                }
            }
            .foregroundStyle(isSelected ? DipleColor.textPrimary : DipleColor.textQuaternary)
            .padding(.bottom, DipleSpace.s)
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(isSelected ? DipleColor.accent : Color.clear)
                    .frame(height: DipleStroke.selection)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.readerControl)
        .accessibilityLabel(count > 0 ? "\(option.title), \(count)" : option.title)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    private var emptyLocation: some View {
        VStack(spacing: DipleSpace.m) {
            Image(systemName: location.systemImage)
                .dipleIcon(24, weight: .light)
                .foregroundStyle(DipleColor.accentInk)

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

    /// Everything that narrows the shelf, in one control.
    ///
    /// Four things live here now: what a source *is* (type), how far into it the reader got
    /// (status), what they filed it under (tags) and how the shelf is ordered. Type and tags
    /// used to be permanent rows of capsules on the page. They are low-frequency choices — a
    /// reader picks a type or a tag occasionally and browses constantly — and each was costing
    /// a row of the page every time it was not being used.
    ///
    /// Type and tags remain different axes and are still not offered as if they were
    /// alternatives to each other: a source has exactly one type, so type is a `Picker`, while
    /// tags are any number and so are toggles. Selecting two tags narrows (AND), as it always
    /// did — a filter that widened on a second tap would not be a filter.
    ///
    /// The label prints what is on. A filter that is active but invisible is a library that
    /// looks broken, and that is now truer than it was, because none of these has a chip on
    /// the page to speak for it.
    private var filterMenu: some View {
        Menu {
            Picker("Type", selection: $type) {
                ForEach(LibraryTypeFilter.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }

            Picker("Status", selection: $status) {
                ForEach(LibraryStatusFilter.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }

            if !viewModel.allTags.isEmpty {
                Menu("Tags") {
                    ForEach(viewModel.allTags, id: \.self) { tag in
                        Toggle(isOn: Binding(
                            get: { selectedTags.contains(tag) },
                            set: { isOn in
                                if isOn { selectedTags.insert(tag) } else { selectedTags.remove(tag) }
                            }
                        )) {
                            Text("#\(tag)")
                        }
                    }
                }
            }

            Picker("Sort Library", selection: $sort) {
                ForEach(LibrarySort.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
        } label: {
            HStack(spacing: DipleSpace.xs) {
                Image(systemName: isNarrowed ? "line.3.horizontal.decrease" : "arrow.up.arrow.down")
                    .dipleIcon(10, weight: .semibold)
                Text(narrowingTitle)
                    .dipleType(.micro, weight: .semibold)
                    .lineLimit(1)
            }
            .foregroundStyle(isNarrowed ? DipleColor.accentInk : DipleColor.textSecondary)
            .diplePadding(.chip)
            .dipleSelected(isNarrowed, in: Capsule())
        }
        .buttonStyle(.readerControl)
        .accessibilityLabel("Filter and sort")
        .accessibilityValue("\(type.rawValue), \(status.rawValue), \(sort.rawValue)")
    }

    /// Whether anything at all is narrowing the shelf. Search is excluded on purpose: the field
    /// is visible on the page and speaks for itself.
    private var isNarrowed: Bool {
        type != .all || status != .any || !selectedTags.isEmpty
    }

    /// What the menu's own label prints. One thing at a time, in the order a reader would name
    /// it, and a count once more than one narrowing is on — three words in a capsule is a
    /// paragraph, and the menu itself is one tap away for the detail.
    private var narrowingTitle: String {
        var active: [String] = []
        if type != .all { active.append(type.rawValue) }
        if let status = status.compactTitle { active.append(status) }
        if selectedTags.count == 1, let tag = selectedTags.first { active.append("#\(tag)") }
        else if selectedTags.count > 1 { active.append("\(selectedTags.count) tags") }

        guard let first = active.first else { return sort.compactTitle }
        return active.count == 1 ? first : "\(first) +\(active.count - 1)"
    }

    private var noResults: some View {
        VStack(spacing: DipleSpace.m) {
            Image(systemName: "magnifyingglass")
                .dipleIcon(24, weight: .light)
                .foregroundStyle(DipleColor.textQuaternary)

            Text("Nothing found")
                .dipleType(.headline)
                .foregroundStyle(DipleColor.textPrimary)

            Text("Try another title, author, source or reading status.")
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
                .multilineTextAlignment(.center)

            Button("Clear search and filters") {
                searchText = ""
                type = .all
                status = .any
                selectedTags = []
                HapticManager.shared.selection()
            }
            .dipleType(.footnote, weight: .semibold)
            .foregroundStyle(DipleColor.accentInk)
            .buttonStyle(.readerControl)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DipleSpace.xxxl)
    }
}
