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
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        titleField
                        bodyField
                        tagsSection
                        bookTagSection
                    }
                    .padding(20)
                }
            }
            .navigationTitle(target.item == nil ? "New Note" : "Edit Note")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.65))
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") { save() }
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(canSave ? Color.dipleAccent : Color(red: 0.35, green: 0.35, blue: 0.4))
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
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("TITLE")

            TextField("Optional", text: $title)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                .cornerRadius(10)
        }
    }

    private var bodyField: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionLabel("NOTE")

            TextEditor(text: $body_)
                .font(.system(size: 15, weight: .regular))
                .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))
                .scrollContentBackground(.hidden)
                .focused($isBodyFocused)
                .frame(minHeight: 180)
                .padding(8)
                .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                .cornerRadius(10)
        }
    }

    private var tagsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("TAGS")

            HStack(spacing: 8) {
                TextField("Add a tag", text: $tagDraft)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.white)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .onSubmit { commitTagDraft() }
                    .submitLabel(.done)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                    .cornerRadius(10)

                Button {
                    commitTagDraft()
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.black)
                        .padding(10)
                        .background(Color.dipleAccent)
                        .clipShape(Circle())
                }
                .disabled(NoteTag.normalized(tagDraft) == nil)
                .opacity(NoteTag.normalized(tagDraft) == nil ? 0.4 : 1)
            }

            if !tags.isEmpty {
                FlowLayout(spacing: 8) {
                    ForEach(tags, id: \.self) { tag in
                        Button {
                            HapticManager.shared.selection()
                            tags.removeAll { $0 == tag }
                        } label: {
                            HStack(spacing: 4) {
                                Text("#\(tag)")
                                    .font(.system(size: 12, weight: .medium))
                                Image(systemName: "xmark")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(Color(red: 0.7, green: 0.7, blue: 0.75))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(Color(red: 0.15, green: 0.15, blue: 0.17))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            if !unusedSuggestions.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Used before")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.45))

                    FlowLayout(spacing: 8) {
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
                .padding(.top, 4)
            }
        }
    }

    private var bookTagSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionLabel("FROM LIBRARY")

            Button {
                HapticManager.shared.selection()
                isBookPickerPresented = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "book.closed")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.dipleAccent)

                    Text(selectedBook?.title ?? "Tag a book or file")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(
                            selectedBook == nil
                                ? Color(red: 0.5, green: 0.5, blue: 0.55)
                                : Color(red: 0.92, green: 0.92, blue: 0.92)
                        )
                        .lineLimit(1)

                    Spacer()

                    if selectedBook != nil {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(Color(red: 0.4, green: 0.4, blue: 0.45))
                            .onTapGesture {
                                HapticManager.shared.selection()
                                selectedBookId = nil
                            }
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(red: 0.35, green: 0.35, blue: 0.4))
                    }
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .background(Color(red: 0.1, green: 0.1, blue: 0.12))
                .cornerRadius(10)
            }
            .buttonStyle(.plain)
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11, weight: .semibold))
            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))
            .padding(.horizontal, 4)
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
