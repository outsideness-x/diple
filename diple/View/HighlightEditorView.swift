import SwiftUI

/// One editor for both a fresh text selection and an existing highlight. Keeping color,
/// comment, tags, copy and deletion in a single sheet avoids nested menus over the reading page
/// and makes a tap on an existing decoration behave exactly like creating it in the first place.
///
/// Tags come last, after the thought rather than before it. They are a filing act — what this
/// sentence *is* to the reader — and putting them above the comment would push the field the
/// editor actually exists for below the fold of a medium detent.
public struct HighlightEditorView: View {
    public let quote: String
    public let isExisting: Bool
    /// Every word already used on a passage anywhere in the library. Sources and notes keep
    /// their own vocabularies; see `HighlightTag`.
    public let tagSuggestions: [String]
    public let onSave: (String, String?, [String]) -> Void
    public let onDelete: (() -> Void)?
    /// The book this passage came from, named only when the sheet was opened somewhere that is
    /// not that book. Inside the reader it stays `nil`: the source is the page underneath, and
    /// printing its title over it would be the app telling the reader where they are standing.
    public let sourceTitle: String?
    /// Opening the passage where it was written. `nil` when there is nowhere to go — the book
    /// has been deleted, or the passage was imported for one that was never here.
    public let onOpenInSource: (() -> Void)?
    /// Growing a note out of this passage, for the moment a thought outruns the comment field.
    public let onExpandIntoNote: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedColorHex: String
    @State private var comment: String
    @State private var tags: [String]
    @State private var isDeleteConfirmationPresented = false
    @State private var didCopy = false
    @State private var isSaving = false
    @FocusState private var isCommentFocused: Bool
    /// Opened from the reader, the sheet rests at medium so the page it came from is still
    /// visible behind it. Opened from the board there is no page behind it and no reason to
    /// keep one in view, while the comment field — the reason to have opened it at all — sits
    /// below the fold of a medium detent once the source strip is above it. So the way in
    /// decides the height, and `sourceTitle` is exactly the signal for which way that was.
    @State private var detent: PresentationDetent

