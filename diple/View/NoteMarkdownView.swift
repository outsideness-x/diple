import SwiftUI

/// Block-level structure of a note.
///
/// `AttributedString(markdown:)` handles inline syntax — bold, italic, code spans, links —
/// but flattens everything above it: a heading arrives as ordinary text and a list loses its
/// bullets. Reading a note is the one place in the app where that structure is the point, so
/// blocks are parsed here and inline syntax is left to the system parser inside each one.
public enum NoteBlock: Identifiable, Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case bulleted([String])
    case numbered([String])
    case tasks([NoteTask])
    case quote(String)
    case callout(kind: NoteCallout, title: String?, body: String)
    case code(language: String?, body: String)
    case math(String)
    case divider

    public var id: String {
        switch self {
        case .heading(let level, let text): return "h\(level)-\(text)"
        case .paragraph(let text): return "p-\(text)"
        case .bulleted(let items): return "ul-\(items.joined(separator: "|"))"
        case .numbered(let items): return "ol-\(items.joined(separator: "|"))"
        case .tasks(let items): return "tasks-\(items.map(\.text).joined(separator: "|"))"
        case .quote(let text): return "q-\(text)"
        case .callout(let kind, let title, let body): return "callout-\(kind.rawValue)-\(title ?? "")-\(body)"
        case .code(let language, let body): return "c-\(language ?? "")-\(body)"
        case .math(let latex): return "math-\(latex)"
        case .divider: return "hr-\(UUID().uuidString)"
        }
    }
}

public struct NoteTask: Equatable {
    public let text: String
    public let isCompleted: Bool
    /// Where this item came from in the raw note, so ticking it rewrites the line it was
    /// parsed from. Two items can carry identical text — "Follow the thread" under two
    /// different headings — and matching on text alone would tick the wrong one.
    public let lineIndex: Int

    public init(text: String, isCompleted: Bool, lineIndex: Int = 0) {
        self.text = text
        self.isCompleted = isCompleted
        self.lineIndex = lineIndex
    }
}

public enum NoteCallout: String, Equatable {
    case note
    case tip
    case important
    case warning

    fileprivate var icon: String {
        switch self {
        case .note: return "note.text"
        case .tip: return "lightbulb"
        case .important: return "sparkles"
        case .warning: return "exclamationmark.triangle"
        }
    }

    fileprivate var fallbackTitle: String {
        rawValue.capitalized
    }
}

public enum NoteMarkdown {
    public struct OutlineItem: Identifiable, Equatable {
        public let level: Int
        public let title: String
        public let anchor: String

        public var id: String { anchor }
    }

