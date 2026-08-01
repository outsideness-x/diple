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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Circle()
                    .fill(displayColor)
                    .frame(width: 10, height: 10)

                Text(formattedDate)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.58))

                Spacer()

                Button {
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .regular))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))
                }
            }

            Button {
                onSelect()
            } label: {
                Text("“\(highlight.text)”")
                    .font(.system(size: 14, weight: .regular, design: .serif))
                    .italic()
                    .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))
                    .multilineTextAlignment(.leading)
                    .lineLimit(5)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(displayColor.opacity(0.3), lineWidth: 1)
        )
    }
}
