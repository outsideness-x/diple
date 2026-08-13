import SwiftMath
import SwiftUI
import UIKit

public enum NoteFormulaMode: String, CaseIterable, Identifiable {
    case inline
    case block

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .inline: return "Inline"
        case .block: return "Block"
        }
    }

    public func markdown(for latex: String) -> String {
        switch self {
        case .inline: return "$\(latex)$"
        case .block: return "$$\n\(latex)\n$$"
        }
    }
}

public enum NoteMathSegment: Equatable {
    case text(String)
    case formula(String)
}

/// Finds math without interpreting TeX itself. Formula source stays portable Markdown while
/// SwiftMath owns typesetting; keeping those responsibilities separate also makes malformed
/// delimiters harmless text instead of destructive parse failures.
public enum NoteMathParser {
    public static func formulaSelection(from source: String) -> (latex: String, mode: NoteFormulaMode) {
        let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("$$"), trimmed.hasSuffix("$$"), trimmed.count >= 4 {
            return (
                String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines),
                .block
            )
        }
        if trimmed.hasPrefix("\\["), trimmed.hasSuffix("\\]"), trimmed.count >= 4 {
            return (
                String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines),
                .block
            )
        }
        if trimmed.hasPrefix("$"), trimmed.hasSuffix("$"), trimmed.count >= 2 {
            return (
                String(trimmed.dropFirst().dropLast()).trimmingCharacters(in: .whitespacesAndNewlines),
                .inline
            )
        }
        if trimmed.hasPrefix("\\("), trimmed.hasSuffix("\\)"), trimmed.count >= 4 {
            return (
                String(trimmed.dropFirst(2).dropLast(2)).trimmingCharacters(in: .whitespacesAndNewlines),
                .inline
            )
        }
        return (trimmed, trimmed.contains("\n") ? .block : .inline)
    }

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
                    .dipleType(.footnote, weight: .semibold)
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

