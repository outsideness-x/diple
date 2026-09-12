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

    public init(commands: [NoteSlashCommand], onPick: @escaping (NoteSlashCommand) -> Void) {
        self.commands = commands
        self.onPick = onPick
    }

    public var body: some View {
        NoteInlineMenu(
            rows: commands.map { NoteInlineMenuRow(id: $0.id, title: $0.title, systemImage: $0.systemImage) },
            accessibilityLabel: "Insert a block"
        ) { row in
            if let command = commands.first(where: { $0.id == row.id }) {
                onPick(command)
            }
        }
    }
}

/// One row of a menu that opens at the caret.
public struct NoteInlineMenuRow: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let systemImage: String

    public init(id: String, title: String, systemImage: String) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
    }
}

/// The panel every caret menu is drawn in — `/` commands, `[[` notes, `#` tags.
///
/// One panel, because three menus at one caret that differ in width, row height or corner would
/// read as three different kinds of thing when they are one: a completion of what is being typed.
public struct NoteInlineMenu: View {
    public let rows: [NoteInlineMenuRow]
    public let accessibilityLabel: String
    public let onPick: (NoteInlineMenuRow) -> Void

    /// Enough rows to be worth opening, few enough that the menu never becomes the page.
    private static let visibleRows = 5
    private static let rowHeight: CGFloat = 38
    static let width: CGFloat = 232

    /// Sized to what it holds, capped at `visibleRows`.
    ///
    /// A `ScrollView` takes every point it is offered, so a fixed max height left a panel of
    /// empty space under a single result — the menu looked broken exactly when the reader had
    /// narrowed it down to the one row they wanted.
    private var height: CGFloat {
        let count = min(CGFloat(rows.count), CGFloat(Self.visibleRows))
        return count * Self.rowHeight + DipleSpace.s
    }

    public init(
        rows: [NoteInlineMenuRow],
        accessibilityLabel: String,
        onPick: @escaping (NoteInlineMenuRow) -> Void
    ) {
        self.rows = rows
        self.accessibilityLabel = accessibilityLabel
        self.onPick = onPick
    }

    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(rows) { row in
                    Button {
                        HapticManager.shared.selection()
                        onPick(row)
                    } label: {
                        HStack(spacing: DipleSpace.m) {
                            Image(systemName: row.systemImage)
                                .dipleIcon(13, weight: .medium)
                                .foregroundStyle(DipleColor.accentInk)
                                .frame(width: 22)
                            Text(row.title)
                                .dipleType(.callout)
                                .foregroundStyle(DipleColor.textPrimary)
                                .lineLimit(1)
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
        .frame(width: Self.width, height: height)
        .background(DipleColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DipleRadius.m, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DipleRadius.m, style: .continuous)
                .stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline)
        )
        .shadow(color: Color.black.opacity(0.3), radius: 18, y: 8)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
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
                                    max(geometry.size.width - NoteInlineMenu.width, 0)
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

/// The `[[` and `#` menu, placed at the caret exactly as the slash menu is.
///
/// What it offers comes from `NoteCompletion`; what choosing does belongs to the page, because a
/// tag is also a property of the note, which only the page holds.
public struct NoteCompletionMenuOverlay: ViewModifier {
    public let context: NoteCompletionContext?
    public let linkTitles: [String]
    public let tagVocabulary: [String]
    public let onPickLink: (NoteCompletion.LinkPick, NoteCompletionContext) -> Void
    public let onPickTag: (NoteCompletion.TagPick, NoteCompletionContext) -> Void

    private static let gap: CGFloat = 6

    public func body(content: Content) -> some View {
        content.overlay(alignment: .topLeading) {
            if let context {
                let rows = rows(for: context)
                if !rows.isEmpty {
                    GeometryReader { geometry in
                        NoteInlineMenu(
                            rows: rows,
                            accessibilityLabel: context.kind == .link ? "Link a note" : "Add a tag"
                        ) { row in
                            pick(row, in: context)
                        }
                        .offset(
                            x: min(
                                max(context.caretRect.minX, 0),
                                max(geometry.size.width - NoteInlineMenu.width, 0)
                            ),
                            y: context.caretRect.maxY + Self.gap
                        )
                    }
                    .transition(.opacity.combined(with: .scale(scale: 0.98, anchor: .topLeading)))
                }
            }
        }
        .animation(DipleMotion.snappy, value: context)
    }

    private func rows(for context: NoteCompletionContext) -> [NoteInlineMenuRow] {
        switch context.kind {
        case .link:
            return NoteCompletion.links(matching: context.query, in: linkTitles).map { pick in
                switch pick {
                case .note(let title):
                    return NoteInlineMenuRow(id: "note:" + title, title: title, systemImage: "note.text")
                case .unwritten(let title):
                    return NoteInlineMenuRow(id: "unwritten:" + title, title: "Link \u{201C}\(title)\u{201D}", systemImage: "link")
                }
            }
        case .tag:
            return NoteCompletion.tags(matching: context.query, in: tagVocabulary).map { pick in
                switch pick {
                case .existing(let tag):
                    return NoteInlineMenuRow(id: "tag:" + tag, title: "#" + tag, systemImage: "number")
                case .new(let tag):
                    return NoteInlineMenuRow(id: "new:" + tag, title: "Add #" + tag, systemImage: "plus")
                }
            }
        }
    }

    private func pick(_ row: NoteInlineMenuRow, in context: NoteCompletionContext) {
        switch context.kind {
        case .link:
            guard let pick = NoteCompletion.links(matching: context.query, in: linkTitles)
                .first(where: { row.id == "note:" + $0.title || row.id == "unwritten:" + $0.title })
            else { return }
            onPickLink(pick, context)
        case .tag:
            guard let pick = NoteCompletion.tags(matching: context.query, in: tagVocabulary)
                .first(where: { row.id == "tag:" + $0.tag || row.id == "new:" + $0.tag })
            else { return }
            onPickTag(pick, context)
        }
    }
}

public extension View {
    /// Shows the `[[` / `#` completion over this editor while one is being typed.
    func noteCompletionMenu(
        context: NoteCompletionContext?,
        linkTitles: [String],
        tagVocabulary: [String],
        onPickLink: @escaping (NoteCompletion.LinkPick, NoteCompletionContext) -> Void,
        onPickTag: @escaping (NoteCompletion.TagPick, NoteCompletionContext) -> Void
    ) -> some View {
        modifier(NoteCompletionMenuOverlay(
            context: context,
            linkTitles: linkTitles,
            tagVocabulary: tagVocabulary,
            onPickLink: onPickLink,
            onPickTag: onPickTag
        ))
    }
}