    public init(
        quote: String,
        initialColorHex: String = DipleColor.Highlight.yellow,
        initialComment: String? = nil,
        initialTags: [String] = [],
        tagSuggestions: [String] = [],
        isExisting: Bool,
        sourceTitle: String? = nil,
        onSave: @escaping (String, String?, [String]) -> Void,
        onDelete: (() -> Void)? = nil,
        onOpenInSource: (() -> Void)? = nil,
        onExpandIntoNote: (() -> Void)? = nil
    ) {
        self.quote = quote
        self.isExisting = isExisting
        self.tagSuggestions = tagSuggestions
        self.onSave = onSave
        self.onDelete = onDelete
        self.sourceTitle = sourceTitle
        self.onOpenInSource = onOpenInSource
        self.onExpandIntoNote = onExpandIntoNote
        _selectedColorHex = State(initialValue: initialColorHex)
        _comment = State(initialValue: initialComment ?? "")
        _tags = State(initialValue: initialTags)
        _detent = State(initialValue: sourceTitle == nil ? .medium : .large)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DipleSpace.xxl) {
                        quoteCard
                        sourceStrip
                        colorPicker
                        commentEditor
                        tagEditor
                        expandIntoNote
                    }
                    .padding(.horizontal, DipleSpace.xl)
                    .padding(.top, DipleSpace.m)
                    .padding(.bottom, DipleSpace.xl)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle(isExisting ? "Edit Highlight" : "New Highlight")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DipleColor.textSecondary)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomActions
            }
            .alert("Delete passage?", isPresented: $isDeleteConfirmationPresented) {
                Button("Delete", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The saved passage and its comment will be removed.")
            }
        }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
        .interactiveDismissDisabled(isSaving)
    }

    private var quoteCard: some View {
        HStack(alignment: .top, spacing: DipleSpace.m) {
            Capsule()
                .fill(selectedColor)
                .frame(width: isSaving ? 7 : 4)
                .shadow(color: selectedColor.opacity(isSaving ? 0.8 : 0), radius: isSaving ? 10 : 0)
                .animation(DipleMotion.snappy, value: selectedColorHex)
                .animation(DipleMotion.standard, value: isSaving)

            VStack(alignment: .leading, spacing: DipleSpace.s) {
                Text("SELECTED PASSAGE")
                    .dipleType(.micro, weight: .semibold)
                    .foregroundStyle(DipleColor.textTertiary)

                Text(quote)
                    .dipleType(.editorialQuote)
                    .readingLineSpacing(for: quote)
                    .foregroundStyle(DipleColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DipleSpace.l)
        .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.l)
        .overlay {
            RoundedRectangle(cornerRadius: DipleRadius.l)
                .stroke(selectedColor.opacity(isSaving ? 0.72 : 0), lineWidth: isSaving ? 1.5 : 0)
                .shadow(color: selectedColor.opacity(isSaving ? 0.32 : 0), radius: 12)
        }
        .scaleEffect(isSaving && !reduceMotion ? 0.99 : 1)
        .animation(DipleMotion.standard, value: isSaving)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Selected passage: \(quote)")
    }

    /// Which book this is, and the way back into it.
    ///
    /// It reads as one row rather than a labelled field because it is not something the reader
    /// sets — it is where they already are. The whole row is the target when there is somewhere
    /// to go, so the name of the book and the act of opening it are not two different places to
    /// aim at in a sheet held with one thumb.
    @ViewBuilder
    private var sourceStrip: some View {
        if let sourceTitle {
            let row = HStack(spacing: DipleSpace.s) {
                Image(systemName: "book.closed")
                    .dipleIcon(11)
                    .foregroundStyle(DipleColor.accentInk)

                Text(sourceTitle)
                    .dipleType(.caption, weight: .medium)
                    .foregroundStyle(DipleColor.textSecondary)
                    .lineLimit(1)

                Spacer(minLength: DipleSpace.s)

                if onOpenInSource != nil {
                    Text("Open in the book")
                        .dipleType(.micro, weight: .semibold)
                        .foregroundStyle(DipleColor.accentInk)
                    Image(systemName: "chevron.right")
                        .dipleIcon(9, weight: .semibold)
                        .foregroundStyle(DipleColor.accentInk)
                }
            }
            .padding(.vertical, DipleSpace.s)
            .contentShape(Rectangle())

            if let onOpenInSource {
                Button {
                    HapticManager.shared.selection()
                    onOpenInSource()
                } label: { row }
                .buttonStyle(.plain)
                .accessibilityLabel("Open this passage in \(sourceTitle)")
            } else {
                row.accessibilityElement(children: .combine)
            }
        }
    }

    /// Last on the page, and that is the argument for it.
    ///
    /// A comment is a line in the margin; a note is a page of your own. The moment the reader
    /// finds out which one they are writing is the moment the field runs out — after they have
    /// read the passage, said their piece and filed it — so the offer sits exactly there rather
    /// than competing with the comment field for the same thought.
    @ViewBuilder
    private var expandIntoNote: some View {
        if let onExpandIntoNote {
            Button {
                HapticManager.shared.selection()
                save(then: onExpandIntoNote)
            } label: {
                HStack(spacing: DipleSpace.s) {
                    Image(systemName: "square.and.pencil")
                        .dipleIcon(13, weight: .semibold)
                    Text("Expand into a note")
                        .dipleType(.footnote, weight: .semibold)
                }
                .foregroundStyle(DipleColor.textSecondary)
                .frame(maxWidth: .infinity, minHeight: 46)
                .overlay {
                    RoundedRectangle(cornerRadius: DipleRadius.m)
                        .stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline)
                }
            }
            .buttonStyle(.readerControl)
            .accessibilityHint("Starts a note with this passage quoted at the top")
        }
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            Text("COLOR")
                .dipleType(.micro, weight: .semibold)
                .foregroundStyle(DipleColor.textTertiary)

            HStack(spacing: 0) {
                ForEach(DipleColor.Highlight.selectable, id: \.hex) { item in
                    Button {
                        HapticManager.shared.selection()
                        withAnimation(DipleMotion.snappy) {
                            selectedColorHex = item.hex
                        }
                    } label: {
                        ZStack {
                            Circle()
                                .fill(DipleColor.Highlight.color(forHex: item.hex))
                                .frame(width: 34, height: 34)

                            if selectedColorHex == item.hex {
                                Circle()
                                    .stroke(DipleColor.textPrimary, lineWidth: 2)
                                    .frame(width: 44, height: 44)
                                Image(systemName: "checkmark")
                                    .dipleIcon(12, weight: .bold)
                                    .foregroundStyle(DipleColor.textOnAccent)
                            }
                        }
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.readerControl)
                    .accessibilityLabel(item.name)
                    .accessibilityAddTraits(selectedColorHex == item.hex ? .isSelected : [])
                }
            }
            .padding(.horizontal, DipleSpace.s)
            .padding(.vertical, DipleSpace.xs)
            .background(DipleColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DipleRadius.m))
            .overlay {
                RoundedRectangle(cornerRadius: DipleRadius.m)
                    .stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline)
            }
        }
    }

    private var commentEditor: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("COMMENT")
                    .dipleType(.micro, weight: .semibold)
                    .foregroundStyle(DipleColor.textTertiary)
                Spacer()
                Text("OPTIONAL")
                    .dipleType(.nano)
                    .foregroundStyle(DipleColor.textQuaternary)
            }

            TextField("Add context or your own thought…", text: $comment, axis: .vertical)
                .lineLimit(3...8)
                .dipleType(.body)
                .foregroundStyle(DipleColor.textPrimary)
                .textInputAutocapitalization(.sentences)
                .focused($isCommentFocused)
                .padding(DipleSpace.m)
                .frame(minHeight: 92, alignment: .topLeading)
                .background(DipleColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DipleRadius.m))
                .overlay {
                    RoundedRectangle(cornerRadius: DipleRadius.m)
                        .stroke(
                            isCommentFocused ? DipleColor.accent.opacity(0.65) : DipleColor.hairline,
                            lineWidth: DipleStroke.hairline
                        )
                }
        }
    }

    private var tagEditor: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            HStack(alignment: .firstTextBaseline) {
                Text("TAGS")
                    .dipleType(.micro, weight: .semibold)
                    .foregroundStyle(DipleColor.textTertiary)
                Spacer()
                Text("OPTIONAL")
                    .dipleType(.nano)
                    .foregroundStyle(DipleColor.textQuaternary)
            }

            TagField(tags: $tags, suggestions: tagSuggestions, emptyPrompt: "File this passage")
        }
    }

    private var bottomActions: some View {
        HStack(spacing: DipleSpace.s) {
            if isExisting, onDelete != nil {
                Button(role: .destructive) {
                    isDeleteConfirmationPresented = true
                } label: {
                    Image(systemName: "trash")
                        .dipleIcon(15, weight: .semibold)
                        .foregroundStyle(DipleColor.destructive)
                        .frame(width: 50, height: 50)
                        .background(DipleColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DipleRadius.m))
                }
                .buttonStyle(.readerControl)
                .accessibilityLabel("Delete highlight")
            }

            Button {
                UIPasteboard.general.string = quote
                HapticManager.shared.impact(.light)
                withAnimation(DipleMotion.snappy) { didCopy = true }
                Task {
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    await MainActor.run {
                        withAnimation(DipleMotion.snappy) { didCopy = false }
                    }
                }
            } label: {
                Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                    .dipleIcon(15, weight: .semibold)
                    .foregroundStyle(didCopy ? DipleColor.success : DipleColor.textSecondary)
                    .frame(width: 50, height: 50)
                    .background(DipleColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DipleRadius.m))
            }
            .buttonStyle(.readerControl)
            .accessibilityLabel(didCopy ? "Copied" : "Copy passage")

            Button {
                save()
            } label: {
                HStack(spacing: DipleSpace.s) {
                    Image(systemName: isSaving ? "checkmark.circle.fill" : "checkmark")
                        .dipleIcon(15, weight: .semibold)
                        .contentTransition(.symbolEffect(.replace))
                    Text(isSaving ? "Saved" : (isExisting ? "Save Changes" : "Save Highlight"))
                        .contentTransition(.opacity)
                }
                .dipleType(.footnote, weight: .semibold)
                .foregroundStyle(DipleColor.textOnAccent)
                .frame(maxWidth: .infinity, minHeight: 50)
                .background(
                    isSaving ? selectedColor : DipleColor.accent,
                    in: RoundedRectangle(cornerRadius: DipleRadius.m)
                )
                .scaleEffect(isSaving && !reduceMotion ? 0.97 : 1)
                .animation(DipleMotion.snappy, value: isSaving)
            }
            .buttonStyle(.readerControl)
            .disabled(isSaving)
            .accessibilityLabel(isSaving ? "Highlight saved" : (isExisting ? "Save changes" : "Save highlight"))
        }
        .padding(.horizontal, DipleSpace.xl)
        .padding(.top, DipleSpace.m)
        .padding(.bottom, DipleSpace.m)
        .background(.ultraThinMaterial)
    }

    private var selectedColor: Color {
        DipleColor.Highlight.color(forHex: selectedColorHex)
    }

    /// `then` runs once the edit is written and before the sheet goes away.
    ///
    /// Leaving for somewhere else has to save first, or a comment typed and then expanded into
    /// a note is a comment the reader watched themselves write and never saw again. It is the
    /// same body as the Save button because there is only one definition of what saving this
    /// sheet means; a second one would drift from it at the first change to either.
    private func save(then continuation: (() -> Void)? = nil) {
        guard !isSaving else { return }
        let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalizedComment = trimmed.isEmpty ? nil : trimmed

        guard !reduceMotion else {
            onSave(selectedColorHex, normalizedComment, tags)
            continuation?()
            dismiss()
            return
        }

        isCommentFocused = false
        withAnimation(DipleMotion.standard) { isSaving = true }

        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(380))
            onSave(selectedColorHex, normalizedComment, tags)
            continuation?()
            dismiss()
        }
    }
}
