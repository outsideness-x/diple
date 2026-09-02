import SwiftUI
import UIKit
import ReadiumShared

/// A finished source's quiet entry point. It is a single editorial row, not a promotional
/// banner, and can be reused by the phone overview and the Mac inspector.
public struct SecondReadEntryView: View {
    public let fragmentCount: Int

    public init(fragmentCount: Int) {
        self.fragmentCount = fragmentCount
    }

    public var body: some View {
        HStack(alignment: .center, spacing: DipleSpace.l) {
            VStack(alignment: .leading, spacing: DipleSpace.xs) {
                Text("Second Read")
                    .dipleType(.headline)
                    .foregroundStyle(DipleColor.textPrimary)
                Text("Your book, made from what stayed with you.")
                    .dipleType(.callout)
                    .foregroundStyle(DipleColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(SecondReadCopy.fragmentCount(fragmentCount))
                    .dipleType(.micro)
                    .foregroundStyle(DipleColor.textQuaternary)
                    .monospacedDigit()
            }

            Spacer(minLength: DipleSpace.s)

            Image(systemName: "arrow.right")
                .dipleIcon(13, weight: .semibold)
                .foregroundStyle(DipleColor.accentInk)
                .accessibilityHidden(true)
        }
        .padding(DipleSpace.l)
        .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.l)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint(Text("Opens your personal edition of this book"))
        .accessibilityIdentifier("secondRead.entry")
    }
}

/// A personal edition, laid out as one continuous reading column. It deliberately owns no
/// NavigationStack: whichever library surface opened it keeps the stack and scroll position,
/// and a source jump pushes the existing reader on top of this view.
public struct SecondReadView: View {
    @StateObject private var model: SecondReadViewModel
    @StateObject private var settingsManager = AppSettingsManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let onReadingUpdated: () -> Void

    public init(
        book: Book,
        database: AppDatabase = .shared,
        onReadingUpdated: @escaping () -> Void = {}
    ) {
        _model = StateObject(wrappedValue: SecondReadViewModel(book: book, database: database))
        self.onReadingUpdated = onReadingUpdated
    }

    private var palette: SecondReadPalette {
        SecondReadPalette(
            theme: settingsManager.settings.readerSettings.theme,
            increasedContrast: colorSchemeContrast == .increased
        )
    }

