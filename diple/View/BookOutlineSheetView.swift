import SwiftUI
import ReadiumShared

public struct BookOutlineSheetView: View {
    public let tableOfContents: [ReadiumShared.Link]
    public let highlights: [Highlight]
    public let bookmarks: [Bookmark]
    public let onSelectLink: (ReadiumShared.Link) -> Void
    public let onSelectHighlight: (Highlight) -> Void
    public let onDeleteHighlight: (Highlight) -> Void
    public let onSelectBookmark: (Bookmark) -> Void
    public let onDeleteBookmark: (Bookmark) -> Void

    @State private var selectedTab: Int = 0
    @Environment(\.dismiss) private var dismiss

    public init(
        tableOfContents: [ReadiumShared.Link],
        highlights: [Highlight],
        bookmarks: [Bookmark] = [],
        onSelectLink: @escaping (ReadiumShared.Link) -> Void,
        onSelectHighlight: @escaping (Highlight) -> Void,
        onDeleteHighlight: @escaping (Highlight) -> Void,
        onSelectBookmark: @escaping (Bookmark) -> Void = { _ in },
        onDeleteBookmark: @escaping (Bookmark) -> Void = { _ in }
    ) {
        self.tableOfContents = tableOfContents
        self.highlights = highlights
        self.bookmarks = bookmarks
        self.onSelectLink = onSelectLink
        self.onSelectHighlight = onSelectHighlight
        self.onDeleteHighlight = onDeleteHighlight
        self.onSelectBookmark = onSelectBookmark
        self.onDeleteBookmark = onDeleteBookmark
    }

    public var body: some View {
        VStack(spacing: 0) {
            // Header & Tab Segmented Control
            VStack(spacing: 14) {
                HStack {
                    Spacer()
                    Button("Done") {
                        HapticManager.shared.selection()
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))
                }

                Picker("Section", selection: $selectedTab) {
                    Text("Contents").tag(0)
                    Text("Quotes (\(highlights.count))").tag(1)
                    Text("Bookmarks (\(bookmarks.count))").tag(2)
                }
                .pickerStyle(.segmented)
                .tint(Color.dipleAccent)
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
            } else if selectedTab == 1 {
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
            } else {
                // Bookmarks Tab
                if bookmarks.isEmpty {
                    VStack(spacing: 12) {
                        Spacer()
                        Image(systemName: "bookmark")
                            .font(.system(size: 32, weight: .thin))
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))
                        Text("No Bookmarks Saved")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))
                        Text("Tap the bookmark icon in the reading controls overlay to save bookmarks with custom titles and color tags.")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.58))
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 32)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 12) {
                            ForEach(bookmarks) { bookmark in
                                BookmarkRowView(
                                    bookmark: bookmark,
                                    onSelect: {
                                        onSelectBookmark(bookmark)
                                        dismiss()
                                    },
                                    onDelete: {
                                        onDeleteBookmark(bookmark)
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

public struct BookmarkRowView: View {
    public let bookmark: Bookmark
    public let onSelect: () -> Void
    public let onDelete: () -> Void

    public init(bookmark: Bookmark, onSelect: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.bookmark = bookmark
        self.onSelect = onSelect
        self.onDelete = onDelete
    }

    public var body: some View {
        Button {
            HapticManager.shared.selection()
            onSelect()
        } label: {
            HStack(spacing: 14) {
                // Color Tag Circle
                Circle()
                    .fill(Color(hex: bookmark.colorHex))
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 4) {
                    Text(bookmark.name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    if let title = bookmark.parsedLocator?.title, !title.isEmpty {
                        Text(title)
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.65))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button {
                    HapticManager.shared.impact(.light)
                    onDelete()
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 14))
                        .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.58))
                        .padding(8)
                }
            }
            .padding(14)
            .background(Color(red: 0.12, green: 0.12, blue: 0.14))
            .cornerRadius(10)
        }
        .buttonStyle(.plain)
    }
}
