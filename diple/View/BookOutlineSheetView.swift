import SwiftUI
import ReadiumShared

/// The book's own apparatus: where it goes, what was marked in it, and what was written
/// about it. Everything here is reached from one control, because all four answer the same
/// question — "what is in this book, mine included".
public struct BookOutlineSheetView: View {
    /// The book's chapters, already laid out on the reading axis.
    ///
    /// **Laid out by the reader, not here.** Building this walks the publication's position
    /// list, which is per kilobyte of text rather than per chapter, so on a long book it is
    /// real work — and a `body` is evaluated again every time anything on this sheet changes,
    /// including each tap on the segmented control. The reader builds it once when the book
    /// opens; see `ReaderViewModel.contents`.
    public let contents: BookContents
    /// The saved passages, as dots against the chapters they fall in. Also built by the reader,
    /// for the same reason: each one parses a stored locator.
    public let marks: [ContentsMark]
    /// Where reading is, in the same `totalProgression` every locator uses.
    public let progress: Double
    /// Where reading is as the reader itself knows it. The resource on screen is a fact where
    /// progression against unmeasured chapters is an estimate, so Contents marks the current
    /// chapter from this first — see `BookContents.current(at:resource:)`.
    public let currentLocator: ReadiumShared.Locator?
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
    /// so it is confirmed here as it is on the board and on the note's own page.
    @State private var noteToDelete: NoteItem?
    @Environment(\.dismiss) private var dismiss

    /// Named rather than numbered. A fourth pane went in between two existing ones, and with
    /// integer tags that is a silent renumbering of every branch below.
    private enum Section: Hashable, CaseIterable {
        case contents
        case quotes
        case notes
        case bookmarks

        var title: String {
            switch self {
            case .contents: return "Contents"
            case .quotes: return "Highlights"
            case .notes: return "Notes"
            case .bookmarks: return "Bookmarks"
            }
        }
    }

    public init(
        contents: BookContents,
        marks: [ContentsMark] = [],
        progress: Double = 0,
        currentLocator: ReadiumShared.Locator? = nil,
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
        self.contents = contents
        self.marks = marks
        self.progress = progress
        self.currentLocator = currentLocator
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
            // Done, then the sections — whose rule for the open one rests on the hairline
            // under them, the way a tab sits on the page it opens.
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

                // The library's rubric, not a system segmented control — the last one in the
                // app, and inside a book it read as a settings widget over the book's own
                // contents. The counts ride as superior figures, and an empty section prints
                // none: "Notes" already says there are none once it is opened.
                DipleRubric(
                    options: Section.allCases,
                    selection: $selectedTab,
                    title: \.title,
                    count: count(in:),
                    identifier: { "outline.\($0)" },
                    size: .sheet
                )
                .accessibilityLabel("Section")
            }
            .padding(.horizontal, DipleSpace.xl)
            .padding(.top, DipleSpace.l)

            Divider()
                .background(DipleColor.surfaceOverlay)

            switch selectedTab {
            case .contents:
                contentsSection

            case .quotes:
                if highlights.isEmpty {
                    VStack(spacing: DipleSpace.m) {
                        Spacer()
                        Image(systemName: "quote.bubble")
                            .dipleIcon(32, weight: .thin)
                            .foregroundStyle(DipleColor.textTertiary)
                        Text("No passages saved")
                            .dipleType(.body, weight: .semibold)
                            .foregroundStyle(DipleColor.textPrimary)
                        Text("Select a passage while you read and mark it in a colour.")
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
                        Text("No bookmarks saved")
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
        // The board and the note's page ask before a note goes, and the two surfaces must not
        // disagree about what a note costs.
        .alert(
            "Delete note?",
            isPresented: Binding(
                get: { noteToDelete != nil },
                set: { if !$0 { noteToDelete = nil } }
            ),
            presenting: noteToDelete
        ) { item in
            Button("Delete", role: .destructive) {
                HapticManager.shared.impact(.light)
                onDeleteNote(item)
                noteToDelete = nil
            }
            Button("Cancel", role: .cancel) { noteToDelete = nil }
        } message: { _ in
            Text("This note will be deleted.")
        }
    }

    /// Contents: the book's chapters, as a column of names.
    ///
    /// A reader looking for a chapter reads down a list — so the list is a list, and its names
    /// are set as the book's own hierarchy rather than as sixty identical rows. What it adds to
    /// a plain table of contents is the reader's own place: the current chapter carries the
    /// accent, the only progress bar on the screen, and the scroll position when the sheet
    /// opens.
    private var contentsSection: some View {
        Group {
            if contents.isEmpty {
                VStack(spacing: DipleSpace.m) {
                    Spacer()
                    Image(systemName: "list.bullet.indent")
                        .dipleIcon(32, weight: .thin)
                        .foregroundStyle(DipleColor.textTertiary)
                    Text("No table of contents")
                        .dipleType(.body, weight: .medium)
                        .foregroundStyle(DipleColor.textTertiary)
                    Spacer()
                }
            } else {
                BookContentsView(
                    contents: contents,
                    currentID: contents.current(at: progress, resource: currentLocator?.href)?.id,
                    progress: progress,
                    marks: marks,
                    onSelect: { link in
                        onSelectLink(link)
                        dismiss()
                    }
                )
            }
        }
    }

    /// What each section holds. The contents are not counted: a figure over them would be the
    /// number of chapters, which is not something a reader opens this sheet to learn.
    private func count(in section: Section) -> Int {
        switch section {
        case .contents: return 0
        case .quotes: return highlights.count
        case .notes: return notes.count
        case .bookmarks: return bookmarks.count
        }
    }

    /// What has been written about this book — the same rows the notes half of Highlights holds,
    /// not a reader-local copy of them. Selecting one hands it back to the reader, which closes
    /// this sheet and opens the note in the book's notebook, on top of the list of its notes;
    /// that is what every other row here does with what it points at.
    @ViewBuilder
    private var notesSection: some View {
        if notes.isEmpty {
            VStack(spacing: DipleSpace.m) {
                Spacer()
                Image(systemName: "square.and.pencil")
                    .dipleIcon(32, weight: .thin)
                    .foregroundStyle(DipleColor.textTertiary)
                Text("No notes yet")
                    .dipleType(.body, weight: .semibold)
                    .foregroundStyle(DipleColor.textPrimary)
                Text("A note written here is filed under this book and tagged with its name, and it waits in Highlights, under Notes, with everything else you have written.")
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
                            onDelete: {
                                noteToDelete = item
                            }
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
            .foregroundStyle(DipleColor.accentInk)
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
                            .foregroundStyle(DipleColor.accentInk)
                            .frame(width: 24, height: 24)
                            .background(DipleColor.accentSoft, in: RoundedRectangle(cornerRadius: DipleRadius.s))

                        Text(item.displayTitle)
                            .dipleType(.body, weight: .semibold)
                            .foregroundStyle(
                                item.isUntitled ? DipleColor.textTertiary : DipleColor.textPrimary
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
                        .fill(DipleColor.Highlight.color(forHex: bookmark.colorHex))
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
