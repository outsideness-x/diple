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
        HStack(alignment: .top, spacing: 12) {
            RoundedRectangle(cornerRadius: 1.5)
                .fill(accentColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: 8) {
                Text(quote.text)
                    .font(.system(size: 15, weight: .regular, design: .serif))
                    .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)

                Text(formattedDate)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.45, green: 0.45, blue: 0.5))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(14)
        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
        .cornerRadius(12)
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
