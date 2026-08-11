import SwiftUI
import UIKit

/// A selection-aware Markdown editor. SwiftUI's `TextEditor` does not expose its selection,
/// which turns formatting controls into append-at-the-end buttons. Keeping the tiny UIKit
/// bridge here lets bold, links and callouts wrap exactly what the writer selected.
public struct NoteEditorView: UIViewRepresentable {
    @Binding public var text: String
    @Binding public var selection: NSRange
    @Binding public var isFocused: Bool
    public let minimumHeight: CGFloat
    public let usesMonospacedFont: Bool
    public let editorAccessibilityLabel: String
    public let editorAccessibilityIdentifier: String

    public init(
        text: Binding<String>,
        selection: Binding<NSRange>,
        isFocused: Binding<Bool>,
        minimumHeight: CGFloat = 280,
        usesMonospacedFont: Bool = false,
        accessibilityLabel: String = "Note body",
        accessibilityIdentifier: String = "note.body"
    ) {
        _text = text
        _selection = selection
        _isFocused = isFocused
        self.minimumHeight = minimumHeight
        self.usesMonospacedFont = usesMonospacedFont
        self.editorAccessibilityLabel = accessibilityLabel
        self.editorAccessibilityIdentifier = accessibilityIdentifier
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
        if view.text != text {
            view.text = text
        }
        let safeLocation = min(selection.location, (text as NSString).length)
        let safeLength = min(selection.length, (text as NSString).length - safeLocation)
        let safeSelection = NSRange(location: safeLocation, length: safeLength)
        if view.selectedRange != safeSelection {
            view.selectedRange = safeSelection
        }
        if isFocused && !view.isFirstResponder {
            view.becomeFirstResponder()
        } else if !isFocused && view.isFirstResponder {
            view.resignFirstResponder()
        }
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, uiView: UITextView, context: Context) -> CGSize? {
        guard let width = proposal.width else { return nil }
        let measured = uiView.sizeThatFits(CGSize(width: width, height: .greatestFiniteMagnitude))
        return CGSize(width: width, height: max(measured.height, minimumHeight))
    }

    public final class Coordinator: NSObject, UITextViewDelegate {
        var parent: NoteEditorView

        init(parent: NoteEditorView) {
            self.parent = parent
        }

        public func textViewDidChange(_ textView: UITextView) {
            parent.text = textView.text
        }

        public func textViewDidChangeSelection(_ textView: UITextView) {
            parent.selection = textView.selectedRange
        }

        public func textViewDidBeginEditing(_ textView: UITextView) {
            parent.isFocused = true
        }

        public func textViewDidEndEditing(_ textView: UITextView) {
            parent.isFocused = false
        }
    }
}

public enum NoteEditing {
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
