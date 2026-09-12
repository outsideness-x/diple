import SwiftUI
import UIKit

/// What each Markdown role wears in the editor.
///
/// Built once per Dynamic Type size and kept on the coordinator: these are a dozen `UIFont`
/// lookups and they must not happen per keystroke. The sizes come from the same `DipleType`
/// roles the rendered page uses, so a heading is the same heading before and after the eye —
/// the page changes its arrangement between the two, never its type.
struct NoteSyntaxStyling {
    let base: [NSAttributedString.Key: Any]
    let typeSize: DynamicTypeSize
    let script: ReaderScript

    private let bodyFont: UIFont
    private let titleFont: UIFont
    private let headingFont: UIFont
    private let monoFont: UIFont
    private let markerColor: UIColor
    private let quoteColor: UIColor
    private let linkColor: UIColor
    private let doneColor: UIColor
    private let quoteParagraph: NSParagraphStyle
    private let codeParagraph: NSParagraphStyle

    init(typeSize: DynamicTypeSize, script: ReaderScript) {
        self.typeSize = typeSize
        self.script = script

        let bodySize = DipleTextStyle.noteBody.scaledSize(for: typeSize)
        bodyFont = .systemFont(ofSize: bodySize, weight: .regular)
        titleFont = .systemFont(ofSize: DipleTextStyle.noteTitle.scaledSize(for: typeSize), weight: .semibold)
        headingFont = .systemFont(ofSize: DipleTextStyle.noteHeading.scaledSize(for: typeSize), weight: .semibold)
        // A shade under the prose, which is what keeps a line of code from standing taller than
        // the sentence around it: a monospaced face at the same nominal size always does.
        monoFont = .monospacedSystemFont(ofSize: bodySize * 0.94, weight: .regular)

        markerColor = UIColor(DipleColor.textQuaternary)
        quoteColor = UIColor(DipleColor.textSecondary)
        linkColor = UIColor(DipleColor.accentInk)
        doneColor = UIColor(DipleColor.textTertiary)

        let paragraph = NSMutableParagraphStyle()
        paragraph.lineSpacing = script.swiftUILineSpacing
        paragraph.paragraphSpacing = DipleSpace.xs

        // The rule down the side of a quote is drawn in the margin this indent opens; see
        // `NoteTextView`. Both halves have to agree, so the width lives in one place.
        let quote = NSMutableParagraphStyle()
        quote.setParagraphStyle(paragraph)
        quote.firstLineHeadIndent = NoteTextView.quoteIndent
        quote.headIndent = NoteTextView.quoteIndent
        quoteParagraph = quote

        let code = NSMutableParagraphStyle()
        code.setParagraphStyle(paragraph)
        code.lineSpacing = 2
        codeParagraph = code

        base = [
            .font: bodyFont,
            .foregroundColor: UIColor(DipleColor.textPrimary),
            .paragraphStyle: paragraph
        ]
    }

    /// Lays one span over the storage.
    ///
    /// Strength and emphasis *add* to whatever font is already there rather than naming one, so
    /// a bold word inside a heading stays a heading. Everything here is `addAttributes`: the
    /// caller has already cleared the lines being restyled to `base`.
    func apply(_ span: NoteSyntaxSpan, to storage: NSTextStorage) {
        let range = span.range
        guard range.location >= 0, range.location + range.length <= storage.length, range.length > 0 else { return }

        switch span.role {
        case .heading(let level):
            storage.addAttributes([.font: level <= 1 ? titleFont : headingFont], range: range)

        case .strong:
            addTrait(.traitBold, in: range, of: storage)

        case .emphasis:
            addTrait(.traitItalic, in: range, of: storage)

        case .code:
            storage.addAttributes([
                .font: monoFont,
                .foregroundColor: quoteColor,
                .paragraphStyle: codeParagraph
            ], range: range)

        case .quote:
            storage.addAttributes([
                .foregroundColor: quoteColor,
                .paragraphStyle: quoteParagraph,
                NoteTextView.quoteAttribute: true
            ], range: range)

        case .task(let isDone):
            storage.addAttributes([
                .font: monoFont,
                .foregroundColor: isDone ? linkColor : markerColor
            ], range: range)

        case .done:
            storage.addAttributes([
                .foregroundColor: doneColor,
                .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                .strikethroughColor: doneColor
            ], range: range)

        case .listMarker:
            storage.addAttributes([.foregroundColor: markerColor], range: range)

        case .link:
            storage.addAttributes([.foregroundColor: linkColor], range: range)

        case .marker:
            storage.addAttributes([.foregroundColor: markerColor], range: range)
        }
    }

