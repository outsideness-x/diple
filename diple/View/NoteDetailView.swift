import SwiftUI

/// Where the board can navigate to. A brand new note has no card to expand from, so it is a
/// route of its own rather than an optional item.
public enum NoteRoute: Hashable {
    case existing(NoteItem)
    case new
    case newFromSource(Book)
    /// A note grown out of a saved passage: the quotation is already in the body, and the
    /// thought goes underneath it.
    case newFromPassage(PassageItem)
    /// A note started with the `+` while standing in a space: it is born in that space.
    case newInSpace(NoteSpace)
    /// The day's page, not yet begun, for a key from `Note.dailyKey(for:)`.
    case daily(String)

    public var item: NoteItem? {
        switch self {
        case .existing(let item): return item
        case .new, .newFromSource, .newFromPassage, .newInSpace, .daily: return nil
        }
    }

    /// The day a new page is the page of, if it is one.
    public var initialDailyDate: String? {
        if case .daily(let key) = self { return key }
        return nil
    }

    /// The title a new note opens with: the day, for a day's page, and nothing for any other.
    public var initialTitle: String {
        if case .daily(let key) = self { return Note.dailyTitle(forKey: key) }
        return ""
    }

    /// The space a new note is born in. Only the new note's own route has one: an existing
    /// note's place belongs to the organising calls, not to its editor (see `Note`).
    public var initialSpaceId: String? {
        if case .newInSpace(let space) = self { return space.id }
        return nil
    }

    /// A blank page the reader asked for with `+` — in the Inbox or in a space. The one kind of
    /// new note that opens with the keyboard on its title: the `+` is the notes workshop's verb,
    /// and asking for a page is asking to write on it.
    public var isBlankPage: Bool {
        switch self {
        case .new, .newInSpace: return true
        case .existing, .newFromSource, .newFromPassage, .daily: return false
        }
    }

    public var initialBookId: String? {
        switch self {
        case .newFromSource(let book): return book.id
        case .newFromPassage(let passage): return passage.highlight.bookId
        case .existing, .new, .newInSpace, .daily: return nil
        }
    }

    /// What a new note already has written in it. Empty for every route but one — a note is
    /// otherwise a blank page on purpose.
    public var initialBody: String {
        if case .newFromPassage(let passage) = self { return passage.noteSeed }
        return ""
    }

    /// The tags a note is born with.
    ///
    /// A note started inside a source — from the reader's own page, or from the source
    /// overview — carries that source's name as a tag from the moment it exists. It is a
    /// normal tag, drawn as a normal chip in the properties row and removable with one tap:
    /// the app files the thought where it was had, and the writer keeps the last word on it.
    /// See `TagName.forSource(titled:)` for what the word is.
    /// A passage carries its own words across as well as its source's.
    ///
    /// This is the one place the three vocabularies touch, and it is one-directional and asked
    /// for: a passage filed as `#objection` that the reader chooses to expand is being expanded
    /// *because* it is an objection, and a note that arrived without the word would have thrown
    /// away the reason it was written. Nothing travels the other way, no menu on one side is
    /// widened by the other, and every inherited chip comes off in a tap.
    public var initialTags: [String] {
        switch self {
        case .newFromSource(let book):
            return [TagName.forSource(titled: book.title)].compactMap { $0 }
        case .newFromPassage(let passage):
            let source = passage.book?.title ?? passage.highlight.bookTitle
            let sourceTag = source.flatMap { TagName.forSource(titled: $0) }
            var tags = passage.tags
            if let sourceTag, !tags.contains(sourceTag) { tags.append(sourceTag) }
            return tags
        case .existing, .new, .newInSpace, .daily:
            return []
        }
    }
}

/// A route can also be raised as a sheet — the reader has no stack of its own to push a note
/// onto, and presents one over the page instead.
extension NoteRoute: Identifiable {
    public var id: String {
        switch self {
        case .existing(let item): return "existing:\(item.id)"
        case .new: return "new"
        case .newFromSource(let book): return "source:\(book.id)"
        case .newFromPassage(let passage): return "passage:\(passage.id)"
        case .newInSpace(let space): return "space:\(space.id)"
        case .daily(let key): return "daily:\(key)"
        }
    }
}

/// A note as a page rather than a form.
///
/// Reading comes first: the note is set as a document — system sans, one column, structure
/// rendered rather than shown as syntax. Editing is a mode you enter, not
/// the resting state, which is what keeps the note something you can sit and read.
///
/// This is also the only note editor in the app. Composing and revising share one screen
/// because two editors drift: a tag rule fixed in one is left broken in the other.
public struct NoteDetailView: View {
    public let route: NoteRoute
    public let books: [Book]
    public let suggestedTags: [String]
    public let allNotes: [NoteItem]
    /// The saved passages this page can draw a connection to. Empty where the host has none
    /// loaded — the block simply does not appear, which is the honest answer: it is a
    /// difference in what is at hand, not a second rule about what counts as related.
    public let passages: [PassageItem]
    public let onSave: (Note, [String]) -> Bool
    public let onDelete: (NoteItem) -> Void
    /// Following a `[[Wiki link]]` in the reading view. The push belongs to whichever stack
    /// this page was opened in, so the route goes back out to its owner rather than being
    /// invented here.
    public let onOpenNote: ((NoteItem) -> Void)?
    /// Opening one of those passages. Same arrangement as `onOpenNote`: what happens next
    /// belongs to the screen this page was opened in, not to this page.
    public let onOpenPassage: ((PassageItem) -> Void)?

