import SwiftUI

/// What a search says when it has found nothing: one line in the editorial face, one plain
/// sentence under it, and nothing drawn.
///
/// Every one of these carried an SF Symbol — a magnifying glass over the Search tab, another
/// over an empty library shelf, a third in an accent tile on the Mac — which is the platform's
/// stock empty state and, on a page of a reading app, the only picture on it. A search that
/// found nothing says so in words, and where there was a query it says what was looked for.
///
/// A *room* that is empty keeps its glyph — Highlights' quotation mark, the Mac's empty shelves:
/// there the picture is of what will live in the room once something does. A search has no such
/// thing to show.
struct DipleEmptyText: View {
    let title: String
    let message: String
    var alignment: TextAlignment = .center

    private var stackAlignment: HorizontalAlignment {
        switch alignment {
        case .leading: return .leading
        case .trailing: return .trailing
        default: return .center
        }
    }

    var body: some View {
        VStack(alignment: stackAlignment, spacing: DipleSpace.s) {
            Text(title)
                .dipleType(.editorialTitle)
                .foregroundStyle(DipleColor.textPrimary)

            Text(message)
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
        }
        .multilineTextAlignment(alignment)
        .fixedSize(horizontal: false, vertical: true)
        .accessibilityElement(children: .combine)
    }
}
