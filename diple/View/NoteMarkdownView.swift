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
    case quote(String)
    case code(String)
    case divider

    public var id: String {
        switch self {
        case .heading(let level, let text): return "h\(level)-\(text)"
        case .paragraph(let text): return "p-\(text)"
        case .bulleted(let items): return "ul-\(items.joined(separator: "|"))"
        case .numbered(let items): return "ol-\(items.joined(separator: "|"))"
        case .quote(let text): return "q-\(text)"
        case .code(let text): return "c-\(text)"
        case .divider: return "hr-\(UUID().uuidString)"
        }
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
        var quote: [String] = []
        var code: [String] = []
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
        func flushQuote() {
            guard !quote.isEmpty else { return }
            blocks.append(.quote(quote.joined(separator: " ")))
            quote = []
        }
        func flushAll() {
            flushParagraph()
            flushBullets()
            flushNumbers()
            flushQuote()
        }

        for line in raw.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("```") {
                if inCode {
                    blocks.append(.code(code.joined(separator: "\n")))
                    code = []
                    inCode = false
                } else {
                    flushAll()
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

            if let item = bulletItem(from: trimmed) {
                flushParagraph()
                flushNumbers()
                flushQuote()
                bullets.append(item)
                continue
            }

            if let item = numberedItem(from: trimmed) {
                flushParagraph()
                flushBullets()
                flushQuote()
                numbers.append(item)
                continue
            }

            if trimmed.hasPrefix(">") {
                flushParagraph()
                flushBullets()
                flushNumbers()
                quote.append(String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces))
                continue
            }

            flushBullets()
            flushNumbers()
            flushQuote()
            paragraph.append(trimmed)
        }

        // An unterminated fence is still text the reader wrote; keep it rather than drop it.
        if inCode, !code.isEmpty {
            blocks.append(.code(code.joined(separator: "\n")))
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
}

/// Reading view for a note's body.
///
/// Set like a page rather than a form: serif for the reader's own words, a measure that stops
/// widening on large screens, and leading loose enough for Hangul — its glyphs are denser than
/// Latin and run together at the line height Latin is comfortable at.
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
                .dipleType(level <= 1 ? .readingTitle : .headline, weight: .semibold)
                .foregroundStyle(DipleColor.textPrimary)
                .padding(.top, level <= 2 ? DipleSpace.s : 0)

        case .paragraph(let text):
            Text(NoteMarkdown.inline(text))
                .dipleType(.readingBody)
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

        case .quote(let text):
            HStack(alignment: .top, spacing: DipleSpace.m) {
                Capsule()
                    .fill(DipleColor.accent.opacity(0.5))
                    .frame(width: 2)

                Text(NoteMarkdown.inline(text))
                    .dipleType(.readingBody)
                    .foregroundStyle(DipleColor.textSecondary)
                    .lineSpacing(script.swiftUILineSpacing)
            }
            .fixedSize(horizontal: false, vertical: true)

        case .code(let text):
            ScrollView(.horizontal, showsIndicators: false) {
                Text(text)
                    .font(.system(.footnote, design: .monospaced))
                    .foregroundStyle(DipleColor.textSecondary)
                    .textSelection(.enabled)
                    .padding(DipleSpace.m)
            }
            .background(DipleColor.surface, in: RoundedRectangle(cornerRadius: DipleRadius.s))
            .overlay(
                RoundedRectangle(cornerRadius: DipleRadius.s)
                    .stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline)
            )

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
                .dipleType(.readingBody)
                .foregroundStyle(DipleColor.textTertiary)
                .monospacedDigit()
                .frame(minWidth: DipleSpace.l, alignment: .trailing)

            Text(NoteMarkdown.inline(text))
                .dipleType(.readingBody)
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
