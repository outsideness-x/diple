import SwiftUI

/// The notes workspace: capture, rediscover and develop ideas without leaving reading.
public struct NotesView: View {
    @StateObject private var viewModel = NotesViewModel()
    // Rows by default, the same trade the library made: a board of cards shows a title and a
    // few lines of each thought, a column of rows shows that plus what it is attached to and
    // how far through its tasks it is, and it can be read down with a thumb. The board stays
    // one tap away for the times a note is recognised by its shape rather than its name.
    @AppStorage("diple_notes_layout") private var storedLayout = NoteLayout.list.rawValue

    /// Ties a card to the page it becomes, so the note expands out of the block the reader
    /// tapped instead of sliding in from the side.
    @Namespace private var cardNamespace

    /// One path for the tab, so a wiki link followed from inside a note pushes onto the same
    /// stack the cards push onto.
    @State private var path = NavigationPath()

    /// Whether the field is on the page. It is not, at rest — the same trade the shelf makes:
    /// a board is read far more often than it is searched, and a resident field charges the
    /// page for every time it is not being used.
    @State private var isSearchFieldShown = false
    @FocusState private var isSearchFocused: Bool

    /// No maximum, deliberately.
    ///
    /// A cap of 360 pt only ever binds in one situation: a single column on a screen wider
    /// than 360 + gutters. There the card stopped at 360 while the track was 400, and the
    /// grid is `.leading`, so all 40 pt of slack collected on the right — 20 pt of margin on
    /// the left against 60 on the right, with the search field and the screen title above
    /// running to the true gutter. On a 393 pt phone the track is narrower than the cap, so
    /// nothing showed; it only appeared on the large phones.
    ///
    /// The minimum is what carries the rule that matters (see CLAUDE.md): a card never
    /// narrows past 240 pt, so a phone gets one full-measure column instead of two columns of
    /// shredded text, while iPad and wide windows still get several. Those cases divide the
    /// track evenly and land well under 360 on their own, so the cap was never doing work
    /// there either.
    private let columns = [
        GridItem(.adaptive(minimum: 240), spacing: DipleSpace.m)
    ]

    private enum NoteLayout: String {
        case cards
        case list
    }

    private var layout: NoteLayout {
        get { NoteLayout(rawValue: storedLayout) ?? .cards }
        nonmutating set { storedLayout = newValue.rawValue }
    }

    public init() {}