/// A focused equation workspace: source and rendered result stay visible together, while
/// common structures are one tap away. The note still stores plain TeX, so this convenience
/// layer never traps a document in a private rich-text format.
public struct NoteFormulaComposer: View {
    private let onInsert: (NoteFormulaMode, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var latex: String
    @State private var mode: NoteFormulaMode
    @State private var selection = NSRange(location: 0, length: 0)
    @State private var isEditorFocused = true

    public init(
        initialLatex: String = "",
        initialMode: NoteFormulaMode = .inline,
        onInsert: @escaping (NoteFormulaMode, String) -> Void
    ) {
        self.onInsert = onInsert
        _latex = State(initialValue: initialLatex)
        _mode = State(initialValue: initialMode)
    }

    public var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DipleSpace.xl) {
                    Picker("Equation style", selection: $mode) {
                        ForEach(NoteFormulaMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityIdentifier("formula.mode")

                    preview

                    VStack(alignment: .leading, spacing: DipleSpace.s) {
                        HStack {
                            sectionLabel("LATEX")
                            Spacer()
                            Text(mode == .inline ? "$ … $" : "$$ … $$")
                                .font(.system(.caption, design: .monospaced))
                                .foregroundStyle(DipleColor.textQuaternary)
                        }

                        NoteEditorView(
                            text: $latex,
                            selection: $selection,
                            isFocused: $isEditorFocused,
                            minimumHeight: 116,
                            usesMonospacedFont: true,
                            accessibilityLabel: "LaTeX source",
                            accessibilityIdentifier: "formula.source"
                        )
                        .padding(DipleSpace.m)
                        .background(DipleColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DipleRadius.m))
                        .overlay {
                            RoundedRectangle(cornerRadius: DipleRadius.m)
                                .stroke(isEditorFocused ? DipleColor.accent.opacity(0.55) : DipleColor.hairline,
                                        lineWidth: isEditorFocused ? DipleStroke.regular : DipleStroke.hairline)
                        }
                    }

                    VStack(alignment: .leading, spacing: DipleSpace.s) {
                        sectionLabel("BUILD")
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: DipleSpace.s) {
                                ForEach(Self.snippets) { snippet in
                                    Button {
                                        HapticManager.shared.selection()
                                        NoteEditing.apply(
                                            to: &latex,
                                            selection: &selection,
                                            prefix: snippet.prefix,
                                            suffix: snippet.suffix,
                                            placeholder: snippet.placeholder
                                        )
                                        isEditorFocused = true
                                    } label: {
                                        Text(snippet.label)
                                            .dipleType(.body, weight: .medium)
                                            .foregroundStyle(DipleColor.textSecondary)
                                            .frame(minWidth: 42, minHeight: 36)
                                            .padding(.horizontal, DipleSpace.xs)
                                            .background(DipleColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DipleRadius.s))
                                            .overlay {
                                                RoundedRectangle(cornerRadius: DipleRadius.s)
                                                    .stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline)
                                            }
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityLabel(snippet.accessibilityLabel)
                                }
                            }
                        }
                    }

                    Label(
                        "Use standard LaTeX math syntax. Fractions, roots, matrices, limits, Greek letters and aligned equations render entirely on device.",
                        systemImage: "lock.shield"
                    )
                    .dipleType(.caption)
                    .foregroundStyle(DipleColor.textTertiary)
                }
                .padding(DipleSpace.xl)
            }
            .background(DipleColor.canvas.ignoresSafeArea())
            .navigationTitle("Equation")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .foregroundStyle(DipleColor.textSecondary)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Insert") {
                        let source = latex.trimmingCharacters(in: .whitespacesAndNewlines)
                        onInsert(mode, source)
                        dismiss()
                    }
                    .fontWeight(.semibold)
                    .foregroundStyle(canInsert ? DipleColor.accent : DipleColor.textQuaternary)
                    .disabled(!canInsert)
                    .accessibilityIdentifier("formula.insert")
                }
            }
        }
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder
    private var preview: some View {
        VStack(alignment: .leading, spacing: DipleSpace.s) {
            sectionLabel("PREVIEW")
            if canInsert {
                NoteMathBlockView(latex: latex.trimmingCharacters(in: .whitespacesAndNewlines))
                    .animation(DipleMotion.snappy, value: latex)
            } else {
                VStack(spacing: DipleSpace.s) {
                    Image(systemName: "function")
                        .dipleIcon(22)
                        .foregroundStyle(DipleColor.accent)
                    Text("Type LaTeX or choose a building block")
                        .dipleType(.callout)
                        .foregroundStyle(DipleColor.textTertiary)
                }
                .frame(maxWidth: .infinity, minHeight: 104)
                .background(DipleColor.surface, in: RoundedRectangle(cornerRadius: DipleRadius.m))
                .overlay {
                    RoundedRectangle(cornerRadius: DipleRadius.m)
                        .stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline)
                }
            }
        }
    }

    private var canInsert: Bool {
        !latex.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func sectionLabel(_ label: String) -> some View {
        Text(label)
            .dipleType(.nano)
            .foregroundStyle(DipleColor.textQuaternary)
    }

    private struct FormulaSnippet: Identifiable {
        let label: String
        let accessibilityLabel: String
        let prefix: String
        let suffix: String
        let placeholder: String

        var id: String { accessibilityLabel }
    }

    private static let snippets: [FormulaSnippet] = [
        .init(label: "a⁄b", accessibilityLabel: "Fraction", prefix: #"\frac{"#, suffix: "}{b}", placeholder: "a"),
        .init(label: "√x", accessibilityLabel: "Square root", prefix: #"\sqrt{"#, suffix: "}", placeholder: "x"),
        .init(label: "xⁿ", accessibilityLabel: "Exponent", prefix: "", suffix: "^{n}", placeholder: "x"),
        .init(label: "xᵢ", accessibilityLabel: "Subscript", prefix: "", suffix: "_{i}", placeholder: "x"),
        .init(label: "Σ", accessibilityLabel: "Sum with limits", prefix: #"\sum_{i=1}^{n} "#, suffix: "", placeholder: "x_i"),
        .init(label: "∫", accessibilityLabel: "Integral with limits", prefix: #"\int_{a}^{b} "#, suffix: #"\,dx"#, placeholder: "f(x)"),
        .init(label: "[ ]", accessibilityLabel: "Matrix", prefix: #"\begin{bmatrix} "#, suffix: #" \end{bmatrix}"#, placeholder: #"a & b \\ c & d"#),
        .init(label: "{ }", accessibilityLabel: "Cases", prefix: #"\begin{cases} "#, suffix: #" \end{cases}"#, placeholder: #"x & x \ge 0 \\ -x & x < 0"#)
    ]
}
