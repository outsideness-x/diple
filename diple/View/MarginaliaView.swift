import SwiftUI
// Scoped on purpose. A plain `import ReadiumShared` brings its own `Content` into the file, and
// `ViewModifier.body(content: Content)` then resolves against that instead of the associated
// type — every `ViewModifier` here stops conforming, with an error pointing at the modifier
// rather than at the import.
import struct ReadiumShared.Locator

/// Which room of the board this is.
///
/// Two rooms over one catalogue — the arrangement the desktop's sidebar already had. The room
/// decides *what it holds* and two small things that follow from that; every control below it
/// is the same board.
///
/// What the room no longer decides is a starting point the reader can walk away from. There
/// used to be a scope bar under the masthead — All / Written / Saved — so Highlights opened on
/// passages and was one tap from a page of notes, with the masthead announcing both counts in
/// both rooms. Two doors into a room you can leave by the same door are one room with a
/// confusing name: a reader who marked something in a book and came to Highlights was shown
/// their notes. Highlights holds passages, Notes holds notes, and neither shows the other's.
public enum MarginaliaDoor {
    case notes
    case highlights

    var title: String {
        switch self {
        case .notes: return "Notes"
        case .highlights: return "Highlights"
        }
    }

    /// What this room holds — fixed for as long as it is open, not a first position.
    var scope: MarginaliaScope {
        switch self {
        case .notes: return .written
        case .highlights: return .saved
        }
    }

    /// The day's passage stands at the top of the room the passages are in, and nowhere else.
    var showsDailyPassage: Bool { self == .highlights }

    /// A note is written from the notes room: this is the room that answers the bar's `+` in
    /// the notes workshop. Nothing writes a passage but reading one, so the passages room
    /// never does.
    var offersNewNote: Bool { self == .notes }
}

/// How the board stands inside another screen's stack rather than as a tab of its own.
///
/// The notes workshop pushes the whole board as its All notes page: every chip, the grouping,
/// the workbench and the filing pass, one row deeper than the Desk rather than on the first
/// screen of the mode. Inside someone else's `NavigationStack` the board must not open a second
/// one, and must not declare destinations of its own — SwiftUI keeps only the declaration nearest
/// the root for a type and silently drops the rest, the trap already recorded under "Home и
/// навигация". So it pushes onto the host's path and the host resolves the routes.
public struct MarginaliaEmbedding {
    let title: String
    let path: Binding<NavigationPath>
    /// A word the board opens already narrowed to — the Tags index sends the reader here with
    /// one chip pressed, which is all a page for one tag would have been.
    let initialTag: String?

    public init(title: String, path: Binding<NavigationPath>, initialTag: String? = nil) {
        self.title = title
        self.path = path
        self.initialTag = initialTag
    }
}

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
/// So the collections keep their tables and share their controls — the filter row, the search
/// field, the order, the grouping and the filing pass are written once and stand in both rooms.
/// What they no longer share is a page: each room shows one kind. What changed is one screen,
/// not one schema.
public struct MarginaliaView: View {
    private let door: MarginaliaDoor
    private let embedding: MarginaliaEmbedding?
    @StateObject private var model: MarginaliaViewModel

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
    /// The passage being made into a card, if any.
    @State private var cardPassage: PassageItem?
    @State private var renameDraft = ""
    @State private var tagDraft = ""
    @State private var isAddingTagToSelection = false
    @State private var isConfirmingBulkDelete = false
    @State private var isFilingPassPresented = false
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

    /// How many names the row prints *per run* before the rest are left to the filter sheet.
    /// Enough that an ordinary library never needs the sheet, few enough that the row stays a
    /// row. It is counted per run rather than over the whole row for the reason the runs exist
    /// at all: one cap across a list that begins with shelves means a library with nine books
    /// prints no words, and the word is what most readers came to press.
    private let visibleFacets = 8

    public init(door: MarginaliaDoor = .notes, embedding: MarginaliaEmbedding? = nil) {
        self.door = door
        self.embedding = embedding
        let model = MarginaliaViewModel(scope: door.scope)
        if let tag = embedding?.initialTag { model.facets.tags = [tag] }
        _model = StateObject(wrappedValue: model)
    }

    private var title: String { embedding?.title ?? door.title }

    /// Every push the board makes, onto whichever stack it is standing in.
    private func push<Route: Hashable>(_ route: Route) {
        if let embedding {
            embedding.path.wrappedValue.append(route)
        } else {
            push(route)
        }
    }

    public var body: some View {
        if embedding != nil {
            board
                // A pushed page keeps the system bar for its back button; the masthead below it
                // still carries the page's name.
                .navigationTitle("")
                .navigationBarTitleDisplayMode(.inline)
                .toolbarBackground(DipleColor.canvas, for: .navigationBar)
        } else {
            NavigationStack(path: $path) {
                board
                    // Set but hidden: it is what a pushed screen labels its own back button with.
                    .navigationTitle(title)
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar(.hidden, for: .navigationBar)
                    .modifier(MarginaliaDestinations(host: self))
            }
        }
    }

    /// The routes the board resolves itself — only when it owns its stack. Embedded, the host
    /// declares them; see `MarginaliaEmbedding`.
    private struct MarginaliaDestinations: ViewModifier {
        let host: MarginaliaView