    /// Splits a note into blocks. Deliberately forgiving: notes are typed by hand, so
    /// anything that is not recognised stays a paragraph rather than disappearing.
    public static func parse(_ raw: String) -> [NoteBlock] {
        var blocks: [NoteBlock] = []
        var paragraph: [String] = []
        var bullets: [String] = []
        var numbers: [String] = []
        var tasks: [NoteTask] = []
        var quote: [String] = []
        var code: [String] = []
        var codeLanguage: String?
        var inCode = false
        var math: [String] = []
        var mathClosingDelimiter = "$$"
        var inMath = false

        func flushParagraph() {
            guard !paragraph.isEmpty else { return }
            blocks.append(.paragraph(paragraph.joined(separator: " ")))
            paragraph = []
        }
        func flushBullets() {
            guard !bullets.isEmpty else { return }
            blocks.append(.bulleted(bullets))
            bullets = []
        }
        func flushNumbers() {
            guard !numbers.isEmpty else { return }
            blocks.append(.numbered(numbers))
            numbers = []
        }
        func flushTasks() {
            guard !tasks.isEmpty else { return }
            blocks.append(.tasks(tasks))
            tasks = []
        }
        func flushQuote() {
            guard !quote.isEmpty else { return }
            if let callout = callout(from: quote) {
                blocks.append(callout)
            } else {
                blocks.append(.quote(quote.joined(separator: " ")))
            }
            quote = []
        }
        func flushAll() {
            flushParagraph()
            flushBullets()
            flushNumbers()
            flushTasks()
            flushQuote()
        }

        for (lineIndex, line) in raw.components(separatedBy: .newlines).enumerated() {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(language: codeLanguage, body: code.joined(separator: "\n")))
                    code = []
                    codeLanguage = nil
                    inCode = false
                } else {
                    flushAll()
                    let language = String(trimmed.dropFirst(3)).trimmingCharacters(in: .whitespaces)
                    codeLanguage = language.isEmpty ? nil : language
                    inCode = true
                }
                continue
            }

            if inCode {
                code.append(line)
                continue
            }

            if inMath {
                if trimmed == mathClosingDelimiter {
                    blocks.append(.math(math.joined(separator: "\n")))
                    math = []
                    inMath = false
                } else {
                    math.append(line)
                }
                continue
            }

            if let latex = singleLineMath(from: trimmed) {
                flushAll()
                blocks.append(.math(latex))
                continue
            }

            if trimmed == "$$" || trimmed == "\\[" {
                flushAll()
                mathClosingDelimiter = trimmed == "$$" ? "$$" : "\\]"
                inMath = true
                continue
            }

            if trimmed.isEmpty {
                flushAll()
                continue
            }

            if isDivider(trimmed) {
                flushAll()
                blocks.append(.divider)
                continue
            }

            if let heading = heading(from: trimmed) {
                flushAll()
                blocks.append(heading)
                continue
            }

            if let task = taskItem(from: trimmed, at: lineIndex) {
                flushParagraph()
                flushBullets()
                flushNumbers()
                flushQuote()
                tasks.append(task)
                continue
            }

            if let item = bulletItem(from: trimmed) {
                flushParagraph()
                flushNumbers()
                flushTasks()
                flushQuote()
                bullets.append(item)
                continue
            }

            if let item = numberedItem(from: trimmed) {
                flushParagraph()
                flushBullets()
                flushTasks()
                flushQuote()
                numbers.append(item)
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushBullets()
                flushNumbers()
                flushTasks()
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }

            flushBullets()
            flushNumbers()
            flushTasks()
            flushQuote()
            paragraph.append(trimmed)
        }

        // An unterminated fence is still text the reader wrote; keep it rather than drop it.
        if inCode, !code.isEmpty {
            blocks.append(.code(language: codeLanguage, body: code.joined(separator: "\n")))
        }
        // An unfinished equation stays visible as source instead of silently disappearing.
        if inMath {
            paragraph.append((mathClosingDelimiter == "$$" ? "$$" : "\\[") + " " + math.joined(separator: " "))
        }
        flushAll()
        return blocks
    }

    private static func singleLineMath(from line: String) -> String? {
        if line.hasPrefix("$$"), line.hasSuffix("$$"), line.count > 4 {
            return String(line.dropFirst(2).dropLast(2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        if line.hasPrefix("\\["), line.hasSuffix("\\]"), line.count > 4 {
            return String(line.dropFirst(2).dropLast(2))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }

    private static func isDivider(_ line: String) -> Bool {
        let stripped = line.replacingOccurrences(of: " ", with: "")
        guard stripped.count >= 3 else { return false }
        return stripped.allSatisfy { $0 == "-" } || stripped.allSatisfy { $0 == "*" }
            || stripped.allSatisfy { $0 == "_" }
    }

    private static func heading(from line: String) -> NoteBlock? {
        guard line.hasPrefix("#") else { return nil }
        let hashes = line.prefix { $0 == "#" }.count
        guard hashes <= 6 else { return nil }
        let rest = line.dropFirst(hashes)
        guard rest.hasPrefix(" ") else { return nil }
        return .heading(level: hashes, text: rest.trimmingCharacters(in: .whitespaces))
    }

    private static func bulletItem(from line: String) -> String? {
        for marker in ["- ", "* ", "+ "] where line.hasPrefix(marker) {
            return String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces)
        }
        return nil
    }

    private static func taskItem(from line: String, at lineIndex: Int) -> NoteTask? {
        for marker in ["- [ ] ", "* [ ] ", "+ [ ] "] where line.hasPrefix(marker) {
            return NoteTask(
                text: String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces),
                isCompleted: false,
                lineIndex: lineIndex
            )
        }
        for marker in ["- [x] ", "- [X] ", "* [x] ", "* [X] ", "+ [x] ", "+ [X] "] where line.hasPrefix(marker) {
            return NoteTask(
                text: String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces),
                isCompleted: true,
                lineIndex: lineIndex
            )
        }
        return nil
    }

    /// Flips one checkbox and hands back the whole note.
    ///
    /// Rewrites only the box on `lineIndex`, leaving that line's indentation, marker and text
    /// exactly as the writer left them — the note stays the portable Markdown it was, so the
    /// change survives export, FTS and CloudKit without a second representation of "done".
    public static func togglingTask(atLine lineIndex: Int, in raw: String) -> String? {
        var lines = raw.components(separatedBy: .newlines)
        guard lines.indices.contains(lineIndex) else { return nil }

        let line = lines[lineIndex]
        let indentation = line.prefix { $0 == " " || $0 == "\t" }
        let rest = line.dropFirst(indentation.count)

        for marker in ["- ", "* ", "+ "] where rest.hasPrefix(marker) {
            let afterMarker = rest.dropFirst(marker.count)
            let replacement: String
            if afterMarker.hasPrefix("[ ] ") {
                replacement = "[x] " + afterMarker.dropFirst(4)
            } else if afterMarker.lowercased().hasPrefix("[x] ") {
                replacement = "[ ] " + afterMarker.dropFirst(4)
            } else {
                return nil
            }
            lines[lineIndex] = indentation + marker + replacement
            return lines.joined(separator: "\n")
        }
        return nil
    }

    private static func callout(from lines: [String]) -> NoteBlock? {
        guard let first = lines.first, first.hasPrefix("[!") else { return nil }
        guard let close = first.firstIndex(of: "]") else { return nil }
        let rawKind = first[first.index(first.startIndex, offsetBy: 2)..<close].lowercased()
        guard let kind = NoteCallout(rawValue: rawKind) else { return nil }
        let title = String(first[first.index(after: close)...])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let body = lines.dropFirst().joined(separator: " ")
        return .callout(
            kind: kind,
            title: title.isEmpty ? nil : title,
            body: body
        )
    }

    private static func numberedItem(from line: String) -> String? {
        let digits = line.prefix { $0.isNumber }
        guard !digits.isEmpty else { return nil }
        let rest = line.dropFirst(digits.count)
        guard rest.hasPrefix(". ") || rest.hasPrefix(") ") else { return nil }
        return String(rest.dropFirst(2)).trimmingCharacters(in: .whitespaces)
    }

    /// Inline syntax, resolved by the system parser. `inlineOnlyPreservingWhitespace` keeps
    /// the text as written instead of collapsing it into a single paragraph run.
    public static func inline(_ text: String) -> AttributedString {
        (try? AttributedString(
            markdown: linkingWikiLinks(in: text),
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
    }

    /// The scheme a `[[Wiki link]]` is rewritten to so the system Markdown parser produces a
    /// real link out of syntax it does not know.
    public static let wikiLinkScheme = "diple-note"

    /// `[[Title]]` is not Markdown, so `AttributedString(markdown:)` left it on screen as
    /// literal double brackets — notation showing through in the one view that exists to hide
    /// it, and no way to follow a link the formatting bar itself writes. Rewriting it to a
    /// link with a private scheme lets the system parser do the work and gives the reading
    /// view something to open. The stored note is untouched: this is a render-time transform,
    /// and `[[Title]]` stays what is written to disk, exported and synced.
    private static func linkingWikiLinks(in text: String) -> String {
        guard text.contains("[["),
              let expression = try? NSRegularExpression(pattern: #"\[\[([^\]\n]+)\]\]"#)
        else { return text }

        let source = text as NSString
        var result = ""
        var cursor = 0
        for match in expression.matches(in: text, range: NSRange(location: 0, length: source.length)) {
            guard match.numberOfRanges > 1 else { continue }
            let title = source.substring(with: match.range(at: 1))
            // Percent-encode against `alphanumerics` rather than a URL component set: a note
            // title is free text and may hold `?`, `&`, `#` or a space, any of which would
            // otherwise end the link early or split it into a query.
            guard let encoded = title.addingPercentEncoding(withAllowedCharacters: .alphanumerics),
                  !title.trimmingCharacters(in: .whitespaces).isEmpty
            else { continue }
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            result += "[\(title)](\(wikiLinkScheme):\(encoded))"
            cursor = match.range.location + match.range.length
        }
        result += source.substring(from: cursor)
        return result
    }

    /// The note title a rendered wiki link points at, or nil for any other URL.
    public static func wikiLinkTitle(from url: URL) -> String? {
        guard url.scheme == wikiLinkScheme else { return nil }
        let encoded = url.absoluteString.dropFirst(wikiLinkScheme.count + 1)
        return String(encoded).removingPercentEncoding
    }

    /// A clean preview for cards, search and share surfaces. Raw Markdown on a card makes
    /// the workspace feel like source code; this keeps the meaning while removing notation.
    public static func plainText(_ markdown: String) -> String {
        parse(markdown).flatMap { block -> [String] in
            switch block {
            case .heading(_, let text), .paragraph(let text), .quote(let text): return [text]
            case .bulleted(let items), .numbered(let items): return items
            case .tasks(let items): return items.map(\.text)
            case .callout(_, let title, let body): return [title, body].compactMap { $0 }
            case .code(_, let body): return [body]
            case .math(let latex): return [latex]
            case .divider: return []
            }
        }
        .joined(separator: " ")
        .replacingOccurrences(of: "**", with: "")
        .replacingOccurrences(of: "__", with: "")
        .replacingOccurrences(of: "~~", with: "")
        .replacingOccurrences(of: "`", with: "")
        // The doubled marks above are literal replacements and so ran first; what is left of a
        // `*word*` after them is a real emphasis pair, and a preview that prints its asterisks
        // is showing the reader the syntax instead of the sentence.
        .replacingOccurrences(
            of: #"\*([^*\n]+)\*"#,
            with: "$1",
            options: .regularExpression
        )
        // Underscores need the word boundaries that asterisks do not: `snake_case_name` is one
        // word to a reader and must not lose its middle to a pair that was never emphasis.
        .replacingOccurrences(
            of: #"(?<![\w_])_([^_\n]+)_(?![\w_])"#,
            with: "$1",
            options: .regularExpression
        )
        // A card should read "the idea", not "[[the idea]]".
        .replacingOccurrences(of: "[[", with: "")
        .replacingOccurrences(of: "]]", with: "")
        // …and "a real link to Readium", not "a real link to [Readium](https://readium.org)".
        // A preview is a sentence, and a URL in the middle of one is noise the reader cannot
        // act on: the card is not tappable at that word anyway.
        .replacingOccurrences(
            of: #"\[([^\]]*)\]\([^)]*\)"#,
            with: "$1",
            options: .regularExpression
        )
        .removingNoteMathDelimiters()
    }

    public static func taskProgress(in markdown: String) -> (completed: Int, total: Int)? {
        let tasks = parse(markdown).flatMap { block -> [NoteTask] in
            if case .tasks(let items) = block { return items }
            return []
        }
        guard !tasks.isEmpty else { return nil }
        return (tasks.filter(\.isCompleted).count, tasks.count)
    }

    public static func outline(in markdown: String) -> [OutlineItem] {
        parse(markdown).enumerated().compactMap { index, block in
            guard case .heading(let level, let text) = block else { return nil }
            return OutlineItem(level: level, title: text, anchor: headingAnchor(at: index))
        }
    }

    public static func headingAnchor(at blockIndex: Int) -> String {
        "note-heading-\(blockIndex)"
    }
}

/// Reading view for a note's body.
///
/// Set like a page rather than a form: system sans for an editing-tool feel, a measure that
/// stops widening on large screens, and leading loose enough for Hangul — its glyphs are
/// denser than Latin and run together at the line height Latin is comfortable at.
public struct NoteMarkdownView: View {
    public let markdown: String
    /// Ticking a box off. When nil the checkboxes are drawn but inert, which is right for a
    /// preview or a specimen and wrong everywhere the note itself is on screen — a control
    /// that looks like a checkbox and cannot be tapped is worse than a bullet.
    public let onToggleTask: ((NoteTask) -> Void)?

    public init(markdown: String, onToggleTask: ((NoteTask) -> Void)? = nil) {
        self.markdown = markdown
        self.onToggleTask = onToggleTask
    }

    private var blocks: [NoteBlock] {
        NoteMarkdown.parse(markdown)
    }

    /// Hangul is denser than Latin and closes up at Latin leading, so the whole note is set
    /// from the script it is actually written in.
    private var script: ReaderScript {
        ReaderScript.detect(in: markdown)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DipleSpace.l) {
            ForEach(Array(blocks.enumerated()), id: \.offset) { index, block in
                view(for: block)
                    .id(block.headingLevel == nil ? "note-block-\(index)" : NoteMarkdown.headingAnchor(at: index))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// One task's words, with or without the rule through them. Both copies have to lay out
    /// identically or the masked one would sit a pixel off its twin, so they differ by exactly
    /// the strikethrough and its colour.
    private func strikeText(_ task: NoteTask, struckThrough: Bool) -> some View {
        NoteInlineMathText(task.text, style: .noteBody)
            .dipleType(.noteBody)
            .foregroundStyle(
                struckThrough || task.isCompleted ? DipleColor.textTertiary : DipleColor.textPrimary
            )
            .strikethrough(struckThrough, color: DipleColor.textQuaternary)
    }

    /// The whole row is the target, not just the 16pt glyph: a checkbox is tapped with a
    /// thumb, and `contentShape` makes the gap between the box and the text count too.
    private func taskRow(_ task: NoteTask) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DipleSpace.m) {
            Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                .dipleIcon(16, weight: task.isCompleted ? .semibold : .regular)
                .foregroundStyle(task.isCompleted ? DipleColor.accentInk : DipleColor.textQuaternary)
                .contentTransition(.symbolEffect(.replace))

            // The rule is drawn rather than switched on. `.strikethrough` is a text attribute:
            // it can only be present or absent, so completing a task snapped a finished line
            // across the words in a single frame — the one moment in Notes worth watching, and
            // it happened between frames. The struck copy is stacked over the plain one and
            // revealed by a mask that scales from the leading edge, so the line travels the way
            // a pen would. Scaling the mask avoids measuring the text, which means it behaves
            // the same at any Dynamic Type size and wraps to as many lines as it likes.
            ZStack(alignment: .leading) {
                strikeText(task, struckThrough: false)
                strikeText(task, struckThrough: true)
                    .mask(alignment: .leading) {
                        Rectangle()
                            .scaleEffect(x: task.isCompleted ? 1 : 0, anchor: .leading)
                    }
            }
                .lineSpacing(script.swiftUILineSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(minHeight: 32)
        .contentShape(Rectangle())
        .animation(DipleMotion.snappy, value: task.isCompleted)
    }

    @ViewBuilder
    private func view(for block: NoteBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            NoteInlineMathText(text, style: level <= 1 ? .noteTitle : .noteHeading)
                .dipleType(level <= 1 ? .noteTitle : .noteHeading, weight: .semibold)
                .foregroundStyle(DipleColor.textPrimary)
                .padding(.top, level <= 2 ? DipleSpace.s : 0)

        case .paragraph(let text):
            NoteInlineMathText(text, style: .noteBody)
                .dipleType(.noteBody)
                .foregroundStyle(DipleColor.textPrimary)
                .lineSpacing(script.swiftUILineSpacing)

        case .bulleted(let items):
            VStack(alignment: .leading, spacing: DipleSpace.s) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    listRow(marker: "•", text: item)
                }
            }

        case .numbered(let items):
            VStack(alignment: .leading, spacing: DipleSpace.s) {
                ForEach(Array(items.enumerated()), id: \.offset) { index, item in
                    listRow(marker: "\(index + 1).", text: item)
                }
            }

        case .tasks(let items):
            VStack(alignment: .leading, spacing: DipleSpace.s) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, task in
                    if let onToggleTask {
                        Button {
                            onToggleTask(task)
                        } label: {
                            taskRow(task)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(task.isCompleted ? [.isButton, .isSelected] : .isButton)
                        .accessibilityHint(task.isCompleted ? "Mark as not done" : "Mark as done")
                    } else {
                        taskRow(task)
                    }
                }
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: DipleSpace.m) {
                Capsule()
                    .fill(DipleColor.accent.opacity(0.5))
                    .frame(width: 2)

                NoteInlineMathText(text, style: .noteBody)
                    .dipleType(.noteBody)
                    .foregroundStyle(DipleColor.textSecondary)
                    .lineSpacing(script.swiftUILineSpacing)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .callout(let kind, let title, let body):
            HStack(alignment: .top, spacing: DipleSpace.m) {
                Image(systemName: kind.icon)
                    .dipleIcon(15, weight: .semibold)
                    .foregroundStyle(DipleColor.accentInk)
                    .frame(width: 24, height: 24)
                    .background(DipleColor.accentSoft, in: RoundedRectangle(cornerRadius: DipleRadius.s))

                VStack(alignment: .leading, spacing: DipleSpace.xs) {
                    Text(title ?? kind.fallbackTitle)
                        .dipleType(.footnote, weight: .semibold)
                        .foregroundStyle(DipleColor.textPrimary)
                    if !body.isEmpty {
                        NoteInlineMathText(body, style: .callout)
                            .dipleType(.callout)
                            .foregroundStyle(DipleColor.textSecondary)
                            .lineSpacing(script.swiftUILineSpacing)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(DipleSpace.m)
            .background(DipleColor.accent.opacity(0.08), in: RoundedRectangle(cornerRadius: DipleRadius.m))
            .overlay(alignment: .leading) {
                RoundedRectangle(cornerRadius: DipleRadius.m)
                    .fill(DipleColor.accent.opacity(0.55))
                    .frame(width: 2)
            }

        case .code(let language, let body):
            VStack(alignment: .leading, spacing: 0) {
                if let language {
                    Text(language.uppercased())
                        .dipleType(.nano)
                        .foregroundStyle(DipleColor.textQuaternary)
                        .padding(.horizontal, DipleSpace.m)
                        .padding(.top, DipleSpace.s)
                }
                ScrollView(.horizontal, showsIndicators: false) {
                    Text(body)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(DipleColor.textSecondary)
                        .textSelection(.enabled)
                        .padding(DipleSpace.m)
                }
            }
            .craftSurface(DipleColor.surface, radius: DipleRadius.s)

        case .math(let latex):
            NoteMathBlockView(latex: latex)

        case .divider:
            Rectangle()
                .fill(DipleColor.separator)
                .frame(height: DipleStroke.hairline)
                .padding(.vertical, DipleSpace.s)
        }
    }

    private func listRow(marker: String, text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: DipleSpace.m) {
            Text(marker)
                .dipleType(.noteBody)
                .foregroundStyle(DipleColor.textTertiary)
                .monospacedDigit()
                .frame(minWidth: DipleSpace.l, alignment: .trailing)

            NoteInlineMathText(text, style: .noteBody)
                .dipleType(.noteBody)
                .foregroundStyle(DipleColor.textPrimary)
                .lineSpacing(script.swiftUILineSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private extension NoteBlock {
    var headingLevel: Int? {
        guard case .heading(let level, _) = self else { return nil }
        return level
    }
}

#Preview("Rendered note") {
    ScrollView {
        NoteMarkdownView(markdown: """
        # Заголовок заметки

        Обычный абзац с **жирным** и *курсивом*. 한국어 텍스트도 함께 표시되어야 합니다.

        ## Список

        - первый пункт
        - второй пункт

        > Цитата, вынесенная из книги.

        ---

        1. Раз
        2. Два

        ```
        let x = 42
        ```
        """)
        .padding(DipleSpace.xl)
    }
    .background(DipleColor.canvas)
    .preferredColorScheme(.dark)
}
