import Foundation

/// What a stretch of a note's Markdown means, while it is still being typed.
///
/// The whole point of this file is that **the text does not change**. Styling a note as it is
/// written is attributes laid over exactly the characters the writer typed: the `##` stays a
/// `##`, and the note that leaves through export, the search index, CloudKit or any other
/// Markdown client is byte for byte the note that was written. What changes is only how it
/// looks while it is in front of the writer — which is the difference between this and a
/// rich-text editor with a Markdown import.
///
/// Kept as plain values over `NSRange`, with no UIKit in sight, so the rules can be read as one
/// table and tested without a text view.
public enum NoteSyntaxRole: Equatable, Sendable {
    /// A whole heading line, level 1…6.
    case heading(level: Int)
    case strong
    case emphasis
    /// `code` between backticks, or any line inside a fence.
    case code
    /// A whole quoted line.
    case quote
    /// A task's box, ticked or not.
    case task(isDone: Bool)
    /// What a ticked task says: struck through, the way the rendered page sets it.
    case done
    /// The bullet or number that opens a list item.
    case listMarker
    /// A `[[wiki link]]`, a `#tag`, or the words of a `[label](url)`.
    case link
    /// Punctuation that carries a meaning without being it — the `#`, the `**`, the backticks,
    /// a link's brackets. Kept at the size of the text it marks and dimmed, so the writing stays
    /// where the eye is while the notation stays where the hand can reach it.
    case marker
}

public struct NoteSyntaxSpan: Equatable, Sendable {
    public let range: NSRange
    public let role: NoteSyntaxRole

    public init(_ range: NSRange, _ role: NoteSyntaxRole) {
        self.range = range
        self.role = role
    }
}

public enum NoteSyntax {
    private static let fence = "```"

    /// Every span in `text`, or only those on the lines `restyling` touches.
    ///
    /// Spans are returned **in application order**: the role of the whole line first, then its
    /// marker, then what is inside it. A bold word inside a heading is meant to arrive after the
    /// heading and thicken it, not to replace it with body type.
    ///
    /// No span ever crosses a line, and the range asked for is always widened to whole lines by
    /// `restyleRange(for:in:)`, so a caller can clear that range and lay these over it without
    /// cutting anything in half.
    public static func spans(in text: NSString, restyling range: NSRange? = nil) -> [NoteSyntaxSpan] {
        guard text.length > 0 else { return [] }
        let whole = NSRange(location: 0, length: text.length)
        let target = clamped(range ?? whole, in: text)
        // A fence changes what every line after it means, so with one in the note the walk has
        // to start at the top to know which side of it a line is on. Without one — the ordinary
        // note — it starts at the line being typed and the cost stops depending on the length.
        let hasFence = text.range(of: fence).location != NSNotFound

        var result: [NoteSyntaxSpan] = []
        var inFence = false
        var location = hasFence
            ? 0
            : text.lineRange(for: NSRange(location: min(target.location, max(text.length - 1, 0)), length: 0)).location
        let end = min(target.location + target.length, text.length)

        while location < text.length {
            let line = text.lineRange(for: NSRange(location: location, length: 0))
            guard line.length > 0 else { break }
            if line.location > end { break }

            let content = trimmingLineBreak(line, in: text)
            let wanted = NSIntersectionRange(line, target).length > 0 || line.location == target.location

            if isFenceLine(content, in: text) {
                if wanted { result.append(NoteSyntaxSpan(content, .marker)) }
                inFence.toggle()
            } else if inFence {
                if wanted, content.length > 0 { result.append(NoteSyntaxSpan(content, .code)) }
            } else if wanted {
                result.append(contentsOf: spans(forLine: content, in: text))
            }

            location = line.location + line.length
        }

        return result
    }

    /// The stretch that has to be styled again after an edit at `edited`.
    ///
    /// Whole lines, because every block rule in Markdown is a rule about a line. The whole note
    /// when a fence is involved: one pair of backticks decides the meaning of everything below
    /// it, and an edit can open or close one.
    public static func restyleRange(for edited: NSRange, in text: NSString) -> NSRange {
        guard text.length > 0 else { return NSRange(location: 0, length: 0) }
        if text.range(of: fence).location != NSNotFound {
            return NSRange(location: 0, length: text.length)
        }
        return text.lineRange(for: clamped(edited, in: text))
    }

    // MARK: - One line

