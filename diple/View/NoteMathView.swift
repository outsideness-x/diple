import SwiftMath
import SwiftUI
import UIKit

public enum NoteMathSegment: Equatable {
    case text(String)
    case formula(String)
}

/// Finds math without interpreting TeX itself. Formula source stays portable Markdown while
/// SwiftMath owns typesetting; keeping those responsibilities separate also makes malformed
/// delimiters harmless text instead of destructive parse failures.
public enum NoteMathParser {
    public static func inlineSegments(in source: String) -> [NoteMathSegment] {
        guard source.contains("$") || source.contains("\\(") else { return [.text(source)] }

        var segments: [NoteMathSegment] = []
        var textStart = source.startIndex
        var cursor = source.startIndex

        func appendText(until end: String.Index) {
            guard textStart < end else { return }
            segments.append(.text(String(source[textStart..<end])))
        }

        while cursor < source.endIndex {
            if source[cursor] == "$", !isEscaped(cursor, in: source), !isDoubleDollar(at: cursor, in: source) {
                let contentStart = source.index(after: cursor)
                if let close = closingDollar(in: source, after: contentStart) {
                    let latex = String(source[contentStart..<close])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !latex.isEmpty {
                        appendText(until: cursor)
                        segments.append(.formula(latex))
                        cursor = source.index(after: close)
                        textStart = cursor
                        continue
                    }
                }
            }

            if source[cursor] == "\\", !isEscaped(cursor, in: source),
               let next = nextIndex(after: cursor, in: source), source[next] == "(" {
                let contentStart = source.index(after: next)
                if let close = closingParenthesis(in: source, after: contentStart) {
                    let latex = String(source[contentStart..<close])
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    if !latex.isEmpty {
                        appendText(until: cursor)
                        segments.append(.formula(latex))
                        cursor = source.index(close, offsetBy: 2)
                        textStart = cursor
                        continue
                    }
                }
            }

            cursor = source.index(after: cursor)
        }

        appendText(until: source.endIndex)
        return segments.isEmpty ? [.text(source)] : segments
    }

    public static func removingDelimiters(from source: String) -> String {
        inlineSegments(in: source).map { segment in
            switch segment {
            case .text(let text), .formula(let text): return text
            }
        }.joined()
    }

    public static func accessibilityText(for source: String) -> String {
        inlineSegments(in: source).map { segment in
            switch segment {
            case .text(let text): return text
            case .formula(let latex): return "Formula: \(latex)"
            }
        }.joined()
    }