    /// The notes a wiki-link can point at. `allNotes` and `route` never change while this
    /// screen is on screen, so this is settled once in `init` — computing it inside `body`
    /// re-filtered the whole library and rebuilt a thirty-item menu on every keystroke.
    private let linkableNotes: [NoteItem]

    @Environment(\.dismiss) private var dismiss

    /// The optional look at the page as it will read — formulas set, callouts drawn, the
    /// outline listed — reached by the eye in the toolbar. The page itself is never in a mode:
    /// it is open for writing from the moment it opens.
    @State private var isPreviewing = false
    @State private var title: String
    @State private var body_: String
    /// The body the Connections block was last built from.
    ///
    /// Connections read every note in the library and run a regular expression over this one.
    /// Under an editor that is always open, wired to `body_`, that would run on every keystroke
    /// — the same cost the caret was moved out of SwiftUI state to avoid. It settles a beat
    /// after typing stops, which is the same moment the note is written.
    @State private var settledBody: String
    @State private var tags: [String]
    @State private var tagDraft: String = ""
    @State private var selectedBookId: String?
    @State private var isBookPickerPresented = false
    @State private var isAddingTag = false
    @State private var slashContext: NoteSlashContext?
    @State private var isBodyFocused = false
    @FocusState private var isTitleFocused: Bool
    @State private var selection = NoteSelectionBox()
    @State private var saveState: NoteSaveState = .saved
    @State private var saveTask: Task<Void, Never>?
    @State private var draftID: String
    @State private var lastSavedSnapshot: String
    @State private var isFormulaComposerPresented = false
    @State private var formulaSeed = ""
    @State private var formulaMode: NoteFormulaMode = .inline
    @State private var formulaSessionID = UUID()

    public init(
        route: NoteRoute,
        books: [Book],
        suggestedTags: [String],
        allNotes: [NoteItem] = [],
        passages: [PassageItem] = [],
        onSave: @escaping (Note, [String]) -> Bool,
        onDelete: @escaping (NoteItem) -> Void = { _ in },
        onOpenNote: ((NoteItem) -> Void)? = nil,
        onOpenPassage: ((PassageItem) -> Void)? = nil
    ) {
        self.route = route
        self.books = books
        self.suggestedTags = suggestedTags
        self.allNotes = allNotes
        self.passages = passages
        self.onSave = onSave
        self.onDelete = onDelete
        self.onOpenNote = onOpenNote
        self.onOpenPassage = onOpenPassage
        self.linkableNotes = Array(allNotes.filter { $0.id != route.item?.id }.prefix(30))

        let item = route.item
        _title = State(initialValue: item?.note.title ?? route.initialTitle)
        _body_ = State(initialValue: item?.note.body ?? route.initialBody)
        _settledBody = State(initialValue: item?.note.body ?? route.initialBody)
        _tags = State(initialValue: item?.tags ?? route.initialTags)
        _selectedBookId = State(initialValue: item?.note.bookId ?? route.initialBookId)
        _draftID = State(initialValue: item?.id ?? UUID().uuidString)
        _lastSavedSnapshot = State(initialValue: Self.snapshot(
            title: item?.note.title ?? route.initialTitle,
            body: item?.note.body ?? route.initialBody,
            tags: item?.tags ?? route.initialTags,
            bookID: item?.note.bookId
        ))
    }

    private enum NoteSaveState {
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

        var color: Color {
            switch self {
            case .saved: return DipleColor.textQuaternary
            case .saving: return DipleColor.accent
            case .failed: return DipleColor.destructive
            }
        }
    }

    private var selectedBook: Book? {
        books.first { $0.id == selectedBookId }
    }

    /// The keyboard is up and the page belongs to the hands: the tab bar steps aside, the
    /// formatting bar takes the bottom of the screen, and the toolbar offers Done.
    private var isWriting: Bool { isBodyFocused || isTitleFocused }

