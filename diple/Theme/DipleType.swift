import SwiftUI
import UIKit

/// The type system.
///
/// Three things this fixes that `.font(.system(size: 14, weight: .medium))` at a call site
/// cannot:
///
/// 1. **Dynamic Type.** `Font.system(size:)` is a fixed point size — it does not respond to
///    the reader's text-size setting at all. Every role here runs its size through
///    `UIFontMetrics` against a matching `TextStyle`, so the app scales the way the system
///    intends while keeping the exact sizes the design calls for.
/// 2. **Tracking.** Letter-spacing is a property of a size, not a decision per label. Large
///    type is set tight so headings read as one mass; small type is opened up so it stays
///    legible. Stored as a *ratio* of the size, per the design rule (−1%…−3% for headings,
///    +1%…+3% for small caps), so tracking scales together with the glyphs.
/// 3. **Two families, and the second one is named at every site that uses it.** The interface is
///    San Francisco. The reading roles below used to be `design: .serif`, which on iOS is New
///    York — a second typeface appearing without warning in quote cards, cover placeholders and
///    search results, and one with no Hangul coverage, so Korean fell back to a third face
///    inside a single line. That is why blanket serif is still forbidden, and why the reading
///    roles differ from the interface ones by size, weight and measure rather than by family.
///
///    The `editorial*` roles are the exception, and they are an enumerated list rather than a
///    category: the wordmark, the lead's headline, a saved passage, a note's own title, and the
///    heading of an empty state or a colophon. Nowhere else. A publisher has a voice in type and
///    the app had none; five places is what buys the voice without the leak.
///
///    The Hangul problem does not follow the face here, and the difference is the whole reason
///    this is safe. New York broke Korean *inside the reader's web view*, where the CSS keyword
///    that selects it swallows the rest of the cascade (see "Шрифт читалки" in CLAUDE.md). In a
///    SwiftUI `Text` there is no cascade to swallow: CoreText falls back per glyph, exactly as
///    `Caveat` — which has no Hangul either — already does for a Korean note. So an editorial
///    role sets Latin and Cyrillic in Literata and lets Korean arrive in the system face. A
///    mixed line is the cost, and it is affordable at a headline and unaffordable down a column
///    of labels, which is precisely the line the enumerated list draws.
public enum DipleFontFamily: Sendable {
    /// San Francisco. Everything not named in the editorial list.
    case system
    /// Literata, bundled. A reading serif drawn for Google Play Books, so it is a publisher's
    /// face by construction rather than by association; full Cyrillic and Greek, no Hangul.
    case editorial

    /// Literata ships as one variable file, and iOS knows it by its family name.
    private static let editorialFamily = "Literata"

    /// The font for this family at an **already scaled** size.
    ///
    /// `Font.custom(_:size:)` — the bare form, not `custom(_:size:relativeTo:)`. That looks like
    /// the Dynamic Type mistake this file exists to prevent, and here it is the opposite: the
    /// size handed in has already been through `UIFontMetrics` in `scaledSize(for:)`, so the
    /// scaling form would apply the reader's setting a second time and compound it.
    func font(size: CGFloat, weight: Font.Weight, design: Font.Design) -> Font {
        switch self {
        case .system:
            return .system(size: size, weight: weight, design: design)
        case .editorial:
            return .custom(Self.editorialFamily, size: size).weight(weight)
        }
    }
}

public struct DipleTextStyle: Sendable {
    public let size: CGFloat
    public let weight: Font.Weight
    public let design: Font.Design
    /// Which of the two faces sets this role.
    public let family: DipleFontFamily
    /// The system style this role scales against.
    public let metrics: Font.TextStyle
    /// Letter-spacing as a fraction of the rendered size. Negative tightens.
    public let trackingRatio: CGFloat

    public init(
        size: CGFloat,
        weight: Font.Weight,
        design: Font.Design = .default,
        family: DipleFontFamily = .system,
        metrics: Font.TextStyle,
        trackingRatio: CGFloat
    ) {
        self.size = size
        self.weight = weight
        self.design = design
        self.family = family
        self.metrics = metrics
        self.trackingRatio = trackingRatio
    }

    // MARK: - Interface roles (sans)

