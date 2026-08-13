import SwiftUI

public struct SelectionColorBarView: View {
    public let onHighlight: (String) -> Void
    public let onAddThought: (String) -> Void
    public let onCopy: () -> Void
    public let onCancel: () -> Void

    private let colors = DipleColor.Highlight.all
    @State private var selectedColorHex = DipleColor.Highlight.yellow

    public init(
        onHighlight: @escaping (String) -> Void,
        onAddThought: @escaping (String) -> Void,
        onCopy: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.onHighlight = onHighlight
        self.onAddThought = onAddThought
        self.onCopy = onCopy
        self.onCancel = onCancel
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            actionRow(showsLabels: true)
            actionRow(showsLabels: false)
        }
        .padding(.horizontal, DipleSpace.l)
        .padding(.vertical, DipleSpace.m)
        .background(DipleColor.surfaceRaised)
        .cornerRadius(24)
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .stroke(DipleColor.hairlineStrong, lineWidth: DipleStroke.hairline)
        )
        .shadow(color: Color.black.opacity(0.5), radius: 10, x: 0, y: 4)
        .padding(.horizontal, DipleSpace.xxl)
    }

    private func actionRow(showsLabels: Bool) -> some View {
        HStack(spacing: DipleSpace.m) {
            selectionAction(
                title: "Highlight",
                systemImage: "highlighter",
                showsLabel: showsLabels,
                tint: DipleColor.Highlight.color(forHex: selectedColorHex)
            ) {
                onHighlight(selectedColorHex)
            }

            selectionAction(
                title: "Add thought",
                systemImage: "square.and.pencil",
                showsLabel: showsLabels,
                tint: DipleColor.accent
            ) {
                onAddThought(selectedColorHex)
            }

            Spacer(minLength: 0)

            Menu {
                ForEach(colors, id: \.hex) { item in
                    Button {
                        HapticManager.shared.selection()
                        selectedColorHex = item.hex
                    } label: {
                        Label(item.name, systemImage: item.hex == selectedColorHex ? "checkmark.circle.fill" : "circle.fill")
                    }
                }
            } label: {
                Circle()
                    .fill(DipleColor.Highlight.color(forHex: selectedColorHex))
                    .frame(width: 26, height: 26)
                    .overlay(Circle().stroke(DipleColor.hairlineStrong, lineWidth: DipleStroke.regular))
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.readerControl)
            .accessibilityLabel("Highlight color")

            Button {
                HapticManager.shared.impact(.light)
                onCopy()
            } label: {
                Image(systemName: "doc.on.doc")
                    .dipleIcon(14, weight: .medium)
                    .foregroundStyle(DipleColor.textSecondary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.readerControl)
            .accessibilityLabel("Copy selection")

            Button {
                HapticManager.shared.impact(.light)
                onCancel()
            } label: {
                Image(systemName: "xmark")
                    .dipleIcon(13)
                    .foregroundStyle(DipleColor.textTertiary)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.readerControl)
            .accessibilityLabel("Cancel selection")
        }
    }

    private func selectionAction(
        title: String,
        systemImage: String,
        showsLabel: Bool,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.shared.impact(.light)
            action()
        } label: {
            HStack(spacing: DipleSpace.xs) {
                Image(systemName: systemImage)
                    .dipleIcon(14, weight: .semibold)
                if showsLabel {
                    Text(title)
                        .dipleType(.footnote, weight: .semibold)
                        .fixedSize()
                }
            }
            .foregroundStyle(tint)
            .frame(minWidth: 44, minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(.readerControl)
        .accessibilityLabel(title)
    }
}

/// Captures the reader's interpretation at the moment a passage still has context around it.
/// The thought is stored on the highlight itself, so it appears in the review surface without
/// forcing the reader to leave the page and construct a separate note first.
public struct SelectionThoughtEditorView: View {
    public let quote: String
    public let onSave: (String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var thought = ""
    @FocusState private var isFocused: Bool

    public init(quote: String, onSave: @escaping (String) -> Void) {
        self.quote = quote
        self.onSave = onSave
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DipleSpace.xl) {
                        VStack(alignment: .leading, spacing: DipleSpace.s) {
                            Text("PASSAGE")
                                .dipleType(.micro, weight: .semibold)
                                .foregroundStyle(DipleColor.accent)

                            Text(quote)
                                .dipleType(.readingCaption)
                                .readingLineSpacing(for: quote)
                                .foregroundStyle(DipleColor.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(DipleSpace.m)
                        .craftSurface()

                        VStack(alignment: .leading, spacing: DipleSpace.s) {
                            Text("YOUR THOUGHT")
                                .dipleType(.micro, weight: .semibold)
                                .foregroundStyle(DipleColor.textTertiary)

                            TextField("Why does this matter?", text: $thought, axis: .vertical)
                                .lineLimit(4...10)
                                .dipleType(.body)
                                .foregroundStyle(DipleColor.textPrimary)
                                .textInputAutocapitalization(.sentences)
                                .focused($isFocused)
                                .padding(DipleSpace.m)
                                .background(DipleColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DipleRadius.m))
                        }
                    }
                    .padding(.horizontal, DipleSpace.xl)
                    .padding(.top, DipleSpace.l)
                }
            }
            .navigationTitle("Add a Thought")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        onSave(thought.trimmingCharacters(in: .whitespacesAndNewlines))
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .disabled(thought.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onAppear { isFocused = true }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }
}
