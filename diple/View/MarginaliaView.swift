import SwiftUI
import ReadiumShared

/// Where the board can go that is not a note.
public enum MarginaliaRoute: Hashable {
    /// A saved passage, opened where it was written rather than in a list of passages. The
    /// locator travels as its stored JSON because `Locator` is not `Hashable` and a navigation
    /// value must be — the same arrangement `HomeRoute` already makes.
    case passage(book: Book, locatorJSON: String)
}

/// One place for everything made out of reading.
///
/// This was two screens. Notes had a board with filters, a search field and a sort; passages
/// had a list of books reachable from Home and nothing else — no tag control at all, though
/// every passage has carried tags since v18. A reader with a thought about Sapiens had to know
/// in advance whether they had written it down or marked it in the text to know which of the
/// two places to look, which is a question about this app's storage layout rather than about
/// their own thinking.
///
/// So the collections keep their tables and share their controls. What changed is one screen,
/// not one schema.
public struct MarginaliaView: View {
    @StateObject private var model = MarginaliaViewModel()

    /// Rows by default, and the key is the board's old one so a reader who already chose the
    /// card grid keeps it. `AppStorage` takes its default only when the key is absent.
    @AppStorage("diple_notes_layout") private var storedLayout = MarginaliaLayout.list.rawValue

    /// Ties a row to the page it becomes, so a note expands out of the entry that was tapped
    /// instead of sliding in from the side.
    @Namespace private var cardNamespace

    /// One path for the tab, so a wiki link followed from inside a note pushes onto the same
    /// stack the rows push onto.
    @State private var path = NavigationPath()

    @State private var isSearchFieldShown = false
    @FocusState private var isSearchFocused: Bool
    @State private var isFilterSheetPresented = false
    @State private var editingPassage: PassageItem?
    @State private var renameDraft = ""
    /// Where to go once the passage sheet has finished closing. A push raised from inside a
    /// sheet is presented into a hierarchy that is still tearing that sheet down and is lost —
    /// the same trap the reader's contents sheet already documents.
    @State private var pendingPush: PendingPush?

    private enum PendingPush {
        case note(NoteRoute)
        case reader(Book, String)
    }

    enum MarginaliaLayout: String {
        case cards
        case list
    }

    private var layout: MarginaliaLayout {
        get { MarginaliaLayout(rawValue: storedLayout) ?? .list }
        nonmutating set { storedLayout = newValue.rawValue }
    }

    /// No maximum, deliberately: a cap only ever binds on a single column wider than the cap,
    /// where all the slack then collects on one side. The minimum is what carries the rule —
    /// a card never narrows past 240 pt, so a phone gets one full-measure column instead of
    /// two columns of shredded text.
    private let columns = [GridItem(.adaptive(minimum: 240), spacing: DipleSpace.m)]

    /// How many names the row prints before the rest are left to the filter sheet. Enough that
    /// an ordinary library never needs the sheet, few enough that the row stays a row.
    private let visibleFacets = 14

    public init() {}

