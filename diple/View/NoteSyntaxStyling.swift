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
    private let bodySize: CGFloat
    /// What a set formula's source is drawn in: nothing that can be seen, and next to no width, so
    /// the room the formula takes is exactly the room its kern asks for.
    private let hiddenFont = UIFont.systemFont(ofSize: 1)

    init(typeSize: DynamicTypeSize, script: ReaderScript) {
        self.typeSize = typeSize
        self.script = script

        let bodySize = DipleTextStyle.noteBody.scaledSize(for: typeSize)
        self.bodySize = bodySize
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

        case .code, .math:
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

    /// Sets a formula in place of its source, without touching a character of it.
    ///
    /// The source stays in the text — the note is still the Markdown it was — drawn in a font too
    /// small and a colour too clear to see, and holding exactly the room the typeset formula needs:
    /// a kern on its last character for the width, a line height for the height. `NoteTextView`
    /// puts the image over that room. Returns `false` when SwiftMath cannot set the LaTeX, and the
    /// source is left as it was: a formula that does not parse never disappears, here as on the
    /// rendered page.
    @discardableResult
    func setFormula(_ formula: NoteFormula, in storage: NSTextStorage) -> Bool {
        let range = formula.range
        guard range.length > 0, range.location + range.length <= storage.length,
              let image = NoteMathRenderer.image(
                latex: formula.latex,
                fontSize: formula.isDisplay ? bodySize * 1.25 : bodySize,
                display: formula.isDisplay
              )
        else { return false }

        let text = storage.mutableString as NSString
        storage.addAttributes([
            .font: hiddenFont,
            .foregroundColor: UIColor.clear,
            NoteTextView.formulaAttribute: NoteFormulaImage(image: image, isDisplay: formula.isDisplay)
        ], range: range)

        if formula.isDisplay {
            // The block's first line carries the whole formula's height and every other line of it
            // folds away; the image stands centred over that first line.
            let firstLine = text.lineRange(for: NSRange(location: range.location, length: 0))
            var line = firstLine
            while line.location < range.location + range.length {
                let isFirst = line.location == firstLine.location
                let paragraph = NSMutableParagraphStyle()
                let height = isFirst ? image.size.height + DipleSpace.m * 2 : 0.01
                paragraph.minimumLineHeight = height
                paragraph.maximumLineHeight = height
                paragraph.paragraphSpacing = isFirst ? DipleSpace.xs : 0
                storage.addAttributes([.paragraphStyle: paragraph], range: line)
                let next = line.location + line.length
                guard next < text.length else { break }
                line = text.lineRange(for: NSRange(location: next, length: 0))
            }
        } else {
            let source = text.substring(with: range) as NSString
            let natural = source.size(withAttributes: [.font: hiddenFont]).width
            storage.addAttributes(
                [.kern: max(0, image.size.width + 2 - natural)],
                range: NSRange(location: range.location + range.length - 1, length: 1)
            )
            // A fraction stands taller than the line it sits in, and the line has to make room
            // rather than let it print over the lines around it.
            if image.size.height + 4 > bodyFont.lineHeight {
                let line = text.lineRange(for: range)
                let current = (storage.attribute(.paragraphStyle, at: line.location, effectiveRange: nil) as? NSParagraphStyle)
                    ?? NSParagraphStyle.default
                let paragraph = NSMutableParagraphStyle()
                paragraph.setParagraphStyle(current)
                paragraph.minimumLineHeight = image.size.height + 4
                storage.addAttributes([.paragraphStyle: paragraph], range: line)
            }
        }
        return true
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
/// The typeset image a formula's hidden source carries, for layout to put over it.
final class NoteFormulaImage: NSObject {
    let image: UIImage
    let isDisplay: Bool

    init(image: UIImage, isDisplay: Bool) {
        self.image = image
        self.isDisplay = isDisplay
    }
}

final class NoteTextView: UITextView {
    static let quoteIndent: CGFloat = 16
    /// Marks the lines the styling set as quotes, so layout can find them without parsing again.
    static let quoteAttribute = NSAttributedString.Key("diple.noteQuote")
    /// Marks a formula's hidden source, carrying its `NoteFormulaImage`.
    static let formulaAttribute = NSAttributedString.Key("diple.noteFormula")

    private var rules: [UIView] = []
    private var formulaViews: [UIImageView] = []
    /// Where each set formula stands and whose source it covers, so a tap on the formula can open it.
    private var formulaPlacements: [(frame: CGRect, range: NSRange, isDisplay: Bool)] = []

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
        /// A set formula, opened at the start of its LaTeX.
        case editFormula(caret: Int)
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
        guard answersMarkdownTaps, textStorage.length > 0, markedTextRange == nil else { return nil }

        // A set formula first. Its source is next to no width, so the nearest caret position to a
        // finger on the formula is almost always its end — beside it, not in it — and the formula
        // would stay set under a tap that meant "let me change this".
        if let formula = formulaPlacements.first(where: { $0.frame.insetBy(dx: -4, dy: -4).contains(point) }) {
            return .editFormula(caret: formulaCaret(for: formula.range, isDisplay: formula.isDisplay))
        }

        guard let position = closestPosition(to: point) else { return nil }
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

    /// Just inside the opening delimiter: after `$` or `\(`, or at the first line of a block.
    private func formulaCaret(for range: NSRange, isDisplay: Bool) -> Int {
        let text = textStorage.mutableString as NSString
        guard range.location + range.length <= text.length else { return range.location }
        if isDisplay {
            let newline = text.range(of: "\n", options: [], range: range)
            return newline.location != NSNotFound ? newline.location + 1 : range.location + 2
        }
        return range.location + (text.character(at: range.location) == 36 ? 1 : 2)
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
        case .editFormula(let caret):
            if !isFirstResponder {
                becomeFirstResponder()
            }
            selectedRange = NSRange(location: min(caret, textStorage.length), length: 0)
            // A selection set from code is not reliably announced; the editor has to hear this one
            // to show the formula's source. Hearing it twice costs nothing — the second finds the
            // formula already open.
            delegate?.textViewDidChangeSelection?(self)
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
        placeFormulas()
    }

    /// Puts each set formula's image over the room its hidden source holds: a display formula
    /// centred on its block's first line and scaled down if the column is narrower than it, an
    /// inline one at the end of its run, centred on the line.
    private func placeFormulas() {
        var placements: [(image: UIImage, frame: CGRect, range: NSRange, isDisplay: Bool)] = []

        if textStorage.length > 0,
           let layoutManager = textLayoutManager,
           let contentManager = layoutManager.textContentManager {
            let documentStart = contentManager.documentRange.location
            let whole = NSRange(location: 0, length: textStorage.length)
            let column = textContainer.size.width

            textStorage.enumerateAttribute(Self.formulaAttribute, in: whole, options: []) { value, range, _ in
                guard let formula = value as? NoteFormulaImage, range.length > 0,
                      let start = contentManager.location(documentStart, offsetBy: range.location),
                      let end = contentManager.location(start, offsetBy: range.length),
                      let textRange = NSTextRange(location: start, end: end)
                else { return }

                var segments: [CGRect] = []
                layoutManager.enumerateTextSegments(in: textRange, type: .standard, options: []) { _, frame, _, _ in
                    segments.append(frame)
                    return true
                }
                let size = formula.image.size

                if formula.isDisplay, let line = segments.first {
                    let scale = column > 0 ? min(1, column / max(size.width, 1)) : 1
                    let width = size.width * scale
                    let height = size.height * scale
                    placements.append((formula.image, CGRect(
                        x: textContainerInset.left + (column - width) / 2,
                        y: textContainerInset.top + line.minY + (line.height - height) / 2,
                        width: width,
                        height: height
                    ), range, true))
                } else if let first = segments.first {
                    // Anchored at the caret just before the opening `$`, which nothing about the
                    // formula moves. Both obvious anchors at the other end are wrong, and both were
                    // measured: a text segment ends where its glyphs end and leaves out the kern
                    // that holds the room, and the caret after the last character stands partway
                    // through that kern, so either put the image over the words before it.
                    let leadingEdge = self.position(from: beginningOfDocument, offset: range.location)
                        .map { caretRect(for: $0).minX }
                        ?? (textContainerInset.left + first.minX)
                    placements.append((formula.image, CGRect(
                        x: leadingEdge + 1,
                        y: textContainerInset.top + first.midY - size.height / 2,
                        width: size.width,
                        height: size.height
                    ), range, false))
                }
            }
        }

        formulaPlacements = placements.map { ($0.frame, $0.range, $0.isDisplay) }

        while formulaViews.count < placements.count {
            let view = UIImageView()
            view.contentMode = .scaleAspectFit
            view.tintColor = UIColor(DipleColor.textPrimary)
            view.isUserInteractionEnabled = false
            view.isAccessibilityElement = false
            addSubview(view)
            formulaViews.append(view)
        }
        for (index, view) in formulaViews.enumerated() {
            guard index < placements.count else {
                view.isHidden = true
                view.image = nil
                continue
            }
            view.isHidden = false
            if view.image !== placements[index].image {
                view.image = placements[index].image
            }
            view.frame = placements[index].frame
        }
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
