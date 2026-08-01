import SwiftUI

/// Compose or edit a note: text, free-form tags, and one library item as a tag.
public struct NoteEditorView: View {
    public let target: NoteEditorTarget
    public let books: [Book]
    public let suggestedTags: [String]
    public let onSave: (Note, [String]) -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var body_: String
    @State private var tags: [String]
    @State private var tagDraft: String = ""
    @State private var selectedBookId: String?
    @State private var isBookPickerPresented = false
    @FocusState private var isBodyFocused: Bool

    public init(
        target: NoteEditorTarget,
        books: [Book],
        suggestedTags: [String],
        onSave: @escaping (Note, [String]) -> Void
    ) {
        self.target = target
        self.books = books
        self.suggestedTags = suggestedTags
        self.onSave = onSave
        _title = State(initialValue: target.item?.note.title ?? "")
        _body_ = State(initialValue: target.item?.note.body ?? "")
        _tags = State(initialValue: target.item?.tags ?? [])
        _selectedBookId = State(initialValue: target.item?.note.bookId)
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

    public var body: some View {
        NavigationStack {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DipleSpace.xxl) {
                        titleField
                        bodyField
                        tagsSection
                        bookTagSection
                    }
                    .padding(DipleSpace.xl)
                }
            }
            .navigationTitle(target.item == nil ? "New Note" : "Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DipleColor.textTertiary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .dipleType(.body, weight: .semibold)
                        .foregroundColor(canSave ? DipleColor.accent : DipleColor.textQuaternary)
                        .disabled(!canSave)
                }
            }
            .sheet(isPresented: $isBookPickerPresented) {
                BookTagPickerView(books: books, selectedBookId: selectedBookId) { bookId in
                    selectedBookId = bookId
                }
            }
        }
    }

    private var titleField: some View {
        VStack(alignment: .leading, spacing: DipleSpace.s) {
            sectionLabel("TITLE")

            TextField("Optional", text: $title)
                .dipleType(.headline)
                .foregroundColor(.white)
                .diplePadding(.field)
                .background(DipleColor.surfaceRaised)
                .cornerRadius(DipleRadius.m)
        }
    }

    private var bodyField: some View {
        VStack(alignment: .leading, spacing: DipleSpace.s) {
            sectionLabel("NOTE")

            TextEditor(text: $body_)
                .dipleType(.body)
                .foregroundStyle(DipleColor.textPrimary)
                .scrollContentBackground(.hidden)
                .focused($isBodyFocused)
                .frame(minHeight: 180)
                .padding(DipleSpace.s)
                .background(DipleColor.surfaceRaised)
                .cornerRadius(DipleRadius.m)
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            sectionLabel("TAGS")

            HStack(spacing: DipleSpace.s) {
                TextField("Add a tag", text: $tagDraft)
                    .dipleType(.callout)
                    .foregroundColor(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { commitTagDraft() }
                    .submitLabel(.done)
                    .padding(.horizontal, DipleSpace.m)
                    .padding(.vertical, DipleSpace.m)
                    .background(DipleColor.surfaceRaised)
                    .cornerRadius(DipleRadius.m)

                Button {
                    commitTagDraft()
                } label: {
                    Image(systemName: "plus")
                        .dipleIcon(14, weight: .semibold)
                        .foregroundStyle(DipleColor.textOnAccent)
                        .padding(DipleSpace.m)
                        .background(DipleColor.accent)
                        .clipShape(Circle())
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
                            .background(DipleColor.surfaceOverlay)
                            .clipShape(Capsule())
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
                        .foregroundColor(
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
                .background(DipleColor.surfaceRaised)
                .cornerRadius(DipleRadius.m)
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .dipleType(.micro, weight: .semibold)
            .foregroundStyle(DipleColor.textTertiary)
            .padding(.horizontal, DipleSpace.xs)
    }

    private func commitTagDraft() {
        guard let tag = NoteTag.normalized(tagDraft) else { return }
        if !tags.contains(tag) {
            tags.append(tag)
            HapticManager.shared.impact(.light)
        }
        tagDraft = ""
    }

    private func save() {
        // A tag typed but never committed is still a tag the user meant to add.
        var finalTags = tags
        if let pending = NoteTag.normalized(tagDraft), !finalTags.contains(pending) {
            finalTags.append(pending)
        }

        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let existing = target.item?.note
        let note = Note(
            id: existing?.id ?? UUID().uuidString,
            title: trimmedTitle.isEmpty ? nil : trimmedTitle,
            body: body_.trimmingCharacters(in: .whitespacesAndNewlines),
            bookId: selectedBookId,
            createdAt: existing?.createdAt ?? Date()
        )
        onSave(note, finalTags)
        HapticManager.shared.impact(.medium)
        dismiss()
    }
}
