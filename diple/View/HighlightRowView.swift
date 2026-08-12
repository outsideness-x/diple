import SwiftUI
import ReadiumShared
import ReadiumNavigator

public struct HighlightRowView: View {
    public let highlight: Highlight
    public let onSelect: () -> Void
    public let onDelete: () -> Void

    private var displayColor: SwiftUI.Color {
        if let readiumColor = ReadiumNavigator.Color(hex: highlight.colorHex) {
            return SwiftUI.Color(uiColor: readiumColor.uiColor)
        }
        return SwiftUI.Color.yellow
    }

    private var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: highlight.createdAt)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            HStack(spacing: DipleSpace.s) {
                Circle()
                    .fill(displayColor)
                    .frame(width: 10, height: 10)

                Text(formattedDate)
                    .dipleType(.micro)
                    .foregroundStyle(DipleColor.textTertiary)

                Spacer()

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .dipleIcon(12)
                        .foregroundStyle(DipleColor.textTertiary)
                }
            }

            Button {
                onSelect()
            } label: {
                Text("“\(highlight.text)”")
                    .dipleType(.readingBody)
                    .italic()
                    .foregroundStyle(DipleColor.textPrimary)
                    .multilineTextAlignment(.leading)
                    .lineLimit(5)
            }
            .buttonStyle(.plain)

            if let comment = highlight.comment, !comment.isEmpty {
                HStack(alignment: .top, spacing: DipleSpace.s) {
                    Image(systemName: "bubble.left")
                        .dipleIcon(10, weight: .medium)
                        .foregroundStyle(DipleColor.accent)

                    Text(comment)
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textSecondary)
                        .multilineTextAlignment(.leading)
                }
            }
        }
        .padding(DipleSpace.m)
        .craftSurface()
        .overlay(
            RoundedRectangle(cornerRadius: DipleRadius.m)
                .stroke(displayColor.opacity(0.3), lineWidth: 1)
        )
    }
}
