import SwiftUI

/// Where the board can navigate to. A brand new note has no card to expand from, so it is a
/// route of its own rather than an optional item.
public enum NoteRoute: Hashable {
    case existing(NoteItem)
    case new

    public var item: NoteItem? {
        switch self {
        case .existing(let item): return item
        case .new: return nil
        }
    }
}

/// A note as a page rather than a form.
///
/// Reading comes first: the note is set as a document — the reader's own words in serif, one
/// column, structure rendered rather than shown as syntax. Editing is a mode you enter, not
/// the resting state, which is what keeps the note something you can sit and read.
///
/// This is also the only note editor in the app. Composing and revising share one screen
/// because two editors drift: a tag rule fixed in one is left broken in the other.
public struct NoteDetailView: View {
    public let route: NoteRoute
    public let books: [Book]
    public let suggestedTags: [String]
    public let onSave: (Note, [String]) -> Bool
    public let onDelete: (NoteItem) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var isEditing: Bool
    @State private var title: String
    @State private var body_: String
    @State private var tags: [String]
    @State private var tagDraft: String = ""
    @State private var selectedBookId: String?
    @State private var isBookPickerPresented = false
    @State private var showDeleteConfirmation = false
    @FocusState private var isBodyFocused: Bool

    public init(
        route: NoteRoute,
        books: [Book],
        suggestedTags: [String],
        onSave: @escaping (Note, [String]) -> Bool,
        onDelete: @escaping (NoteItem) -> Void = { _ in }
    ) {
        self.route = route
        self.books = books
        self.suggestedTags = suggestedTags
        self.onSave = onSave
        self.onDelete = onDelete

        let item = route.item
        _isEditing = State(initialValue: item == nil)
        _title = State(initialValue: item?.note.title ?? "")
        _body_ = State(initialValue: item?.note.body ?? "")
        _tags = State(initialValue: item?.tags ?? [])
        _selectedBookId = State(initialValue: item?.note.bookId)
    }

