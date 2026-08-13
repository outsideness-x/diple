import SwiftUI
import UIKit

/// Where the caret is, held outside SwiftUI's state.
///
/// The selection used to be a `@Binding NSRange`, and the caret moves on **every** keystroke.
/// Each move wrote SwiftUI state, so a single character invalidated the note twice — once for
/// the text and once for the caret — and each invalidation re-measured the entire note through
/// `sizeThatFits`, which is a full TextKit layout pass. That is the typing lag.
///
/// Nothing on screen renders from the caret: it exists only so the formatting bar can wrap the
/// words the writer actually selected, and the bar reads it at the moment a button is tapped.
/// A reference type carries it with no invalidation at all. `pending` is the other direction —
/// a caret position set by code rather than by the user, which the text view adopts on the next
/// update and then forgets.
public final class NoteSelectionBox {
    public var range: NSRange
    fileprivate var pending: NSRange?

    public init(range: NSRange = NSRange(location: 0, length: 0)) {
        self.range = range
    }

    /// Moves the caret from code. Editing commands use this after rewriting the text.
    public func move(to range: NSRange) {
        self.range = range
        pending = range
    }
}

/// A slash command being typed: what has been entered after the `/`, where the whole thing
/// sits in the text, and where the caret is so a menu can be put beside it.
public struct NoteSlashContext: Equatable {
    /// What follows the slash. Empty right after typing `/`, which is when the full list shows.
    public let query: String
    /// The `/query` itself, replaced wholesale when a command is chosen.
    public let range: NSRange
    /// Caret position in the text view's own coordinate space, so an overlay on the editor can
    /// place a menu without converting between spaces.
    public let caretRect: CGRect
}

/// One entry in the slash menu.
///
/// Deliberately expressed as the same prefix/suffix pair the formatting bar already uses, so a
/// command means exactly what the corresponding button means. Two lists of "what a heading is"
/// would drift the first time one of them was tuned.
public struct NoteSlashCommand: Identifiable, Equatable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let prefix: String
    public let suffix: String
    public let placeholder: String
    public let isLineCommand: Bool
    /// Extra words a reader might type to find this. "todo" should reach the task command even
    /// though the command is called Task.
    let keywords: [String]

    public static let all: [NoteSlashCommand] = [
        .init(id: "h1", title: "Heading", systemImage: "textformat.size.larger",
              prefix: "# ", suffix: "", placeholder: "Heading", isLineCommand: true,
              keywords: ["h1", "title"]),
        .init(id: "h2", title: "Subheading", systemImage: "textformat.size",
              prefix: "## ", suffix: "", placeholder: "Subheading", isLineCommand: true,
              keywords: ["h2"]),
        .init(id: "task", title: "Task", systemImage: "checklist",
              prefix: "- [ ] ", suffix: "", placeholder: "Task", isLineCommand: true,
              keywords: ["todo", "checkbox", "check"]),
        .init(id: "bullet", title: "Bulleted list", systemImage: "list.bullet",
              prefix: "- ", suffix: "", placeholder: "List item", isLineCommand: true,
              keywords: ["ul", "list"]),
        .init(id: "number", title: "Numbered list", systemImage: "list.number",
              prefix: "1. ", suffix: "", placeholder: "List item", isLineCommand: true,
              keywords: ["ol", "ordered"]),
        .init(id: "quote", title: "Quote", systemImage: "text.quote",
              prefix: "> ", suffix: "", placeholder: "Quote", isLineCommand: true,
              keywords: ["blockquote"]),
        .init(id: "callout", title: "Callout", systemImage: "sparkles",
              prefix: "> [!NOTE] ", suffix: "", placeholder: "Note", isLineCommand: true,
              keywords: ["note", "aside"]),
        .init(id: "divider", title: "Divider", systemImage: "minus",
              prefix: "---\n", suffix: "", placeholder: "", isLineCommand: true,
              keywords: ["hr", "rule", "separator"]),
        .init(id: "code", title: "Code", systemImage: "chevron.left.forwardslash.chevron.right",
              prefix: "`", suffix: "`", placeholder: "code", isLineCommand: false,
              keywords: ["monospace"]),
        .init(id: "bold", title: "Bold", systemImage: "bold",
              prefix: "**", suffix: "**", placeholder: "bold text", isLineCommand: false,
              keywords: ["strong"]),
        .init(id: "link", title: "Link", systemImage: "link",
              prefix: "[", suffix: "](https://)", placeholder: "link title", isLineCommand: false,
              keywords: ["url", "href"])
    ]

    /// Matches on the visible title first and the aliases second, both as prefixes rather than
    /// as "contains": a menu that reorders itself around a substring buried mid-word feels
    /// arbitrary, and typing is meant to narrow, not to shuffle.
    public static func matching(_ query: String) -> [NoteSlashCommand] {
        let needle = query.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
        guard !needle.isEmpty else { return all }
        return all.filter { command in
            let title = command.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            return title.hasPrefix(needle) || command.keywords.contains { $0.hasPrefix(needle) }
        }
    }
}

