import SwiftUI
import ReadiumShared
import ReadiumNavigator

public struct HighlightRowView: View {
    public let highlight: Highlight
    public let onSelect: () -> Void
    public let onDelete: () -> Void

    private var displayColor: SwiftUI.Color {
        DipleColor.Highlight.color(forHex: highlight.colorHex)
    }

    /// Day and month, and the year only when it is not this one — see `DipleDate`.
    private var formattedDate: String {
        DipleDate.day(highlight.createdAt)
    }

    public var body: some View {
        HStack(alignment: .top, spacing: DipleSpace.m) {
            Capsule()
                .fill(displayColor)
                .frame(width: 3)

            VStack(alignment: .leading, spacing: DipleSpace.s) {
                Button {
                    onSelect()
                } label: {
                    Text(highlight.text)
                        .dipleType(.editorialQuote)
                        .readingLineSpacing(for: highlight.text)
                        .foregroundStyle(DipleColor.textPrimary)
                        .multilineTextAlignment(.leading)
                        .lineLimit(5)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.plain)

                if let comment = highlight.comment, !comment.isEmpty {
                    HStack(alignment: .top, spacing: DipleSpace.s) {
                        Image(systemName: "bubble.left")
                            .dipleIcon(11, weight: .medium)
                            .foregroundStyle(DipleColor.textQuaternary)

                        Text(comment)
                            .dipleType(.callout)
                            .foregroundStyle(DipleColor.textSecondary)
                            .multilineTextAlignment(.leading)
                    }
                }

                HStack(spacing: DipleSpace.s) {
                    Text(formattedDate)
                        .dipleType(.micro)
                        .foregroundStyle(DipleColor.textQuaternary)

                    Spacer()

                    Button {
                        onDelete()
                    } label: {
                        Image(systemName: "trash")
                            .dipleIcon(12)
                            .foregroundStyle(DipleColor.textTertiary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Delete highlight")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DipleSpace.m)
        .craftSurface()
    }
}
