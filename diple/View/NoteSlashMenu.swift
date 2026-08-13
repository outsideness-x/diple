import SwiftUI

/// The command list a `/` summons, anchored beside the caret.
///
/// The formatting bar it stands beside is a fixed row of twelve glyphs: to use it you leave
/// the words, find an icon and come back. A slash menu is reached without moving — the hand
/// stays where it was writing, and the command is named rather than drawn, so it can be found
/// by typing what it is called instead of by recognising a pictogram.
///
/// Deliberately kept a list of the same prefixes the bar applies, not a second definition of
/// what a heading is; see `NoteSlashCommand`.
public struct NoteSlashMenu: View {
    public let commands: [NoteSlashCommand]
    public let onPick: (NoteSlashCommand) -> Void

    /// Enough rows to be worth opening, few enough that the menu never becomes the page.
    private static let visibleRows = 5
    private static let rowHeight: CGFloat = 38

    /// Sized to what it holds, capped at `visibleRows`.
    ///
    /// A `ScrollView` takes every point it is offered, so a fixed max height left a panel of
    /// empty space under a single result — the menu looked broken exactly when the reader had
    /// narrowed it down to the one command they wanted.
    private var height: CGFloat {
        let rows = min(CGFloat(commands.count), CGFloat(Self.visibleRows))
        return rows * Self.rowHeight + DipleSpace.s
    }

    public init(commands: [NoteSlashCommand], onPick: @escaping (NoteSlashCommand) -> Void) {
        self.commands = commands
        self.onPick = onPick
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(commands) { command in
                    Button {
                        HapticManager.shared.selection()
                        onPick(command)
                    } label: {
                        HStack(spacing: DipleSpace.m) {
                            Image(systemName: command.systemImage)
                                .dipleIcon(13, weight: .medium)
                                .foregroundStyle(DipleColor.accent)
                                .frame(width: 22)
                            Text(command.title)
                                .dipleType(.callout)
                                .foregroundStyle(DipleColor.textPrimary)
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, DipleSpace.m)
                        .frame(height: Self.rowHeight)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.slashRow)
                }
            }
            .padding(.vertical, DipleSpace.xs)
        }
        // Sized to its longest row rather than stretched: a menu that spans the column reads
        // as a new screen, and this is a completion, not a destination.
        .frame(width: 232, height: height)
        .background(DipleColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DipleRadius.m, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DipleRadius.m, style: .continuous)
                .stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Insert a block")
    }
}

/// A highlight that fills the row rather than scaling it. The reader-control style's shrink
/// reads as a button being pressed; inside a list it reads as the list flinching.
private struct SlashRowButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? DipleColor.accentSoft : Color.clear)
    }
}

private extension ButtonStyle where Self == SlashRowButtonStyle {
    static var slashRow: SlashRowButtonStyle { SlashRowButtonStyle() }
}

/// Places the menu next to the caret without letting it leave the editor.
///
/// The caret rect arrives in the text view's own coordinate space, and this overlay is applied
/// to that same view, so no conversion is needed — which is the whole reason the rect is
/// published rather than recomputed on the SwiftUI side.
public struct NoteSlashMenuOverlay: ViewModifier {
    public let context: NoteSlashContext?
    public let onPick: (NoteSlashCommand) -> Void
    public let onDismiss: () -> Void

    private static let menuWidth: CGFloat = 232
    private static let gap: CGFloat = 6

    public func body(content: Content) -> some View {
        content.overlay(alignment: .topLeading) {
            if let context {
                let commands = NoteSlashCommand.matching(context.query)
                if commands.isEmpty {
                    // Nothing matches, so the reader is typing prose that happens to begin
                    // with a slash. Showing an empty panel over their words would be worse
                    // than showing nothing.
                    Color.clear.frame(width: 0, height: 0)
                } else {
                    GeometryReader { geometry in
                        NoteSlashMenu(commands: commands, onPick: onPick)
                            .offset(
                                x: min(
                                    max(context.caretRect.minX, 0),
                                    max(geometry.size.width - Self.menuWidth, 0)
                                ),
                                y: context.caretRect.maxY + Self.gap
                            )
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                }
            }
        }
        .animation(DipleMotion.snappy, value: context)
        .onChange(of: context == nil) { _, isClosed in
            if isClosed { onDismiss() }
        }
    }
}

public extension View {
    /// Shows the slash menu over this editor while one is being typed.
    func noteSlashMenu(
        context: NoteSlashContext?,
        onPick: @escaping (NoteSlashCommand) -> Void,
        onDismiss: @escaping () -> Void = {}
    ) -> some View {
        modifier(NoteSlashMenuOverlay(context: context, onPick: onPick, onDismiss: onDismiss))
    }
}