    private static func spans(forLine line: NSRange, in text: NSString) -> [NoteSyntaxSpan] {
        guard line.length > 0 else { return [] }
        var result: [NoteSyntaxSpan] = []

        var cursor = line.location
        let end = line.location + line.length
        while cursor < end, isIndentation(text.character(at: cursor)) { cursor += 1 }

        // A rule across the page is all notation and no text.
        if let divider = dividerRange(line, from: cursor, in: text) {
            return [NoteSyntaxSpan(divider, .marker)]
        }

        if let level = headingLevel(from: cursor, in: text, end: end) {
            var marker = level
            if cursor + marker < end, text.character(at: cursor + marker) == 32 { marker += 1 }
            result.append(NoteSyntaxSpan(line, .heading(level: level)))
            result.append(NoteSyntaxSpan(NSRange(location: cursor, length: marker), .marker))
            result.append(contentsOf: inlineSpans(in: NSRange(location: cursor + marker, length: end - cursor - marker), of: text))
            return result
        }

        if cursor < end, text.character(at: cursor) == 62 { // ">"
            var marker = 1
            if cursor + marker < end, text.character(at: cursor + marker) == 32 { marker += 1 }
            result.append(NoteSyntaxSpan(line, .quote))
            result.append(NoteSyntaxSpan(NSRange(location: cursor, length: marker), .marker))
            var rest = NSRange(location: cursor + marker, length: end - cursor - marker)
            // A callout announces itself with `[!NOTE]`, which is notation rather than words.
            if let label = calloutLabel(in: rest, of: text) {
                result.append(NoteSyntaxSpan(label, .marker))
                let after = label.location + label.length
                rest = NSRange(location: after, length: max(0, rest.location + rest.length - after))
            }
            result.append(contentsOf: inlineSpans(in: rest, of: text))
            return result
        }

        if let item = listItem(from: cursor, in: text, end: end) {
            result.append(NoteSyntaxSpan(item.marker, .listMarker))
            if let box = item.box {
                result.append(NoteSyntaxSpan(box, .task(isDone: item.isDone)))
            }
            let rest = NSRange(location: item.contentStart, length: max(0, end - item.contentStart))
            if item.isDone, rest.length > 0 {
                result.append(NoteSyntaxSpan(rest, .done))
            }
            result.append(contentsOf: inlineSpans(in: rest, of: text))
            return result
        }

        return inlineSpans(in: NSRange(location: cursor, length: end - cursor), of: text)
    }

    // MARK: - Inside a line

    /// Walks a line once, left to right, and never backtracks past a span it has already
    /// claimed. That is what keeps `**bold**` inside a code span from being bold: the backticks
    /// are read first and the walk resumes after them.
    private static func inlineSpans(in range: NSRange, of text: NSString) -> [NoteSyntaxSpan] {
        guard range.length > 0 else { return [] }
        var result: [NoteSyntaxSpan] = []
        let end = range.location + range.length
        var index = range.location

        while index < end {
            let character = text.character(at: index)

            switch character {
            case 96: // "`"
                if let close = firstIndex(of: 96, from: index + 1, before: end, in: text) {
                    result.append(NoteSyntaxSpan(NSRange(location: index, length: close - index + 1), .code))
                    result.append(NoteSyntaxSpan(NSRange(location: index, length: 1), .marker))
                    result.append(NoteSyntaxSpan(NSRange(location: close, length: 1), .marker))
                    index = close + 1
                    continue
                }

            case 42, 95: // "*", "_"
                if let emphasis = emphasis(at: index, in: range, of: text) {
                    result.append(NoteSyntaxSpan(emphasis.content, emphasis.isStrong ? .strong : .emphasis))
                    result.append(NoteSyntaxSpan(emphasis.opening, .marker))
                    result.append(NoteSyntaxSpan(emphasis.closing, .marker))
                    index = emphasis.closing.location + emphasis.closing.length
                    continue
                }

            case 91: // "["
                if let link = link(at: index, in: range, of: text) {
                    result.append(contentsOf: link.spans)
                    index = link.end
                    continue
                }

            case 35: // "#"
                if opensWord(at: index, in: range, of: text), let tag = tag(at: index, before: end, in: text) {
                    result.append(NoteSyntaxSpan(tag, .link))
                    index = tag.location + tag.length
                    continue
                }

            default:
                break
            }

            index += 1
        }

        return result
    }

    private struct Emphasis {
        let opening: NSRange
        let closing: NSRange
        let content: NSRange
        let isStrong: Bool
    }

