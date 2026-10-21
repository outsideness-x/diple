import SwiftUI

/// A piece of the feed before it is read: what its source says about it, and the ways in.
///
/// Tapping a row opens this rather than the piece, for the same reason a passage on the board
/// opens its sheet rather than the book: the feed is where the reader decides, and reading a
/// piece files it in the library. Here a reader can see what an essay is about — the magazine's
/// own dek and its opening — or read a paper's whole abstract, and only then spend the fetch.
///
/// For a paper this is the abstract page arXiv itself would show — title, authors, fields, the
/// abstract with its formulas typeset — and the paper is one tap away in either form: the HTML
/// arXiv makes of it, reflowed into the reader's own page, or the PDF as its authors set it.
struct FeedItemSheet: View {
    let item: FeedItem
    let source: FeedSource?
    /// The library row the piece already is, if any.
    let book: Book?
    let isKeeping: Bool
    /// What the fetch is doing, while the piece is on its way to the reader — set where the
    /// page stays on screen during it, as the Mac's inspector does. The phone goes to the
    /// piece's title page instead.
    let openingStage: String?
    let onRead: (FeedReading.Format) -> Void
    let onKeep: () -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var showsEveryAuthor = false
    /// A paper opens at full height: its abstract is what the sheet is for, and at half height
    /// the title, the authors and the fields leave it two lines. An essay's dek fits half.
    @State private var detent: PresentationDetent
    @ScaledMetric(relativeTo: .footnote) private var sealSize: CGFloat = 22

    init(
        item: FeedItem,
        source: FeedSource?,
        book: Book?,
        isKeeping: Bool,
        openingStage: String? = nil,
        onRead: @escaping (FeedReading.Format) -> Void,
        onKeep: @escaping () -> Void
    ) {
        self.item = item
        self.source = source
        self.book = book
        self.isKeeping = isKeeping
        self.openingStage = openingStage
        self.onRead = onRead
        self.onKeep = onKeep
        _detent = State(initialValue: item.arxivID != nil ? .large : .medium)
    }

    private var isPaper: Bool { item.arxivID != nil }

    private var paragraphs: [String] {
        item.summary.components(separatedBy: "\n\n").filter { !$0.isEmpty }
    }

    /// `Quanta Magazine · 19 Oct` — whose, and when.
    private var sourceLine: String {
        let name = source.map { $0.isArxiv ? "arXiv" : $0.title } ?? item.link.host ?? ""
        let date = item.publishedAt.map { DipleDate.day($0) }
        return [name, date].compactMap { $0 }.joined(separator: " · ")
    }

    private var authorsLine: String? {
        guard !item.authors.isEmpty else { return nil }
        if showsEveryAuthor || item.authors.count <= 4 {
            return item.authors.joined(separator: ", ")
        }
        return item.byline
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DipleSpace.xl) {
                head
                if !paragraphs.isEmpty { text }
            }
            .padding(.horizontal, DipleSpace.xl)
            .padding(.top, DipleSpace.xxl)
            .padding(.bottom, DipleSpace.xxl)
            .frame(maxWidth: 640, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
        .scrollIndicators(.hidden)
        .background(DipleColor.canvas.ignoresSafeArea())
        .safeAreaInset(edge: .bottom, spacing: 0) { actions }
        .presentationDetents([.medium, .large], selection: $detent)
        .presentationDragIndicator(.visible)
        .presentationBackground(DipleColor.canvas)
    }

    // MARK: - The page

