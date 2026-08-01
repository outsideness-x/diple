import SwiftUI
import ReadiumShared

public struct TOCRowView: View {
    public let link: ReadiumShared.Link
    public let depth: Int
    public let onSelect: (ReadiumShared.Link) -> Void

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button {
                onSelect(link)
            } label: {
                HStack(spacing: 8) {
                    Text(link.title ?? link.href)
                        .font(.system(size: depth == 0 ? 15 : 14, weight: depth == 0 ? .medium : .regular))
                        .foregroundColor(depth == 0 ? Color(red: 0.92, green: 0.92, blue: 0.92) : Color(red: 0.75, green: 0.75, blue: 0.78))
                        .multilineTextAlignment(.leading)
                        .padding(.leading, CGFloat(depth * 16))
                    Spacer()
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()
                .background(Color(red: 0.12, green: 0.12, blue: 0.14))
                .padding(.leading, CGFloat(20 + depth * 16))

            if !link.children.isEmpty {
                ForEach(link.children, id: \.self) { childLink in
                    TOCRowView(link: childLink, depth: depth + 1, onSelect: onSelect)
                }
            }
        }
    }
}