    public var body: some View {
        ZStack {
            palette.page.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    header

                    if model.items.isEmpty {
                        emptyState
                    } else {
                        ForEach(model.items) { item in
                            if item.showsChapterMarker, let chapter = item.chapterTitle {
                                chapterMarker(chapter)
                            }

                            SecondReadItemView(
                                item: item,
                                book: model.book,
                                contextState: model.contextState(for: item.id),
                                isExpanded: model.expandedIDs.contains(item.id),
                                palette: palette,
                                readerSettings: settingsManager.settings.readerSettings,
                                onToggleContext: {
                                    model.toggleContext(for: item, reduceMotion: reduceMotion)
                                }
                            )
                        }
                    }

                    Color.clear
                        .frame(height: DipleSpace.xxxl * 4)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: SecondReadLayout.readingMeasure, alignment: .leading)
                .padding(.horizontal, DipleSpace.xl)
                .frame(maxWidth: .infinity)
            }
            .scrollIndicators(.hidden)
        }
        .accessibilityIdentifier("secondRead.screen")
        .navigationTitle(Text("Second Read"))
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbarBackground(palette.page, for: .navigationBar)
        .toolbarBackground(.visible, for: .navigationBar)
        .toolbarColorScheme(palette.colorScheme, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "chevron.left")
                        .dipleIcon(15, weight: .semibold)
                        .foregroundStyle(palette.secondaryInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Back"))
            }
        }
        .toolbar(.hidden, for: .tabBar)
        .hidesDipleTabBar()
        .navigationDestination(for: SecondReadSourceRoute.self) { route in
            ReaderContainerView(
                book: route.book,
                startingLocator: Locator.from(jsonString: route.locatorJSON)
            ) {
                model.reload()
                onReadingUpdated()
            }
        }
        .alert("Second Read", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    @ViewBuilder
    private var header: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: DipleSpace.l) {
                    headerCover
                    headerIdentity
                }
            } else {
                HStack(alignment: .top, spacing: DipleSpace.l) {
                    headerCover
                    headerIdentity
                }
            }
        }
        .padding(.top, DipleSpace.xxl)
        .padding(.bottom, DipleSpace.xxxl * 2)
        .accessibilityElement(children: .contain)
    }

    private var headerCover: some View {
        BookCoverView(
            coverPath: model.book.coverPath,
            title: model.book.title,
            author: model.book.author,
            isCompact: true
        )
        .frame(maxWidth: DipleSpace.xxl * 3)
        .accessibilityHidden(true)
    }

    private var headerIdentity: some View {
        VStack(alignment: .leading, spacing: DipleSpace.s) {
            Text("SECOND READ")
                .dipleType(.nano, weight: .semibold)
                .foregroundStyle(palette.tertiaryInk)
            Text(model.book.title)
                .dipleType(.readingTitle)
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let author = model.book.author,
               !author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                Text(author)
                    .dipleType(.callout)
                    .foregroundStyle(palette.secondaryInk)
            }
            Text("What stayed with you.")
                .dipleType(.caption)
                .foregroundStyle(palette.tertiaryInk)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func chapterMarker(_ title: String) -> some View {
        VStack(alignment: .leading, spacing: DipleSpace.xs) {
            Text("CHAPTER")
                .dipleType(.nano, weight: .semibold)
                .foregroundStyle(palette.tertiaryInk)
            Text(title)
                .dipleType(.headline, weight: .medium)
                .foregroundStyle(palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.top, DipleSpace.xxxl)
        .padding(.bottom, DipleSpace.xxl)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text("Chapter \(title)"))
        .accessibilityAddTraits(.isHeader)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            Text("Nothing marked here yet.")
                .dipleType(.title)
                .foregroundStyle(palette.ink)
            Text("Highlights and thoughts from this book will become your Second Read.")
                .modifier(SecondReadTextModifier(
                    role: .context,
                    settings: settingsManager.settings.readerSettings
                ))
                .foregroundStyle(palette.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            if model.isSourceAvailable {
                NavigationLink(value: SecondReadSourceRoute(book: model.book, locatorJSON: nil)) {
                    SecondReadControlLabel(title: "Return to Book", palette: palette)
                }
                .buttonStyle(.plain)
                .padding(.top, DipleSpace.s)
                .accessibilityIdentifier("secondRead.returnToBook")
            } else {
                Text("Source unavailable")
                    .dipleType(.footnote, weight: .semibold)
                    .foregroundStyle(palette.quaternaryInk)
                    .frame(minHeight: 44)
            }
        }
        .frame(maxWidth: SecondReadLayout.emptyMeasure, alignment: .leading)
        .padding(.bottom, DipleSpace.xxxl * 3)
    }
}

