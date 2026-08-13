import SwiftUI

/// The control that answers a text selection, floating over the page beside the words it
/// belongs to.
///
/// Selecting a sentence used to raise a half-height modal sheet with its own navigation bar,
/// a Save button and a comment field. That is a form, and a form is the wrong shape for the
/// gesture: highlighting while reading is a single decision — which colour — made dozens of
/// times in a sitting, and the sheet made each one cost a page you could no longer see, a
/// scroll and two taps. Colour is therefore the action here, not a setting to configure before
/// one: a tap on a swatch saves and gets out of the way. Writing a thought is the rarer
/// intent, so it keeps the full editor, reached deliberately from `Note`.
///
/// The bar takes its palette from `ReaderChrome` for the same reason the reader's own bars do:
/// it sits on paper, sepia or night, and a fixed dark card is legible on exactly one of them.
public struct ReaderSelectionBar: View {
    public let chrome: ReaderChrome
    public let onPickColor: (String) -> Void
    public let onAddNote: () -> Void
    public let onCopy: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didCopy = false
    @State private var appeared = false
    /// The swatch the reader just committed to, held for the length of its exit.
    @State private var committedHex: String?

    public init(
        chrome: ReaderChrome,
        onPickColor: @escaping (String) -> Void,
        onAddNote: @escaping () -> Void,
        onCopy: @escaping () -> Void
    ) {
        self.chrome = chrome
        self.onPickColor = onPickColor
        self.onAddNote = onAddNote
        self.onCopy = onCopy
    }

    public var body: some View {
        HStack(spacing: DipleSpace.xs) {
            ForEach(DipleColor.Highlight.all, id: \.hex) { item in
                Button {
                    commit(item.hex)
                } label: {
                    Circle()
                        .fill(DipleColor.Highlight.color(forHex: item.hex))
                        .frame(width: 26, height: 26)
                        .overlay {
                            Circle().stroke(chrome.separator, lineWidth: DipleStroke.hairline)
                        }
                        // The chosen swatch swells and fades as the bar leaves, so the colour
                        // reads as going onto the page rather than the bar merely vanishing
                        // and a highlight appearing somewhere behind it. The others shrink
                        // away, which leaves the eye on the one that was picked.
                        .scaleEffect(scale(for: item.hex))
                        .opacity(opacity(for: item.hex))
                        .frame(width: 40, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.readerControl)
                .disabled(committedHex != nil)
                .accessibilityLabel("Highlight \(item.name)")
            }

            Rectangle()
                .fill(chrome.separator)
                .frame(width: DipleStroke.hairline, height: 24)
                .padding(.horizontal, DipleSpace.hair)

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
        .accessibilityLabel("Selection actions")
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

    /// Saves, then lets the swatch finish leaving.
    ///
    /// The save itself is not delayed — the highlight is written and the decoration appears on
    /// the page immediately, which is the whole point of a one-tap action. What is held back is
    /// only this view's own exit, and only for as long as a spring takes to read. At Reduce
    /// Motion there is nothing to wait for and the call goes straight through.
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
