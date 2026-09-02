import SwiftUI

/// Presentation of a saved quote, used by the hub. Deletion lives in a context menu rather
/// than an inline button; the reader's own list (`HighlightRowView`) stays a separate view
/// because it also carries navigation to the passage.
public struct QuoteCardView: View {
    public let quote: Highlight
    public let onCommentRequest: (() -> Void)?
    public let onDeleteRequest: (() -> Void)?

    public init(
        quote: Highlight,
        onCommentRequest: (() -> Void)? = nil,
        onDeleteRequest: (() -> Void)? = nil
    ) {
        self.quote = quote
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
                Button(action: onCommentRequest) {
                    Label(comment == nil ? "Add comment" : "Edit comment", systemImage: "bubble.left")
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
public struct QuoteCommentEditorView: View {
    public let quote: Highlight
    public let onSave: (String) -> Void
    public let onCancel: () -> Void

    @State private var comment: String

    public init(
        quote: Highlight,
        onSave: @escaping (String) -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.quote = quote
        self.onSave = onSave
        self.onCancel = onCancel
        self._comment = State(initialValue: quote.comment ?? "")
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

                if quote.comment != nil {
                    Section {
                        Button("Remove comment", role: .destructive) {
                            onSave("")
                        }
                    }
                }
            }
            .navigationTitle(quote.comment == nil ? "Add comment" : "Edit comment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(comment)
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled()
    }
}