        func body(content: Content) -> some View {
            content
                .navigationDestination(for: NoteRoute.self) { route in
                    host.noteDestination(for: route)
                }
                .navigationDestination(for: MarginaliaRoute.self) { route in
                    switch route {
                    case let .passage(book, locatorJSON):
                        ReaderContainerView(
                            book: book,
                            startingLocator: Locator.from(jsonString: locatorJSON),
                            onReadingUpdated: { host.model.load() }
                        )
                    }
                }
                .navigationDestination(for: Book.self) { book in
                    ReaderContainerView(book: book, onReadingUpdated: { host.model.load() })
                }
        }
    }

    private var board: some View {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                // One stable root under the stack. Swapping empty/workspace while the first
                // note autosaved invalidated the active destination and made the editor look
                // as though it had vanished.
                workspace
            }
            .sheet(item: $cardPassage) { passage in
                PassageCardSheet(passage: passage)
            }
            .sheet(item: $editingPassage, onDismiss: consumePendingPush) { passage in
                passageEditor(for: passage)
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
            .alert("Delete \(model.selectedEntries.count) items?", isPresented: $isConfirmingBulkDelete) {
                Button("Delete", role: .destructive) { model.deleteSelection() }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Notes go to Recently deleted for thirty days. Passages and their comments are removed for good.")
            }
            .refreshesOnTabActivation { model.load() }
    }

    // MARK: - Frame

    private var workspace: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DipleSpace.l, pinnedViews: [.sectionHeaders]) {
                masthead

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

    /// The day's passage, at the head of the room it belongs to.
    ///
    /// It used to open the front page, where it was the largest thing on a screen about what to
    /// read next, and where it made Home a third place saved passages lived. Here it is the
    /// first thing in the room that holds them — which is also where the daily notification and
    /// the widget now land.
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
            push(MarginaliaRoute.passage(book: book, locatorJSON: item.quote.locator))
        } else if let passage = model.entries
            .compactMap(\.passageItem)
            .first(where: { $0.id == item.quote.id }) {
            editingPassage = passage
        }
    }

    private var masthead: some View {
        DipleMasthead(title: title, strapline: strapline) {
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
            // No `+` here any more. In the notes workshop the bar's own verb circle *is* the
            // `+`, always under the thumb; a second one in the masthead would be two controls
            // for one act on one screen.
    }

    /// What this room holds in total, not what it is currently showing — the narrowed count
    /// belongs on the chips, where pressing one is what changes it.
    ///
    /// Its own kind and nothing else. Both counts were printed in both rooms while the scope
    /// bar could walk between them; over a page of passages, "4 notes · 12 passages" now names
    /// a collection this room does not contain.
    private var strapline: String? {
        if model.isSelecting {
            let count = model.selectedEntries.count
            return count == 0 ? "Choose what to collect" : "\(count) selected"
        }
        let total = model.totalInScope
        guard total > 0 else { return nil }
        switch door {
        case .notes: return total == 1 ? "1 note" : "\(total) notes"
        case .highlights: return total == 1 ? "1 passage" : "\(total) passages"
        }
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
                    editingPassage = item
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

        // No question: a note goes to Recently deleted and can be brought back for thirty days.
        // A passage, which cannot, is still asked about.
        Button(role: .destructive) {
            HapticManager.shared.impact(.light)
            model.delete(.note(item))
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    @ViewBuilder
    private func passageMenu(_ item: PassageItem) -> some View {
        selectButton(.passage(item))

        if let book = item.book, item.highlight.parsedLocator != nil {
            Button {
                push(MarginaliaRoute.passage(book: book, locatorJSON: item.highlight.locator))
            } label: {
                Label("Open in the book", systemImage: "book")
            }
        }

        Button {
            push(NoteRoute.newFromPassage(item))
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
        push(NoteRoute.existing(item))
    }

    // MARK: - Destinations

    @ViewBuilder
    fileprivate func noteDestination(for route: NoteRoute) -> some View {
        let page = NoteDetailView(
            route: route,
            books: model.books,
            suggestedTags: model.noteTagVocabulary,
            allNotes: model.entries.compactMap(\.noteItem),
            passages: model.entries.compactMap(\.passageItem),
            onSave: { note, tags in model.save(note, tags: tags) },
            onDelete: { model.delete(.note($0)) },
            onOpenNote: { push(NoteRoute.existing($0)) },
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
            push(route)
        case let .reader(book, locatorJSON):
            push(MarginaliaRoute.passage(book: book, locatorJSON: locatorJSON))
        }
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
            // The room's own glyph, the one the tab bar already stands for. A page with
            // writing on it over an empty passages room was the last place the two collections
            // were still being drawn as one.
            Image(systemName: door == .notes ? "note.text" : "quote.opening")
                .dipleIcon(30, weight: .thin)
                .foregroundStyle(DipleColor.accentInk)

            VStack(spacing: DipleSpace.s) {
                Text(door == .notes ? "Write the first note" : "Nothing marked yet")
                    .dipleType(.editorialTitle)
                    .foregroundStyle(DipleColor.textPrimary)

                Text(
                    door == .notes
                        ? "Everything you write collects here, by source and by tag. Passages you keep while reading are in Highlights."
                        : "Mark a passage while reading and it collects here, by source, by tag and by the colour you marked it with."
                )
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DipleSpace.xxxl)
            }

            // No button here: in the notes workshop the bar's `+` is already under the thumb,
            // and an empty state that repeats it is two controls for one act on one screen.
        }
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical, alignment: .center) { length, _ in
            max(length - DipleSpace.scrollBottom, 420)
        }
    }
}

