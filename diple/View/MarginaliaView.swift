import SwiftUI
// Scoped on purpose. A plain `import ReadiumShared` brings its own `Content` into the file, and
// `ViewModifier.body(content: Content)` then resolves against that instead of the associated
// type — every `ViewModifier` here stops conforming, with an error pointing at the modifier
// rather than at the import.
import struct ReadiumShared.Locator

/// Which half of Highlights is open: the passages marked in books, or the notes written about
/// them.
///
/// Two halves of one room, not two rooms. They were two places in the tab bar (2026-09-07), then
/// notes left for a workshop of their own (2026-09-11), and on 2026-09-27 they came back as the
/// second half of Highlights: a note is what the reader made of a book, the same as a passage
/// is, and the room that keeps one keeps the other.
///
/// The half still decides what the board holds and nothing else. It is not a scope the reader
/// can widen: a reader who marked something in a book and came here is shown passages, and one
/// who wrote about it is one tap from notes — never a page of both, which was the confusing
/// room the 2026-09-07 split undid.
public enum MarginaliaDoor: String, CaseIterable, Identifiable {
    case highlights
    case notes

    public var id: Self { self }

    /// The half's name on the rubric. The first one is called by what it holds, not by the
    /// room's name: "Highlights" over "Highlights · Notes" would print the same word twice.
    var title: String {
        switch self {
        case .highlights: return "Passages"
        case .notes: return "Notes"
        }
    }

    /// What a page pushed from this half labels its back button with.
    var backTitle: String {
        switch self {
        case .highlights: return "Highlights"
        case .notes: return "Notes"
        }
    }

    /// What this half holds — fixed for as long as it is open, not a first position.
    var scope: MarginaliaScope {
        switch self {
        case .notes: return .written
        case .highlights: return .saved
        }
    }

    /// The day's passage stands at the top of the half the passages are in, and nowhere else.
    var showsDailyPassage: Bool { self == .highlights }

    /// A note can be started here, without a book — the pencil in the masthead. Nothing writes a
    /// passage but reading one, so the passages half never offers it.
    var offersNewNote: Bool { self == .notes }
}

/// Where the board can go that is not a note.
public enum MarginaliaRoute: Hashable {
    /// A saved passage, opened where it was written rather than in a list of passages. The
    /// locator travels as its stored JSON because `Locator` is not `Hashable` and a navigation
    /// value must be — the same arrangement `HomeRoute` already makes.
    case passage(book: Book, locatorJSON: String)
}

/// Everything made out of reading, in one room: the passages marked in books, and the notes
/// written about them.
///
/// This was two screens once. Notes had a board with filters, a search field and a sort;
/// passages had a list of books reachable from Home and nothing else — no tag control at all,
/// though every passage has carried tags since v18. So the collections keep their tables and
/// share their controls — the filter row, the search field, the order, the grouping and the
/// filing pass are written once and stand over both halves. What they do not share is a page:
/// each half shows one kind, under the rubric that switches between them.
///
/// **One stack, two boards.** Each half keeps its own model, so a chip pressed among the
/// passages does not narrow the notes, and its own scroll position, so going to the other half
/// and back lands where the reader was. Both stay mounted — hidden by opacity, the way the tab
/// roots are — and both push onto this view's one path, which declares every route once:
/// SwiftUI keeps only the declaration nearest the root for a type and drops the rest silently
/// (see "Home и навигация" in CLAUDE.md).
public struct MarginaliaView: View {
    @StateObject private var passages = MarginaliaViewModel(scope: .saved)
    @StateObject private var notes = MarginaliaViewModel(scope: .written)

    /// Passages first, at every launch: the room is named for them, and it is where the day's
    /// passage — and the notification and widget that bring the reader here — stands.
    @State private var door: MarginaliaDoor = .highlights

    /// One path for the room, so a wiki link followed from inside a note pushes onto the same
    /// stack the rows push onto.
    @State private var path = NavigationPath()

    /// Ties a row to the page it becomes, so a note expands out of the entry that was tapped
    /// instead of sliding in from the side.
    @Namespace private var cardNamespace

