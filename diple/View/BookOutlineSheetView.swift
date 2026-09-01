import SwiftUI
import ReadiumShared

/// The book's own apparatus: where it goes, what was marked in it, and what was written
/// about it. Everything here is reached from one control, because all four answer the same
/// question — "what is in this book, mine included".
public struct BookOutlineSheetView: View {
    public let tableOfContents: [ReadiumShared.Link]
    public let highlights: [Highlight]
    public let notes: [NoteItem]
    public let bookmarks: [Bookmark]
    public let onSelectLink: (ReadiumShared.Link) -> Void
    public let onSelectHighlight: (Highlight) -> Void
    public let onDeleteHighlight: (Highlight) -> Void
    public let onSelectNote: (NoteItem) -> Void
    public let onDeleteNote: (NoteItem) -> Void
    public let onNewNote: () -> Void
    public let onSelectBookmark: (Bookmark) -> Void
    public let onDeleteBookmark: (Bookmark) -> Void

    @State private var selectedTab: Section = .contents
    /// The note a trash tap is asking about. Writing is not re-creatable the way a quote is,
    /// so it is confirmed here as it is on the notes board.
    @State private var noteToDelete: NoteItem?
    @Environment(\.dismiss) private var dismiss

    /// Named rather than numbered. A fourth pane went in between two existing ones, and with
    /// integer tags that is a silent renumbering of every branch below.
    private enum Section: Hashable {
        case contents
        case quotes
        case notes
        case bookmarks
    }

    public init(
        tableOfContents: [ReadiumShared.Link],
        highlights: [Highlight],
        notes: [NoteItem] = [],
        bookmarks: [Bookmark] = [],
        onSelectLink: @escaping (ReadiumShared.Link) -> Void,
        onSelectHighlight: @escaping (Highlight) -> Void,
        onDeleteHighlight: @escaping (Highlight) -> Void,
        onSelectNote: @escaping (NoteItem) -> Void = { _ in },
        onDeleteNote: @escaping (NoteItem) -> Void = { _ in },
        onNewNote: @escaping () -> Void = {},
        onSelectBookmark: @escaping (Bookmark) -> Void = { _ in },
        onDeleteBookmark: @escaping (Bookmark) -> Void = { _ in }
    ) {
        self.tableOfContents = tableOfContents
        self.highlights = highlights
        self.notes = notes
        self.bookmarks = bookmarks
        self.onSelectLink = onSelectLink
        self.onSelectHighlight = onSelectHighlight
        self.onDeleteHighlight = onDeleteHighlight
        self.onSelectNote = onSelectNote
        self.onDeleteNote = onDeleteNote
        self.onNewNote = onNewNote
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

                // Counts without brackets, which is two characters a segment and the
                // difference between four labels that fit on the narrowest phone and four
                // that truncate. An empty section drops its count entirely rather than
                // printing a zero: "Notes" already says there are none once it is opened,
                // and "Notes 0" spends width saying it twice.
                Picker("Section", selection: $selectedTab) {
                    Text("Contents").tag(Section.contents)
                    Text(label("Quotes", highlights.count)).tag(Section.quotes)
                    Text(label("Notes", notes.count)).tag(Section.notes)
                    Text(label("Bookmarks", bookmarks.count)).tag(Section.bookmarks)
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

            switch selectedTab {
            case .contents:
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

            case .quotes:
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

            case .notes:
                notesSection

            case .bookmarks:
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
        .animation(DipleMotion.standard, value: notes)
        .confirmationDialog(
            "Delete this note?",
            isPresented: Binding(
                get: { noteToDelete != nil },
                set: { if !$0 { noteToDelete = nil } }
            ),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let note = noteToDelete { onDeleteNote(note) }
                noteToDelete = nil
            }
            Button("Cancel", role: .cancel) { noteToDelete = nil }
        } message: {
            // A quote can be marked again off the page it came from; writing cannot. The
            // notes board asks before deleting for the same reason, and the two surfaces
            // must not disagree about how much a note is worth.
            Text("This note and its tags will be removed everywhere, not only from this book.")
        }
    }

    /// `Quotes 3`, and plain `Quotes` when there are none.
    private func label(_ name: String, _ count: Int) -> String {
        count > 0 ? "\(name) \(count)" : name
    }

    /// What has been written about this book — the same rows the notes tab holds, not a
    /// reader-local copy of them. Selecting one hands it back to the reader, which closes this
    /// sheet and opens the note; that is what every other row here does with what it points at.
    @ViewBuilder
    private var notesSection: some View {
        if notes.isEmpty {
            VStack(spacing: DipleSpace.m) {
                Spacer()
                Image(systemName: "square.and.pencil")
                    .dipleIcon(32, weight: .thin)
                    .foregroundStyle(DipleColor.textTertiary)
                Text("No Notes Yet")
                    .dipleType(.body, weight: .semibold)
                    .foregroundStyle(DipleColor.textPrimary)
                Text("A note written here is filed under this book and tagged with its name, and it waits for you in Notes with everything else you have written.")
                    .dipleType(.footnote, weight: .regular)
                    .foregroundStyle(DipleColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DipleSpace.xxxl)
                newNoteButton
                    .padding(.top, DipleSpace.s)
                    .padding(.horizontal, DipleSpace.xxxl)
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: DipleSpace.m) {
                    // At the top of the list rather than only in the empty state: a reader
                    // who came here to re-read a thought is the likeliest person to have
                    // another one.
                    newNoteButton

                    ForEach(notes) { item in
                        NoteOutlineRowView(
                            item: item,
                            onSelect: {
                                onSelectNote(item)
                                dismiss()
                            },
                            onDelete: { noteToDelete = item }
                        )
                    }
                }
                .padding(.horizontal, DipleSpace.xl)
                .padding(.vertical, DipleSpace.l)
            }
        }
    }