/// A selection-aware Markdown editor. SwiftUI's `TextEditor` does not expose its selection,
/// which turns formatting controls into append-at-the-end buttons. Keeping the tiny UIKit
/// bridge here lets bold, links and callouts wrap exactly what the writer selected.
public struct NoteEditorView: UIViewRepresentable {
    @Binding public var text: String
    public let selection: NoteSelectionBox
    @Binding public var isFocused: Bool
    public let minimumHeight: CGFloat
    public let usesMonospacedFont: Bool
    public let editorAccessibilityLabel: String
    public let editorAccessibilityIdentifier: String
    /// Reports a slash command being typed, and `nil` the moment it stops being one.
    ///
    /// A callback rather than another binding: this is nil almost always, and publishing it
    /// only when it actually changes keeps the editor's per-keystroke cost where the rest of
    /// this file worked to put it — see `NoteSelectionBox`.
    public let onSlashChanged: ((NoteSlashContext?) -> Void)?

    public init(
        text: Binding<String>,
        selection: NoteSelectionBox,
        isFocused: Binding<Bool>,
        minimumHeight: CGFloat = 280,
        usesMonospacedFont: Bool = false,
        accessibilityLabel: String = "Note body",
        accessibilityIdentifier: String = "note.body",
        onSlashChanged: ((NoteSlashContext?) -> Void)? = nil
    ) {
        _text = text
        self.selection = selection
        _isFocused = isFocused
        self.minimumHeight = minimumHeight
        self.usesMonospacedFont = usesMonospacedFont
        self.editorAccessibilityLabel = accessibilityLabel
        self.editorAccessibilityIdentifier = accessibilityIdentifier
        self.onSlashChanged = onSlashChanged
    }

    public func makeCoordinator() -> Coordinator { Coordinator(parent: self) }

    public func makeUIView(context: Context) -> UITextView {
        let view = UITextView()
        view.delegate = context.coordinator
        view.backgroundColor = .clear
        view.textColor = UIColor(DipleColor.textPrimary)
        view.tintColor = UIColor(DipleColor.accent)
        let baseFont = usesMonospacedFont
            ? UIFont.monospacedSystemFont(ofSize: 16, weight: .regular)
            : UIFont.systemFont(ofSize: 17, weight: .regular)
        view.font = UIFontMetrics(forTextStyle: .body).scaledFont(for: baseFont)
        view.adjustsFontForContentSizeCategory = true
        view.isScrollEnabled = false
        view.textContainerInset = .zero
        view.textContainer.lineFragmentPadding = 0
        view.keyboardDismissMode = .interactive
        view.smartDashesType = .no
        view.smartQuotesType = .no
        view.autocorrectionType = usesMonospacedFont ? .no : .default
        view.spellCheckingType = usesMonospacedFont ? .no : .default
        view.accessibilityLabel = editorAccessibilityLabel
        view.accessibilityIdentifier = editorAccessibilityIdentifier
        return view
    }

    public func updateUIView(_ view: UITextView, context: Context) {
        context.coordinator.parent = self

        // Multi-stage input — Hangul jamo composing into a syllable, or any marked text from
        // a candidate keyboard — lives in the text view until it is committed. Writing `text`
        // or the selection back mid-composition tears it down and drops what was being typed.
        guard view.markedTextRange == nil else { return }

        if view.text != text {
            view.text = text
            // Assigning `text` collapses the caret; without a pending position of our own it
            // belongs at the end of what was just written, not back at zero.
            if selection.pending == nil {
                selection.pending = NSRange(location: (text as NSString).length, length: 0)
            }
        }

        if let pending = selection.pending {
            let length = (view.text as NSString).length
            let location = min(pending.location, length)
            let safe = NSRange(location: location, length: min(pending.length, length - location))
            if view.selectedRange != safe {
                view.selectedRange = safe
            }
            selection.range = safe
            selection.pending = nil
        }

        if isFocused && !view.isFirstResponder {
            view.becomeFirstResponder()
        } else if !isFocused && view.isFirstResponder {
            view.resignFirstResponder()
        }
    }

