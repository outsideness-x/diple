import SwiftUI

/// Presentation of a saved quote, used by the hub. Deletion lives in a context menu rather
/// than an inline button; the reader's own list (`HighlightRowView`) stays a separate view
/// because it also carries navigation to the passage.
public struct QuoteCardView: View {
    public let quote: Highlight
    /// Passed in rather than read here: a list draws many of these, and a card that fetched its
    /// own tags would put a query behind every row of a scroll.
    public let tags: [String]
    public let onCommentRequest: (() -> Void)?
    public let onDeleteRequest: (() -> Void)?

    public init(
        quote: Highlight,
        tags: [String] = [],
        onCommentRequest: (() -> Void)? = nil,
        onDeleteRequest: (() -> Void)? = nil
    ) {
        self.quote = quote
        self.tags = tags
        self.onCommentRequest = onCommentRequest
        self.onDeleteRequest = onDeleteRequest
    }

    private var accentColor: Color {
        Color(hex: quote.colorHex)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: quote.createdAt)
    }

    private var comment: String? {
        let trimmed = quote.comment?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (trimmed?.isEmpty ?? true) ? nil : trimmed
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DipleSpace.m) {
            Capsule()
                .fill(accentColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: DipleSpace.s) {
                Text(quote.text)
                    .dipleType(.editorialQuote)
                    .readingLineSpacing(for: quote.text)
                    .foregroundStyle(DipleColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                if let comment {
                    HStack(alignment: .top, spacing: DipleSpace.s) {
                        Image(systemName: "bubble.left")
                            .dipleIcon(11, weight: .medium)
                            .foregroundStyle(DipleColor.textQuaternary)

                        Text(comment)
                            .dipleType(.callout)
                            .foregroundStyle(DipleColor.textSecondary)
                            .multilineTextAlignment(.leading)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if !tags.isEmpty {
                    // The reader's own words, under their own quiet line — the same chip the
                    // notes board uses, so a tag looks like a tag wherever it is read.
                    FlowLayout(spacing: DipleSpace.xs) {
                        ForEach(tags, id: \.self) { tag in
                            TagChipView(label: tag, kind: .text)
                        }
                    }
                }

                HStack(spacing: DipleSpace.m) {
                    Text(formattedDate)
                        .dipleType(.micro)
                        .foregroundStyle(DipleColor.textQuaternary)

                    Spacer()

                    if let onCommentRequest {
                        Button(action: onCommentRequest) {
                            Label(comment == nil ? "Comment" : "Edit", systemImage: "bubble.left")
                                .dipleType(.micro, weight: .semibold)
                                .foregroundStyle(DipleColor.textTertiary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(comment == nil ? "Add comment to passage" : "Edit the comment on this passage")
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DipleSpace.m)
        .craftSurface()
        .contextMenu {
            Button {
                UIPasteboard.general.string = quote.text
                HapticManager.shared.impact(.light)
            } label: {
                Label("Copy passage", systemImage: "doc.on.doc")
            }

            if let onCommentRequest {
                // One room with two doors, both saying what they open: the inline control
                // beneath the quote is the common act — write the thought — while the menu
                // names the sheet for what it now holds, a comment and the passage's tags.
                Button(action: onCommentRequest) {
                    Label("Edit passage", systemImage: "square.and.pencil")
                }
            }

            if let onDeleteRequest {
                Button(role: .destructive, action: onDeleteRequest) {
                    Label("Delete passage", systemImage: "trash")
                }
            }
        }
    }
}

/// A focused editor shared by the iPhone/iPad quote list and the Mac quote inspector.
///
/// It holds everything a reader adds *to* a passage — the thought and the filing — while the
/// reader's own `HighlightEditorView` additionally owns colour, because colour is a mark on the
/// page and this screen has no page. Two editors, two jobs; one vocabulary between them.
public struct QuoteCommentEditorView: View {
    public let quote: Highlight
    public let suggestions: [String]
    public let onSave: (String, [String]) -> Void
    public let onCancel: () -> Void

    @State private var comment: String
    @State private var tags: [String]
    @State private var echoes: [PassageEcho] = []

    public init(
        quote: Highlight,
        tags: [String] = [],
        suggestions: [String] = [],
        onSave: @escaping (String, [String]) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.quote = quote
        self.suggestions = suggestions
        self.onSave = onSave
        self.onCancel = onCancel
        self._comment = State(initialValue: quote.comment ?? "")
        self._tags = State(initialValue: tags)
    }

    public var body: some View {
        NavigationStack {
            Form {
                Section("Passage") {
                    Text(quote.text)
                        .dipleType(.readingCaption)
                        .foregroundStyle(DipleColor.textSecondary)
                        .lineLimit(4)
                }

                Section("Comment") {
                    TextField("Your thoughts about this passage", text: $comment, axis: .vertical)
                        .lineLimit(4...12)
                        .textInputAutocapitalization(.sentences)
                }

                Section("Tags") {
                    TagField(tags: $tags, suggestions: suggestions, emptyPrompt: "File this passage")
                        .padding(.vertical, DipleSpace.xs)
                }

                if !echoes.isEmpty {
                    Section("Elsewhere in your reading") {
                        ForEach(echoes) { echo in
                            EchoRow(echo: echo)
                        }
                    }
                }

                if quote.comment != nil {
                    Section {
                        // Removing the thought leaves the filing alone: they are separate
                        // things the reader added, and one button must not take both.
                        Button("Remove comment", role: .destructive) {
                            onSave("", tags)
                        }
                    }
                }
            }
            .navigationTitle("Passage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(comment, tags)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
        .task {
            echoes = await PassageEchoService.shared.echoes(for: quote, limit: 3)
        }
    }
}

/// One passage that answers the one being edited.
///
/// Deliberately **not** a link. This sheet holds unsaved edits, and a row that navigated away
/// from it would have to either discard them or invent a save-on-leave rule that exists nowhere
/// else in the app. It is enough to recognise the passage here; Highlights is where you go to
/// sit with it.
private struct EchoRow: View {
    let echo: PassageEcho

    var body: some View {
        VStack(alignment: .leading, spacing: DipleSpace.xs) {
            Text(echo.passage.text)
                .dipleType(.readingCaption)
                .foregroundStyle(DipleColor.textSecondary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DipleSpace.xs) {
                if let title = echo.passage.bookTitle, !title.isEmpty {
                    Text(title)
                        .dipleType(.nano, weight: .medium)
                        .foregroundStyle(DipleColor.textTertiary)
                        .lineLimit(1)
                    Text("·")
                        .dipleType(.nano)
                        .foregroundStyle(DipleColor.textQuaternary)
                }
                // The words the two passages share. Printed, not implied: a connection the
                // reader can check is one they can also disagree with.
                Text(echo.sharedTerms.joined(separator: " · "))
                    .dipleType(.nano)
                    .foregroundStyle(DipleColor.textQuaternary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, DipleSpace.hair)
    }
}