    /// `*` and `_`, singly for emphasis and doubled for strength.
    ///
    /// Two rules keep ordinary prose out of it: the marker has to sit against the word it opens
    /// (`2 * 3 * 4` is arithmetic, not italics), and an underscore has to open a word, so
    /// `snake_case_names` stay upright.
    private static func emphasis(at index: Int, in range: NSRange, of text: NSString) -> Emphasis? {
        let end = range.location + range.length
        let marker = text.character(at: index)
        let isStrong = index + 1 < end && text.character(at: index + 1) == marker
        let width = isStrong ? 2 : 1
        let contentStart = index + width
        guard contentStart < end, !isBlank(text.character(at: contentStart)) else { return nil }
        if marker == 95, !opensWord(at: index, in: range, of: text) { return nil }

        var scan = contentStart
        while scan < end {
            guard text.character(at: scan) == marker else { scan += 1; continue }
            if isStrong {
                guard scan + 1 < end, text.character(at: scan + 1) == marker else { scan += 1; continue }
            }
            guard scan > contentStart, !isBlank(text.character(at: scan - 1)) else { scan += width; continue }
            return Emphasis(
                opening: NSRange(location: index, length: width),
                closing: NSRange(location: scan, length: width),
                content: NSRange(location: index, length: scan + width - index),
                isStrong: isStrong
            )
        }
        return nil
    }

    private struct Link {
        let spans: [NoteSyntaxSpan]
        let end: Int
    }

    /// `[[Another note]]` and `[label](url)`. In both the words are the link and the brackets
    /// are notation; in the second the address is notation too, because nobody reads a URL.
    private static func link(at index: Int, in range: NSRange, of text: NSString) -> Link? {
        let end = range.location + range.length

        if index + 1 < end, text.character(at: index + 1) == 91 { // "[["
            guard let close = firstPair(of: 93, from: index + 2, before: end, in: text) else { return nil }
            let inner = NSRange(location: index + 2, length: close - index - 2)
            guard inner.length > 0 else { return nil }
            return Link(
                spans: [
                    NoteSyntaxSpan(inner, .link),
                    NoteSyntaxSpan(NSRange(location: index, length: 2), .marker),
                    NoteSyntaxSpan(NSRange(location: close, length: 2), .marker)
                ],
                end: close + 2
            )
        }

        guard let label = firstIndex(of: 93, from: index + 1, before: end, in: text),
              label + 1 < end, text.character(at: label + 1) == 40, // "("
              let address = firstIndex(of: 41, from: label + 2, before: end, in: text) // ")"
        else { return nil }

        return Link(
            spans: [
                NoteSyntaxSpan(NSRange(location: index + 1, length: label - index - 1), .link),
                NoteSyntaxSpan(NSRange(location: index, length: 1), .marker),
                NoteSyntaxSpan(NSRange(location: label, length: address - label + 1), .marker)
            ],
            end: address + 1
        )
    }

    /// `#tag` — everything up to the first space or sentence punctuation. Letters outside Latin
    /// are ordinary tag letters: a Russian or Korean tag is a tag.
    private static func tag(at index: Int, before end: Int, in text: NSString) -> NSRange? {
        var scan = index + 1
        while scan < end, isTagCharacter(text.character(at: scan)) { scan += 1 }
        guard scan > index + 1 else { return nil }
        return NSRange(location: index, length: scan - index)
    }

    // MARK: - Line openers

    private static func headingLevel(from start: Int, in text: NSString, end: Int) -> Int? {
        var scan = start
        while scan < end, text.character(at: scan) == 35, scan - start < 6 { scan += 1 }
        let level = scan - start
        guard level > 0 else { return nil }
        // `#tag` at the head of a line is a tag, not a heading: a heading's hashes are followed
        // by a space, or by nothing at all.
        guard scan == end || text.character(at: scan) == 32 else { return nil }
        return level
    }

    private struct ListItem {
        let marker: NSRange
        let box: NSRange?
        let isDone: Bool
        let contentStart: Int
    }