    /// UIKit's text view inset, which `TextEditor` inherits and does not surface.
    private static let textEditorInset: CGFloat = 5

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
        ZStack {
            DipleColor.canvas.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: DipleSpace.xxl) {
                    if isEditing {
                        editor
                    } else {
                        reader
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
        .navigationTitle(isEditing ? (route.item == nil ? "New Note" : "Editing") : "")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DipleColor.canvas, for: .navigationBar)
        .toolbarColorScheme(.dark, for: .navigationBar)
        .toolbar { toolbarContent }
        // A note reads as a page of its own, so the board's tab bar steps out of the way —
        // the same treatment the reader gets.
        .toolbar(.hidden, for: .tabBar)
        .sheet(isPresented: $isBookPickerPresented) {
            BookTagPickerView(books: books, selectedBookId: selectedBookId) { bookId in
                selectedBookId = bookId
            }
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
        .animation(DipleMotion.standard, value: isEditing)
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        if isEditing {
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
                    Button {
                        UIPasteboard.general.string = body_
                        HapticManager.shared.impact(.light)
                    } label: {
                        Label("Copy Text", systemImage: "doc.on.doc")
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

    private var reader: some View {
        VStack(alignment: .leading, spacing: DipleSpace.l) {
            Text(displayTitle)
                .dipleType(.readingTitle)
                .foregroundStyle(
                    title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        ? DipleColor.textTertiary
                        : DipleColor.textPrimary
                )
                .multilineTextAlignment(.leading)

            metadataLine

            if !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                NoteMarkdownView(markdown: body_)
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
        }
    }

    private var metadataLine: some View {
        HStack(spacing: DipleSpace.s) {
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
        }
    }

    private var wordCountLabel: String {
        let words = body_.split { $0.isWhitespace || $0.isNewline }.count
        return words == 1 ? "1 word" : "\(words) words"
    }

    // MARK: - Editing

    private var editor: some View {
        VStack(alignment: .leading, spacing: DipleSpace.xxl) {
            TextField("Title", text: $title, axis: .vertical)
                .dipleType(.readingTitle)
                .foregroundStyle(DipleColor.textPrimary)
                .textInputAutocapitalization(.sentences)

            Rectangle()
                .fill(DipleColor.separator)
                .frame(height: DipleStroke.hairline)

            // Markdown is written as markdown. The face stays the reading face so switching
            // modes does not reflow the text under the reader's eyes.
            TextEditor(text: $body_)
                .dipleType(.readingBody)
                .foregroundStyle(DipleColor.textPrimary)
                .lineSpacing(ReaderScript.detect(in: body_).swiftUILineSpacing)
                .scrollContentBackground(.hidden)
                .scrollDisabled(true)
                .focused($isBodyFocused)
                .frame(minHeight: 240, alignment: .topLeading)
                // TextEditor carries a built-in text inset that TextField and Text do not,
                // and it is not exposed. Left alone, the body sits a few points right of the
                // title above it and of where the same text sits when reading — which reads
                // as a wobble in the margin every time the mode changes.
                .padding(.horizontal, -Self.textEditorInset)

            tagsSection
            bookTagSection
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            sectionLabel("TAGS")

            HStack(spacing: DipleSpace.s) {
                TextField("Add a tag", text: $tagDraft)
                    .dipleType(.callout)
                    .foregroundStyle(DipleColor.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { commitTagDraft() }
                    .submitLabel(.done)
                    .diplePadding(.field)
                    .background(DipleColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DipleRadius.m))

                Button {
                    commitTagDraft()
                } label: {
                    Image(systemName: "plus")
                        .dipleIcon(14, weight: .semibold)
                        .foregroundStyle(DipleColor.textOnAccent)
                        .padding(DipleSpace.m)
                        .background(DipleColor.accent, in: Circle())
                }
                .disabled(NoteTag.normalized(tagDraft) == nil)
                .opacity(NoteTag.normalized(tagDraft) == nil ? 0.4 : 1)
            }

            if !tags.isEmpty {
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
                    }
                }
            }

            if !unusedSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: DipleSpace.s) {
                    Text("Used before")
                        .dipleType(.micro)
                        .foregroundStyle(DipleColor.textQuaternary)

                    FlowLayout(spacing: DipleSpace.s) {
                        ForEach(unusedSuggestions, id: \.self) { tag in
                            Button {
                                HapticManager.shared.selection()
                                tags.append(tag)
                            } label: {
                                TagChipView(label: tag, kind: .text)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
                .padding(.top, DipleSpace.xs)
            }
        }
    }

    private var bookTagSection: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            sectionLabel("FROM LIBRARY")

            Button {
                HapticManager.shared.selection()
                isBookPickerPresented = true
            } label: {
                HStack(spacing: DipleSpace.m) {
                    Image(systemName: "book.closed")
                        .dipleIcon(14, weight: .medium)
                        .foregroundStyle(DipleColor.accent)

                    Text(selectedBook?.title ?? "Tag a book or file")
                        .dipleType(.callout)
                        .foregroundStyle(
                            selectedBook == nil
                                ? DipleColor.textTertiary
                                : DipleColor.textPrimary
                        )
                        .lineLimit(1)

                    Spacer()

                    if selectedBook != nil {
                        Image(systemName: "xmark.circle.fill")
                            .dipleIcon(15)
                            .foregroundStyle(DipleColor.textQuaternary)
                            .onTapGesture {
                                HapticManager.shared.selection()
                                selectedBookId = nil
                            }
                    } else {
                        Image(systemName: "chevron.right")
                            .dipleIcon(12, weight: .semibold)
                            .foregroundStyle(DipleColor.textQuaternary)
                    }
                }
                .diplePadding(.field)
                .background(DipleColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DipleRadius.m))
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .dipleType(.micro, weight: .semibold)
            .foregroundStyle(DipleColor.textTertiary)
    }

    // MARK: - Actions

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
        guard save() else { return }
        isBodyFocused = false

        if route.item == nil {
            dismiss()
        } else {
            isEditing = false
        }
    }

    private func save() -> Bool {
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
            id: existing?.id ?? UUID().uuidString,
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            body: body_.trimmingCharacters(in: .whitespacesAndNewlines),
            bookId: selectedBookId,
            createdAt: existing?.createdAt ?? Date()
        )
        let didSave = onSave(note, finalTags)
        if didSave {
            HapticManager.shared.impact(.medium)
        } else {
            HapticManager.shared.notification(.error)
        }
        return didSave
    }
}
