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
            VStack(spacing: DipleSpace.m) {
                HStack {
                    Spacer()
                    Button("Done") {
                        HapticManager.shared.selection()
                        dismiss()
                    }
                    .dipleType(.body, weight: .medium)
                    .foregroundStyle(DipleColor.textPrimary)
                }

                Picker("Section", selection: $selectedTab) {
                    Text("Contents").tag(0)
                    Text("Quotes (\(highlights.count))").tag(1)
                    Text("Bookmarks (\(bookmarks.count))").tag(2)
                }
                .pickerStyle(.segmented)
                .tint(DipleColor.accent)
                .onChange(of: selectedTab) { _, _ in
                    HapticManager.shared.selection()
                }
            }
            .padding(.horizontal, DipleSpace.xl)
            .padding(.top, DipleSpace.l)
            .padding(.bottom, DipleSpace.m)

            Divider()
                .background(DipleColor.surfaceOverlay)

            if selectedTab == 0 {
                if tableOfContents.isEmpty {
                    VStack(spacing: DipleSpace.m) {
                        Spacer()
                        Image(systemName: "list.bullet.indent")
                            .dipleIcon(32, weight: .thin)
                            .foregroundStyle(DipleColor.textTertiary)
                        Text("No Table of Contents")
                            .dipleType(.body, weight: .medium)
                            .foregroundStyle(DipleColor.textTertiary)
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
                        .padding(.vertical, DipleSpace.s)
                    }
                }
            } else if selectedTab == 1 {
                if highlights.isEmpty {
                    VStack(spacing: DipleSpace.m) {
                        Spacer()
                        Image(systemName: "quote.bubble")
                            .dipleIcon(32, weight: .thin)
                            .foregroundStyle(DipleColor.textTertiary)
                        Text("No Quotes Saved")
                            .dipleType(.body, weight: .semibold)
                            .foregroundStyle(DipleColor.textPrimary)
                        Text("Select text in the book to save quotes with your favorite colors.")
                            .dipleType(.footnote, weight: .regular)
                            .foregroundStyle(DipleColor.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DipleSpace.xxxl)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: DipleSpace.m) {
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
                        .padding(.horizontal, DipleSpace.xl)
                        .padding(.vertical, DipleSpace.l)
                    }
                }
            } else {
                // Bookmarks Tab
                if bookmarks.isEmpty {
                    VStack(spacing: DipleSpace.m) {
                        Spacer()
                        Image(systemName: "bookmark")
                            .dipleIcon(32, weight: .thin)
                            .foregroundStyle(DipleColor.textTertiary)
                        Text("No Bookmarks Saved")
                            .dipleType(.body, weight: .semibold)
                            .foregroundStyle(DipleColor.textPrimary)
                        Text("Tap the bookmark icon in the reading controls overlay to save bookmarks with custom titles and color tags.")
                            .dipleType(.footnote, weight: .regular)
                            .foregroundStyle(DipleColor.textTertiary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, DipleSpace.xxxl)
                        Spacer()
                    }
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: DipleSpace.m) {
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
                        .padding(.horizontal, DipleSpace.xl)
                        .padding(.vertical, DipleSpace.l)
                    }
                }
            }
        }
        .background(DipleColor.canvas.opacity(0.6).ignoresSafeArea())
        .presentationBackground(.regularMaterial)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
        .animation(DipleMotion.standard, value: selectedTab)
        .animation(DipleMotion.standard, value: bookmarks)
        .animation(DipleMotion.standard, value: highlights)
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

    private var subtitle: String? {
        guard let locator = bookmark.parsedLocator else { return nil }
        let chapter = locator.title?.trimmingCharacters(in: .whitespacesAndNewlines)
        let position = locator.locations.totalProgression
            .map { "\(Int((min(max($0, 0), 1)) * 100))%" }

        return [chapter?.isEmpty == false ? chapter : nil, position]
            .compactMap { $0 }
            .joined(separator: " · ")
            .nilIfEmpty
    }

    public var body: some View {
        // The delete button must be a sibling of the tappable row, not nested inside
        // another Button's label — a Button inside a Button label never receives taps,
        // so tapping the trash icon used to navigate to the bookmark instead.
        HStack(spacing: DipleSpace.m) {
            Button {
                HapticManager.shared.selection()
                onSelect()
            } label: {
                HStack(spacing: DipleSpace.m) {
                    // Color Tag Circle
                    Circle()
                        .fill(Color(hex: bookmark.colorHex))
                        .frame(width: 12, height: 12)

                    VStack(alignment: .leading, spacing: DipleSpace.xs) {
                        Text(bookmark.name)
                            .dipleType(.body, weight: .semibold)
                            .foregroundStyle(DipleColor.textPrimary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        if let subtitle {
                            Text(subtitle)
                                .dipleType(.caption)
                                .foregroundStyle(DipleColor.textTertiary)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                HapticManager.shared.impact(.light)
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .dipleIcon(14)
                    .foregroundStyle(DipleColor.textTertiary)
                    .padding(DipleSpace.s)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(DipleSpace.m)
        .background(DipleColor.surfaceRaised)
        .cornerRadius(DipleRadius.m)
    }
}

extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