    /// Measuring a text view is a full layout of every line it holds, and SwiftUI asks for the
    /// size far more often than the text changes. The answer is cached against the only two
    /// inputs that can change it.
    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let cache = context.coordinator
        if cache.measuredWidth == width, cache.measuredText == uiView.text, let height = cache.measuredHeight {
            return CGSize(width: width, height: height)
        }
        let measured = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        let height = max(measured.height, minimumHeight)
        cache.measuredWidth = width
        cache.measuredText = uiView.text
        cache.measuredHeight = height
        return CGSize(width: width, height: height)
    }

    public final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoteEditorView

        var measuredWidth: CGFloat?
        var measuredText: String?
        var measuredHeight: CGFloat?
        var lastSlashContext: NoteSlashContext?

        init(parent: NoteEditorView) {
            self.parent = parent
        }

        /// Carries a list on to the next line, and ends it on an empty one.
        ///
        /// This editor shows Markdown as written, so typing `- ` already produces a bullet and
        /// needs no transform. What it lacked is the other half of the rule every Markdown
        /// editor has: pressing Return inside a list should start the next item, and pressing
        /// it on an item with nothing in it should end the list rather than adding another
        /// empty marker to delete by hand. Without it a checklist is typed by retyping `- [ ] `
        /// eleven times.
        public func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard text == "\n", textView.markedTextRange == nil else { return true }

            let source = textView.text as NSString
            let line = source.lineRange(for: NSRange(location: range.location, length: 0))
            let content = source.substring(with: line)
            guard let marker = NoteListMarker(line: content) else { return true }

            // An item with nothing after its marker is the writer saying "done". The marker is
            // cleared instead of being duplicated onto a new line.
            if marker.isEmptyItem {
                let toClear = NSRange(location: line.location, length: marker.prefixLength)
                if let range = textView.textRange(for: toClear) {
                    textView.replace(range, withText: "")
                }
                return false
            }

            textView.insertText("\n" + marker.nextPrefix)
            return false
        }

        public func textViewDidChange(_ textView: UITextView) {
            // Still composing: the text view holds provisional glyphs that are not yet the
            // note's text, and publishing them starts an edit SwiftUI would try to write back.
            guard textView.markedTextRange == nil else { return }
            parent.selection.range = textView.selectedRange
            parent.text = textView.text
            publishSlashContext(in: textView)
        }

        public func textViewDidChangeSelection(_ textView: UITextView) {
            // Deliberately does not touch SwiftUI state — see `NoteSelectionBox`.
            parent.selection.range = textView.selectedRange
            // Moving the caret away from a half-typed command has to close the menu, so this
            // runs here too — but only publishes on an actual change, so an ordinary caret
            // move still costs nothing.
            publishSlashContext(in: textView)
        }

        private func publishSlashContext(in textView: UITextView) {
            guard let onSlashChanged = parent.onSlashChanged else { return }
            let context = Self.slashContext(in: textView)
            guard context != lastSlashContext else { return }
            lastSlashContext = context
            onSlashChanged(context)
        }

        /// Finds a `/command` being typed immediately before the caret.
        ///
        /// The slash has to open a word — at the start of a line or after a space — so a URL
        /// or a date typed mid-sentence never opens a menu. Anything with a space in it has
        /// stopped being a command and become prose.
        static func slashContext(in textView: UITextView) -> NoteSlashContext? {
            let source = textView.text as NSString
            let caret = textView.selectedRange
            guard caret.length == 0, caret.location <= source.length else { return nil }

            let line = source.lineRange(for: NSRange(location: caret.location, length: 0))
            var index = caret.location - 1
            while index >= line.location {
                let character = source.character(at: index)
                if character == 47 { // "/"
                    let opensWord = index == line.location
                        || source.character(at: index - 1) == 32
                        || source.character(at: index - 1) == 10
                    guard opensWord else { return nil }
                    let range = NSRange(location: index, length: caret.location - index)
                    guard let start = textView.selectedTextRange?.start else { return nil }
                    return NoteSlashContext(
                        query: source.substring(with: NSRange(
                            location: index + 1,
                            length: caret.location - index - 1
                        )),
                        range: range,
                        caretRect: textView.caretRect(for: start)
                    )
                }
                // A space or newline before any slash means the caret is in ordinary prose.
                if character == 32 || character == 10 { return nil }
                index -= 1
            }
            return nil
        }

        public func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        public func textViewDidEndEditing(_ textView: UITextView) {
            // Composition is committed when editing ends; publish whatever it produced.
            if parent.text != textView.text {
                parent.text = textView.text
            }
            parent.isFocused = false
        }
    }
}

