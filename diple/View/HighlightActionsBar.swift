import SwiftUI

/// The control that answers a passage, floating over the page beside the words it belongs to.
///
/// It has two lives, and which one it is in is the whole of its behaviour.
///
/// **Pending.** A selection settled and nothing has been written. The reader has said *this
/// passage* and not yet said anything else, so the bar offers only what is true of a passage
/// rather than of a saved quote: the colours, a translation, a copy. Writing a thought needs
/// something to attach the thought to, so the note is dimmed and takes no touches; deleting
/// needs something to delete, so it is not drawn at all. Tapping away here leaves nothing
/// behind — no row, no decoration, no sync.
///
/// **Committed.** A highlight exists, either because a colour was just tapped or because the
/// reader came back and tapped the mark. Everything is live, the current colour wears a ring,
/// and a tap on a *different* swatch recolours the one highlight rather than making a second.
///
/// The move from the first to the second happens under the reader's finger and does not close
/// the bar: choosing a colour is the act of saving, and the commonest thing to want next is
/// the note that was dimmed a moment ago. So the swatches only play their exit when the tap
/// is genuinely the last one — a recolour in `committed`, which ends with the bar leaving.
///
/// The bar takes its palette from `ReaderChrome` for the same reason the reader's own bars do:
/// it sits on paper, sepia or night, and a fixed dark card is legible on exactly one of them.
public struct HighlightActionsBar: View {
    /// Whether there is anything saved behind this bar yet.
    ///
    /// Named `Mode` and not `State`: a nested type called `State` inside a `View` shadows
    /// SwiftUI's own property wrapper, and every `@State` in the file stops compiling with
    /// "enum 'State' cannot be used as an attribute".
    public enum Mode: Equatable {
        /// A live selection. Nothing is in the database.
        case pending
        /// A saved highlight, in this colour.
        case committed(colorHex: String)

        var isPending: Bool { self == .pending }

        var colorHex: String? {
            switch self {
            case .pending: return nil
            case let .committed(hex): return hex
            }
        }
    }

    public let chrome: ReaderChrome
    public let mode: Mode
    /// Whether the passage has anything in it worth handing to the translator. False for the
    /// one case the reader can still reach — a stored quote whose text arrived empty — where
    /// the sheet would open on a blank string.
    public let canTranslate: Bool
    public let onPickColor: (String) -> Void
    /// `nil` where the system translator does not exist, which today is Mac Catalyst: the
    /// `Translation` framework ships no Catalyst slice at all. The glyph is then not drawn,
    /// rather than drawn dead.
    public let onTranslate: (() -> Void)?
    public let onAddNote: () -> Void
    public let onCopy: () -> Void
    /// `nil` while nothing has been saved — in `pending`, and on PDF before a colour is
    /// chosen. There is no such thing as removing a highlight that was never made.
    public let onDelete: (() -> Void)?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var didCopy = false
    @State private var appeared = false
    /// The swatch the reader just committed to, held for the length of its exit. Only ever set
    /// by a tap that closes the bar — see `commit`.
    @State private var committedHex: String?

    public init(
        chrome: ReaderChrome,
        mode: Mode,
        canTranslate: Bool = false,
        onPickColor: @escaping (String) -> Void,
        onTranslate: (() -> Void)? = nil,
        onAddNote: @escaping () -> Void,
        onCopy: @escaping () -> Void,
        onDelete: (() -> Void)? = nil
    ) {
        self.chrome = chrome
        self.mode = mode
        self.canTranslate = canTranslate
        self.onPickColor = onPickColor
        self.onTranslate = onTranslate
        self.onAddNote = onAddNote
        self.onCopy = onCopy
        self.onDelete = onDelete
    }

    /// Zero, and every control carries its own 44 pt frame instead.
    ///
    /// Eight controls at the 44 pt minimum is 352 pt of a 375 pt screen, which leaves the row
    /// nothing to spend on gaps: with the old 4 pt spacing and 40 pt swatches this bar was
    /// 393 pt wide the moment the delete button appeared, i.e. already wider than the phone it
    /// had to fit on. Moving the air *inside* the hit targets buys 24 pt and costs nothing
    /// optically — a 26 pt swatch in a 44 pt frame leaves the same 18 pt between two circles
    /// that a 26 pt swatch in a 40 pt frame plus 4 pt of spacing did.
    private static let itemSpacing: CGFloat = 0

    /// The tappable square every control fills. Below this a control is a target the HIG says
    /// a finger cannot reliably hit, and the swatches used to be 40 pt wide.
    private static let hitTarget: CGFloat = 44

    public var body: some View {
        HStack(spacing: Self.itemSpacing) {
            ForEach(DipleColor.Highlight.selectable, id: \.hex) { item in
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

            if let onTranslate {
                // `globe`, not `translate`: the two read the same at 15 pt, and `globe` has
                // been in SF Symbols since the beginning, so the glyph never becomes the thing
                // that pins the deployment target.
                action(
                    systemImage: "globe",
                    label: "Translate passage",
                    isEnabled: canTranslate,
                    action: onTranslate
                )
            }

            // Dimmed rather than hidden in `pending`. A control that disappears and comes back
            // moves the three beside it, so the row would reflow under the finger at the exact
            // moment the reader is aiming at one of them; a control that greys out says the
            // same thing and holds still. Delete is the exception — it is not merely
            // unavailable there, it has no referent.
            action(
                systemImage: "text.bubble",
                label: "Add a note",
                isEnabled: !mode.isPending,
                action: onAddNote
            )

            action(
                systemImage: didCopy ? "checkmark" : "doc.on.doc",
                label: didCopy ? "Copied" : "Copy passage",
                tint: didCopy ? DipleColor.success : nil
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
                // row of saturated swatches reads as one more colour to mark the passage with.
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

    /// A hairline with no padding of its own. The 44 pt frames on either side already leave a
    /// glyph roughly 14 pt clear of it, and at this width the row has no points to spare.
    private var separator: some View {
        Rectangle()
            .fill(chrome.separator)
            .frame(width: DipleStroke.hairline, height: 24)
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
            // the one that was picked. Nothing of this happens on the tap that *creates* a
            // highlight, because that tap does not end the bar.
            .scaleEffect(scale(for: hex))
            .opacity(opacity(for: hex))
            .frame(width: Self.hitTarget, height: Self.hitTarget)
            .contentShape(Rectangle())
    }

    private func isCurrent(_ hex: String) -> Bool {
        guard let currentColorHex = mode.colorHex else { return false }
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

    /// Hands the colour on, and plays the swatches out only if the bar is about to go with it.
    ///
    /// In `committed` a colour tap is a recolour and the last thing the reader wants from this
    /// bar, so it ends the way it always did: the write goes through immediately — the mark on
    /// the page changes at once, which is the point of a one-tap action — and only this view's
    /// own exit is held back, for as long as a spring takes to read.
    ///
    /// In `pending` the same tap *creates* the highlight and the bar stays, on the spot, so
    /// that the note it has just enabled is one tap away. Playing the exit here would fade out
    /// four swatches that are about to be needed again and disable them permanently, since
    /// nothing clears `committedHex` on a bar that never leaves.
    private func commit(_ hex: String) {
        guard committedHex == nil else { return }

        guard !mode.isPending, !reduceMotion else {
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
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .dipleIcon(15, weight: .semibold)
                .foregroundStyle(tint ?? (isEnabled ? chrome.control : chrome.secondary.opacity(0.4)))
                .frame(width: Self.hitTarget, height: Self.hitTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.readerControl)
        .disabled(!isEnabled)
        .accessibilityLabel(label)
    }
}