    private func addTrait(_ trait: UIFontDescriptor.SymbolicTraits, in range: NSRange, of storage: NSTextStorage) {
        storage.enumerateAttribute(.font, in: range, options: []) { value, subrange, _ in
            let current = (value as? UIFont) ?? bodyFont
            var traits = current.fontDescriptor.symbolicTraits
            traits.insert(trait)
            guard let descriptor = current.fontDescriptor.withSymbolicTraits(traits) else { return }
            storage.addAttributes([.font: UIFont(descriptor: descriptor, size: current.pointSize)], range: subrange)
        }
    }
}

/// The editor's text view, which owes the page one thing TextKit will not draw: the rule down
/// the side of a quoted line.
///
/// A quote is indented by its paragraph style and the rule stands in the margin that opens. It
/// is the same 2pt accent capsule the rendered page sets beside a quote — without it an indented
/// line is only an indented line, and the mark of a quotation is the mark, not the gap.
///
/// The rules are thin subviews placed on layout, **not** a `draw(_:)` override. The editor never
/// scrolls on its own — SwiftUI's scroll view does — so this view is as tall as the whole note,
/// and drawing into it would give it a backing store the size of the note: hundreds of
/// megabytes for a long one, to paint a few 2pt lines. A view per quote block costs nothing, and
/// its dynamic colour follows light and dark without being asked.
final class NoteTextView: UITextView {
    static let quoteIndent: CGFloat = 16
    /// Marks the lines the styling set as quotes, so layout can find them without parsing again.
    static let quoteAttribute = NSAttributedString.Key("diple.noteQuote")

    private var rules: [UIView] = []

    /// A `[[wiki link]]` was tapped; the title inside the brackets.
    var onOpenLink: ((String) -> Void)?
    /// A task's box was ticked or unticked in place.
    var onTaskToggled: (() -> Void)?

    /// Off for the formula source, which is LaTeX and has no boxes or links to press.
    var answersMarkdownTaps = true

    private lazy var actionTap: UITapGestureRecognizer = {
        let tap = UITapGestureRecognizer(target: self, action: #selector(performAction(_:)))
        tap.delegate = tapGate
        return tap
    }()
    private lazy var tapGate = TapGate(view: self)

    /// Lets the box-and-link tap see a touch **only** when it lands on a box or a link.
    ///
    /// Failing in `gestureRecognizerShouldBegin` is not enough, and this was measured: a tap
    /// recognizer merely present on the text view — even one that fails on every touch — stopped
    /// an ordinary tap from placing the caret in a note with text in it. A recognizer that never
    /// receives the touch is not in that competition at all. Its own object, because the text
    /// view is already the delegate of its scroll recognizers.
    private final class TapGate: NSObject, UIGestureRecognizerDelegate {
        weak var view: NoteTextView?

        init(view: NoteTextView) {
            self.view = view
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldReceive touch: UITouch) -> Bool {
            guard let view else { return false }
            return view.action(at: touch.location(in: view)) != nil
        }
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        addGestureRecognizer(actionTap)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        addGestureRecognizer(actionTap)
    }

    // MARK: - Boxes and links that answer a tap

    fileprivate enum Action {
        /// The one character between a box's brackets.
        case toggle(NSRange)
        case open(String)
    }

    /// Whether a tap here lands on a task's box or on a wiki link, found by character rather than
    /// by `UITextView`'s own link handling: in editable text a link answers only a long press, and
    /// a box is not a link at all.
    ///
    /// The line comes first — the caret position nearest the finger — and only that line's
    /// spans are read, so two boxes on neighbouring lines can never both claim one tap. Within the
    /// line the box's target reaches back over its bullet and out to 44 pt: the `[ ]` alone is
    /// narrower than a fingertip.
    fileprivate func action(at point: CGPoint) -> Action? {
        guard answersMarkdownTaps, textStorage.length > 0, markedTextRange == nil,
              let position = closestPosition(to: point)
        else { return nil }
        let text = textStorage.mutableString as NSString
        let offset = min(self.offset(from: beginningOfDocument, to: position), text.length)
        let line = text.lineRange(for: NSRange(location: offset, length: 0))
        let spans = NoteSyntax.spans(in: text, restyling: line)

        for span in spans {
            switch span.role {
            case .task:
                let bullet = spans.first {
                    $0.role == .listMarker && $0.range.location + $0.range.length == span.range.location
                }
                let start = bullet?.range.location ?? span.range.location
                let area = NSRange(location: start, length: span.range.location + span.range.length - start)
                if contains(point, in: area, reach: 44) {
                    return .toggle(NSRange(location: span.range.location + 1, length: 1))
                }

            case .link:
                guard span.range.location >= 2,
                      text.substring(with: NSRange(location: span.range.location - 2, length: 2)) == "[["
                else { continue }
                let area = NSRange(location: span.range.location - 2, length: span.range.length + 4)
                if contains(point, in: area, reach: 0) {
                    let title = text.substring(with: span.range).trimmingCharacters(in: .whitespaces)
                    return title.isEmpty ? nil : .open(title)
                }

            default:
                continue
            }
        }
        return nil
    }

    private func contains(_ point: CGPoint, in range: NSRange, reach: CGFloat) -> Bool {
        guard let start = position(from: beginningOfDocument, offset: range.location),
              let end = position(from: start, offset: range.length),
              let textRange = textRange(from: start, to: end)
        else { return false }
        return selectionRects(for: textRange).contains { selection in
            let rect = selection.rect
            guard !rect.isNull, rect.width > 0 else { return false }
            let grow = CGSize(width: max(0, reach - rect.width) / 2, height: max(0, reach - rect.height) / 2)
            return rect.insetBy(dx: -grow.width, dy: -grow.height).contains(point)
        }
    }

    /// A tap on a box or a link belongs to the box or the link. The text view's own taps would
    /// also put the caret there and raise the keyboard — ticking a box on a page being read is
    /// not a request to start typing on it.
    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        if gestureRecognizer !== actionTap,
           gestureRecognizer is UITapGestureRecognizer,
           action(at: gestureRecognizer.location(in: self)) != nil {
            return false
        }
        return super.gestureRecognizerShouldBegin(gestureRecognizer)
    }