/// The list marker a line begins with, and what the next line's should be.
///
/// Kept as a value type rather than a pile of string checks in the delegate so the rules are
/// testable on their own and read as one table.
struct NoteListMarker {
    /// Leading whitespace, preserved so a nested item stays nested.
    let indentation: String
    /// What to repeat on the next line — the same bullet, or the next number.
    let nextPrefix: String
    /// How many characters the marker occupies, indentation included.
    let prefixLength: Int
    /// Nothing follows the marker on this line.
    let isEmptyItem: Bool

    init?(line: String) {
        let withoutNewline = line.hasSuffix("\n") ? String(line.dropLast()) : line
        let indentation = String(withoutNewline.prefix { $0 == " " || $0 == "\t" })
        let body = withoutNewline.dropFirst(indentation.count)

        // A task is checked before a plain bullet: "- [ ] x" also starts with "- ", and
        // matching that first would carry the item on as an ordinary bullet.
        for prefix in ["- [ ] ", "- [x] ", "- [X] ", "* [ ] ", "* [x] "] where body.hasPrefix(prefix) {
            // A finished item continues as a fresh, unfinished one — carrying "[x]" forward
            // would mark work as done before it was written down.
            let carried = String(prefix.prefix(2)) + "[ ] "
            self.init(
                indentation: indentation,
                nextPrefix: indentation + carried,
                prefixLength: indentation.count + prefix.count,
                isEmptyItem: body.count == prefix.count
            )
            return
        }

        for prefix in ["- ", "* ", "+ ", "> "] where body.hasPrefix(prefix) {
            self.init(
                indentation: indentation,
                nextPrefix: indentation + prefix,
                prefixLength: indentation.count + prefix.count,
                isEmptyItem: body.count == prefix.count
            )
            return
        }

        let digits = body.prefix { $0.isNumber }
        if !digits.isEmpty, let number = Int(digits) {
            let rest = body.dropFirst(digits.count)
            for separator in [". ", ") "] where rest.hasPrefix(separator) {
                let prefixLength = digits.count + separator.count
                self.init(
                    indentation: indentation,
                    nextPrefix: indentation + "\(number + 1)\(separator)",
                    prefixLength: indentation.count + prefixLength,
                    isEmptyItem: body.count == prefixLength
                )
                return
            }
        }

        return nil
    }

    private init(indentation: String, nextPrefix: String, prefixLength: Int, isEmptyItem: Bool) {
        self.indentation = indentation
        self.nextPrefix = nextPrefix
        self.prefixLength = prefixLength
        self.isEmptyItem = isEmptyItem
    }
}

private extension UITextView {
    /// `UITextView` edits through `UITextRange`, but everything else here speaks `NSRange`.
    /// Going through the text view's own conversion keeps the undo stack intact, which
    /// rewriting `text` directly would flatten.
    func textRange(for range: NSRange) -> UITextRange? {
        guard let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length)
        else { return nil }
        return textRange(from: start, to: end)
    }
}

public enum NoteEditing {
    /// Runs a slash command: removes the `/query` that summoned it, then applies the command
    /// exactly as the matching formatting-bar button would.
    ///
    /// The two steps are separate on purpose. Deleting the trigger first means the command
    /// operates on a line that no longer contains it, so a line command like `# ` measures the
    /// real line rather than one with a stray `/heading` still in it.
    public static func applySlash(
        _ command: NoteSlashCommand,
        replacing range: NSRange,
        in text: inout String,
        selection: NoteSelectionBox
    ) {
        let source = text as NSString
        guard range.location >= 0, range.location + range.length <= source.length else { return }
        text = source.replacingCharacters(in: range, with: "")
        selection.range = NSRange(location: range.location, length: 0)

        apply(
            to: &text,
            selection: selection,
            prefix: command.prefix,
            suffix: command.suffix,
            placeholder: command.placeholder,
            isLineCommand: command.isLineCommand
        )
    }

