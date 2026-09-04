import SwiftUI

/// The three pieces of tagging — the removable chips, the suggestion menu and the "New tag"
/// prompt — as one view.
///
/// There were already two copies of them, in `BookTagsSheetView` and in `NoteDetailView`, and a
/// passage is the third thing in this app that can be tagged. A third copy is where a tag rule
/// fixed in one place stays broken in the other two, so the pieces move here instead.
///
/// It owns presentation and nothing else. The binding is the whole contract, and each host
/// keeps its own answer to *when the set is written*: a note autosaves as it is edited, a
/// source commits once as its sheet goes away, a passage commits with the rest of its editor.
/// Folding that decision in here would force one of those rhythms onto the other two.
///
/// `NoteDetailView` deliberately still has its own row: its chips share the line with the
/// linked-source chip and its menu carries two more items, so adopting this would mean opening
/// slots in it until it was a worse version of both.
public struct TagField: View {
    @Binding public var tags: [String]
    /// Every tag already in use in this vocabulary. Books, notes and passages keep separate
    /// ones — see `HighlightTag` — so what arrives here is the host's list, not a global one.
    public let suggestions: [String]
    /// What the add control says while nothing is tagged yet.
    public let emptyPrompt: String

    @State private var draft: String = ""
    @State private var isAddingTag = false

    public init(tags: Binding<[String]>, suggestions: [String], emptyPrompt: String = "Add a tag") {
        _tags = tags
        self.suggestions = suggestions
        self.emptyPrompt = emptyPrompt
    }

    private var unusedSuggestions: [String] {
        suggestions.filter { !tags.contains($0) }
    }

    public var body: some View {
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
                        Button("#\(tag)") { append(tag) }
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
                    Text(tags.isEmpty ? emptyPrompt : "Add")
                        .dipleType(.caption, weight: .medium)
                }
                .foregroundStyle(DipleColor.textTertiary)
                .diplePadding(.chip)
                .overlay(Capsule().stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline))
            }
            .accessibilityLabel("Add a tag")
        }
        .alert("New tag", isPresented: $isAddingTag) {
            TextField("Tag", text: $draft)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
            Button("Add", action: commitDraft)
            Button("Cancel", role: .cancel) { draft = "" }
        }
        // A word typed into the prompt is a word the reader meant. Both alert buttons resolve
        // the draft, so this only catches a field torn down with the prompt still open.
        .onDisappear(perform: commitDraft)
    }

    private func append(_ tag: String) {
        guard !tags.contains(tag) else { return }
        tags.append(tag)
    }

    private func commitDraft() {
        guard let tag = TagName.normalized(draft) else {
            draft = ""
            return
        }
        if !tags.contains(tag) {
            tags.append(tag)
            HapticManager.shared.selection()
        }
        draft = ""
    }
}