    @objc private func performAction(_ tap: UITapGestureRecognizer) {
        guard tap.state == .ended, let action = action(at: tap.location(in: self)) else { return }
        switch action {
        case .toggle(let mark):
            toggleTask(at: mark)
        case .open(let title):
            onOpenLink?(title)
        }
    }

    /// Rewrites the one character inside the brackets, through the text view's own editing path:
    /// the undo stack keeps it, the delegate hears it like any keystroke — so the line restyles
    /// and the note publishes — and the caret stays where the writer left it.
    private func toggleTask(at mark: NSRange) {
        let text = textStorage.mutableString as NSString
        guard mark.location + mark.length <= text.length,
              let start = position(from: beginningOfDocument, offset: mark.location),
              let end = position(from: start, offset: mark.length),
              let range = textRange(from: start, to: end)
        else { return }

        let isDone = text.substring(with: mark).lowercased() == "x"
        let caret = selectedRange
        replace(range, withText: isDone ? " " : "x")
        if selectedRange != caret {
            selectedRange = caret
        }
        onTaskToggled?()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        placeQuoteRules()
    }

    private func placeQuoteRules() {
        var blocks: [CGRect] = []

        if textStorage.length > 0,
           let layoutManager = textLayoutManager,
           let contentManager = layoutManager.textContentManager {
            let documentStart = contentManager.documentRange.location
            let whole = NSRange(location: 0, length: textStorage.length)
            var segments: [CGRect] = []

            textStorage.enumerateAttribute(Self.quoteAttribute, in: whole, options: []) { value, range, _ in
                guard value != nil, range.length > 0,
                      let start = contentManager.location(documentStart, offsetBy: range.location),
                      let end = contentManager.location(start, offsetBy: range.length),
                      let textRange = NSTextRange(location: start, end: end)
                else { return }
                layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
                    segments.append(frame)
                    return true
                }
            }

            // Consecutive quoted lines are one quotation and get one rule, as on the rendered
            // page; a blank line between two quotes keeps them two. The reach is the air between
            // two lines of one paragraph style — line spacing plus paragraph spacing, 12 pt for
            // Latin and 16 for Hangul — and never a whole empty line, which is 30 and more.
            let reach = DipleSpace.l + DipleSpace.xs
            for frame in segments.sorted(by: { $0.minY < $1.minY }) {
                if let last = blocks.last, frame.minY <= last.maxY + reach {
                    blocks[blocks.count - 1] = CGRect(
                        x: last.minX, y: last.minY,
                        width: last.width, height: max(last.maxY, frame.maxY) - last.minY
                    )
                } else {
                    blocks.append(frame)
                }
            }
        }

        while rules.count < blocks.count {
            let rule = UIView()
            rule.backgroundColor = UIColor(DipleColor.accent).withAlphaComponent(0.5)
            rule.layer.cornerRadius = 1
            rule.isUserInteractionEnabled = false
            rule.isAccessibilityElement = false
            addSubview(rule)
            rules.append(rule)
        }

        for (index, rule) in rules.enumerated() {
            guard index < blocks.count else {
                rule.isHidden = true
                continue
            }
            let block = blocks[index]
            rule.isHidden = false
            rule.frame = CGRect(
                x: textContainerInset.left,
                y: textContainerInset.top + block.minY + 2,
                width: 2,
                height: max(0, block.height - 4)
            )
        }
    }
}
