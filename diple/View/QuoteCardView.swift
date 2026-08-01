import SwiftUI

/// Read-only presentation of a saved quote, used by the hub. The reader's own list
/// (`HighlightRowView`) stays separate because it carries navigation and deletion.
public struct QuoteCardView: View {
    public let quote: Highlight

    public init(quote: Highlight) {
        self.quote = quote
    }

    private var accentColor: Color {
        Color(hex: quote.colorHex)
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: quote.createdAt)
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DipleSpace.m) {
            Capsule()
                .fill(accentColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: DipleSpace.s) {
                Text(quote.text)
                    .dipleType(.readingBody)
                    .readingLineSpacing(for: quote.text)
                    .foregroundStyle(DipleColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(formattedDate)
                    .dipleType(.micro)
                    .foregroundStyle(DipleColor.textQuaternary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DipleSpace.m)
        .craftSurface()
        .contextMenu {
            Button {
                UIPasteboard.general.string = quote.text
                HapticManager.shared.impact(.light)
            } label: {
                Label("Copy Quote", systemImage: "doc.on.doc")
            }
        }
    }
}
