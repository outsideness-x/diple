import SwiftUI
import ReadiumShared

public struct TOCView: View {
    public let tableOfContents: [ReadiumShared.Link]
    public let onSelectLink: (ReadiumShared.Link) -> Void
    @Environment(\.dismiss) private var dismiss

    public init(tableOfContents: [ReadiumShared.Link], onSelectLink: @escaping (ReadiumShared.Link) -> Void) {
        self.tableOfContents = tableOfContents
        self.onSelectLink = onSelectLink
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Table of Contents")
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

            if tableOfContents.isEmpty {
                VStack(spacing: 12) {
                    Spacer()
                    Image(systemName: "list.bullet.indent")
                        .font(.system(size: 32, weight: .thin))
                        .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))
                    Text("No Table of Contents")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.65))
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(tableOfContents, id: \.self) { link in
                            TOCRowView(link: link, depth: 0) { selectedLink in
                                onSelectLink(selectedLink)
                                dismiss()
                            }
                        }
                    }
                    .padding(.vertical, 8)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
    }
}

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
