import SwiftUI
import ReadiumShared
import ReadiumNavigator

public struct HighlightsView: View {
    public let highlights: [Highlight]
    public let onSelectHighlight: (Highlight) -> Void
    public let onDeleteHighlight: (Highlight) -> Void
    @Environment(\.dismiss) private var dismiss

    public init(
        highlights: [Highlight],
        onSelectHighlight: @escaping (Highlight) -> Void,
        onDeleteHighlight: @escaping (Highlight) -> Void
    ) {
        self.highlights = highlights
        self.onSelectHighlight = onSelectHighlight
        self.onDeleteHighlight = onDeleteHighlight
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Highlights & Quotes")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            Divider()
                .background(Color(red: 0.16, green: 0.16, blue: 0.18))

            if highlights.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "quote.bubble")
                        .font(.system(size: 32, weight: .thin))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))
                    Text("No Highlights Yet")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))
                    Text("Select text in the book to save quotes with your favorite colors.")
                        .font(.system(size: 13, weight: .regular))
                        .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.58))
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(highlights) { highlight in
                            HighlightRowView(
                                highlight: highlight,
                                onSelect: {
                                    onSelectHighlight(highlight)
                                    dismiss()
                                },
                                onDelete: {
                                    onDeleteHighlight(highlight)
                                }
                            )
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.vertical, 16)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
    }
}

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