    private var newNoteButton: some View {
        Button {
            HapticManager.shared.selection()
            onNewNote()
            dismiss()
        } label: {
            HStack(spacing: DipleSpace.s) {
                Image(systemName: "square.and.pencil")
                    .dipleIcon(13, weight: .semibold)
                Text("Write a note")
                    .dipleType(.footnote, weight: .semibold)
            }
            .foregroundStyle(DipleColor.accent)
            .frame(maxWidth: .infinity, minHeight: 48)
            .background(DipleColor.accentSoft, in: RoundedRectangle(cornerRadius: DipleRadius.m))
        }
        .buttonStyle(.readerControl)
        .accessibilityIdentifier("reader.outline.newNote")
    }
}

/// One note in the book's apparatus.
///
/// Set as a card, like the quote and bookmark rows beside it, rather than as the catalogue
/// entry the notes board uses: inside this sheet a note is an object of the same kind as a
/// quote, and a bare row among cards reads as a different kind of thing.
public struct NoteOutlineRowView: View {
    public let item: NoteItem
    public let onSelect: () -> Void
    public let onDelete: () -> Void

    public init(item: NoteItem, onSelect: @escaping () -> Void, onDelete: @escaping () -> Void) {
        self.item = item
        self.onSelect = onSelect
        self.onDelete = onDelete
    }

    /// Age first, then tags — the notes board's order, and for its reason: the tags are the
    /// part that can afford to be lost to truncation. The book is not printed at all; this
    /// list is inside it.
    private var dateline: String {
        var parts = [item.note.updatedAt.formatted(.relative(presentation: .named, unitsStyle: .wide))]
        parts.append(contentsOf: item.tags.map { "#\($0)" })
        return parts.joined(separator: " · ")
    }

    public var body: some View {
        // The delete button is a sibling of the tappable row, never nested inside another
        // Button's label — see `BookmarkRowView` for what that costs.
        HStack(alignment: .top, spacing: DipleSpace.s) {
            Button {
                HapticManager.shared.selection()
                onSelect()
            } label: {
                VStack(alignment: .leading, spacing: DipleSpace.s) {
                    HStack(alignment: .top, spacing: DipleSpace.s) {
                        Image(systemName: "note.text")
                            .dipleIcon(11, weight: .semibold)
                            .foregroundStyle(DipleColor.accent)
                            .frame(width: 24, height: 24)
                            .background(DipleColor.accentSoft, in: RoundedRectangle(cornerRadius: DipleRadius.s))

                        Text(item.displayTitle)
                            .dipleType(.body, weight: .semibold)
                            .foregroundStyle(
                                item.displayTitle == "Untitled" ? DipleColor.textTertiary : DipleColor.textPrimary
                            )
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)

                        Spacer(minLength: 0)
                    }

                    if !item.previewText.isEmpty {
                        Text(item.previewText)
                            .dipleType(.callout)
                            .readingLineSpacing(for: item.previewText)
                            .foregroundStyle(DipleColor.textSecondary)
                            .multilineTextAlignment(.leading)
                            .lineLimit(3)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Text(dateline)
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            Button {
                HapticManager.shared.impact(.light)
                onDelete()
            } label: {
                Image(systemName: "trash")
                    .dipleIcon(12)
                    .foregroundStyle(DipleColor.textTertiary)
                    .padding(DipleSpace.s)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Delete note")
        }
        .padding(DipleSpace.m)
        .craftSurface()
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