    private var canSave: Bool {
        let hasBody = !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        // A day's page arrives with its date already in the title, and a page holding only the
        // date it was opened on is not a page anybody wrote. It exists from its first word.
        if route.item == nil, route.initialDailyDate != nil { return hasBody }
        return hasBody || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var unusedSuggestions: [String] {
        suggestedTags.filter { !tags.contains($0) }
    }

    /// The heading the reading view shows.
    ///
    /// Falls back to the note's opening line the same way a card does. It did not, so a note
    /// without a title was called by its first line on the board and "Untitled" the moment it
    /// was opened — the same note under two names, and the emptier name on the bigger type.
    private var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { return trimmed }
        return NoteItem(
            note: Note(id: draftID, title: nil, body: body_, bookId: selectedBookId),
            tags: tags,
            book: selectedBook
        ).displayTitle
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DipleSpace.xxl) {
                        if isPreviewing {
                            reader { anchor in
                                withAnimation(DipleMotion.gentle) {
                                    proxy.scrollTo(anchor, anchor: .top)
                                }
                            }
                        } else {
                            editor
                        }
                    }
                    // A page of prose stops being readable long before it stops being wide, so the
                    // column holds its measure and the margins take the rest.
                    .frame(maxWidth: 680, alignment: .leading)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.horizontal, DipleSpace.xl)
                    .padding(.top, DipleSpace.l)
                    .padding(.bottom, DipleSpace.scrollBottom)
                }
            }
        }
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DipleColor.canvas, for: .navigationBar)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // Only with the body's own keyboard up. These buttons write into the body, and a
            // bar offering Bold while the caret sits in the title offers to format somewhere
            // the writer is not looking.
            if isBodyFocused {
                formattingBar
            }
        }
        // A note page takes the tab bar down for as long as it is open, the way the reader
        // does. Two reasons, and either would be enough.
        //
        // The first is what the bar would say. Its `+` starts a note; offered over a note that
        // is open and being written, it offers to start a second one. A page is not a place,
        // and the bar belongs to places.
        //
        // The second is that it cannot be drawn over this page at all. The floating bar sits in
        // the shell's ZStack above the whole root, and above a page holding the editor's
        // `UITextView` the hosting view's layout never settles: `layoutSubviews` re-enters
        // forever, `makeUIView` builds text view after text view, and the main thread sits at
        // 100% — the keyboard cannot even come up. It went unseen until now because the two had
        // never met: before the page opened for writing, the bar was up only over the *rendered*
        // note, and editing hid it.
        .hidesDipleTabBar()
        .sheet(isPresented: $isBookPickerPresented) {
            BookTagPickerView(books: books, selectedBookId: selectedBookId) { bookId in
                selectedBookId = bookId
            }
        }
        .sheet(isPresented: $isFormulaComposerPresented) {
            NoteFormulaComposer(initialLatex: formulaSeed, initialMode: formulaMode) { mode, latex in
                NoteEditing.insertFormula(latex, mode: mode, in: &body_, selection: selection)
                isBodyFocused = true
            }
            .id(formulaSessionID)
        }
        .alert("New tag", isPresented: $isAddingTag) {
            TextField("Tag", text: $tagDraft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Add") { commitTagDraft() }
            Button("Cancel", role: .cancel) { tagDraft = "" }
        }
        .environment(\.openURL, OpenURLAction { url in
            // Only this app's own wiki-link scheme is intercepted; a real http link in a note
            // must still open the way the reader expects.
            guard let title = NoteMarkdown.wikiLinkTitle(from: url) else { return .systemAction }
            guard let target = note(titled: title), let onOpenNote else { return .handled }
            HapticManager.shared.selection()
            onOpenNote(target)
            return .handled
        })
        .animation(DipleMotion.standard, value: isPreviewing)
        .onAppear {
            // A note started *inside* a source opens ready to write. The reader tapped a
            // pencil with a book in hand and has one sentence in mind; asking them to find the
            // text field afterwards spends a tap on nothing, and on a phone it is the tap that
            // loses the thought.
            //
            // A blank page asked for with `+` opens with the keyboard on its title. That used to
            // be deliberately left alone, when "New note" was one of four equal controls on the
            // board and the next move was as likely a template or a tag. In the notes workshop
            // the `+` is the verb the whole mode is built around, and Things, Bear and Apple Notes
            // all answer it the same way: here is the page, write.
            // The day's page too: its title is the date, already written, and what the reader
            // came to put down is the first line of the day.
            if route.item == nil && (route.initialBookId != nil || route.initialDailyDate != nil) {
                isBodyFocused = true
            }
        }
        .task {
            // After the push has landed rather than during it: focus asked for while the page is
            // still sliding in is dropped by the text field it was meant for.
            guard route.isBlankPage else { return }
            try? await Task.sleep(for: .milliseconds(350))
            isTitleFocused = true
        }
        .onChange(of: title) { _, _ in scheduleSave() }
        .onChange(of: body_) { _, _ in scheduleSave() }
        .onChange(of: tags) { _, _ in scheduleSave() }
        .onChange(of: selectedBookId) { _, _ in scheduleSave() }
        .onDisappear {
            saveTask?.cancel()
            if canSave && currentSnapshot != lastSavedSnapshot {
                _ = save(feedback: false)
            }
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        // An empty new note has never been written anywhere, so "Saved" would be a claim about
        // a row that does not exist. The indicator appears once there is something a save could
        // actually be about — and the *item* appears with it: a principal toolbar item holding
        // an empty view sends UIKit into an endless measuring loop, which pinned the main thread
        // at 100% on every blank page.
        if canSave || route.item != nil {
            ToolbarItem(placement: .principal) {
                HStack(spacing: DipleSpace.s) {
                    Circle()
                        .fill(saveState.color)
                        .frame(width: 6, height: 6)
                        // The dot swells while a write is pending and settles when it
                        // lands, so saving is something the writer catches at the edge of
                        // vision rather than a word that quietly changes. Scaling leaves
                        // the dot's own 6pt footprint alone, so the row never reflows.
                        .scaleEffect(saveState == .saving ? 1.5 : 1)
                    Text(saveState.label)
                        .dipleType(.micro)
                        .foregroundStyle(saveState.color)
                        .contentTransition(.opacity)
                }
                .animation(DipleMotion.snappy, value: saveState)
            }
        }

        if isWriting {
            ToolbarItem(placement: .navigationBarTrailing) {
                // Puts the keyboard down. It leaves nothing, because there was no mode to
                // leave: what is written is already written, and Back is the way off the page.
                Button("Done") { finishWriting() }
                    .dipleType(.body, weight: .semibold)
                    .foregroundStyle(DipleColor.accentInk)
            }
        } else {
            ToolbarItem(placement: .navigationBarTrailing) {
                // The page as it will read: formulas set, callouts drawn, the outline listed.
                // Not the old Read half of a Read/Edit pair — nothing here is switched off by
                // it, and the writing state it returns to is the one the page opens in.
                Button {
                    HapticManager.shared.selection()
                    isPreviewing.toggle()
                } label: {
                    Image(systemName: isPreviewing ? "square.and.pencil" : "eye")
                        .dipleIcon(16)
                        .foregroundStyle(isPreviewing ? DipleColor.accentInk : DipleColor.textSecondary)
                }
                .buttonStyle(.readerControl)
                .accessibilityLabel(isPreviewing ? "Back to writing" : "Read the page")
                .accessibilityIdentifier("note.preview")
            }

            ToolbarItem(placement: .navigationBarTrailing) {
                Menu {
                    ShareLink(item: exportMarkdown) {
                        Label("Share Markdown", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        UIPasteboard.general.string = exportMarkdown
                        HapticManager.shared.impact(.light)
                    } label: {
                        Label("Copy Markdown", systemImage: "doc.on.doc")
                    }

                    Button {
                        UIPasteboard.general.string = NoteMarkdown.plainText(body_)
                        HapticManager.shared.impact(.light)
                    } label: {
                        Label("Copy plain text", systemImage: "text.alignleft")
                    }

                    if let item = route.item {
                        // No question first: the note goes to Recently deleted and can be
                        // brought back for thirty days. A save landing after this — the editor's
                        // own `onDisappear` — does not bring it back; `saveNote` keeps where a
                        // note lives, and that includes the bin.
                        Button(role: .destructive) {
                            HapticManager.shared.impact(.light)
                            onDelete(item)
                            dismiss()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .dipleIcon(16)
                        .foregroundStyle(DipleColor.textSecondary)
                }
            }
        }
    }

    // MARK: - Reading

    private func reader(scrollTo: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: DipleSpace.l) {
            Text(displayTitle)
                .dipleType(.noteTitle)
                .foregroundStyle(
                    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? DipleColor.textTertiary
                        : DipleColor.textPrimary
                )
                .multilineTextAlignment(.leading)

            metadataLine

            if outline.count > 1 {
                outlinePanel(scrollTo: scrollTo)
                    .padding(.top, DipleSpace.xs)
            }

            if !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                NoteMarkdownView(markdown: body_, onToggleTask: toggleTask)
                    .textSelection(.enabled)
                    .padding(.top, DipleSpace.s)
            }

            if !tags.isEmpty || selectedBook != nil {
                Rectangle()
                    .fill(DipleColor.separator)
                    .frame(height: DipleStroke.hairline)
                    .padding(.vertical, DipleSpace.s)

                FlowLayout(spacing: DipleSpace.s) {
                    if let book = selectedBook {
                        TagChipView(label: book.title, kind: .book)
                    }
                    ForEach(tags, id: \.self) { tag in
                        TagChipView(label: tag, kind: .text)
                    }
                }
            }

            connectionsSection
        }
    }

    private var outline: [NoteMarkdown.OutlineItem] {
        NoteMarkdown.outline(in: body_)
    }

    private func outlinePanel(scrollTo: @escaping (String) -> Void) -> some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            Label("On this page", systemImage: "list.bullet.indent")
                .dipleType(.micro, weight: .semibold)
                .foregroundStyle(DipleColor.textTertiary)

            ForEach(outline) { item in
                Button {
                    HapticManager.shared.selection()
                    scrollTo(item.anchor)
                } label: {
                    HStack(spacing: DipleSpace.s) {
                        Text(item.title)
                            .dipleType(.callout)
                            .foregroundStyle(item.level <= 2 ? DipleColor.textSecondary : DipleColor.textTertiary)
                            .lineLimit(1)
                        Spacer()
                        Image(systemName: "arrow.down")
                            .dipleIcon(9)
                            .foregroundStyle(DipleColor.textQuaternary)
                    }
                    .padding(.leading, CGFloat(max(item.level - 1, 0)) * DipleSpace.m)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(DipleSpace.m)
        .craftSurface(DipleColor.surface, radius: DipleRadius.m)
    }

    @ViewBuilder
    private var connectionsSection: some View {
        let backlinks = NoteKnowledge.backlinks(to: currentNoteForConnections, among: allNotes)
        let outgoing = NoteKnowledge.outgoing(from: settledBody, among: allNotes)
            .filter { $0.id != route.item?.id }
        let related = relatedNotes(excluding: Set((backlinks + outgoing).map(\.id)))

        let saved = relatedPassages()

        if !backlinks.isEmpty || !outgoing.isEmpty || !related.isEmpty || !saved.isEmpty {
            Rectangle()
                .fill(DipleColor.separator)
                .frame(height: DipleStroke.hairline)
                .padding(.top, DipleSpace.l)

            VStack(alignment: .leading, spacing: DipleSpace.l) {
                VStack(alignment: .leading, spacing: DipleSpace.xs) {
                    Text("CONNECTIONS")
                        .dipleType(.nano)
                        .foregroundStyle(DipleColor.accentInk)
                    Text("Part of a larger thought")
                        .dipleType(.headline)
                        .foregroundStyle(DipleColor.textPrimary)
                }

                if !backlinks.isEmpty {
                    connectionGroup("Links here", icon: "arrow.turn.up.left", notes: backlinks)
                }
                if !outgoing.isEmpty {
                    connectionGroup("Linked notes", icon: "link", notes: outgoing)
                }
                if !related.isEmpty {
                    connectionGroup("Related by context", icon: "sparkles", notes: related)
                }
                if !saved.isEmpty {
                    passageGroup(saved)
                }
            }
        }
    }

    /// The passages this note is standing next to.
    ///
    /// The block used to look only at notes, so a note about Sapiens could not see a single
    /// thing the reader had marked in Sapiens — the most obvious connection in the app, and the
    /// one the reader is most likely to want while writing. Same test as `relatedNotes`: the
    /// same source, or a word in common. The vocabularies stay separate; what is compared here
    /// is the words themselves, which is what the reader sees on both chips.
    private func relatedPassages() -> [PassageItem] {
        passages.filter { passage in
            let sharesBook = selectedBookId != nil && passage.highlight.bookId == selectedBookId
            let sharesTag = !Set(tags).isDisjoint(with: passage.tags)
            return sharesBook || sharesTag
        }
    }

    private func passageGroup(_ passages: [PassageItem]) -> some View {
        VStack(alignment: .leading, spacing: DipleSpace.s) {
            Label("Marked in the text", systemImage: "quote.opening")
                .dipleType(.micro, weight: .semibold)
                .foregroundStyle(DipleColor.textTertiary)

            ForEach(passages.prefix(4)) { passage in
                Button {
                    onOpenPassage?(passage)
                } label: {
                    HStack(spacing: DipleSpace.m) {
                        // The mark's own colour, as a rule down the side rather than under it:
                        // in a stack of connection cards there is no entry to close, so the
                        // stain goes where a margin would put it.
                        Capsule()
                            .fill(Color(hex: passage.highlight.colorHex))
                            .frame(width: 3)

                        VStack(alignment: .leading, spacing: DipleSpace.xs) {
                            Text(passage.highlight.text)
                                .dipleType(.editorialQuote)
                                .foregroundStyle(DipleColor.textPrimary)
                                .multilineTextAlignment(.leading)
                                .lineLimit(2)
                                .fixedSize(horizontal: false, vertical: true)

                            if let comment = passage.comment {
                                Text(comment)
                                    .dipleType(.caption)
                                    .foregroundStyle(DipleColor.textTertiary)
                                    .lineLimit(1)
                            }
                        }

                        Spacer(minLength: 0)

                        if onOpenPassage != nil {
                            Image(systemName: "chevron.right")
                                .dipleIcon(10, weight: .semibold)
                                .foregroundStyle(DipleColor.textQuaternary)
                        }
                    }
                    .padding(DipleSpace.m)
                    .craftSurface(DipleColor.surface)
                }
                .buttonStyle(.plain)
                .disabled(onOpenPassage == nil)
            }
        }
    }

    private func connectionGroup(_ title: String, icon: String, notes: [NoteItem]) -> some View {
        VStack(alignment: .leading, spacing: DipleSpace.s) {
            Label(title, systemImage: icon)
                .dipleType(.micro, weight: .semibold)
                .foregroundStyle(DipleColor.textTertiary)

            ForEach(notes.prefix(4)) { note in
                NavigationLink(value: NoteRoute.existing(note)) {
                    HStack(spacing: DipleSpace.m) {
                        Image(systemName: "note.text")
                            .dipleIcon(12, weight: .semibold)
                            .foregroundStyle(DipleColor.accentInk)
                            .frame(width: 28, height: 28)
                            .background(DipleColor.accentSoft, in: RoundedRectangle(cornerRadius: DipleRadius.s))
                        VStack(alignment: .leading, spacing: DipleSpace.xs) {
                            Text(note.displayTitle)
                                .dipleType(.footnote, weight: .semibold)
                                .foregroundStyle(DipleColor.textPrimary)
                                .lineLimit(1)
                            Text(note.previewText)
                                .dipleType(.caption)
                                .foregroundStyle(DipleColor.textTertiary)
                                .lineLimit(1)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .dipleIcon(10, weight: .semibold)
                            .foregroundStyle(DipleColor.textQuaternary)
                    }
                    .padding(DipleSpace.m)
                    .craftSurface(DipleColor.surface)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var currentNoteForConnections: NoteItem {
        if let item = route.item { return item }
        let note = Note(id: draftID, title: title, body: settledBody, bookId: selectedBookId)
        return NoteItem(note: note, tags: tags, book: selectedBook)
    }

    private func relatedNotes(excluding excluded: Set<String>) -> [NoteItem] {
        allNotes.filter { candidate in
            guard candidate.id != route.item?.id, !excluded.contains(candidate.id) else { return false }
            let sharesBook = selectedBookId != nil && candidate.note.bookId == selectedBookId
            let sharesTag = !Set(tags).isDisjoint(with: candidate.tags)
            return sharesBook || sharesTag
        }
    }

    private var metadataLine: some View {
        FlowLayout(spacing: DipleSpace.s) {
            if let item = route.item {
                Text(item.note.updatedAt.formatted(date: .abbreviated, time: .shortened))
                    .dipleType(.micro)
                    .foregroundStyle(DipleColor.textQuaternary)

                Text("·")
                    .dipleType(.micro)
                    .foregroundStyle(DipleColor.textQuaternary)
            }

            Text(wordCountLabel)
                .dipleType(.micro)
                .monospacedDigit()
                .foregroundStyle(DipleColor.textQuaternary)

            Text("·")
                .dipleType(.micro)
                .foregroundStyle(DipleColor.textQuaternary)

            Label(readingTimeLabel, systemImage: "book.pages")
                .dipleType(.micro)
                .foregroundStyle(DipleColor.textQuaternary)
        }
    }

    /// Counted over the prose, not the notation. Splitting the raw Markdown counted `##` and
    /// `[ ]` as words — and ticking a checkbox changed the total, because `[ ]` is two tokens
    /// and `[x]` is one.
    private var wordCount: Int {
        NoteMarkdown.plainText(body_).split { $0.isWhitespace || $0.isNewline }.count
    }

    private var wordCountLabel: String {
        let words = wordCount
        return words == 1 ? "1 word" : "\(words) words"
    }

    private var readingTimeLabel: String {
        let minutes = max(1, Int(ceil(Double(wordCount) / 220)))
        return "\(minutes) min read"
    }

    /// Share and Copy hand out the same bytes the folder export writes, from the same
    /// serialiser — a note shared to a friend and a note exported to a vault must not be two
    /// different documents. What is local here is only that it reads the *live* editor state,
    /// so sharing a note mid-edit shares what is on screen.
    private var exportMarkdown: String {
        NoteMarkdownExport.document(title: title, body: body_, tags: tags)
    }

    // MARK: - Editing

    private var editor: some View {
        VStack(alignment: .leading, spacing: DipleSpace.l) {
            TextField("Title", text: $title, axis: .vertical)
                .dipleType(.noteTitle)
                .foregroundStyle(DipleColor.textPrimary)
                .textInputAutocapitalization(.sentences)
                .focused($isTitleFocused)
                .accessibilityIdentifier("note.title")

            // Properties belong under the title, where a reader looks to find out what a
            // document *is*, not at the far end of the page after the writing. They were a
            // form at the bottom: to tag a note you had to scroll past your own text, and on
            // a short note they floated in the middle of nothing. This is also what the Mac
            // build has always done with its Properties block — the two were disagreeing
            // about the same screen.
            propertiesRow

            Rectangle()
                .fill(DipleColor.separator)
                .frame(height: DipleStroke.hairline)

            ZStack(alignment: .topLeading) {
                if body_.isEmpty {
                    // Says what the writer can do, not merely that the field is empty. The
                    // list rules and the formatting bar are both invisible until used, and a
                    // blank "Start writing…" taught neither.
                    VStack(alignment: .leading, spacing: DipleSpace.s) {
                        Text("Start writing…")
                            .dipleType(.noteBody)
                            .foregroundStyle(DipleColor.textQuaternary)
                        Text("Begin a line with **-** for a list, **- [ ]** for a task, **#** for a heading, or **>** to quote. Return carries the list on.")
                            .dipleType(.caption)
                            .foregroundStyle(DipleColor.textQuaternary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .allowsHitTesting(false)
                }

                // The body takes the room that is left rather than reserving 280 pt. That
                // floor was put there to give the text somewhere to live while the tags sat
                // below it; with the properties moved up there is nothing underneath to hold
                // apart, and on a two-line note the floor was simply a hole in the page.
                NoteEditorView(
                    text: $body_,
                    selection: selection,
                    isFocused: $isBodyFocused,
                    onSlashChanged: { slashContext = $0 },
                    onOpenLink: { title in
                        guard let target = note(titled: title), let onOpenNote else { return }
                        HapticManager.shared.selection()
                        onOpenNote(target)
                    },
                    onTaskToggled: {
                        announceTaskToggle(in: body_)
                        saveTask?.cancel()
                        _ = save(feedback: false)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .noteSlashMenu(context: slashContext) { command in
                    guard let context = slashContext else { return }
                    NoteEditing.applySlash(command, replacing: context.range, in: &body_, selection: selection)
                    slashContext = nil
                    isBodyFocused = true
                }
            }

            // What this thought is standing next to stays on the page now that the page is
            // never left: the backlinks, the notes it points at, and the passages marked in
            // the same book. This is the bridge back to reading, and it belongs under the
            // writing rather than behind a mode.
            connectionsSection
        }
    }

    /// Tags and the linked source, as one quiet line of properties under the title.
    private var propertiesRow: some View {
        FlowLayout(spacing: DipleSpace.s) {
            ForEach(tags, id: \.self) { tag in
                Button {
                    HapticManager.shared.selection()
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
                .accessibilityLabel("Remove tag \(tag)")
            }

            if let book = selectedBook {
                Button {
                    HapticManager.shared.selection()
                    selectedBookId = nil
                } label: {
                    HStack(spacing: DipleSpace.xs) {
                        Image(systemName: "book.closed")
                            .dipleIcon(10, weight: .medium)
                        Text(book.title)
                            .dipleType(.caption, weight: .medium)
                            .lineLimit(1)
                        Image(systemName: "xmark")
                            .dipleIcon(9, weight: .bold)
                    }
                    .foregroundStyle(DipleColor.accentInk)
                    .diplePadding(.chip)
                    .background(DipleColor.accentSoft, in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove book \(book.title)")
            }

            Menu {
                Button {
                    isBookPickerPresented = true
                } label: {
                    Label(selectedBook == nil ? "Link a source" : "Change source", systemImage: "book.closed")
                }

                if !unusedSuggestions.isEmpty {
                    Divider()
                    ForEach(unusedSuggestions.prefix(8), id: \.self) { tag in
                        Button("#\(tag)") { tags.append(tag) }
                    }
                }

                Divider()
                Button {
                    isAddingTag = true
                } label: {
                    Label("New tag", systemImage: "number")
                }
            } label: {
                HStack(spacing: DipleSpace.xs) {
                    Image(systemName: "plus")
                        .dipleIcon(10, weight: .semibold)
                    Text(tags.isEmpty && selectedBook == nil ? "Add tags or a source" : "Add")
                        .dipleType(.caption, weight: .medium)
                }
                .foregroundStyle(DipleColor.textTertiary)
                .diplePadding(.chip)
                .overlay(Capsule().stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline))
            }
            .accessibilityLabel("Add tags or a source")
        }
    }

    private var formattingBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DipleSpace.xs) {
                formatButton("H1", accessibility: "Heading") {
                    apply(prefix: "# ", placeholder: "Heading", isLineCommand: true)
                }
                formatButton(systemImage: "bold", accessibility: "Bold") {
                    apply(prefix: "**", suffix: "**", placeholder: "bold text")
                }
                formatButton(systemImage: "italic", accessibility: "Italic") {
                    apply(prefix: "*", suffix: "*", placeholder: "italic text")
                }
                formatButton("ƒx", accessibility: "Equation") {
                    presentFormulaComposer()
                }
                barDivider
                formatButton(systemImage: "checklist", accessibility: "Task") {
                    apply(prefix: "- [ ] ", placeholder: "Task", isLineCommand: true)
                }
                formatButton(systemImage: "list.bullet", accessibility: "Bulleted list") {
                    apply(prefix: "- ", placeholder: "List item", isLineCommand: true)
                }
                formatButton(systemImage: "text.quote", accessibility: "Quote") {
                    apply(prefix: "> ", placeholder: "Quote", isLineCommand: true)
                }
                barDivider
                formatButton(systemImage: "link", accessibility: "Link") {
                    apply(prefix: "[", suffix: "](https://)", placeholder: "link title")
                }
                if !linkableNotes.isEmpty {
                    Menu {
                        ForEach(linkableNotes) { note in
                            Button(note.displayTitle) {
                                apply(prefix: "[[", suffix: "]]", placeholder: note.displayTitle)
                            }
                        }
                    } label: {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .dipleIcon(15, weight: .semibold)
                            .foregroundStyle(DipleColor.textSecondary)
                            .frame(width: 36, height: 36)
                            .background(DipleColor.surfaceRaised.opacity(0.8), in: RoundedRectangle(cornerRadius: DipleRadius.s))
                    }
                    .accessibilityLabel("Link another note")
                }
                formatButton(systemImage: "chevron.left.forwardslash.chevron.right", accessibility: "Code") {
                    apply(prefix: "`", suffix: "`", placeholder: "code")
                }

                Menu {
                    Button("Callout") {
                        apply(prefix: "> [!NOTE] ", placeholder: "Note", isLineCommand: true)
                    }
                    Button("Tip") {
                        apply(prefix: "> [!TIP] ", placeholder: "Tip", isLineCommand: true)
                    }
                    Button("Divider") {
                        apply(prefix: "---\n", placeholder: "", isLineCommand: true)
                    }
                    if route.item == nil {
                        Divider()
                        Button("Reading notes template") { applyTemplate(.reading) }
                        Button("Evergreen idea template") { applyTemplate(.evergreen) }
                        Button("Daily reflection template") { applyTemplate(.reflection) }
                    }
                } label: {
                    Image(systemName: "plus")
                        .dipleIcon(15, weight: .semibold)
                        .foregroundStyle(DipleColor.textSecondary)
                        .frame(width: 36, height: 36)
                }
            }
            .padding(.horizontal, DipleSpace.m)
            .padding(.vertical, DipleSpace.s)
        }
        .background(.ultraThinMaterial)
        .overlay(alignment: .top) {
            Rectangle().fill(DipleColor.hairline).frame(height: DipleStroke.hairline)
        }
    }

    private func formatButton(
        _ label: String? = nil,
        systemImage: String? = nil,
        accessibility: String,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.shared.selection()
            action()
        } label: {
            Group {
                if let systemImage {
                    Image(systemName: systemImage).dipleIcon(15, weight: .semibold)
                } else {
                    Text(label ?? "").dipleType(.footnote, weight: .semibold)
                }
            }
            .foregroundStyle(DipleColor.textSecondary)
            .frame(width: 36, height: 36)
            .background(DipleColor.surfaceRaised.opacity(0.8), in: RoundedRectangle(cornerRadius: DipleRadius.s))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibility)
    }

    private var barDivider: some View {
        Rectangle()
            .fill(DipleColor.separator)
            .frame(width: DipleStroke.hairline, height: 22)
            .padding(.horizontal, DipleSpace.xs)
    }


    // MARK: - Actions

    /// Resolves a wiki link's title the same way `NoteKnowledge` does when it builds the
    /// Connections list, so following a link and appearing in "Linked notes" cannot disagree
    /// about what a title matches.
    private func note(titled title: String) -> NoteItem? {
        let target = title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return allNotes.first { candidate in
            candidate.id != route.item?.id
                && candidate.displayTitle
                    .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == target
        }
    }

    /// Ticking a box is a finished decision, not a keystroke, so it is written straight away
    /// rather than left to the typing debounce: the board's progress bar would otherwise stay
    /// stale until the page was left.
    private func toggleTask(_ task: NoteTask) {
        guard let updated = NoteMarkdown.togglingTask(atLine: task.lineIndex, in: body_) else { return }
        announceTaskToggle(in: updated)
        body_ = updated
        saveTask?.cancel()
        _ = save(feedback: false)
    }

    /// Clearing the last item is the end of something, not another tick, and the hand should hear
    /// the difference. One rule for a box ticked on the set page and one ticked in the text.
    private func announceTaskToggle(in markdown: String) {
        let progress = NoteMarkdown.taskProgress(in: markdown)
        let finishedTheList = progress.map { $0.completed == $0.total && $0.total > 0 } ?? false
        if finishedTheList {
            HapticManager.shared.notification(.success)
        } else {
            HapticManager.shared.impact(.light)
        }
    }

    private func commitTagDraft() {
        guard let tag = NoteTag.normalized(tagDraft) else { return }
        if !tags.contains(tag) {
            tags.append(tag)
            HapticManager.shared.impact(.light)
        }
        tagDraft = ""
    }

    /// Puts the keyboard down and writes what is there.
    ///
    /// Not "leaving edit mode": there is no mode to leave. Done used to dismiss a new note
    /// outright, because it was the only way out of a page that had opened in a state; the way
    /// off the page is Back, and Done is what the thumb reaches for when the thought is
    /// finished and the page is not.
    private func finishWriting() {
        isBodyFocused = false
        isTitleFocused = false
        guard canSave else { return }
        saveTask?.cancel()
        _ = save(feedback: true)
    }

    private func save(feedback: Bool) -> Bool {
        // A tag typed but never committed is still a tag the user meant to add.
        var finalTags = tags
        if let pending = NoteTag.normalized(tagDraft), !finalTags.contains(pending) {
            finalTags.append(pending)
            tags = finalTags
            tagDraft = ""
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = route.item?.note
        // Where the note lives travels only on its first write — `saveNote` keeps the stored
        // row's place for every write after that, so a page left open can never undo a move.
        let note = Note(
            id: existing?.id ?? draftID,
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            body: body_.trimmingCharacters(in: .whitespacesAndNewlines),
            bookId: selectedBookId,
            createdAt: existing?.createdAt ?? Date(),
            spaceId: existing?.spaceId ?? route.initialSpaceId,
            dailyDate: existing?.dailyDate ?? route.initialDailyDate
        )
        // Whatever is being written has stopped moving long enough to be written down, which
        // is exactly when the Connections block is worth rebuilding.
        settledBody = body_

        let didSave = onSave(note, finalTags)
        if didSave {
            lastSavedSnapshot = currentSnapshot
            saveState = .saved
            if feedback { HapticManager.shared.impact(.medium) }
        } else {
            saveState = .failed
            if feedback { HapticManager.shared.notification(.error) }
        }
        return didSave
    }

    private var currentSnapshot: String {
        Self.snapshot(title: title, body: body_, tags: tags, bookID: selectedBookId)
    }

    private static func snapshot(title: String, body: String, tags: [String], bookID: String?) -> String {
        ([title, body, tags.sorted().joined(separator: "\u{1F}"), bookID ?? ""] as [String])
            .joined(separator: "\u{1E}")
    }

    private func scheduleSave() {
        guard canSave, currentSnapshot != lastSavedSnapshot else { return }
        saveTask?.cancel()
        saveState = .saving
        saveTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled else { return }
            _ = save(feedback: false)
        }
    }

    private func apply(
        prefix: String,
        suffix: String = "",
        placeholder: String,
        isLineCommand: Bool = false
    ) {
        NoteEditing.apply(
            to: &body_,
            selection: selection,
            prefix: prefix,
            suffix: suffix,
            placeholder: placeholder,
            isLineCommand: isLineCommand
        )
        isBodyFocused = true
    }

    private func presentFormulaComposer() {
        let source = body_ as NSString
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

    private enum NoteTemplate {
        case reading
        case evergreen
        case reflection
    }

    private func applyTemplate(_ template: NoteTemplate) {
        guard title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        switch template {
        case .reading:
            title = "Reading notes"
            body_ = "## The central idea\n\n\n\n## What surprised me\n\n\n\n## In the author’s words\n\n> \n\n## My synthesis\n\n\n\n- [ ] Follow this thread"
        case .evergreen:
            title = "One clear idea"
            body_ = "> [!IMPORTANT] Claim\n> State the idea in one precise sentence.\n\n## Why it matters\n\n\n\n## Evidence\n\n\n\n## Connections\n\n"
        case .reflection:
            title = Date().formatted(date: .long, time: .omitted)
            body_ = "## What stayed with me\n\n\n\n## What changed my mind\n\n\n\n## What I want to explore next\n\n- [ ] "
        }
        selection.move(to: NSRange(location: (body_ as NSString).length, length: 0))
        isBodyFocused = true
    }
}

public enum NoteKnowledge {
    public static func wikiLinks(in markdown: String) -> [String] {
        guard let expression = try? NSRegularExpression(pattern: #"\[\[([^\]]+)\]\]"#) else { return [] }
        let source = markdown as NSString
        return expression.matches(in: markdown, range: NSRange(location: 0, length: source.length)).compactMap { match in
            guard match.numberOfRanges > 1 else { return nil }
            return source.substring(with: match.range(at: 1))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    public static func outgoing(from markdown: String, among notes: [NoteItem]) -> [NoteItem] {
        let linkedTitles = Set(wikiLinks(in: markdown).map { $0.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) })
        return notes.filter { note in
            linkedTitles.contains(note.displayTitle.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current))
        }
    }

    public static func backlinks(to note: NoteItem, among notes: [NoteItem]) -> [NoteItem] {
        let target = note.displayTitle.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        return notes.filter { candidate in
            guard candidate.id != note.id else { return false }
            return wikiLinks(in: candidate.note.body).contains { link in
                link.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current) == target
            }
        }
    }
}

