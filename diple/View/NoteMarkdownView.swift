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
        case .divider: return "hr-\(UUID().uuidString)"
        }
    }
}

public struct NoteTask: Equatable {
    public let text: String
    public let isCompleted: Bool
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

        for line in raw.components(separatedBy: .newlines) {
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

            if let task = taskItem(from: trimmed) {
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
        flushAll()
        return blocks
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

    private static func taskItem(from line: String) -> NoteTask? {
        for marker in ["- [ ] ", "* [ ] ", "+ [ ] "] where line.hasPrefix(marker) {
            return NoteTask(
                text: String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces),
                isCompleted: false
            )
        }
        for marker in ["- [x] ", "- [X] ", "* [x] ", "* [X] ", "+ [x] ", "+ [X] "] where line.hasPrefix(marker) {
            return NoteTask(
                text: String(line.dropFirst(marker.count)).trimmingCharacters(in: .whitespaces),
                isCompleted: true
            )
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
            markdown: text,
            options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        )) ?? AttributedString(text)
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
            case .divider: return []
            }
        }
        .joined(separator: " ")
        .replacingOccurrences(of: "**", with: "")
        .replacingOccurrences(of: "__", with: "")
        .replacingOccurrences(of: "~~", with: "")
        .replacingOccurrences(of: "`", with: "")
    }

    public static func taskProgress(in markdown: String) -> (completed: Int, total: Int)? {
        let tasks = parse(markdown).flatMap { block -> [NoteTask] in
            if case .tasks(let items) = block { return items }
            return []
        }
        guard !tasks.isEmpty else { return nil }
        return (tasks.filter(\.isCompleted).count, tasks.count)
    }
}

/// Reading view for a note's body.
///
/// Set like a page rather than a form: system sans for an editing-tool feel, a measure that
/// stops widening on large screens, and leading loose enough for Hangul — its glyphs are
/// denser than Latin and run together at the line height Latin is comfortable at.
public struct NoteMarkdownView: View {
    public let markdown: String

    public init(markdown: String) {
        self.markdown = markdown
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
            ForEach(blocks) { block in
                view(for: block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func view(for block: NoteBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(NoteMarkdown.inline(text))
                .dipleType(level <= 1 ? .noteTitle : .noteHeading, weight: .semibold)
                .foregroundStyle(DipleColor.textPrimary)
                .padding(.top, level <= 2 ? DipleSpace.s : 0)

        case .paragraph(let text):
            Text(NoteMarkdown.inline(text))
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
                    HStack(alignment: .firstTextBaseline, spacing: DipleSpace.m) {
                        Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                            .dipleIcon(16, weight: task.isCompleted ? .semibold : .regular)
                            .foregroundStyle(task.isCompleted ? DipleColor.accent : DipleColor.textQuaternary)

                        Text(NoteMarkdown.inline(task.text))
                            .dipleType(.noteBody)
                            .foregroundStyle(task.isCompleted ? DipleColor.textTertiary : DipleColor.textPrimary)
                            .strikethrough(task.isCompleted, color: DipleColor.textQuaternary)
                            .lineSpacing(script.swiftUILineSpacing)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }

        case .quote(let text):
            HStack(alignment: .top, spacing: DipleSpace.m) {
                Capsule()
                    .fill(DipleColor.accent.opacity(0.5))
                    .frame(width: 2)

                Text(NoteMarkdown.inline(text))
                    .dipleType(.noteBody)
                    .foregroundStyle(DipleColor.textSecondary)
                    .lineSpacing(script.swiftUILineSpacing)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .callout(let kind, let title, let body):
            HStack(alignment: .top, spacing: DipleSpace.m) {
                Image(systemName: kind.icon)
                    .dipleIcon(15, weight: .semibold)
                    .foregroundStyle(DipleColor.accent)
                    .frame(width: 24, height: 24)
                    .background(DipleColor.accentSoft, in: RoundedRectangle(cornerRadius: DipleRadius.s))

                VStack(alignment: .leading, spacing: DipleSpace.xs) {
                    Text(title ?? kind.fallbackTitle)
                        .dipleType(.footnote, weight: .semibold)
                        .foregroundStyle(DipleColor.textPrimary)
                    if !body.isEmpty {
                        Text(NoteMarkdown.inline(body))
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

            Text(NoteMarkdown.inline(text))
                .dipleType(.noteBody)
                .foregroundStyle(DipleColor.textPrimary)
                .lineSpacing(script.swiftUILineSpacing)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
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