    private static func closingDollar(in source: String, after start: String.Index) -> String.Index? {
        var cursor = start
        while cursor < source.endIndex {
            if source[cursor] == "$", !isEscaped(cursor, in: source), !isDoubleDollar(at: cursor, in: source) {
                return cursor
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    private static func closingParenthesis(in source: String, after start: String.Index) -> String.Index? {
        var cursor = start
        while cursor < source.endIndex {
            if source[cursor] == "\\", !isEscaped(cursor, in: source),
               let next = nextIndex(after: cursor, in: source), source[next] == ")" {
                return cursor
            }
            cursor = source.index(after: cursor)
        }
        return nil
    }

    private static func isDoubleDollar(at index: String.Index, in source: String) -> Bool {
        if let next = nextIndex(after: index, in: source), source[next] == "$" { return true }
        guard index > source.startIndex else { return false }
        return source[source.index(before: index)] == "$"
    }

    private static func isEscaped(_ index: String.Index, in source: String) -> Bool {
        var cursor = index
        var slashCount = 0
        while cursor > source.startIndex {
            let previous = source.index(before: cursor)
            guard source[previous] == "\\" else { break }
            slashCount += 1
            cursor = previous
        }
        return slashCount.isMultiple(of: 2) == false
    }

    private static func nextIndex(after index: String.Index, in source: String) -> String.Index? {
        let next = source.index(after: index)
        return next < source.endIndex ? next : nil
    }
}

extension String {
    func removingNoteMathDelimiters() -> String {
        NoteMathParser.removingDelimiters(from: self)
    }
}

private enum NoteMathRenderer {
    private static let cache = NSCache<NSString, UIImage>()

    static func image(latex: String, fontSize: CGFloat, display: Bool) -> UIImage? {
        let key = "\(display ? "display" : "text")|\(fontSize.rounded(.toNearestOrAwayFromZero))|\(latex)" as NSString
        if let cached = cache.object(forKey: key) { return cached }

        let renderer = MTMathImage(
            latex: latex,
            fontSize: fontSize,
            textColor: .black,
            labelMode: display ? .display : .text,
            textAlignment: .center
        )
        let (_, rendered) = renderer.asImage()
        guard let image = rendered?.withRenderingMode(.alwaysTemplate) else { return nil }
        cache.setObject(image, forKey: key)
        return image
    }
}

/// A single SwiftUI `Text` keeps prose wrapping naturally around equation images. This is
/// materially better than laying inline math out as chips: a formula remains part of the
/// sentence, participates in Dynamic Type and wraps at the same measure as surrounding copy.
public struct NoteInlineMathText: View {
    private let source: String
    private let style: DipleTextStyle

    @Environment(\.dynamicTypeSize) private var typeSize

    public init(_ source: String, style: DipleTextStyle) {
        self.source = source
        self.style = style
    }

    public var body: some View {
        renderedText
            .accessibilityLabel(NoteMathParser.accessibilityText(for: source))
    }

    private var renderedText: Text {
        let segments = NoteMathParser.inlineSegments(in: source)
        guard segments.contains(where: { if case .formula = $0 { return true }; return false }) else {
            return Text(NoteMarkdown.inline(source))
        }

        let fontSize = style.scaledSize(for: typeSize)
        return segments.reduce(Text("")) { result, segment in
            switch segment {
            case .text(let text):
                return result + Text(NoteMarkdown.inline(text))
            case .formula(let latex):
                guard let image = NoteMathRenderer.image(latex: latex, fontSize: fontSize, display: false) else {
                    return result + Text("$\(latex)$").foregroundColor(DipleColor.destructive)
                }
                return result + Text(Image(uiImage: image).renderingMode(.template)).baselineOffset(-1)
            }
        }
    }
}

public struct NoteMathBlockView: View {
    public let latex: String

    @Environment(\.dynamicTypeSize) private var typeSize

    public init(latex: String) {
        self.latex = latex
    }

    public var body: some View {
        let fontSize = DipleTextStyle.noteBody.scaledSize(for: typeSize) * 1.25
        let rendered = NoteMathRenderer.image(latex: latex, fontSize: fontSize, display: true)

        VStack(alignment: .leading, spacing: DipleSpace.m) {
            HStack(spacing: DipleSpace.s) {
                Text("ƒx")
                    .font(.system(size: 13, weight: .semibold, design: .serif))
                    .foregroundStyle(DipleColor.accent)
                Text("EQUATION")
                    .dipleType(.nano)
                    .foregroundStyle(DipleColor.textQuaternary)

                Spacer()

                Button {
                    UIPasteboard.general.string = latex
                    HapticManager.shared.impact(.light)
                } label: {
                    Image(systemName: "doc.on.doc")
                        .dipleIcon(12)
                        .foregroundStyle(DipleColor.textTertiary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Copy LaTeX")
            }

            if let rendered {
                GeometryReader { geometry in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack {
                            Spacer(minLength: 0)
                            Image(uiImage: rendered)
                                .renderingMode(.template)
                                .foregroundStyle(DipleColor.textPrimary)
                            Spacer(minLength: 0)
                        }
                        .frame(minWidth: geometry.size.width)
                        .frame(height: max(rendered.size.height + DipleSpace.m, 48))
                    }
                }
                .frame(height: max(rendered.size.height + DipleSpace.m, 48))
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Equation")
                .accessibilityValue(latex)
            } else {
                VStack(alignment: .leading, spacing: DipleSpace.s) {
                    Label("Check the LaTeX syntax", systemImage: "exclamationmark.triangle")
                        .dipleType(.footnote, weight: .semibold)
                        .foregroundStyle(DipleColor.destructive)
                    Text(latex)
                        .font(.system(.footnote, design: .monospaced))
                        .foregroundStyle(DipleColor.textSecondary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(DipleSpace.m)
        .background(DipleColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DipleRadius.m))
        .overlay {
            RoundedRectangle(cornerRadius: DipleRadius.m)
                .stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline)
        }
        .contextMenu {
            Button("Copy LaTeX", systemImage: "doc.on.doc") {
                UIPasteboard.general.string = latex
            }
        }
    }
}