    /// 32 — a screen's own title, at rest: a collection header standing alone at the top of a
    /// page, with nothing beside it. Reserved for a plain word or two — "Notes", "Highlights" —
    /// never for a title that shares its block with a cover or a dateline; that is `display`.
    public static let hero = DipleTextStyle(size: 32, weight: .bold, metrics: .largeTitle, trackingRatio: -0.030)
    /// 26 — the largest thing in a block that is not a bare screen title. The Continue lead's
    /// title.
    public static let display = DipleTextStyle(size: 26, weight: .semibold, metrics: .title, trackingRatio: -0.025)
    /// 20 — empty-state headings, sheet titles.
    public static let title = DipleTextStyle(size: 20, weight: .semibold, metrics: .title3, trackingRatio: -0.02)
    /// 17 — section headings.
    public static let headline = DipleTextStyle(size: 17, weight: .semibold, metrics: .headline, trackingRatio: -0.015)
    /// 15 — the default interface size. Row titles, primary labels.
    public static let body = DipleTextStyle(size: 15, weight: .regular, metrics: .subheadline, trackingRatio: -0.005)
    /// 14 — secondary labels, descriptive copy in sheets.
    public static let callout = DipleTextStyle(size: 14, weight: .regular, metrics: .subheadline, trackingRatio: 0)
    /// 13 — buttons, toasts, dense list rows.
    public static let footnote = DipleTextStyle(size: 13, weight: .medium, metrics: .footnote, trackingRatio: 0.005)
    /// 12 — authors, secondary metadata.
    public static let caption = DipleTextStyle(size: 12, weight: .regular, metrics: .caption, trackingRatio: 0.01)
    /// 11 — chips, counters, dates.
    public static let micro = DipleTextStyle(size: 11, weight: .medium, metrics: .caption2, trackingRatio: 0.02)
    /// 10 — the smallest readable label: percentages, timestamps on a card.
    public static let nano = DipleTextStyle(size: 10, weight: .semibold, metrics: .caption2, trackingRatio: 0.03)
    /// 9 — glyph-adjacent labels inside a chip. Never on its own line.
    public static let tag = DipleTextStyle(size: 9, weight: .semibold, metrics: .caption2, trackingRatio: 0.03)

    // MARK: - Content roles

    /// 22 — a book title given room, on a cover placeholder or a detail header.
    public static let readingTitle = DipleTextStyle(size: 22, weight: .semibold, metrics: .title2, trackingRatio: -0.015)
    /// 16 — quoted passages from publications. A step above `body`, and set with the open
    /// tracking of running text rather than the tightened tracking of a label.
    public static let readingBody = DipleTextStyle(size: 16, weight: .regular, metrics: .subheadline, trackingRatio: 0)
    /// 19 — a passage set as a pull quote: the one thing on the page that is meant to be read
    /// rather than scanned. A step above `readingBody` and deliberately *not* a step towards
    /// `readingTitle` — weight is what a heading uses to be a heading, and a quote borrowing it
    /// starts announcing itself instead of speaking. Size and the open tracking of running text
    /// do the work; the weight stays regular.
    public static let readingQuote = DipleTextStyle(size: 19, weight: .regular, metrics: .body, trackingRatio: 0)
    /// 14 — a quote compressed into a list row.
    public static let readingCaption = DipleTextStyle(size: 14, weight: .regular, metrics: .footnote, trackingRatio: 0)

    // MARK: - Editorial roles (Literata)
    //
    // The complete list. A fifth one is a decision, not a convenience — see the note on
    // `DipleFontFamily` above about why this stays enumerated.
    //
    // **The sizes here are not the sizes they replace, and the reason is set width rather than
    // taste.** Measured with CoreText at 26 pt on "Artificial Rosetta Stone": SF semibold sets
    // it in 270.4 pt, Literata medium in 290.7 — 7.5% wider, which costs about a word of
    // measure on every headline in the app. Apparent size is *not* what differs: the two faces
    // have the same cap height (0.705 em) and near-identical x-height (0.510 against 0.519), so
    // matching by point size would have been matching the wrong quantity. Each role below is
    // set to the size at which Literata occupies the measure its predecessor did.

    /// 34 — the wordmark, on the front page and nowhere else. A publication prints its name
    /// once, at the top of page one, not in the running head of every screen.
    public static let wordmark = DipleTextStyle(
        size: 34, weight: .regular, family: .editorial,
        metrics: .largeTitle, trackingRatio: -0.02
    )

    /// 24 — the headline of the lead item, and of the colophon's own title. This is the block
    /// the front page is about, and the place a serif earns most: a title of a *work*, not a
    /// label on a control.
    ///
    /// 24, not the 26 of the `display` it replaces. At 26 it sets 7.5% wider than the SF it
    /// took over from, and this headline was already the one thing on Home allowed to run to
    /// three lines and truncate. At 24 the measure matches to within a point, so no title
    /// anywhere reflows; the 8% of cap height given up is invisible beside a 17 pt quote.
    public static let editorialLead = DipleTextStyle(
        size: 24, weight: .medium, family: .editorial,
        metrics: .title, trackingRatio: -0.015
    )