    /// The passage open in its editor — from a row, from the day's passage, or from a note's
    /// Connections. Here rather than in each half, because a note page is pushed onto this
    /// view's stack and has no half of its own to raise a sheet from.
    @State private var editingPassage: PassageItem?
    /// Where to go once the passage sheet has finished closing. A push raised from inside a
    /// sheet is presented into a hierarchy that is still tearing that sheet down and is lost —
    /// the same trap the reader's contents sheet already documents.
    @State private var pendingPush: PendingPush?

    @Environment(\.dipleTabIsActive) private var isTabActive

    private enum PendingPush {
        case note(NoteRoute)
        case reader(Book, String)
    }

    public init() {}

    public var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                half(.highlights, model: passages)
                half(.notes, model: notes)
            }
            // Set but hidden: it is what a pushed screen labels its own back button with.
            .navigationTitle(door.backTitle)
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
                        onReadingUpdated: reloadBoth
                    )
                }
            }
            .navigationDestination(for: Book.self) { book in
                ReaderContainerView(book: book, onReadingUpdated: reloadBoth)
            }
        }
        .sheet(item: $editingPassage, onDismiss: consumePendingPush) { passage in
            passageEditor(for: passage)
        }
        // The notification and the widget open on the day's passage, which stands in the
        // passages half.
        .onReceive(NotificationCenter.default.publisher(for: .dipleOpenDailyResurfacing)) { _ in
            door = .highlights
        }
    }

    /// One half, mounted whether or not it is open. Only the open one counts as the active tab:
    /// that is what its scroll reports to the tab bar, what hides the bar while it is choosing,
    /// and what reloads it when the reader comes back to it.
    private func half(_ side: MarginaliaDoor, model: MarginaliaViewModel) -> some View {
        let isOpen = door == side
        return MarginaliaBoardPage(
            door: side,
            model: model,
            room: $door,
            counts: [.highlights: passages.totalInScope, .notes: notes.totalInScope],
            cardNamespace: cardNamespace,
            openNote: { path.append($0) },
            openInBook: { path.append($0) },
            openPassage: { editingPassage = $0 }
        )
        .environment(\.dipleTabIsActive, isTabActive && isOpen)
        .opacity(isOpen ? 1 : 0)
        .allowsHitTesting(isOpen)
        .accessibilityHidden(!isOpen)
        .zIndex(isOpen ? 1 : 0)
    }

    private func reloadBoth() {
        passages.load()
        notes.load()
    }

    // MARK: - Destinations

    /// The one note editor in the app, given everything the room holds — every note for its
    /// wiki links, every passage for its Connections, the whole vocabulary for its tag menu.
    @ViewBuilder
    private func noteDestination(for route: NoteRoute) -> some View {
        let page = NoteDetailView(
            route: route,
            books: notes.books,
            suggestedTags: notes.noteTagVocabulary,
            allNotes: notes.entries.compactMap(\.noteItem),
            passages: notes.entries.compactMap(\.passageItem),
            onSave: { note, tags in notes.save(note, tags: tags) },
            onDelete: { notes.delete(.note($0)) },
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
            tagSuggestions: passages.passageTagVocabulary,
            isExisting: true,
            sourceTitle: passage.book?.title ?? passage.highlight.bookTitle,
            onSave: { colorHex, comment, tags in
                passages.savePassage(passage, colorHex: colorHex, comment: comment, tags: tags)
                // A note's Connections read passages out of the notes half's copy.
                notes.load()
            },
            onDelete: {
                passages.delete(.passage(passage))
                notes.load()
            },
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
}

/// One half of Highlights: the board of passages, or the board of notes.
///
/// Every control is written once and stands over both — the rubric that switches them, the
/// filter row, the search field, the order, the grouping, the workbench and the filing pass.
/// The half knows only which kind it holds; where anything opens is the room's business, so it
/// hands every push to it.
private struct MarginaliaBoardPage: View {
    let door: MarginaliaDoor
    @ObservedObject var model: MarginaliaViewModel
    /// Which half is open, for the rubric under the masthead.
    @Binding var room: MarginaliaDoor
    /// How many rows each half holds, for the rubric's superior figures. The other half's number
    /// comes from the other model, which only the room observes.
    let counts: [MarginaliaDoor: Int]
    let cardNamespace: Namespace.ID
    let openNote: (NoteRoute) -> Void
    let openInBook: (MarginaliaRoute) -> Void
    let openPassage: (PassageItem) -> Void

    /// Rows by default, and the key is the board's old one so a reader who already chose the
    /// card grid keeps it. `AppStorage` takes its default only when the key is absent. Both
    /// halves read the one key: a layout is how the reader likes to look at the room.
    @AppStorage("diple_notes_layout") private var storedLayout = MarginaliaLayout.list.rawValue

    @State private var isSearchFieldShown = false
    @FocusState private var isSearchFocused: Bool
    @State private var isFilterSheetPresented = false
    /// The passage being made into a card, if any.
    @State private var cardPassage: PassageItem?
    @State private var renameDraft = ""
    @State private var tagDraft = ""
    @State private var isAddingTagToSelection = false
    @State private var isConfirmingBulkDelete = false
    @State private var isFilingPassPresented = false

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

    /// How many names the row prints *per run* before the rest are left to the filter sheet.
    /// Enough that an ordinary library never needs the sheet, few enough that the row stays a
    /// row. It is counted per run rather than over the whole row for the reason the runs exist
    /// at all: one cap across a list that begins with shelves means a library with nine books
    /// prints no words, and the word is what most readers came to press.
    private let visibleFacets = 8

    var body: some View {
        // One stable root. Swapping empty/workspace while the first note autosaved invalidated
        // the active destination and made the editor look as though it had vanished.
        workspace
            .sheet(item: $cardPassage) { passage in
                PassageCardSheet(passage: passage)
            }
            .sheet(isPresented: $isFilingPassPresented) {
                MarginaliaFilingView(model: model)
            }
            .sheet(isPresented: $isFilterSheetPresented) {
                // The detents are the sheet's own: how tall it should open is a fact about how
                // many names it is holding, and only it knows that.
                MarginaliaFilterSheet(model: model)
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
            .alert("Add a tag", isPresented: $isAddingTagToSelection) {
                TextField("Tag", text: $tagDraft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Add") { model.tagSelection(tagDraft) }
                Button("Cancel", role: .cancel) { tagDraft = "" }
            } message: {
                Text("The word is added to each chosen row. Nothing already there is replaced.")
            }
            .alert(bulkDeleteTitle, isPresented: $isConfirmingBulkDelete) {
                Button("Delete", role: .destructive) { model.deleteSelection() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text(
                    door == .notes
                        ? "The chosen notes will be deleted."
                        : "The chosen passages and their comments will be removed."
                )
            }
            .refreshesOnTabActivation { model.load() }
    }

    private var bulkDeleteTitle: String {
        let count = model.selectedEntries.count
        switch door {
        case .notes: return count == 1 ? "Delete 1 note?" : "Delete \(count) notes?"
        case .highlights: return count == 1 ? "Delete 1 passage?" : "Delete \(count) passages?"
        }
    }

    // MARK: - Frame

    private var workspace: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DipleSpace.l, pinnedViews: [.sectionHeaders]) {
                masthead

                if !model.isSelecting {
                    rubric
                }

                dailyPassage

                if model.totalInScope == 0 {
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
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if model.isSelecting {
                selectionBar
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .modifier(HidesTabBarWhileSelecting(isSelecting: model.isSelecting))
    }

    /// The two halves, under the room's name — set the way the library sets its queue.
    ///
    /// Gone while choosing: choosing is a mode with one way out, Done in the masthead, and a
    /// rubric left live would be a second way to walk off a selection without saying so.
    private var rubric: some View {
        DipleRubric(
            options: MarginaliaDoor.allCases,
            selection: $room,
            title: \.title,
            count: { counts[$0] ?? 0 },
            identifier: { "highlights.\($0.rawValue)" }
        )
        .padding(.horizontal, DipleSpace.xl)
    }

    /// The day's passage, at the head of the half it belongs to.
    ///
    /// It used to open the front page, where it was the largest thing on a screen about what to
    /// read next, and where it made Home a third place saved passages lived. Here it is the
    /// first thing in the half that holds them — which is also where the daily notification and
    /// the widget land.
    @ViewBuilder
    private var dailyPassage: some View {
        if door.showsDailyPassage, !model.isNarrowed, !model.isSelecting {
            DailyResurfacingCard { item in openDaily(item) }
                .padding(.horizontal, DipleSpace.xl)
        }
    }

    /// Into the book, at the passage — the point of resurfacing is to return to an idea in its
    /// place. A passage whose book is gone has nowhere to open and gets its own editor instead,
    /// which is the nearest thing left to standing in front of it.
    private func openDaily(_ item: DailyResurfacingItem) {
        if let book = item.summary.book, item.quote.parsedLocator != nil {
            openInBook(.passage(book: book, locatorJSON: item.quote.locator))
        } else if let passage = model.entries
            .compactMap(\.passageItem)
            .first(where: { $0.id == item.quote.id }) {
            openPassage(passage)
        }
    }

    /// The room's name, not the half's: the rubric right under it says which half is open, and
    /// a title that changed with it would say the same thing twice, one line apart.
    private var masthead: some View {
        DipleMasthead(title: "Highlights", strapline: strapline) {
            if model.isSelecting {
                selectionMastheadActions
            } else {
                browsingMastheadActions
            }
        }
        .padding(.horizontal, DipleSpace.xl)
    }

    @ViewBuilder
    private var selectionMastheadActions: some View {
        Button {
            HapticManager.shared.selection()
            withAnimation(DipleMotion.snappy) { model.selectAllVisible() }
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
            withAnimation(DipleMotion.standard) { model.endSelecting() }
        } label: {
            Text("Done")
                .dipleType(.footnote, weight: .semibold)
                .foregroundStyle(DipleColor.accentInk)
                .frame(minWidth: 44, minHeight: 44)
        }
        .buttonStyle(.readerControl)
    }

    private var isEverythingSelected: Bool {
        !model.results.isEmpty && model.selectedEntries.count == model.results.count
    }


    @ViewBuilder
    private var browsingMastheadActions: some View {
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

            // The notes half's own verb: a note that starts here, about no book yet. It files
            // itself under one from its page — the properties line links a source and carries
            // its name as a tag, exactly as a note written inside the book is born with.
            if door.offersNewNote {
                Button {
                    HapticManager.shared.selection()
                    openNote(.new)
                } label: {
                    MastheadGlyph(systemImage: "square.and.pencil")
                }
                .buttonStyle(.readerControl)
                .accessibilityLabel("New note")
                .accessibilityIdentifier("notes.new")
            }
    }

    /// Only while choosing. At rest the rubric under the name already prints what each half
    /// holds, and a strapline counting the open half would say it a second time, one line up.
    private var strapline: String? {
        guard model.isSelecting else { return nil }
        let count = model.selectedEntries.count
        return count == 0 ? "Choose what to collect" : "\(count) selected"
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

    /// The filter row, read in runs rather than as one list.
    ///
    /// It used to be a single ranking by count: a swatch, a shelf, two words, another shelf,
    /// six more words, in whatever order the numbers happened to fall that minute. Three kinds
    /// of thing at three shapes in no order is a heap, and the way you use a heap is to read
    /// all of it — which is the one thing a control band across the top of a catalogue must
    /// not ask for.
    ///
    /// So the row has a grammar now: the door to everything, then the lenses, then marks, then
    /// shelves, then words, each run in its own stretch with a hairline between. The order
    /// never changes, so after a day of use the reader is not reading the row at all — they
    /// know the words are on the right and scroll straight there.
    private var chipRow: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: DipleSpace.s) {
                    Color.clear.frame(width: 0, height: 0).id(Self.chipRowStart)

                    if !model.sourceOptions.isEmpty || !model.tagOptions.isEmpty {
                        filterSheetChip
                    }

                    if model.isNarrowed {
                        clearChip
                    }

                    if !model.lensOptions.isEmpty {
                        runDivider

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

                    ForEach(facetRuns) { run in
                        runDivider

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
                    }
                }
                // The runs animate as one row. Without it a chip pressed at the far right of
                // the words jumps to the head of its own run while everything after it slides
                // a capsule's width sideways, all in the same frame.
                .animation(DipleMotion.snappy, value: model.facetOptions)
            }
            .contentMargins(.horizontal, 0, for: .scrollContent)
            // A chosen chip sorts to the front of its run, which is no use if the row is still
            // scrolled to where the reader pressed it. The row returns to its start whenever
            // the narrowing changes, so what is now in force is always the first thing on it.
            .onChange(of: model.facets) { _, _ in
                withAnimation(DipleMotion.standard) {
                    proxy.scrollTo(Self.chipRowStart, anchor: .leading)
                }
            }
        }
    }

    /// The runs the row prints, capped. The split lives on `MarginaliaBoard` because the
    /// desktop needs the identical one — it wraps each run onto its own line instead of ruling
    /// between them, but it is the same three runs and the same per-run cap.
    private var facetRuns: [MarginaliaBoard.FacetRun] {
        MarginaliaBoard.runs(of: model.facetOptions, limit: visibleFacets)
    }

    /// What separates two runs. A hairline, at the height of the capsules beside it and not of
    /// the band: a rule as tall as the row would be a wall, and the runs are neighbours in one
    /// sentence rather than two paragraphs.
    private var runDivider: some View {
        Rectangle()
            .fill(DipleColor.hairline)
            .frame(width: DipleStroke.hairline, height: 18)
            .padding(.horizontal, DipleSpace.xs)
            .accessibilityHidden(true)
    }

    private static let chipRowStart = "marginalia.chips.start"

    /// The door to everything the row could not print.
    ///
    /// The number on it is **what is behind the door**, not how many filters are on. It used to
    /// be the latter, which on a library of thirty names was a second copy of something the row
    /// already says twice — every chosen chip carries a cross, and Clear stands next to this —
    /// and on a library of three hundred left the reader with no way to know that the eight
    /// shelves in front of them were eight of two hundred and ninety. A row that is a fraction
    /// has to say so; how big the fraction is, is the one fact the row itself cannot show.
    ///
    /// The ring still says filters are in force. That is a state, and it is what `dipleSelected`
    /// is for; the count beside it is a size.
    private var filterSheetChip: some View {
        Button {
            HapticManager.shared.selection()
            isFilterSheetPresented = true
        } label: {
            HStack(spacing: DipleSpace.xs) {
                Image(systemName: "line.3.horizontal.decrease")
                    .dipleIcon(11, weight: .semibold)
                    .foregroundStyle(model.facets.isEmpty ? DipleColor.textTertiary : DipleColor.accentInk)

                if hiddenFacetCount > 0 {
                    Text("+\(hiddenFacetCount)")
                        .dipleType(.micro, weight: .regular)
                        .monospacedDigit()
                        .foregroundStyle(DipleColor.textQuaternary)
                }
            }
            .diplePadding(.chip)
            .frame(minHeight: 28)
            .dipleSelected(!model.facets.isEmpty, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            hiddenFacetCount > 0
                ? "All sources and tags, \(hiddenFacetCount) more not shown"
                : "All sources and tags"
        )
    }

    /// How many names the row is not printing. The runs are capped per kind and the marks are
    /// never capped, so the two cancel and this is exactly what the sheet holds beyond the row.
    private var hiddenFacetCount: Int {
        let shown = facetRuns.reduce(0) { $0 + $1.options.count }
        return max(0, model.facetOptions.count - shown)
    }

    /// One way out of every narrowing at once.
    ///
    /// Each chosen chip already carries its own cross, and with one filter in force that is the
    /// shorter path — so this appears beside the door to the sheet rather than in place of the
    /// crosses. With a colour, a shelf and two words in force, and a search string besides,
    /// undoing them one at a time is four taps and a scroll to find the fourth; the reader who
    /// wants their catalogue back wants all of it back.
    private var clearChip: some View {
        Button {
            HapticManager.shared.selection()
            withAnimation(DipleMotion.standard) { model.clearNarrowing() }
        } label: {
            Text("Clear")
                .dipleType(.micro, weight: .semibold)
                .foregroundStyle(DipleColor.textTertiary)
                .diplePadding(.chip)
                .frame(minHeight: 28)
                .background(DipleColor.surfaceOverlay, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Clear every filter")
        .transition(.opacity.combined(with: .scale(scale: 0.9)))
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
        case .color(let hex): return .color(hex)
        }
    }

    // MARK: - The catalogue

    @ViewBuilder
    private var content: some View {
        LazyVStack(alignment: .leading, spacing: DipleSpace.l) {
            if model.lenses.contains(.unsorted), model.results.count > 1, !model.isSelecting {
                filingInvitation
            }

            ForEach(model.groups) { group in
                if model.grouping != .none {
                    groupHeader(group)
                }
                entries(of: group)
            }
        }
        .padding(.horizontal, DipleSpace.xl)
    }

    /// The way into the filing pass, and it appears only where it makes sense: standing in
    /// Unsorted with more than one row in front of you. A resident control for a ritual nobody
    /// performs most days is the same trade the masthead already refuses.
    private var filingInvitation: some View {
        Button {
            HapticManager.shared.selection()
            isFilingPassPresented = true
        } label: {
            HStack(spacing: DipleSpace.m) {
                Image(systemName: "tray.and.arrow.down")
                    .dipleIcon(15, weight: .medium)
                    .foregroundStyle(DipleColor.accentInk)

                VStack(alignment: .leading, spacing: DipleSpace.xs) {
                    Text("Sort these out")
                        .dipleType(.body, weight: .semibold)
                        .foregroundStyle(DipleColor.textPrimary)
                    Text("One at a time, with the words you use.")
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)
                        .lineLimit(1)
                }

                Spacer(minLength: DipleSpace.s)

                Text("\(model.results.count)")
                    .dipleType(.footnote, weight: .semibold)
                    .monospacedDigit()
                    .foregroundStyle(DipleColor.textTertiary)

                Image(systemName: "chevron.right")
                    .dipleIcon(11, weight: .semibold)
                    .foregroundStyle(DipleColor.textQuaternary)
            }
            .padding(DipleSpace.m)
            .craftSurface(DipleColor.surface)
        }
        .buttonStyle(.bookCard)
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
        if model.isSelecting {
            selectableRow(entry)
        } else {
            switch entry {
            case .note(let item):
                NavigationLink(value: NoteRoute.existing(item)) {
                    NoteCardView(item: item, style: layout == .cards ? .card : .row)
                }
                .buttonStyle(.bookCard)
                .matchedTransitionSource(id: item.id, in: cardNamespace)
                .contextMenu { noteMenu(item) }

            case .passage(let item):
                // A passage opens its own editor rather than the book. On this board the reader
                // is going over what they have made — commenting, tagging, filing — and the
                // comment is the thing they came for; the way back into the page is one row
                // inside the sheet. Home's resurfacing card keeps the opposite rule for the
                // opposite reason.
                Button {
                    HapticManager.shared.selection()
                    openPassage(item)
                } label: {
                    PassageRowView(passage: item, style: layout == .cards ? .card : .row)
                }
                .buttonStyle(.bookCard)
                .contextMenu { passageMenu(item) }
            }
        }
    }

    /// The same entry, with a mark in front of it.
    ///
    /// The mark sits in a fixed leading column that every row gets, chosen or not, so the left
    /// edge of the catalogue stays flush while choosing. A check that only appears on the
    /// chosen rows makes the column shuffle sideways under the thumb on every tap.
    private func selectableRow(_ entry: MarginaliaEntry) -> some View {
        let isSelected = model.isSelected(entry)
        return Button {
            HapticManager.shared.selection()
            withAnimation(DipleMotion.snappy) { model.toggleSelection(entry) }
        } label: {
            HStack(alignment: .top, spacing: DipleSpace.m) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .dipleIcon(18, weight: .regular)
                    .foregroundStyle(isSelected ? DipleColor.accentInk : DipleColor.textQuaternary)
                    .frame(width: 22)
                    .padding(.top, layout == .cards ? DipleSpace.l : DipleSpace.xl)

                entryContent(entry)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    @ViewBuilder
    private func entryContent(_ entry: MarginaliaEntry) -> some View {
        switch entry {
        case .note(let item):
            NoteCardView(item: item, style: layout == .cards ? .card : .row)
        case .passage(let item):
            PassageRowView(passage: item, style: layout == .cards ? .card : .row)
        }
    }

    @ViewBuilder
    private func noteMenu(_ item: NoteItem) -> some View {
        selectButton(.note(item))

        Button {
            UIPasteboard.general.string = item.note.body
        } label: {
            Label("Copy text", systemImage: "doc.on.doc")
        }

        // Asked about, like a passage. There is no Recently deleted to bring it back from any
        // more, and a passage can at least be marked again from its page; a thought cannot.
        Button(role: .destructive) {
            model.confirmDelete(.note(item))
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func passageMenu(_ item: PassageItem) -> some View {
        selectButton(.passage(item))

        if let book = item.book, item.highlight.parsedLocator != nil {
            Button {
                openInBook(.passage(book: book, locatorJSON: item.highlight.locator))
            } label: {
                Label("Open in the book", systemImage: "book")
            }
        }

        Button {
            openNote(.newFromPassage(item))
        } label: {
            Label("Expand into a note", systemImage: "square.and.pencil")
        }

        Button {
            UIPasteboard.general.string = item.highlight.text
        } label: {
            Label("Copy passage", systemImage: "doc.on.doc")
        }

        // Beside Copy rather than instead of it: text is what goes into a document, a picture
        // is what goes into a conversation, and the passage is the same passage either way.
        Button {
            cardPassage = item
        } label: {
            Label("Share as a card", systemImage: "text.below.photo")
        }

        Button(role: .destructive) {
            model.confirmDelete(.passage(item))
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    /// The way in to choosing. A long press is where iOS has put "act on several of these"
    /// for a decade, and it costs the board no resident control — the masthead is already four
    /// glyphs wide, and a fifth spent on a mode nobody is in most of the time is the trade this
    /// app keeps refusing.
    private func selectButton(_ entry: MarginaliaEntry) -> some View {
        Button {
            HapticManager.shared.selection()
            withAnimation(DipleMotion.standard) { model.beginSelecting(with: entry) }
        } label: {
            Label("Select", systemImage: "checkmark.circle")
        }
    }

    // MARK: - The workbench

    /// What can be done to the rows that were chosen.
    ///
    /// It takes the tab bar's place rather than floating above it. Choosing is a mode with one
    /// way out — Done, in the masthead — and leaving navigation live underneath it would offer
    /// three ways to abandon a selection without saying that is what they do.
    private var selectionBar: some View {
        let chosen = model.selectedEntries.count

        return HStack(spacing: DipleSpace.s) {
            Button(action: collect) {
                HStack(spacing: DipleSpace.s) {
                    Image(systemName: "square.and.pencil")
                        .dipleIcon(14, weight: .semibold)
                    Text("Collect into a note")
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

            // Share rather than a bare Copy. The system sheet carries Copy inside it, and
            // adds the destinations a compilation is actually for — a vault, a draft, a
            // colleague — for the same one control the bar can afford.
            ShareLink(
                item: model.selectedDocument,
                preview: SharePreview(model.selectedDocument.name)
            ) {
                Image(systemName: "square.and.arrow.up")
                    .dipleIcon(15, weight: .semibold)
                    .foregroundStyle(DipleColor.textSecondary)
                    .frame(width: 46, height: 46)
                    .background(DipleColor.surfaceOverlay, in: Circle())
            }
            .buttonStyle(.readerControl)
            .accessibilityLabel("Share all")

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

    /// The gathered note is opened, not merely written. A document that appears somewhere in a
    /// list is a document you have to go and find.
    private func collect() {
        guard let item = model.collect() else { return }
        HapticManager.shared.impact(.light)
        openNote(.existing(item))
    }

    // MARK: - Deletion

    private var deleteTitle: String {
        model.entryToDelete?.kind == .saved ? "Delete passage?" : "Delete note?"
    }

    /// Both are asked about. A passage can be marked again from the same page; something
    /// written cannot, and since 2026-09-27 there is no Recently deleted to fetch it back from.
    private var deleteMessage: String {
        model.entryToDelete?.kind == .saved
            ? "This passage and its comment will be removed."
            : "This note will be deleted."
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
            // Each half's own glyph. A page with writing on it over an empty passages half was
            // the last place the two collections were still being drawn as one.
            Image(systemName: door == .notes ? "note.text" : "quote.opening")
                .dipleIcon(30, weight: .thin)
                .foregroundStyle(DipleColor.accentInk)

            VStack(spacing: DipleSpace.s) {
                Text(door == .notes ? "Write the first note" : "Nothing marked yet")
                    .dipleType(.editorialTitle)
                    .foregroundStyle(DipleColor.textPrimary)

                Text(
                    door == .notes
                        ? "A note written in a book lands here with the book’s name on it. One started with the pencil above can be linked to a book from its page."
                        : "Mark a passage while reading and it collects here, by source, by tag and by the colour you marked it with."
                )
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DipleSpace.xxxl)
            }

            // No button here: the pencil is already in the masthead above, and an empty state
            // that repeats it is two controls for one act on one screen.
        }
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical, alignment: .center) { length, _ in
            max(length - DipleSpace.scrollBottom, 420)
        }
    }
}

