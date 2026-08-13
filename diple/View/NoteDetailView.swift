import SwiftUI

/// Where the board can navigate to. A brand new note has no card to expand from, so it is a
/// route of its own rather than an optional item.
public enum NoteRoute: Hashable {
    case existing(NoteItem)
    case new
    case newFromSource(Book)

    public var item: NoteItem? {
        switch self {
        case .existing(let item): return item
        case .new, .newFromSource: return nil
        }
    }

    public var initialBookId: String? {
        if case .newFromSource(let book) = self { return book.id }
        return nil
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
    public let onSave: (Note, [String]) -> Bool
    public let onDelete: (NoteItem) -> Void
    /// Following a `[[Wiki link]]` in the reading view. The push belongs to whichever stack
    /// this page was opened in, so the route goes back out to its owner rather than being
    /// invented here.
    public let onOpenNote: ((NoteItem) -> Void)?

    /// The notes a wiki-link can point at. `allNotes` and `route` never change while this
    /// screen is on screen, so this is settled once in `init` — computing it inside `body`
    /// re-filtered the whole library and rebuilt a thirty-item menu on every keystroke.
    private let linkableNotes: [NoteItem]

    @Environment(\.dismiss) private var dismiss

    @State private var isEditing: Bool
    @State private var title: String
    @State private var body_: String
    @State private var tags: [String]
    @State private var tagDraft: String = ""
    @State private var selectedBookId: String?
    @State private var isBookPickerPresented = false
    @State private var isAddingTag = false
    @State private var slashContext: NoteSlashContext?
    @State private var showDeleteConfirmation = false
    @State private var isBodyFocused = false
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
        onSave: @escaping (Note, [String]) -> Bool,
        onDelete: @escaping (NoteItem) -> Void = { _ in },
        onOpenNote: ((NoteItem) -> Void)? = nil
    ) {
        self.route = route
        self.books = books
        self.suggestedTags = suggestedTags
        self.allNotes = allNotes
        self.onSave = onSave
        self.onDelete = onDelete
        self.onOpenNote = onOpenNote
        self.linkableNotes = Array(allNotes.filter { $0.id != route.item?.id }.prefix(30))

        let item = route.item
        _isEditing = State(initialValue: item == nil)
        _title = State(initialValue: item?.note.title ?? "")
        _body_ = State(initialValue: item?.note.body ?? "")
        _tags = State(initialValue: item?.tags ?? [])
        _selectedBookId = State(initialValue: item?.note.bookId ?? route.initialBookId)
        _draftID = State(initialValue: item?.id ?? UUID().uuidString)
        _lastSavedSnapshot = State(initialValue: Self.snapshot(
            title: item?.note.title ?? "",
            body: item?.note.body ?? "",
            tags: item?.tags ?? [],
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

    private var canSave: Bool {
        !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var unusedSuggestions: [String] {
        suggestedTags.filter { !tags.contains($0) }
    }

    private var displayTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    public var body: some View {
        ScrollViewReader { proxy in
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DipleSpace.xxl) {
                        if isEditing {
                            editor
                        } else {
                            reader { anchor in
                                withAnimation(DipleMotion.gentle) {
                                    proxy.scrollTo(anchor, anchor: .top)
                                }
                            }
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
        .navigationTitle(isEditing ? (route.item == nil ? "New Note" : "Editing") : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DipleColor.canvas, for: .navigationBar)
        .toolbar { toolbarContent }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if isEditing {
                formattingBar
            }
        }
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
        .alert("Delete Note?", isPresented: $showDeleteConfirmation) {
            Button("Delete", role: .destructive) {
                if let item = route.item {
                    onDelete(item)
                }
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This note and its tags will be removed.")
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
        .animation(DipleMotion.standard, value: isEditing)
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
        if isEditing {
            ToolbarItem(placement: .principal) {
                // An empty new note has never been written anywhere, so "Saved" would be a
                // claim about a row that does not exist. The indicator appears once there is
                // something a save could actually be about.
                if canSave || route.item != nil {
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

            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Done") { commit() }
                    .dipleType(.body, weight: .semibold)
                    .foregroundStyle(canSave ? DipleColor.accent : DipleColor.textQuaternary)
                    .disabled(!canSave)
            }
        } else {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button {
                    HapticManager.shared.selection()
                    isEditing = true
                } label: {
                    Image(systemName: "square.and.pencil")
                        .dipleIcon(16)
                        .foregroundStyle(DipleColor.accent)
                }
                .buttonStyle(.readerControl)
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
                        Label("Copy Plain Text", systemImage: "text.alignleft")
                    }

                    if route.item != nil {
                        Button(role: .destructive) {
                            showDeleteConfirmation = true
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
        let outgoing = NoteKnowledge.outgoing(from: body_, among: allNotes)
            .filter { $0.id != route.item?.id }
        let related = relatedNotes(excluding: Set((backlinks + outgoing).map(\.id)))

        if !backlinks.isEmpty || !outgoing.isEmpty || !related.isEmpty {
            Rectangle()
                .fill(DipleColor.separator)
                .frame(height: DipleStroke.hairline)
                .padding(.top, DipleSpace.l)

            VStack(alignment: .leading, spacing: DipleSpace.l) {
                VStack(alignment: .leading, spacing: DipleSpace.xs) {
                    Text("CONNECTIONS")
                        .dipleType(.nano)
                        .foregroundStyle(DipleColor.accent)
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
                            .foregroundStyle(DipleColor.accent)
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
        let note = Note(id: draftID, title: title, body: body_, bookId: selectedBookId)
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

    private var exportMarkdown: String {
        var parts: [String] = []
        if !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append("# \(title.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
        if !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            parts.append(body_.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if !tags.isEmpty {
            parts.append(tags.map { "#\($0)" }.joined(separator: " "))
        }
        return parts.joined(separator: "\n\n")
    }

    // MARK: - Editing

    private var editor: some View {
        VStack(alignment: .leading, spacing: DipleSpace.l) {
            TextField("Title", text: $title, axis: .vertical)
                .dipleType(.noteTitle)
                .foregroundStyle(DipleColor.textPrimary)
                .textInputAutocapitalization(.sentences)
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
                    onSlashChanged: { slashContext = $0 }
                )
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .noteSlashMenu(context: slashContext) { command in
                    guard let context = slashContext else { return }
                    NoteEditing.applySlash(command, replacing: context.range, in: &body_, selection: selection)
                    slashContext = nil
                    isBodyFocused = true
                }
            }
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
                    .foregroundStyle(DipleColor.accent)
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

    /// Ticking a box is a finished decision, not a keystroke, so it is written straight away
    /// rather than through the typing debounce — which is also gated on `isEditing` and would
    /// never fire here, leaving the board's progress bar stale until the page was left.
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

    private func toggleTask(_ task: NoteTask) {
        guard let updated = NoteMarkdown.togglingTask(atLine: task.lineIndex, in: body_) else { return }

        // Clearing the last item is the end of something, not another tick, and the hand
        // should hear the difference.
        let progress = NoteMarkdown.taskProgress(in: updated)
        let finishedTheList = progress.map { $0.completed == $0.total && $0.total > 0 } ?? false
        if finishedTheList {
            HapticManager.shared.notification(.success)
        } else {
            HapticManager.shared.impact(.light)
        }

        body_ = updated
        saveTask?.cancel()
        _ = save(feedback: false)
    }

    private func commitTagDraft() {
        guard let tag = NoteTag.normalized(tagDraft) else { return }
        if !tags.contains(tag) {
            tags.append(tag)
            HapticManager.shared.impact(.light)
        }
        tagDraft = ""
    }

    /// Leaves editing. A new note has nothing to fall back to, so finishing it also leaves
    /// the page; an existing one drops into its reading view.
    private func commit() {
        guard canSave else { return }
        saveTask?.cancel()
        guard save(feedback: true) else { return }
        isBodyFocused = false

        if route.item == nil {
            dismiss()
        } else {
            isEditing = false
        }
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
        let note = Note(
            id: existing?.id ?? draftID,
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            body: body_.trimmingCharacters(in: .whitespacesAndNewlines),
            bookId: selectedBookId,
            createdAt: existing?.createdAt ?? Date()
        )
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
        guard isEditing, canSave, currentSnapshot != lastSavedSnapshot else { return }
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
