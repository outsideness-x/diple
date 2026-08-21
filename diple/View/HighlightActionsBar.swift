import SwiftUI

/// The control that answers a tap on an existing highlight, floating over the page beside the
/// words it belongs to.
///
/// It used to answer a *selection* instead, and that was one step too early. Selecting a
/// sentence raised a bar of five swatches and nothing was saved until one of them was tapped,
/// so the commonest act in the app — mark this passage — cost a decision the reader had not
/// asked to make yet. A selection is already the decision; the colour is a detail about it.
///
/// So a selection now becomes a highlight the moment it settles, in whichever colour was used
/// last, and this bar appears only when the reader comes back and taps one. Everything that was
/// on it stays on it — recolour, copy, write a thought — and it gains the one action the old
/// order never needed: removing a highlight that should not have been made. That is the price
/// of saving without asking, and it has to be one tap away, next to the colours, not buried.
///
/// The bar takes its palette from `ReaderChrome` for the same reason the reader's own bars do:
/// it sits on paper, sepia or night, and a fixed dark card is legible on exactly one of them.
public struct HighlightActionsBar: View {
    public let chrome: ReaderChrome
    /// The colour the highlight is currently marked in, so the bar can show which of the five
    /// it already is rather than presenting all of them as equally untaken. `nil` when the bar
    /// is answering a selection that has not been saved yet — see `onDelete`.
    public let currentColorHex: String?
    public let onPickColor: (String) -> Void
    public let onAddNote: () -> Void
    public let onCopy: () -> Void
    /// `nil` on the one surface where a highlight cannot be tapped again.
    ///
    /// The EPUB navigator draws highlights as decorations and reports taps on them, so there a
    /// selection saves straight away and this bar is what a later tap opens — with a way to
    /// undo the save. The PDF navigator has no decoration layer at all: a highlight on a PDF is
    /// invisible on the page and there is nothing to tap. Saving silently on every selection
    /// there would scatter quotes a reader could neither see nor remove, so PDFs keep the older
    /// order — the bar answers the selection, and tapping a colour is what saves. Nothing has
    /// been created yet at that point, so there is nothing to delete.
    public let onDelete: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didCopy = false
    @State private var appeared = false
    /// The swatch the reader just committed to, held for the length of its exit.
    @State private var committedHex: String?

    public init(
        chrome: ReaderChrome,
        currentColorHex: String? = nil,
        onPickColor: @escaping (String) -> Void,
        onAddNote: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.chrome = chrome
        self.currentColorHex = currentColorHex
        self.onPickColor = onPickColor
        self.onAddNote = onAddNote
        self.onCopy = onCopy
        self.onDelete = onDelete
    }

    public var body: some View {
        HStack(spacing: DipleSpace.xs) {
            ForEach(DipleColor.Highlight.all, id: \.hex) { item in
                Button {
                    commit(item.hex)
                } label: {
                    swatch(hex: item.hex)
                }
                .buttonStyle(.readerControl)
                .disabled(committedHex != nil)
                .accessibilityLabel("Highlight \(item.name)")
                .accessibilityAddTraits(isCurrent(item.hex) ? [.isSelected] : [])
            }

            separator

            action(systemImage: "text.bubble", label: "Add a note", action: onAddNote)

            action(
                systemImage: didCopy ? "checkmark" : "doc.on.doc",
                label: didCopy ? "Copied" : "Copy passage",
                tint: didCopy ? DipleColor.success : chrome.control
            ) {
                onCopy()
                withAnimation(DipleMotion.snappy) { didCopy = true }
                Task { @MainActor in
                    try? await Task.sleep(for: .milliseconds(1200))
                    withAnimation(DipleMotion.snappy) { didCopy = false }
                }
            }

            if let onDelete {
                separator

                // Destructive, and set apart by a rule rather than by colour: a red glyph in a
                // row of five saturated swatches reads as a sixth colour to mark the passage
                // with.
                action(systemImage: "trash", label: "Remove highlight", action: onDelete)
            }
        }
        .padding(.horizontal, DipleSpace.s)
        .background {
            Capsule(style: .continuous)
                .fill(chrome.tint)
                .background(.regularMaterial, in: Capsule(style: .continuous))
                .environment(\.colorScheme, chrome.colorScheme)
        }
        .overlay {
            Capsule(style: .continuous).stroke(chrome.separator, lineWidth: DipleStroke.hairline)
        }
        .shadow(color: Color.black.opacity(0.28), radius: 16, y: 6)
        .scaleEffect(appeared || reduceMotion ? 1 : 0.92)
        .opacity(appeared || reduceMotion ? 1 : 0)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(DipleMotion.snappy) { appeared = true }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Highlight actions")
    }

    private var separator: some View {
        Rectangle()
            .fill(chrome.separator)
            .frame(width: DipleStroke.hairline, height: 24)
            .padding(.horizontal, DipleSpace.hair)
    }

    /// The colour the highlight already carries wears a ring rather than a tick: a checkmark
    /// drawn inside a 26pt circle has to be small enough to be a smudge on the two darkest
    /// swatches, while a ring reads at a glance against page, sepia and night alike.
    private func swatch(hex: String) -> some View {
        Circle()
            .fill(DipleColor.Highlight.color(forHex: hex))
            .frame(width: 26, height: 26)
            .overlay {
                Circle().stroke(chrome.separator, lineWidth: DipleStroke.hairline)
            }
            .overlay {
                Circle()
                    .stroke(chrome.control, lineWidth: 2)
                    .padding(-4)
                    .opacity(isCurrent(hex) ? 1 : 0)
            }
            // The chosen swatch swells and fades as the bar leaves, so the colour reads as
            // going onto the page rather than the bar merely vanishing and the highlight
            // changing somewhere behind it. The others shrink away, which leaves the eye on
            // the one that was picked.
            .scaleEffect(scale(for: hex))
            .opacity(opacity(for: hex))
            .frame(width: 40, height: 44)
            .contentShape(Rectangle())
    }

    private func isCurrent(_ hex: String) -> Bool {
        guard let currentColorHex else { return false }
        return hex.caseInsensitiveCompare(currentColorHex) == .orderedSame
    }

    private func scale(for hex: String) -> CGFloat {
        guard let committedHex, !reduceMotion else { return 1 }
        return committedHex == hex ? 2.1 : 0.5
    }

    /// Every swatch fades on commit; what differs is the direction it leaves in, which
    /// `scale(for:)` carries — the chosen one outward onto the page, the rest inward.
    private func opacity(for hex: String) -> Double {
        committedHex == nil || reduceMotion ? 1 : 0
    }

    /// Recolours, then lets the swatch finish leaving.
    ///
    /// The write itself is not delayed — the highlight changes colour on the page immediately,
    /// which is the whole point of a one-tap action. What is held back is only this view's own
    /// exit, and only for as long as a spring takes to read. At Reduce Motion there is nothing
    /// to wait for and the call goes straight through.
    private func commit(_ hex: String) {
        guard committedHex == nil else { return }

        guard !reduceMotion else {
            onPickColor(hex)
            return
        }

        withAnimation(DipleMotion.snappy) { committedHex = hex }
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            onPickColor(hex)
        }
    }

    private func action(
        systemImage: String,
        label: String,
        tint: SwiftUI.Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .dipleIcon(15, weight: .semibold)
                .foregroundStyle(tint ?? chrome.control)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.readerControl)
        .accessibilityLabel(label)
    }
}
