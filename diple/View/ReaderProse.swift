import SwiftUI

/// Which face sets a run of text on a reader surface.
enum ReaderProseFace {
    /// The publication's own words, in the face the reader chose for the page.
    case reading
    /// The reader's own words, in the app's face — so the distinction between what was printed
    /// and what was written survives Increase Contrast rather than resting on a tint.
    case app
}

/// The publication's words, set the way the reader set the page.
///
/// More than one surface prints the book's prose without the navigator under it — Second Read's
/// excerpts and their context, a footnote raised at the foot of the page — and all of them have
/// to answer the reader's face, scale and leading identically. Two switches over `ReaderFont`
/// drift, and the drift shows as the same paragraph set two ways depending on which screen it
/// was read from.
///
/// Pagination and margins are deliberately absent: those are properties of a page being turned,
/// and none of these surfaces turn.
struct ReaderProseModifier: ViewModifier {
    let style: DipleTextStyle
    let settings: ReaderSettings
    let face: ReaderProseFace

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    func body(content: Content) -> some View {
        let scaledSize = UIFontMetrics(forTextStyle: style.metrics.uiTextStyle).scaledValue(
            for: style.size * settings.fontSizeScale,
            compatibleWith: UITraitCollection(
                preferredContentSizeCategory: dynamicTypeSize.uiContentSizeCategory
            )
        )

        return content
            .font(font(size: scaledSize))
            .lineSpacing(max(3, 6 + CGFloat(settings.lineHeightAdjustment * 10)))
    }

    private func font(size: CGFloat) -> Font {
        switch face {
        case .app: return .system(size: size, weight: .regular, design: .default)
        case .reading: return settings.font.proseFont(size: size)
        }
    }
}

extension View {
    func readerProse(
        _ style: DipleTextStyle,
        settings: ReaderSettings,
        face: ReaderProseFace = .reading
    ) -> some View {
        modifier(ReaderProseModifier(style: style, settings: settings, face: face))
    }
}
