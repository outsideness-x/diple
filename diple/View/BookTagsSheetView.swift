import SwiftUI

/// Tagging one source.
///
/// The chips, the suggestion menu and the "New tag" prompt now live in `TagField` — tagging
/// should not be a different skill depending on what is being tagged. What stays here is where
/// the set is *written*: a note autosaves as it is edited, while a source has no editor to
/// autosave into, so the set is committed once when this sheet goes away. Writing on every chip
/// would put a CloudKit save in the outbox per keystroke of a five-second task.
public struct BookTagsSheetView: View {
    public let book: Book
    /// Every tag already in use across the library, offered as suggestions.
    public let suggestions: [String]
    public let onCommit: ([String]) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var tags: [String]
    /// `onDisappear` fires for an interactive dismissal as well as for Done, and both must
    /// commit — but only once.
    @State private var hasCommitted = false

    public init(book: Book, tags: [String], suggestions: [String], onCommit: @escaping ([String]) -> Void) {
        self.book = book
        self.suggestions = suggestions
        self.onCommit = onCommit
        _tags = State(initialValue: tags)
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
                    .foregroundStyle(DipleColor.accentInk)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .onDisappear(perform: commit)
    }

    private var editor: some View {
        TagField(tags: $tags, suggestions: suggestions)
    }

    private func commit() {
        guard !hasCommitted else { return }
        hasCommitted = true
        onCommit(tags)
    }
}