    private static func listItem(from start: Int, in text: NSString, end: Int) -> ListItem? {
        var afterMarker: Int?

        let first = start < end ? text.character(at: start) : 0
        if first == 45 || first == 42 || first == 43 { // "-", "*", "+"
            if start + 1 < end, text.character(at: start + 1) == 32 { afterMarker = start + 2 }
        } else if isDigit(first) {
            var scan = start
            while scan < end, isDigit(text.character(at: scan)) { scan += 1 }
            if scan + 1 < end,
               text.character(at: scan) == 46 || text.character(at: scan) == 41, // ".", ")"
               text.character(at: scan + 1) == 32 {
                afterMarker = scan + 2
            }
        }

        guard let contentStart = afterMarker else { return nil }
        let marker = NSRange(location: start, length: contentStart - start)

        // A box is checked before a plain bullet, because `- [ ] x` opens like one.
        if contentStart + 2 < end,
           text.character(at: contentStart) == 91, // "["
           text.character(at: contentStart + 2) == 93 { // "]"
            let mark = text.character(at: contentStart + 1)
            let isDone = mark == 120 || mark == 88 // "x", "X"
            if mark == 32 || isDone {
                var after = contentStart + 3
                if after < end, text.character(at: after) == 32 { after += 1 }
                return ListItem(
                    marker: marker,
                    box: NSRange(location: contentStart, length: 3),
                    isDone: isDone,
                    contentStart: after
                )
            }
        }

        return ListItem(marker: marker, box: nil, isDone: false, contentStart: contentStart)
    }

    private static func dividerRange(_ line: NSRange, from start: Int, in text: NSString) -> NSRange? {
        let end = line.location + line.length
        guard end - start >= 3 else { return nil }
        let rule = text.character(at: start)
        guard rule == 45 || rule == 42 || rule == 95 else { return nil }
        var scan = start
        while scan < end, text.character(at: scan) == rule { scan += 1 }
        guard scan - start >= 3 else { return nil }
        while scan < end, isIndentation(text.character(at: scan)) { scan += 1 }
        guard scan == end else { return nil }
        return NSRange(location: start, length: end - start)
    }

    private static func calloutLabel(in range: NSRange, of text: NSString) -> NSRange? {
        guard range.length > 2,
              text.character(at: range.location) == 91, // "["
              text.character(at: range.location + 1) == 33 // "!"
        else { return nil }
        let end = range.location + range.length
        guard let close = firstIndex(of: 93, from: range.location + 2, before: end, in: text) else { return nil }
        var after = close + 1
        if after < end, text.character(at: after) == 32 { after += 1 }
        return NSRange(location: range.location, length: after - range.location)
    }

    // MARK: - Characters

    private static func isFenceLine(_ content: NSRange, in text: NSString) -> Bool {
        var scan = content.location
        let end = content.location + content.length
        while scan < end, isIndentation(text.character(at: scan)) { scan += 1 }
        guard end - scan >= 3 else { return false }
        return text.character(at: scan) == 96
            && text.character(at: scan + 1) == 96
            && text.character(at: scan + 2) == 96
    }

    private static func trimmingLineBreak(_ line: NSRange, in text: NSString) -> NSRange {
        var length = line.length
        while length > 0 {
            let last = text.character(at: line.location + length - 1)
            guard last == 10 || last == 13 else { break }
            length -= 1
        }
        return NSRange(location: line.location, length: length)
    }

    private static func firstIndex(of character: unichar, from start: Int, before end: Int, in text: NSString) -> Int? {
        var scan = start
        while scan < end {
            if text.character(at: scan) == character { return scan }
            scan += 1
        }
        return nil
    }

    private static func firstPair(of character: unichar, from start: Int, before end: Int, in text: NSString) -> Int? {
        var scan = start
        while scan + 1 < end {
            if text.character(at: scan) == character, text.character(at: scan + 1) == character { return scan }
            scan += 1
        }
        return nil
    }

    private static func opensWord(at index: Int, in range: NSRange, of text: NSString) -> Bool {
        guard index > range.location else { return true }
        return isBlank(text.character(at: index - 1))
    }

    private static func isBlank(_ character: unichar) -> Bool {
        character == 32 || character == 9 || character == 10 || character == 13
    }

    private static func isIndentation(_ character: unichar) -> Bool {
        character == 32 || character == 9
    }

    private static func isDigit(_ character: unichar) -> Bool {
        character >= 48 && character <= 57
    }

    /// Stated as what ends a tag rather than what a tag may contain, so every script keeps its
    /// letters without being listed.
    private static func isTagCharacter(_ character: unichar) -> Bool {
        if isBlank(character) { return false }
        switch character {
        case 35, 44, 46, 59, 58, 33, 63, 40, 41, 91, 93, 123, 125, 34, 39, 96, 42:
            return false
        default:
            return true
        }
    }

    private static func clamped(_ range: NSRange, in text: NSString) -> NSRange {
        let location = max(0, min(range.location, text.length))
        let length = max(0, min(range.length, text.length - location))
        return NSRange(location: location, length: length)
    }
}