    public var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                // Keep one stable root under NavigationStack. The previous empty/workspace
                // swap happened while the first note autosaved (or the last was deleted),
                // invalidating the active destination and making the editor appear to vanish.
                workspace
            }
            // Set but hidden: it is what a pushed screen labels its own back button with.
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: NoteRoute.self) { route in
                destination(for: route)
            }
            .alert("Error", isPresented: $viewModel.showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred.")
            }
            .alert("Delete note?", isPresented: $viewModel.showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    viewModel.deleteConfirmedNote()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This note will be removed permanently.")
            }
            .refreshesOnTabActivation { viewModel.load() }
        }
    }

    private var workspace: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DipleSpace.l, pinnedViews: [.sectionHeaders]) {
                masthead

                if viewModel.items.isEmpty {
                    emptyState
                } else {
                    Section {
                        if viewModel.filteredItems.isEmpty {
                            noResults
                        } else {
                            notesContent
                        }
                    } header: {
                        controls
                    }
                }
            }
            .padding(.bottom, DipleSpace.scrollBottom)
        }
        .scrollDismissesKeyboard(.interactively)
        .tracksTabBarCollapse()
    }

    /// The head of the board.
    ///
    /// `CONTINUE THINKING` is gone from above it. It was a run of accent small caps heading
    /// nothing — what sat under it was the pinned control band, not the list — and it spent the
    /// app's loudest colour on a label with no function. The board's name is in the masthead
    /// now, where the shelf's and the front page's are.
    ///
    /// Sort and layout share one control, for the reason the shelf already pairs status with
    /// sort: both answer "how should this board be presented" rather than "what is on it".
    private var masthead: some View {
        DipleMasthead(title: "Notes", strapline: strapline) {
            Menu {
                Picker("Sort", selection: $viewModel.sort) {
                    ForEach(NoteSort.allCases) { option in
                        Label(option.title, systemImage: option.systemImage).tag(option)
                    }
                }

                Picker("Layout", selection: layoutBinding) {
                    Label("Cards", systemImage: "square.grid.2x2").tag(NoteLayout.cards)
                    Label("List", systemImage: "rectangle.grid.1x2").tag(NoteLayout.list)
                }
            } label: {
                MastheadGlyph(systemImage: "arrow.up.arrow.down")
            }
            .buttonStyle(.readerControl)
            .accessibilityLabel("Sort and lay out the board")

            Button {
                HapticManager.shared.selection()
                withAnimation(DipleMotion.standard) {
                    if isSearchFieldShown || !viewModel.query.isEmpty {
                        viewModel.query = ""
                        isSearchFieldShown = false
                        isSearchFocused = false
                    } else {
                        isSearchFieldShown = true
                    }
                }
            } label: {
                MastheadGlyph(
                    systemImage: isSearchFieldShown || !viewModel.query.isEmpty
                        ? "xmark" : "magnifyingglass"
                )
            }
            .buttonStyle(.readerControl)
            .accessibilityLabel(
                isSearchFieldShown || !viewModel.query.isEmpty ? "Close search" : "Search every note"
            )

            Button {
                HapticManager.shared.selection()
                path.append(NoteRoute.new)
            } label: {
                MastheadGlyph(systemImage: "plus")
            }
            .buttonStyle(.readerControl)
            .accessibilityLabel("New note")
            .accessibilityIdentifier("notes.new")
        }
        .padding(.horizontal, DipleSpace.xl)
    }

    private var strapline: String? {
        let count = viewModel.items.count
        guard count > 0 else { return nil }
        return count == 1 ? "1 note" : "\(count) notes"
    }

    /// `layout` is a computed property over `@AppStorage`, and a `Picker` needs a binding.
    private var layoutBinding: Binding<NoteLayout> {
        Binding(get: { layout }, set: { newValue in
            HapticManager.shared.selection()
            withAnimation(DipleMotion.snappy) { layout = newValue }
        })
    }

    /// The filter row, and the field when it has been asked for.
    ///
    /// It pins, and it is painted in the canvas with a hairline under it rather than in a
    /// material. A material earns its blur when there is something behind it worth seeing
    /// through to — that is why the reader's bars use one over a page of type. Over a list of
    /// notes there is only the canvas behind it, so the blur bought nothing and charged a
    /// visible grey plate with a hard edge straight across the page.
    private var controls: some View {
        VStack(spacing: DipleSpace.m) {
            if isSearchFieldShown || !viewModel.query.isEmpty {
                DipleSearchField(
                    text: $viewModel.query,
                    prompt: "Search every note",
                    identifier: "notes.search"
                )
                .focused($isSearchFocused)
                .onAppear { isSearchFocused = true }
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            filterBar
        }
        .padding(.horizontal, DipleSpace.xl)
        .padding(.top, DipleSpace.s)
        .padding(.bottom, DipleSpace.m)
        .background(DipleColor.canvas)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DipleColor.hairline)
                .frame(height: DipleStroke.hairline)
        }
    }

    /// A new note has no card on the board, so there is nothing for it to expand out of —
    /// it gets the standard push. `NavigationTransition` has no type eraser, so the two
    /// cases are branched here rather than resolved into one value.
    @ViewBuilder
    private func destination(for route: NoteRoute) -> some View {
        let page = NoteDetailView(
            route: route,
            books: viewModel.books,
            suggestedTags: viewModel.allTags,
            allNotes: viewModel.items,
            onSave: { note, tags in
                viewModel.save(note, tags: tags)
            },
            onDelete: { item in
                viewModel.delete(item)
            },
            onOpenNote: { path.append(NoteRoute.existing($0)) }
        )

        switch route {
        case .existing(let item):
            page.navigationTransition(.zoom(sourceID: item.id, in: cardNamespace))
        case .new, .newFromSource:
            page
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DipleSpace.s) {
                ForEach(viewModel.availableFilters, id: \.self) { filter in
                    Button {
                        HapticManager.shared.selection()
                        viewModel.filter = filter
                    } label: {
                        chip(for: filter)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }

    @ViewBuilder
    private func chip(for filter: NoteFilter) -> some View {
        let isSelected = viewModel.filter == filter
        switch filter {
        case .all:
            filterChip("All", systemImage: "tray.full", isSelected: isSelected)
        case .recent:
            filterChip("This week", systemImage: "clock", isSelected: isSelected)
        case .linked:
            filterChip("From library", systemImage: "book.closed", isSelected: isSelected)
        case .untagged:
            filterChip("Unsorted", systemImage: "tray", isSelected: isSelected)
        case .tag(let tag):
            TagChipView(label: tag, kind: .text, isSelected: isSelected)
        case .book:
            TagChipView(label: viewModel.title(for: filter), kind: .book, isSelected: isSelected)
        }
    }

    private func filterChip(_ title: String, systemImage: String, isSelected: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .dipleType(.micro)
            .foregroundColor(isSelected ? DipleColor.accentInk : DipleColor.textTertiary)
            .diplePadding(.chip)
            .dipleSelected(isSelected, in: Capsule())
    }

    @ViewBuilder
    private var notesContent: some View {
        if layout == .cards {
            LazyVGrid(columns: columns, alignment: .leading, spacing: DipleSpace.m) {
                noteLinks
            }
            .padding(.horizontal, DipleSpace.xl)
        } else {
            LazyVStack(spacing: 0) {
                noteLinks
            }
            .padding(.horizontal, DipleSpace.xl)
        }
    }

    private var noteLinks: some View {
        ForEach(viewModel.filteredItems) { item in
            NavigationLink(value: NoteRoute.existing(item)) {
                NoteCardView(item: item, style: layout == .cards ? .card : .row)
            }
            .buttonStyle(.bookCard)
            .matchedTransitionSource(id: item.id, in: cardNamespace)
            .contextMenu {
                Button {
                    UIPasteboard.general.string = item.note.body
                } label: {
                    Label("Copy text", systemImage: "doc.on.doc")
                }

                Button(role: .destructive) {
                    viewModel.confirmDelete(item)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var noResults: some View {
        VStack(spacing: DipleSpace.m) {
            Image(systemName: viewModel.query.isEmpty ? "line.3.horizontal.decrease.circle" : "text.magnifyingglass")
                .dipleIcon(24, weight: .light)
                .foregroundStyle(DipleColor.accentInk)
            Text(viewModel.query.isEmpty ? "Nothing in this view" : "No matching notes")
                .dipleType(.headline)
                .foregroundStyle(DipleColor.textPrimary)
            Text(viewModel.query.isEmpty ? "Choose another filter or create a note here." : "Try a title, phrase, tag, author or book.")
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
                .multilineTextAlignment(.center)
            if !viewModel.query.isEmpty {
                Button("Clear search") { viewModel.query = "" }
                    .dipleType(.footnote, weight: .semibold)
                    .foregroundStyle(DipleColor.accentInk)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DipleSpace.xl)
        .padding(.vertical, DipleSpace.xxxl)
    }

    private var emptyState: some View {
        VStack(spacing: DipleSpace.xl) {
            Image(systemName: "note.text")
                .dipleIcon(30, weight: .thin)
                .foregroundStyle(DipleColor.accentInk)

            VStack(spacing: DipleSpace.s) {
                Text("Write the first note")
                    .dipleType(.editorialTitle)
                    .foregroundStyle(DipleColor.textPrimary)

                Text("Start with the thought itself. You can connect a source or add tags when they become useful.")
                    .dipleType(.callout)
                    .foregroundStyle(DipleColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DipleSpace.xxxl)
            }

            NavigationLink(value: NoteRoute.new) {
                HStack(spacing: DipleSpace.s) {
                    Image(systemName: "plus")
                        .dipleIcon(14, weight: .semibold)
                    Text("New note")
                        .dipleType(.body, weight: .semibold)
                }
                .foregroundStyle(DipleColor.textOnAccent)
                .diplePadding(.buttonLarge)
                .background(DipleColor.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("notes.new")
            .padding(.top, DipleSpace.s)

        }
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical, alignment: .center) { length, _ in
            max(length - DipleSpace.scrollBottom, 420)
        }
    }
}