    public var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                // One stable root under the stack. Swapping empty/workspace while the first
                // note autosaved invalidated the active destination and made the editor look
                // as though it had vanished.
                workspace
            }
            // Set but hidden: it is what a pushed screen labels its own back button with.
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: NoteRoute.self) { route in
                noteDestination(for: route)
            }
            .navigationDestination(for: MarginaliaRoute.self) { route in
                switch route {
                case let .passage(book, locatorJSON):
                    ReaderContainerView(
                        book: book,
                        startingLocator: Locator.from(jsonString: locatorJSON),
                        onReadingUpdated: { model.load() }
                    )
                }
            }
            .navigationDestination(for: Book.self) { book in
                ReaderContainerView(book: book, onReadingUpdated: { model.load() })
            }
            .sheet(item: $editingPassage, onDismiss: consumePendingPush) { passage in
                passageEditor(for: passage)
            }
            .sheet(isPresented: $isFilterSheetPresented) {
                MarginaliaFilterSheet(model: model)
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
            .alert("Error", isPresented: $model.showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(model.errorMessage ?? "An unknown error occurred.")
            }
            .alert(deleteTitle, isPresented: $model.showDeleteConfirmation) {
                Button("Delete", role: .destructive) { model.deleteConfirmedEntry() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(deleteMessage)
            }
            // Both prompts hang off the board rather than off the filter sheet, so a rename
            // started from a chip and the merge confirmed after it are presented into the same
            // hierarchy — an alert raised from inside a sheet that is itself closing is an
            // alert nobody sees.
            .alert(
                "Rename tag",
                isPresented: Binding(
                    get: { model.tagToRename != nil },
                    set: { if !$0 { model.tagToRename = nil } }
                ),
                presenting: model.tagToRename
            ) { tag in
                TextField("Tag", text: $renameDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
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
            .refreshesOnTabActivation { model.load() }
            .onReceive(NotificationCenter.default.publisher(for: .dipleShowSavedPassages)) { _ in
                showSavedPassages()
            }
        }
    }

    // MARK: - Frame

    private var workspace: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DipleSpace.l, pinnedViews: [.sectionHeaders]) {
                masthead

                if model.entries.isEmpty {
                    emptyState
                } else {
                    Section {
                        if model.results.isEmpty {
                            noResults
                        } else {
                            content
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

    private var masthead: some View {
        DipleMasthead(title: "Notes", strapline: strapline) {
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

                Picker("Layout", selection: layoutBinding) {
                    Label("Cards", systemImage: "square.grid.2x2").tag(MarginaliaLayout.cards)
                    Label("List", systemImage: "rectangle.grid.1x2").tag(MarginaliaLayout.list)
                }
            } label: {
                MastheadGlyph(systemImage: "arrow.up.arrow.down")
            }
            .buttonStyle(.readerControl)
            .accessibilityLabel("Sort, group and lay out the board")

            Button {
                HapticManager.shared.selection()
                withAnimation(DipleMotion.standard) {
                    if isSearchFieldShown || !model.rawQuery.isEmpty {
                        model.rawQuery = ""
                        isSearchFieldShown = false
                        isSearchFocused = false
                    } else {
                        isSearchFieldShown = true
                    }
                }
            } label: {
                MastheadGlyph(
                    systemImage: isSearchFieldShown || !model.rawQuery.isEmpty
                        ? "xmark" : "magnifyingglass"
                )
            }
            .buttonStyle(.readerControl)
            .accessibilityLabel(
                isSearchFieldShown || !model.rawQuery.isEmpty
                    ? "Close search" : "Search everything you have made"
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

    /// What the board holds in total, not what it is currently showing — the filtered count
    /// belongs on the scope segments, where pressing one is what changes it.
    private var strapline: String? {
        var parts: [String] = []
        let written = model.totalWritten
        let saved = model.totalSaved
        if written > 0 { parts.append(written == 1 ? "1 note" : "\(written) notes") }
        if saved > 0 { parts.append(saved == 1 ? "1 passage" : "\(saved) passages") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var layoutBinding: Binding<MarginaliaLayout> {
        Binding(get: { layout }, set: { newValue in
            HapticManager.shared.selection()
            withAnimation(DipleMotion.snappy) { layout = newValue }
        })
    }

    // MARK: - The control band

    /// It pins, and it is painted in the canvas with a hairline under it rather than in a
    /// material. A material earns its blur over something worth seeing through to; over a list
    /// of notes there is only the canvas behind it, and the blur bought a visible grey plate
    /// with a hard edge straight across the page.
    private var controls: some View {
        VStack(spacing: DipleSpace.m) {
            if isSearchFieldShown || !model.rawQuery.isEmpty {
                searchField
            }

            MarginaliaScopeBar(
                scope: $model.scope,
                counts: { model.count(for: $0) },
                // The bar appears only when the board actually holds both kinds. With notes
                // and no passages, three segments would offer two rooms that show the same
                // rows and one that is empty.
                isAvailable: { _ in model.totalWritten > 0 && model.totalSaved > 0 }
            )

            chipRow
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

    private var searchField: some View {
        VStack(alignment: .leading, spacing: DipleSpace.s) {
            DipleSearchField(
                text: $model.rawQuery,
                prompt: "Search everything · #tag · @source",
                identifier: "notes.search"
            )
            .focused($isSearchFocused)
            .onAppear { isSearchFocused = true }

            if let token = MarginaliaQuery.activeToken(in: model.rawQuery) {
                tokenSuggestions(for: token)
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }

    /// What the field offers while a `#` or `@` is still being typed. Choosing one takes the
    /// half-typed word back out of the field and puts it in the filter row instead, so the
    /// field is left holding only what is genuinely free text.
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
            .contentMargins(.horizontal, 0, for: .scrollContent)
        }
    }

    private var chipRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DipleSpace.s) {
                    Color.clear.frame(width: 0, height: 0).id(Self.chipRowStart)

                    if !model.sourceOptions.isEmpty || !model.tagOptions.isEmpty {
                        filterSheetChip
                    }

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

                    ForEach(model.facetOptions.prefix(visibleFacets)) { option in
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
                }
            }
            .contentMargins(.horizontal, 0, for: .scrollContent)
            // A chosen chip sorts to the front of the row, which is no use if the row is still
            // scrolled to where the reader pressed it. The row returns to its start whenever
            // the narrowing changes, so what is now in force is always the first thing on it.
            .onChange(of: model.facets) { _, _ in
                withAnimation(DipleMotion.standard) {
                    proxy.scrollTo(Self.chipRowStart, anchor: .leading)
                }
            }
        }
    }

    private static let chipRowStart = "marginalia.chips.start"

    private var filterSheetChip: some View {
        Button {
            HapticManager.shared.selection()
            isFilterSheetPresented = true
        } label: {
            HStack(spacing: DipleSpace.xs) {
                Image(systemName: "line.3.horizontal.decrease")
                    .dipleIcon(10, weight: .semibold)
                if model.facets.count > 0 {
                    Text("\(model.facets.count)")
                        .dipleType(.micro, weight: .semibold)
                        .monospacedDigit()
                }
            }
            .foregroundStyle(model.facets.isEmpty ? DipleColor.textTertiary : DipleColor.accentInk)
            .diplePadding(.chip)
            .dipleSelected(!model.facets.isEmpty, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("All sources and tags")
    }

    /// What a chip can do besides narrow.
    ///
    /// Renaming lives here rather than on a screen of its own. A page for one tag would be the
    /// board again with one chip pressed — the same rows, the same order, one less control —
    /// and the only thing it could offer that the chip cannot is this menu.
    @ViewBuilder
    private func facetMenu(_ option: MarginaliaFacetOption) -> some View {
        Button {
            HapticManager.shared.selection()
            withAnimation(DipleMotion.standard) {
                model.lenses = []
                model.facets = MarginaliaFacets()
                model.toggle(option)
            }
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
        }
    }

    // MARK: - The catalogue

    @ViewBuilder
    private var content: some View {
        LazyVStack(alignment: .leading, spacing: DipleSpace.l) {
            ForEach(model.groups) { group in
                if model.grouping != .none {
                    groupHeader(group)
                }
                entries(of: group)
            }
        }
        .padding(.horizontal, DipleSpace.xl)
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
                .frame(width: 18, height: 27)
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
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func entries(of group: MarginaliaGroup) -> some View {
        if layout == .cards {
            LazyVGrid(columns: columns, alignment: .leading, spacing: DipleSpace.m) {
                ForEach(group.entries) { entry in
                    row(for: entry)
                }
            }
        } else {
            LazyVStack(spacing: 0) {
                ForEach(group.entries) { entry in
                    row(for: entry)
                }
            }
        }
    }

    @ViewBuilder
    private func row(for entry: MarginaliaEntry) -> some View {
        switch entry {
        case .note(let item):
            NavigationLink(value: NoteRoute.existing(item)) {
                NoteCardView(item: item, style: layout == .cards ? .card : .row)
            }
            .buttonStyle(.bookCard)
            .matchedTransitionSource(id: item.id, in: cardNamespace)
            .contextMenu { noteMenu(item) }

        case .passage(let item):
            // A passage opens its own editor rather than the book. On this board the reader is
            // going over what they have made — commenting, tagging, filing — and the comment is
            // the thing they came for; the way back into the page is one row inside the sheet.
            // Home's resurfacing card keeps the opposite rule for the opposite reason.
            Button {
                HapticManager.shared.selection()
                editingPassage = item
            } label: {
                PassageRowView(passage: item, style: layout == .cards ? .card : .row)
            }
            .buttonStyle(.bookCard)
            .contextMenu { passageMenu(item) }
        }
    }

    @ViewBuilder
    private func noteMenu(_ item: NoteItem) -> some View {
        Button {
            UIPasteboard.general.string = item.note.body
        } label: {
            Label("Copy text", systemImage: "doc.on.doc")
        }

        Button(role: .destructive) {
            model.confirmDelete(.note(item))
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func passageMenu(_ item: PassageItem) -> some View {
        if let book = item.book, item.highlight.parsedLocator != nil {
            Button {
                path.append(MarginaliaRoute.passage(book: book, locatorJSON: item.highlight.locator))
            } label: {
                Label("Open in the book", systemImage: "book")
            }
        }

        Button {
            path.append(NoteRoute.newFromPassage(item))
        } label: {
            Label("Expand into a note", systemImage: "square.and.pencil")
        }

        Button {
            UIPasteboard.general.string = item.highlight.text
        } label: {
            Label("Copy passage", systemImage: "doc.on.doc")
        }

        Button(role: .destructive) {
            model.confirmDelete(.passage(item))
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    // MARK: - Destinations

    @ViewBuilder
    private func noteDestination(for route: NoteRoute) -> some View {
        let page = NoteDetailView(
            route: route,
            books: model.books,
            suggestedTags: model.noteTagVocabulary,
            allNotes: model.entries.compactMap(\.noteItem),
            passages: model.entries.compactMap(\.passageItem),
            onSave: { note, tags in model.save(note, tags: tags) },
            onDelete: { model.delete(.note($0)) },
            onOpenNote: { path.append(NoteRoute.existing($0)) },
            onOpenPassage: { editingPassage = $0 }
        )

        // A new note has no row on the board to expand out of, so it gets the standard push.
        // `NavigationTransition` has no type eraser, so the cases branch here.
        switch route {
        case .existing(let item):
            page.navigationTransition(.zoom(sourceID: item.id, in: cardNamespace))
        case .new, .newFromSource, .newFromPassage:
            page
        }
    }

    /// The passage editor is the reader's own, not a second one. A sheet that drifted from the
    /// one in the reader would mean a passage edited from the board and the same passage edited
    /// on its page were two different objects with two different rules.
    private func passageEditor(for passage: PassageItem) -> some View {
        HighlightEditorView(
            quote: passage.highlight.text,
            initialColorHex: passage.highlight.colorHex,
            initialComment: passage.comment,
            initialTags: passage.tags,
            tagSuggestions: model.passageTagVocabulary,
            isExisting: true,
            sourceTitle: passage.book?.title ?? passage.highlight.bookTitle,
            onSave: { colorHex, comment, tags in
                model.savePassage(passage, colorHex: colorHex, comment: comment, tags: tags)
            },
            onDelete: { model.delete(.passage(passage)) },
            onOpenInSource: openInSourceAction(for: passage),
            onExpandIntoNote: { pendingPush = .note(.newFromPassage(passage)) }
        )
    }

    private func openInSourceAction(for passage: PassageItem) -> (() -> Void)? {
        guard let book = passage.book, passage.highlight.parsedLocator != nil else { return nil }
        return { pendingPush = .reader(book, passage.highlight.locator) }
    }

    private func consumePendingPush() {
        guard let pendingPush else { return }
        self.pendingPush = nil
        switch pendingPush {
        case .note(let route):
            path.append(route)
        case let .reader(book, locatorJSON):
            path.append(MarginaliaRoute.passage(book: book, locatorJSON: locatorJSON))
        }
    }

    /// Home's "All highlights" row lands here rather than pushing a list of its own: there is
    /// one place for this now, and a second door into a copy of it would be the arrangement
    /// this screen exists to end.
    private func showSavedPassages() {
        path = NavigationPath()
        model.clearNarrowing()
        model.scope = .saved
        model.grouping = .source
    }

    // MARK: - Deletion

    private var deleteTitle: String {
        model.entryToDelete?.kind == .saved ? "Delete passage?" : "Delete note?"
    }

    /// A passage can be marked again from the same page; something written cannot. Both are
    /// asked about here all the same, because on this board they are rows of one catalogue and
    /// two different costs for the identical gesture is how a reader learns to distrust it.
    private var deleteMessage: String {
        model.entryToDelete?.kind == .saved
            ? "This passage and its comment will be removed."
            : "This note will be removed permanently."
    }

    // MARK: - Empty

    private var noResults: some View {
        VStack(spacing: DipleSpace.m) {
            Image(systemName: model.rawQuery.isEmpty ? "line.3.horizontal.decrease.circle" : "text.magnifyingglass")
                .dipleIcon(24, weight: .light)
                .foregroundStyle(DipleColor.accentInk)

            Text(model.rawQuery.isEmpty ? "Nothing in this view" : "No matches")
                .dipleType(.headline)
                .foregroundStyle(DipleColor.textPrimary)

            if let summary = model.narrowingSummary {
                Text(summary)
                    .dipleType(.callout)
                    .foregroundStyle(DipleColor.textTertiary)
                    .multilineTextAlignment(.center)
            }

            if model.isNarrowed {
                Button("Clear the filters") {
                    HapticManager.shared.selection()
                    withAnimation(DipleMotion.standard) { model.clearNarrowing() }
                }
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

                Text("Everything you write, and every passage you keep while reading, collects here — by source and by tag.")
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

public extension Notification.Name {
    /// Home asking the board to show the passages. Cross-tab, because the destination is a tab
    /// root rather than a screen Home can push.
    static let dipleShowSavedPassages = Notification.Name("diple.showSavedPassages")
}
