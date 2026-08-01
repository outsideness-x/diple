import SwiftUI
import ReadiumShared

public struct BookOutlineSheetView: View {
    public let tableOfContents: [ReadiumShared.Link]
    public let highlights: [Highlight]
    public let onSelectLink: (ReadiumShared.Link) -> Void
    public let onSelectHighlight: (Highlight) -> Void
    public let onDeleteHighlight: (Highlight) -> Void

    @State private var selectedTab: Int = 0
    @Environment(\.dismiss) private var dismiss

    public init(
        tableOfContents: [ReadiumShared.Link],
        highlights: [Highlight],
        onSelectLink: @escaping (ReadiumShared.Link) -> Void,
        onSelectHighlight: @escaping (Highlight) -> Void,
        onDeleteHighlight: @escaping (Highlight) -> Void
    ) {
        self.tableOfContents = tableOfContents
        self.highlights = highlights
        self.onSelectLink = onSelectLink
        self.onSelectHighlight = onSelectHighlight
        self.onDeleteHighlight = onDeleteHighlight
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header & Tab Segmented Control
            VStack(spacing: 14) {
                HStack {
                    Spacer()
                    Button("Done") {
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))
                }

                Picker("Section", selection: $selectedTab) {
                    Text("Contents").tag(0)
                    Text("Quotes (\(highlights.count))").tag(1)
                }
                .pickerStyle(.segmented)
            }
            .padding(.horizontal, 20)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Divider()
                .background(Color(red: 0.16, green: 0.16, blue: 0.18))

            if selectedTab == 0 {
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
            } else {
                if highlights.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "quote.bubble")
                            .font(.system(size: 32, weight: .thin))
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))
                        Text("No Quotes Saved")
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
        }
        .background(Color.black.ignoresSafeArea())
    }
}