    /// 17 — a saved passage, set as the quotation it is. Regular weight and open tracking, for
    /// the reason recorded on `readingQuote`: weight is how a heading announces itself, and a
    /// quote borrowing it starts declaiming instead of speaking.
    ///
    /// Deliberately not the 19 of `readingQuote`. Home's quote was moved *down* to 16 once
    /// before, because at 19 it ran to eight unbounded lines and took nearly half the screen
    /// from the lead — see the note on hierarchy in CLAUDE.md. Literata sets 10% wider again,
    /// so 19 here would be worse than the 19 that was rejected. 17 keeps the step up from body
    /// copy that says "this is quoted" while leaving the lead its rank.
    public static let editorialQuote = DipleTextStyle(
        size: 17, weight: .regular, family: .editorial,
        metrics: .body, trackingRatio: 0
    )

    /// 20 — the heading of an empty state or of the colophon. The one place an editorial face
    /// sets interface copy, and it is allowed because it is alone on its screen.
    public static let editorialTitle = DipleTextStyle(
        size: 20, weight: .medium, family: .editorial,
        metrics: .title3, trackingRatio: -0.01
    )

    // MARK: - Note roles (system sans)
    //
    // The body of a note stays San Francisco deliberately. A note is what the reader wrote, not
    // what a publisher set, and it is the text most likely to mix three scripts in one
    // paragraph — the case an editorial face handles worst.

    /// 24 — the editable title of a note.
    public static let noteTitle = DipleTextStyle(size: 24, weight: .semibold, metrics: .title2, trackingRatio: -0.018)
    /// 20 — second-level and smaller Markdown headings.
    public static let noteHeading = DipleTextStyle(size: 20, weight: .semibold, metrics: .title3, trackingRatio: -0.012)
    /// 17 — note prose and Markdown source in the editor.
    public static let noteBody = DipleTextStyle(size: 17, weight: .regular, metrics: .body, trackingRatio: 0)

    // MARK: - Resolution

    /// The point size this role renders at under the given Dynamic Type setting.
    public func scaledSize(for typeSize: DynamicTypeSize) -> CGFloat {
#if targetEnvironment(macCatalyst)
        // Catalyst otherwise inherits the compact iPad scale, which looks undersized in a
        // desktop window viewed from farther away than a handheld screen.
        let platformSize = size * 1.16
#else
        let platformSize = size
#endif
        return UIFontMetrics(forTextStyle: metrics.uiTextStyle).scaledValue(
            for: platformSize,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: typeSize.uiContentSizeCategory)
        )
    }

    /// The font for this role, already scaled. `weight` overrides the role's default for the
    /// cases where the same size carries two emphases in one screen.
    public func font(for typeSize: DynamicTypeSize, weight override: Font.Weight? = nil) -> Font {
        family.font(
            size: scaledSize(for: typeSize),
            weight: override ?? weight,
            design: design
        )
    }

    /// Letter-spacing in points at the rendered size.
    public func tracking(for typeSize: DynamicTypeSize) -> CGFloat {
        scaledSize(for: typeSize) * trackingRatio
    }
}

// MARK: - Application

private struct DipleTypeModifier: ViewModifier {
    let style: DipleTextStyle
    let weightOverride: Font.Weight?

    @Environment(\.dynamicTypeSize) private var typeSize

    func body(content: Content) -> some View {
        content
            .font(style.font(for: typeSize, weight: weightOverride))
            .tracking(style.tracking(for: typeSize))
    }
}

public extension View {
    /// Applies a type role: scaled font and its paired tracking, together.
    ///
    /// Font and tracking are never applied separately — a size without its tracking is half
    /// the role, and that is exactly the difference between type that has been set and type
    /// that has merely been sized.
    func dipleType(_ style: DipleTextStyle, weight: Font.Weight? = nil) -> some View {
        modifier(DipleTypeModifier(style: style, weightOverride: weight))
    }
}

/// SF Symbols and other glyphs. Tracking is meaningless on a single glyph, so icons take a
/// size directly — but still scale, otherwise an icon beside scaled text ends up a stamp.
public struct DipleIcon: ViewModifier {
    let size: CGFloat
    let weight: Font.Weight

    @Environment(\.dynamicTypeSize) private var typeSize

