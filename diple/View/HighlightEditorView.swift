import SwiftUI

/// One editor for both a fresh text selection and an existing highlight. Keeping color,
/// comment, copy and deletion in a single sheet avoids nested menus over the reading page and
/// makes a tap on an existing decoration behave exactly like creating it in the first place.
public struct HighlightEditorView: View {
    public let quote: String
    public let isExisting: Bool
    public let onSave: (String, String?) -> Void
    public let onDelete: (() -> Void)?

    @Environment(\.dismiss) private var dismiss
    @State private var selectedColorHex: String
    @State private var comment: String
    @State private var isDeleteConfirmationPresented = false
    @State private var didCopy = false
    @FocusState private var isCommentFocused: Bool

    public init(
        quote: String,
        initialColorHex: String = DipleColor.Highlight.yellow,
        initialComment: String? = nil,
        isExisting: Bool,
        onSave: @escaping (String, String?) -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.quote = quote
        self.isExisting = isExisting
        self.onSave = onSave
        self.onDelete = onDelete
        _selectedColorHex = State(initialValue: initialColorHex)
        _comment = State(initialValue: initialComment ?? "")
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DipleSpace.xxl) {
                        quoteCard
                        colorPicker
                        commentEditor
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
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DipleColor.textSecondary)
                }
            }
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomActions
            }
            .alert("Delete Highlight?", isPresented: $isDeleteConfirmationPresented) {
                Button("Delete", role: .destructive) {
                    onDelete?()
                    dismiss()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("The saved passage and its comment will be removed.")
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(.regularMaterial)
    }

    private var quoteCard: some View {
        HStack(alignment: .top, spacing: DipleSpace.m) {
            Capsule()
                .fill(selectedColor)
                .frame(width: 4)
                .animation(DipleMotion.snappy, value: selectedColorHex)

            VStack(alignment: .leading, spacing: DipleSpace.s) {
                Text("SELECTED PASSAGE")
                    .dipleType(.micro, weight: .semibold)
                    .foregroundStyle(DipleColor.textTertiary)

                Text(quote)
                    .dipleType(.readingCaption)
                    .readingLineSpacing(for: quote)
                    .foregroundStyle(DipleColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DipleSpace.l)
        .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.l)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Selected passage: \(quote)")
    }

    private var colorPicker: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            Text("COLOR")
                .dipleType(.micro, weight: .semibold)
                .foregroundStyle(DipleColor.textTertiary)

            HStack(spacing: 0) {
                ForEach(DipleColor.Highlight.all, id: \.hex) { item in
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
                let trimmed = comment.trimmingCharacters(in: .whitespacesAndNewlines)
                onSave(selectedColorHex, trimmed.isEmpty ? nil : trimmed)
                dismiss()
            } label: {
                Label(isExisting ? "Save Changes" : "Save Highlight", systemImage: "checkmark")
                    .dipleType(.footnote, weight: .semibold)
                    .foregroundStyle(DipleColor.textOnAccent)
                    .frame(maxWidth: .infinity, minHeight: 50)
                    .background(DipleColor.accent, in: RoundedRectangle(cornerRadius: DipleRadius.m))
            }
            .buttonStyle(.readerControl)
        }
        .padding(.horizontal, DipleSpace.xl)
        .padding(.top, DipleSpace.m)
        .padding(.bottom, DipleSpace.m)
        .background(.ultraThinMaterial)
    }

    private var selectedColor: Color {
        DipleColor.Highlight.color(forHex: selectedColorHex)
    }
}