    private var head: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            HStack(spacing: DipleSpace.s) {
                FeedSeal(source: source, size: sealSize)
                Text(sourceLine)
                    .dipleType(.footnote, weight: .medium)
                    .foregroundStyle(DipleColor.textSecondary)
                    .lineLimit(1)
                Spacer(minLength: DipleSpace.s)
                if let number = item.arxivNumber {
                    Text(number)
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)
                        .monospacedDigit()
                        .textSelection(.enabled)
                }
            }

            Text(item.title)
                .dipleType(.editorialLead)
                .foregroundStyle(DipleColor.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)

            if let authorsLine {
                Button {
                    guard item.authors.count > 4 else { return }
                    HapticManager.shared.selection()
                    withAnimation(DipleMotion.standard) { showsEveryAuthor.toggle() }
                } label: {
                    Text(authorsLine)
                        .dipleType(.footnote, weight: .regular)
                        .foregroundStyle(DipleColor.textSecondary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .contentTransition(.opacity)
                }
                .buttonStyle(.plain)
                .disabled(item.authors.count <= 4)
                .accessibilityHint(item.authors.count > 4 && !showsEveryAuthor ? "Shows every author" : "")
            }

            if isPaper, !item.categories.isEmpty {
                FlowLayout(spacing: DipleSpace.xs) {
                    ForEach(Array(item.categories.prefix(5).enumerated()), id: \.offset) { index, code in
                        Text(ArxivField.name(for: code))
                            .dipleType(.micro, weight: index == 0 ? .semibold : .medium)
                            .foregroundStyle(index == 0 ? DipleColor.textSecondary : DipleColor.textTertiary)
                            .diplePadding(.chip)
                            .background(DipleColor.surfaceOverlay, in: Capsule())
                    }
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Fields: " + item.categories.prefix(5).map(ArxivField.name(for:)).joined(separator: ", "))
            }
        }
    }

    /// The opening in the work's own face, at a reading measure — or, for a paper, the abstract
    /// whole, under its name, with its formulas set as formulas.
    private var text: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            if isPaper {
                Text("Abstract")
                    .dipleSectionHeading()
            }
            ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                FeedProse(paragraph)
                    .foregroundStyle(DipleColor.textPrimary.opacity(0.92))
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
            }
        }
        .padding(.top, DipleSpace.hair)
    }

    // MARK: - The ways in

    private var primaryTitle: String {
        if let book {
            return book.progress > 0 ? String(localized: "Continue reading") : String(localized: "Read")
        }
        return isPaper ? String(localized: "Read the paper") : String(localized: "Read")
    }

    private var actions: some View {
        VStack(spacing: DipleSpace.m) {
            Button {
                HapticManager.shared.impact(.light)
                onRead(.best)
            } label: {
                HStack(spacing: DipleSpace.s) {
                    if openingStage != nil {
                        ProgressView()
                            .controlSize(.small)
                            .tint(DipleColor.textOnAccent)
                    }
                    Text(openingStage ?? primaryTitle)
                        .dipleType(.body, weight: .semibold)
                        .lineLimit(1)
                        .contentTransition(.opacity)
                }
                .foregroundStyle(DipleColor.textOnAccent)
                .frame(maxWidth: .infinity)
                .diplePadding(.buttonLarge)
                .background(DipleColor.accent, in: Capsule())
                .contentShape(Capsule())
                .animation(DipleMotion.standard, value: openingStage)
            }
            .buttonStyle(.readerControl)
            .disabled(openingStage != nil)
            .accessibilityIdentifier("feed.read")

            HStack(spacing: 0) {
                if book == nil {
                    secondary(
                        isKeeping ? "Keeping…" : "Keep for later",
                        systemImage: "tray.and.arrow.down",
                        isEnabled: !isKeeping
                    ) {
                        onKeep()
                    }
                }
                if isPaper {
                    secondary("PDF", systemImage: "doc.richtext") { onRead(.pdf) }
                }
                secondary(isPaper ? "arXiv" : "Website", systemImage: "safari") {
                    openURL(item.link)
                }
                ShareLink(item: item.link, subject: Text(item.title)) {
                    secondaryLabel("Share", systemImage: "square.and.arrow.up")
                }
                .buttonStyle(.readerControl)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, DipleSpace.xl)
        .padding(.top, DipleSpace.m)
        .padding(.bottom, DipleSpace.s)
        .background {
            DipleColor.canvas
                .overlay(alignment: .top) {
                    Rectangle().fill(DipleColor.hairline).frame(height: DipleStroke.hairline)
                }
                .ignoresSafeArea()
        }
    }

    private func secondary(
        _ title: String,
        systemImage: String,
        isEnabled: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.shared.selection()
            action()
        } label: {
            secondaryLabel(title, systemImage: systemImage)
        }
        .buttonStyle(.readerControl)
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.5)
        .frame(maxWidth: .infinity)
    }

    /// A glyph over its word, both quiet: the accent is spent once on this sheet, on reading.
    private func secondaryLabel(_ title: String, systemImage: String) -> some View {
        VStack(spacing: DipleSpace.xs) {
            Image(systemName: systemImage)
                .dipleIcon(16)
            Text(LocalizedStringKey(title))
                .dipleType(.caption, weight: .medium)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .foregroundStyle(DipleColor.textSecondary)
        .frame(maxWidth: .infinity, minHeight: 44)
        .contentShape(Rectangle())
    }
}

/// A paragraph of a feed's prose, in the work's face, with any TeX in it set as formulas.
///
/// arXiv abstracts carry their mathematics as `$…$`. Printed as written, `$\mathcal{O}(n \log
/// n)$` is a paragraph of backslashes; set by SwiftMath — the same renderer, cache and template
/// colouring a note's formulas use — it is the expression the authors meant, inline in the
/// sentence and wrapping with it. A formula SwiftMath cannot set falls back to its source in the
/// secondary ink: never red here, because the mistake, if any, is not the reader's.
struct FeedProse: View {
    private let text: String

    @Environment(\.dynamicTypeSize) private var typeSize

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        rendered
            .dipleType(.editorialQuote)
            // The leading every passage drawn by SwiftUI takes, by script: Hangul and kana need
            // more air than Latin.
            .lineSpacing(ReaderScript.detect(in: text).swiftUILineSpacing)
            .accessibilityLabel(NoteMathParser.accessibilityText(for: text))
    }

    private var rendered: Text {
        let segments = NoteMathParser.inlineSegments(in: text)
        guard segments.contains(where: { if case .formula = $0 { return true }; return false }) else {
            return Text(verbatim: text)
        }
        let size = DipleTextStyle.editorialQuote.scaledSize(for: typeSize)
        return segments.reduce(Text(verbatim: "")) { result, segment in
            switch segment {
            case .text(let words):
                return result + Text(verbatim: words)
            case .formula(let latex):
                guard let image = NoteMathRenderer.image(latex: latex, fontSize: size * 0.94, display: false) else {
                    return result + Text(verbatim: latex).foregroundColor(DipleColor.textSecondary)
                }
                return result + Text(Image(uiImage: image).renderingMode(.template)).baselineOffset(-size * 0.12)
            }
        }
    }
}