    public func body(content: Content) -> some View {
#if targetEnvironment(macCatalyst)
        let platformSize = size * 1.16
#else
        let platformSize = size
#endif
        let scaled = UIFontMetrics(forTextStyle: .body).scaledValue(
            for: platformSize,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: typeSize.uiContentSizeCategory)
        )
        return content.font(.system(size: scaled, weight: weight))
    }
}

public extension View {
    /// Sizes a glyph so it tracks Dynamic Type alongside the text it sits with.
    func dipleIcon(_ size: CGFloat, weight: Font.Weight = .medium) -> some View {
        modifier(DipleIcon(size: size, weight: weight))
    }
}

// MARK: - Bridges to UIKit metrics

extension Font.TextStyle {
    /// `UIFontMetrics` is the only API that scales an arbitrary point size, and it speaks
    /// `UIFont.TextStyle`.
    var uiTextStyle: UIFont.TextStyle {
        switch self {
        case .largeTitle: return .largeTitle
        case .title: return .title1
        case .title2: return .title2
        case .title3: return .title3
        case .headline: return .headline
        case .subheadline: return .subheadline
        case .body: return .body
        case .callout: return .callout
        case .footnote: return .footnote
        case .caption: return .caption1
        case .caption2: return .caption2
        @unknown default: return .body
        }
    }
}

extension DynamicTypeSize {
    var uiContentSizeCategory: UIContentSizeCategory {
        switch self {
        case .xSmall: return .extraSmall
        case .small: return .small
        case .medium: return .medium
        case .large: return .large
        case .xLarge: return .extraLarge
        case .xxLarge: return .extraExtraLarge
        case .xxxLarge: return .extraExtraExtraLarge
        case .accessibility1: return .accessibilityMedium
        case .accessibility2: return .accessibilityLarge
        case .accessibility3: return .accessibilityExtraLarge
        case .accessibility4: return .accessibilityExtraExtraLarge
        case .accessibility5: return .accessibilityExtraExtraExtraLarge
        @unknown default: return .large
        }
    }
}

private struct DipleTypeSpecimen: View {
    private let roles: [(String, DipleTextStyle)] = [
        ("hero", .hero), ("display", .display), ("title", .title), ("headline", .headline),
        ("body", .body), ("callout", .callout), ("footnote", .footnote),
        ("caption", .caption), ("micro", .micro), ("nano", .nano), ("tag", .tag)
    ]
    private let content: [(String, DipleTextStyle)] = [
        ("readingTitle", .readingTitle), ("readingQuote", .readingQuote),
        ("readingBody", .readingBody), ("readingCaption", .readingCaption)
    ]
    private let editorial: [(String, DipleTextStyle)] = [
        ("wordmark", .wordmark), ("editorialLead", .editorialLead),
        ("editorialQuote", .editorialQuote), ("editorialTitle", .editorialTitle)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: DipleSpace.xxl) {
                VStack(alignment: .leading, spacing: DipleSpace.m) {
                    Text("INTERFACE — SANS")
                        .dipleType(.nano)
                        .foregroundStyle(DipleColor.textTertiary)

                    ForEach(roles, id: \.0) { role in
                        Text("\(role.0) · the quick brown fox")
                            .dipleType(role.1)
                            .foregroundStyle(DipleColor.textPrimary)
                    }
                }

                VStack(alignment: .leading, spacing: DipleSpace.m) {
                    Text("CONTENT")
                        .dipleType(.nano)
                        .foregroundStyle(DipleColor.textTertiary)

                    ForEach(content, id: \.0) { role in
                        Text("\(role.0) · 책을 읽는 사람")
                            .dipleType(role.1)
                            .foregroundStyle(DipleColor.textPrimary)
                    }
                }

                // Three scripts on purpose. Latin and Cyrillic must be Literata; Hangul must
                // fall back to the system face cleanly rather than to tofu. That fallback is
                // the whole assumption the editorial roles rest on, so it is looked at rather
                // than assumed.
                VStack(alignment: .leading, spacing: DipleSpace.m) {
                    Text("EDITORIAL — LITERATA")
                        .dipleType(.nano)
                        .foregroundStyle(DipleColor.textTertiary)

                    ForEach(editorial, id: \.0) { role in
                        Text("«Пиранези» · 책을 읽는 · \(role.0)")
                            .dipleType(role.1)
                            .foregroundStyle(DipleColor.textPrimary)
                    }
                }
            }
            .padding(DipleSpace.xl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(DipleColor.canvas)
    }
}

#Preview("Type scale") {
    DipleTypeSpecimen()
        .preferredColorScheme(.dark)
}