    /// Runs an editing command against the caret the editor is actually holding, and hands the
    /// resulting caret position back for the text view to adopt.
    public static func apply(
        to text: inout String,
        selection: NoteSelectionBox,
        prefix: String,
        suffix: String = "",
        placeholder: String,
        isLineCommand: Bool = false
    ) {
        var range = selection.range
        apply(
            to: &text,
            selection: &range,
            prefix: prefix,
            suffix: suffix,
            placeholder: placeholder,
            isLineCommand: isLineCommand
        )
        selection.move(to: range)
    }

    public static func insertFormula(
        _ latex: String,
        mode: NoteFormulaMode,
        in text: inout String,
        selection: NoteSelectionBox
    ) {
        var range = selection.range
        insertFormula(latex, mode: mode, in: &text, selection: &range)
        selection.move(to: range)
    }

    /// Wraps the selection or inserts a useful placeholder, then selects the meaningful part
    /// so the next keystroke replaces it. Line commands operate on the whole current line.
    public static func apply(
        to text: inout String,
        selection: inout NSRange,
        prefix: String,
        suffix: String = "",
        placeholder: String,
        isLineCommand: Bool = false
    ) {
        let source = text as NSString
        let safeLocation = min(selection.location, source.length)
        let safeLength = min(selection.length, source.length - safeLocation)
        var target = NSRange(location: safeLocation, length: safeLength)

        if isLineCommand {
            target = source.lineRange(for: target)
            if target.length > 0, source.substring(with: target).hasSuffix("\n") {
                target.length -= 1
            }
        }

        let selected = target.length == 0 ? placeholder : source.substring(with: target)
        let replacement = prefix + selected + suffix
        text = source.replacingCharacters(in: target, with: replacement)
        selection = NSRange(location: target.location + prefix.utf16.count, length: selected.utf16.count)
    }

    /// Replaces exactly the current selection and optionally keeps a meaningful range inside
    /// the inserted source selected. Formula composition uses this to return from its preview
    /// without losing the user's insertion point in the main note editor.
    public static func replaceSelection(
        in text: inout String,
        selection: inout NSRange,
        with replacement: String,
        selecting selectedRangeInReplacement: NSRange? = nil
    ) {
        let source = text as NSString
        let safeLocation = min(selection.location, source.length)
        let safeLength = min(selection.length, source.length - safeLocation)
        let target = NSRange(location: safeLocation, length: safeLength)
        text = source.replacingCharacters(in: target, with: replacement)

        if let selectedRangeInReplacement {
            let replacementLength = replacement.utf16.count
            let location = min(selectedRangeInReplacement.location, replacementLength)
            let length = min(selectedRangeInReplacement.length, replacementLength - location)
            selection = NSRange(location: target.location + location, length: length)
        } else {
            selection = NSRange(location: target.location + replacement.utf16.count, length: 0)
        }
    }

    public static func insertFormula(
        _ latex: String,
        mode: NoteFormulaMode,
        in text: inout String,
        selection: inout NSRange
    ) {
        let source = text as NSString
        let safeLocation = min(selection.location, source.length)
        let safeLength = min(selection.length, source.length - safeLocation)
        let targetEnd = safeLocation + safeLength

        let leadingBreak = mode == .block && safeLocation > 0 && source.character(at: safeLocation - 1) != 10
            ? "\n\n"
            : ""
        let trailingBreak = mode == .block && targetEnd < source.length && source.character(at: targetEnd) != 10
            ? "\n\n"
            : ""
        let markdown = mode.markdown(for: latex)
        let replacement = leadingBreak + markdown + trailingBreak
        let delimiterLength = mode == .inline ? 1 : 3
        let formulaRange = NSRange(
            location: leadingBreak.utf16.count + delimiterLength,
            length: latex.utf16.count
        )
        replaceSelection(
            in: &text,
            selection: &selection,
            with: replacement,
            selecting: formulaRange
        )
    }
}