private struct SecondReadItemView: View {
    let item: SecondReadItem
    let book: Book
    let contextState: SecondReadViewModel.ContextState
    let isExpanded: Bool
    let palette: SecondReadPalette
    let readerSettings: ReaderSettings
    let onToggleContext: () -> Void

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: DipleSpace.l) {
            passage

            if let note = item.noteText {
                personalNote(note)
            }

            actions
        }
        .padding(.bottom, DipleSpace.xxxl + DipleSpace.xxl)
        .id(item.id)
        .accessibilityIdentifier("secondRead.item.\(item.id)")
    }

    @ViewBuilder
    private var passage: some View {
        if isExpanded {
            switch contextState {
            case .available(let context):
                expandedContext(context)
                    .transition(.opacity)
            case .unavailable:
                VStack(alignment: .leading, spacing: DipleSpace.m) {
                    collapsedPassage
                    Text("Original context is unavailable for this passage.")
                        .dipleType(.caption)
                        .foregroundStyle(palette.tertiaryInk)
                        .accessibilityIdentifier("secondRead.contextUnavailable")
                }
                .transition(.opacity)
            case .idle, .loading:
                VStack(alignment: .leading, spacing: DipleSpace.m) {
                    collapsedPassage
                    ProgressView()
                        .tint(palette.secondaryInk)
                        .controlSize(.small)
                        .accessibilityLabel(Text("Loading original context"))
                }
                .transition(.opacity)
            }
        } else {
            collapsedPassage
        }
    }

    private var collapsedPassage: some View {
        Text(item.highlightedText)
            .modifier(SecondReadTextModifier(role: .passage, settings: readerSettings))
            .foregroundStyle(palette.ink)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
            .accessibilityLabel(Text("Highlighted passage: \(item.highlightedText)"))
    }

    private func expandedContext(_ context: SecondReadContext) -> some View {
        VStack(alignment: .leading, spacing: DipleSpace.l) {
            ForEach(Array(context.precedingParagraphs.enumerated()), id: \.offset) { _, paragraph in
                contextText(paragraph)
            }

            highlightedParagraph(context)
                .modifier(SecondReadTextModifier(role: .passage, settings: readerSettings))
                .foregroundStyle(palette.ink)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityLabel(Text("Original context, highlighted passage: \(context.highlightedText)"))

            ForEach(Array(context.followingParagraphs.enumerated()), id: \.offset) { _, paragraph in
                contextText(paragraph)
            }
        }
        .accessibilityIdentifier("secondRead.context.\(item.id)")
    }

    private func contextText(_ text: String) -> some View {
        Text(text)
            .modifier(SecondReadTextModifier(role: .context, settings: readerSettings))
            .foregroundStyle(palette.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    private func highlightedParagraph(_ context: SecondReadContext) -> Text {
        Text(spacedPrefix(context.targetPrefix))
        + Text(context.highlightedText)
            .fontWeight(.semibold)
            .foregroundColor(palette.ink)
            .underline(true, color: palette.marker)
        + Text(spacedSuffix(context.targetSuffix))
    }

    private func personalNote(_ note: String) -> some View {
        VStack(alignment: .leading, spacing: DipleSpace.s) {
            Text("YOUR NOTE")
                .dipleType(.nano, weight: .semibold)
                .foregroundStyle(palette.tertiaryInk)
            Text(note)
                .modifier(SecondReadTextModifier(role: .note, settings: readerSettings))
                .foregroundStyle(palette.noteInk)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
                .accessibilityLabel(Text("Personal note: \(note)"))
        }
    }

    private var actions: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 0) {
                    actionControls
                }
            } else {
                HStack(spacing: DipleSpace.xl) {
                    actionControls
                }
            }
        }
    }

    @ViewBuilder
    private var actionControls: some View {
        if item.canShowContext {
            SecondReadAction(title: isExpanded ? "Hide Context" : "Show Context", palette: palette) {
                onToggleContext()
            }
            .accessibilityIdentifier(isExpanded ? "secondRead.hideContext" : "secondRead.showContext")
        }

        if item.canOpenInBook {
            NavigationLink(value: SecondReadSourceRoute(book: book, locatorJSON: item.locatorJSON)) {
                SecondReadControlLabel(title: "Open in Book", palette: palette)
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("secondRead.openInBook")
        } else {
            Text("Source unavailable")
                .dipleType(.footnote)
                .foregroundStyle(palette.quaternaryInk)
                .frame(minHeight: 44)
                .accessibilityLabel(Text("Open in Book unavailable"))
        }
    }

    private func spacedPrefix(_ text: String) -> String {
        text.isEmpty ? "" : text + " "
    }

    private func spacedSuffix(_ text: String) -> String {
        text.isEmpty ? "" : " " + text
    }
}

