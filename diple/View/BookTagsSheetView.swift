import SwiftUI

/// Tagging one source.
///
/// The chips, the suggestion menu and the "New tag" prompt are the same three pieces
/// `NoteDetailView` already uses for a note's tags, in the same order — tagging should not be a
/// different skill depending on what is being tagged. What differs is only where the set is
/// written: a note autosaves as it is edited, while a source has no editor to autosave into, so
/// the set is committed once when this sheet goes away. Writing on every chip would put a
/// CloudKit save in the outbox per keystroke of a five-second task.
public struct BookTagsSheetView: View {
    public let book: Book
    /// Every tag already in use across the library, offered as suggestions.
    public let suggestions: [String]
    public let onCommit: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tags: [String]
    @State private var draft: String = ""
    @State private var isAddingTag = false
    /// `onDisappear` fires for an interactive dismissal as well as for Done, and both must
    /// commit — but only once.
    @State private var hasCommitted = false

    public init(book: Book, tags: [String], suggestions: [String], onCommit: @escaping ([String]) -> Void) {
        self.book = book
        self.suggestions = suggestions
        self.onCommit = onCommit
        _tags = State(initialValue: tags)
    }

    private var unusedSuggestions: [String] {
        suggestions.filter { !tags.contains($0) }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DipleSpace.xl) {
                        Text(book.title)
                            .dipleType(.headline)
                            .foregroundStyle(DipleColor.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        editor

                        if tags.isEmpty {
                            Text("A tag is a shelf, not a folder — a source can sit on as many as you like.")
                                .dipleType(.callout)
                                .foregroundStyle(DipleColor.textTertiary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, DipleSpace.xl)
                    .padding(.top, DipleSpace.l)
                    .padding(.bottom, DipleSpace.scrollBottom)
                }
            }
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        HapticManager.shared.selection()
                        dismiss()
                    }
                    .foregroundStyle(DipleColor.accent)
                }
            }
            .alert("New tag", isPresented: $isAddingTag) {
                TextField("Tag", text: $draft)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Add", action: commitDraft)
                Button("Cancel", role: .cancel) { draft = "" }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear(perform: commit)
    }

    private var editor: some View {
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

            Menu {
                if !unusedSuggestions.isEmpty {
                    ForEach(unusedSuggestions.prefix(8), id: \.self) { tag in
                        Button("#\(tag)") { tags.append(tag) }
                    }
                    Divider()
                }

                Button {
                    isAddingTag = true
                } label: {
                    Label("New tag", systemImage: "number")
                }
            } label: {
                HStack(spacing: DipleSpace.xs) {
                    Image(systemName: "plus")
                        .dipleIcon(10, weight: .semibold)
                    Text(tags.isEmpty ? "Add a tag" : "Add")
                        .dipleType(.caption, weight: .medium)
                }
                .foregroundStyle(DipleColor.textTertiary)
                .diplePadding(.chip)
                .overlay(Capsule().stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline))
            }
            .accessibilityLabel("Add a tag")
        }
    }

    private func commitDraft() {
        guard let tag = BookTag.normalized(draft) else { return }
        if !tags.contains(tag) {
            tags.append(tag)
            HapticManager.shared.selection()
        }
        draft = ""
    }

    private func commit() {
        guard !hasCommitted else { return }
        hasCommitted = true
        // A tag typed into the prompt but never confirmed is still a tag the reader meant.
        var finalTags = tags
        if let pending = BookTag.normalized(draft), !finalTags.contains(pending) {
            finalTags.append(pending)
        }
        onCommit(finalTags)
    }
}
