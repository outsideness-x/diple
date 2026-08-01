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
                HStack(spacing: DipleSpace.s) {
                    Text(link.title ?? link.href)
                        .dipleType(depth == 0 ? .body : .callout, weight: depth == 0 ? .medium : .regular)
                        .foregroundStyle(depth == 0 ? DipleColor.textPrimary : DipleColor.textSecondary)
                        .multilineTextAlignment(.leading)
                        .padding(.leading, CGFloat(depth * 16))
                    Spacer()
                }
                .padding(.horizontal, DipleSpace.xl)
                .padding(.vertical, DipleSpace.m)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Divider()
                .background(DipleColor.surfaceRaised)
                .padding(.leading, CGFloat(20 + depth * 16))

            if !link.children.isEmpty {
                ForEach(link.children, id: \.self) { childLink in
                    TOCRowView(link: childLink, depth: depth + 1, onSelect: onSelect)
                }
            }
        }
    }
}