private struct SecondReadAction: View {
    let title: LocalizedStringKey
    let palette: SecondReadPalette
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            SecondReadControlLabel(title: title, palette: palette)
        }
        .buttonStyle(.plain)
    }
}

private struct SecondReadControlLabel: View {
    let title: LocalizedStringKey
    let palette: SecondReadPalette

    @State private var isHovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(title)
            .dipleType(.footnote, weight: .semibold)
            .foregroundStyle(isHovering ? palette.ink : palette.tertiaryInk)
            .underline(isHovering)
            .frame(minHeight: 44)
            .contentShape(Rectangle())
            .onHover { hovering in
                if reduceMotion {
                    isHovering = hovering
                } else {
                    withAnimation(DipleMotion.snappy) { isHovering = hovering }
                }
            }
    }
}

private enum SecondReadTextRole: Equatable {
    case passage
    case context
    case note
}

/// Mirrors the reader's durable font, scale and leading choices without copying pagination-only
/// settings. Original prose uses the selected reading face; personal notes stay in the app's
/// system face so the distinction survives Increase Contrast without relying on tint alone.
private struct SecondReadTextModifier: ViewModifier {
    let role: SecondReadTextRole
    let settings: ReaderSettings

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Self.Content) -> some View {
        let style: DipleTextStyle = switch role {
        case .passage: .readingQuote
        case .context, .note: .readingBody
        }
        let scaledSize = UIFontMetrics(forTextStyle: style.metrics.uiTextStyle).scaledValue(
            for: style.size * settings.fontSizeScale,
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory
            )
        )
        let lineSpacing = max(3, 6 + CGFloat(settings.lineHeightAdjustment * 10))

        return content
            .font(font(size: scaledSize))
            .lineSpacing(lineSpacing)
    }

    private func font(size: CGFloat) -> Font {
        if role == .note {
            return .system(size: size, weight: .regular, design: .default)
        }
        switch settings.font {
        case .serif:
            return .system(size: size, weight: .regular, design: .serif)
        case .sanFrancisco:
            return .system(size: size, weight: .regular, design: .default)
        case .atkinson, .openDyslexic:
            guard let family = settings.font.registeredFamilyName else {
                return .system(size: size, weight: .regular, design: .default)
            }
            return .custom(family, size: size)
        }
    }
}

private enum SecondReadLayout {
    /// About 65–75 characters for the reader's normal type size: a book measure, not a
    /// screenshot-specific frame. It remains a maximum and gives way on compact windows.
    static let readingMeasure: CGFloat = 720
    static let emptyMeasure: CGFloat = 520
}

private struct SecondReadPalette {
    let page: Color
    let ink: Color
    let secondaryInk: Color
    let tertiaryInk: Color
    let quaternaryInk: Color
    let noteInk: Color
    let marker: Color
    let colorScheme: ColorScheme

    init(theme: ReaderPageTheme, increasedContrast: Bool = false) {
        page = Color(hex: theme.backgroundHex)
        ink = Color(hex: theme.inkHex)
        secondaryInk = ink.opacity(increasedContrast ? 0.9 : 0.76)
        tertiaryInk = ink.opacity(increasedContrast ? 0.76 : 0.56)
        quaternaryInk = ink.opacity(increasedContrast ? 0.62 : 0.38)
        noteInk = ink.opacity(increasedContrast ? 1 : 0.88)
        marker = DipleColor.accent
        colorScheme = (theme == .carbon || theme == .ink) ? .dark : .light
    }
}

private enum SecondReadCopy {
    static func fragmentCount(_ count: Int) -> String {
        if count == 1 {
            return String(localized: "1 fragment", comment: "Second Read item count, singular")
        }
        let format = String(localized: "%lld fragments", comment: "Second Read item count, plural")
        return String.localizedStringWithFormat(format, Int64(count))
    }
}
