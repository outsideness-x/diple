import SwiftUI

/// The first page of the notes workshop — Things' main list, for notes.
///
/// It is a table of contents, not a feed: the places notes are kept, each with what it holds,
/// and the few notes the reader pinned to have at hand. Every note is one tap into a place and a
/// second into the note, and the `+` in the bar starts one from wherever the reader stands.
///
/// Set in the catalogue register the rest of the app uses — a glyph, a name, a count and a
/// hairline, no cards and no wells — with the section heads Home already prints. Monochrome
/// throughout: the accent on this page belongs to the `+` alone.
struct NotesDeskView: View {
    @ObservedObject var model: NotesWorkshopModel
    let open: (NotesPlace) -> Void
    let openNote: (NoteRoute) -> Void

    @State private var query = ""
    @State private var isSearching = false
    @FocusState private var isSearchFocused: Bool
    @State private var isCreatingSpace = false
    @State private var isArrangingSpaces = false
    @State private var editingSpace: NoteSpace?
    @State private var spaceToDelete: NoteSpace?

    private var dayTitle: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    var body: some View {
        ZStack {
            DipleColor.canvas.ignoresSafeArea()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: DipleSpace.xxl) {
                    masthead

                    if isSearching {
                        DipleSearchField(
                            text: $query,
                            prompt: "Find a note",
                            identifier: "desk.search",
                            focus: $isSearchFocused
                        )
                        .transition(.move(edge: .top).combined(with: .opacity))
                    }

                    if !query.isEmpty {
                        searchResults
                    } else {
                        contents
                    }
                }
                .padding(.horizontal, DipleSpace.xl)
                .padding(.bottom, DipleSpace.scrollBottom)
            }
            .scrollDismissesKeyboard(.interactively)
            .tracksTabBarCollapse()
        }
        .sheet(isPresented: $isCreatingSpace) {
            NoteSpaceEditor { name, symbol in
                model.createSpace(named: name, symbol: symbol)
            }
        }
        .sheet(isPresented: $isArrangingSpaces) {
            NotesSpacesEditor(model: model)
        }
        .sheet(item: $editingSpace) { space in
            NoteSpaceEditor(space: space) { name, symbol in
                model.update(space, name: name, symbol: symbol)
            }
        }
        .spaceDeletionAlert(model: model, space: $spaceToDelete)
    }

    private var masthead: some View {
        DipleMasthead(title: "Notes", strapline: dayTitle) {
            Button {
                HapticManager.shared.selection()
                withAnimation(DipleMotion.standard) {
                    if isSearching {
                        query = ""
                        isSearching = false
                        isSearchFocused = false
                    } else {
                        isSearching = true
                        isSearchFocused = true
                    }
                }
            } label: {
                MastheadGlyph(systemImage: isSearching ? "xmark" : "magnifyingglass")
            }
            .buttonStyle(.readerControl)
            .accessibilityLabel(isSearching ? "Close search" : "Find a note")

            // Settings has to be reachable from this workshop too; a reader who lives in Notes
            // should not have to cross to Reading to change the appearance.
            MastheadButton(systemImage: "gearshape", label: "Settings") {
                NotificationCenter.default.post(name: .dipleOpenSettings, object: nil)
            }
        }
    }

    // MARK: - Contents

    @ViewBuilder
    private var contents: some View {
        VStack(spacing: 0) {
            placeRow("tray", "Inbox", count: model.inbox.count, identifier: "desk.inbox") {
                open(.inbox)
            }
            placeRow("checklist", "Tasks", count: model.openTaskCount, identifier: "desk.tasks") {
                open(.tasks)
            }
        }

        if model.items.isEmpty {
            firstNote
        }

        if !model.pinned.isEmpty {
            section("PINNED") {
                ForEach(model.pinned) { item in
                    pinnedRow(item)
                        .contextMenu {
                            Button {
                                model.setPinned(false, item)
                            } label: {
                                Label("Unpin", systemImage: "pin.slash")
                            }
                            Button(role: .destructive) {
                                model.trash([item])
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
            }
        }

        section("SPACES", action: model.spaces.isEmpty ? nil : ("Edit", { isArrangingSpaces = true })) {
            ForEach(model.spaces) { space in
                placeRow(space.symbol, space.name, count: model.spaceCounts[space.id] ?? 0) {
                    open(.space(space.id))
                }
                .contextMenu {
                    Button {
                        editingSpace = space
                    } label: {
                        Label("Name and glyph…", systemImage: "pencil")
                    }
                    Button(role: .destructive) {
                        spaceToDelete = space
                    } label: {
                        Label("Delete space…", systemImage: "trash")
                    }
                }
            }
            // Always there, and quieter than a space: the one way to make a place, standing
            // at the end of the places it would join.
            newSpaceRow
        }

        if !model.sources.isEmpty {
            section("FROM READING") {
                ForEach(model.sources) { entry in
                    sourceRow(entry)
                }
            }
        }

        VStack(spacing: 0) {
            placeRow("rectangle.stack", "All notes", count: model.items.count) {
                open(.allNotes)
            }
            placeRow("number", "Tags", count: model.tagVocabulary.count) {
                open(.tags)
            }
            // Only while there is something in it: an empty bin is not a place worth a row.
            if !model.trashed.isEmpty {
                placeRow("trash", "Recently deleted", count: model.trashed.count) {
                    open(.trash)
                }
            }
        }
    }

    /// Said once, on an empty workshop, where it does its work: what the `+` is for. The rows
    /// above stay, because they are the structure the first note will arrive into.
    private var firstNote: some View {
        VStack(alignment: .leading, spacing: DipleSpace.s) {
            Text("Write the first note")
                .dipleType(.editorialTitle)
                .foregroundStyle(DipleColor.textPrimary)
            Text("Press + to start one. It waits in the Inbox until it has a place; a note you write inside a book is filed under that book.")
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var searchResults: some View {
        let results = NotesDesk.search(query, in: model.items)
        return VStack(alignment: .leading, spacing: 0) {
            if results.isEmpty {
                Text("No notes match")
                    .dipleType(.callout)
                    .foregroundStyle(DipleColor.textTertiary)
                    .padding(.vertical, DipleSpace.l)
            }
            ForEach(results) { item in
                Button {
                    HapticManager.shared.selection()
                    openNote(.existing(item))
                } label: {
                    NoteCardView(item: item, style: .row)
                }
                .buttonStyle(.bookCard)
            }
        }
    }

    // MARK: - Rows

    private func section<Content: View>(
        _ title: String,
        action: (label: String, perform: () -> Void)? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DipleSpace.xs) {
            HStack {
                Text(title)
                    .dipleType(.micro, weight: .semibold)
                    .foregroundStyle(DipleColor.textTertiary)
                Spacer()
                if let action {
                    Button {
                        HapticManager.shared.selection()
                        action.perform()
                    } label: {
                        Text(action.label)
                            .dipleType(.micro, weight: .semibold)
                            .foregroundStyle(DipleColor.textTertiary)
                            .frame(minHeight: 28)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            VStack(spacing: 0) {
                content()
            }
        }
    }

    private var newSpaceRow: some View {
        Button {
            HapticManager.shared.selection()
            isCreatingSpace = true
        } label: {
            HStack(spacing: DipleSpace.m) {
                Image(systemName: "plus")
                    .dipleIcon(13)
                    .foregroundStyle(DipleColor.textTertiary)
                    .frame(width: 24)
                Text("New space")
                    .dipleType(.body)
                    .foregroundStyle(DipleColor.textTertiary)
                Spacer()
            }
            .frame(minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bookCard)
        .accessibilityIdentifier("desk.newSpace")
    }

    /// A place: its glyph, its name, and how much stands in it. The count is the one fact a
    /// table of contents owes the reader — whether a place is worth going into — and a place
    /// with nothing in it says so by printing no number rather than a zero.
    private func placeRow(
        _ symbol: String,
        _ title: String,
        count: Int,
        identifier: String? = nil,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.shared.selection()
            action()
        } label: {
            HStack(spacing: DipleSpace.m) {
                Image(systemName: symbol)
                    .dipleIcon(15)
                    .foregroundStyle(DipleColor.textSecondary)
                    .frame(width: 24)

                Text(title)
                    .dipleType(.body)
                    .foregroundStyle(DipleColor.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: DipleSpace.s)

                if count > 0 {
                    Text("\(count)")
                        .dipleType(.footnote, weight: .regular)
                        .monospacedDigit()
                        .foregroundStyle(DipleColor.textTertiary)
                }
            }
            .frame(minHeight: 48)
            .deskRule()
            .contentShape(Rectangle())
        }
        .buttonStyle(.bookCard)
        .accessibilityIdentifier(identifier ?? "desk.place")
        .accessibilityLabel(count > 0 ? "\(title), \(count)" : title)
    }

    private func pinnedRow(_ item: NoteItem) -> some View {
        Button {
            HapticManager.shared.selection()
            openNote(.existing(item))
        } label: {
            HStack(spacing: DipleSpace.m) {
                Image(systemName: "pin")
                    .dipleIcon(13)
                    .foregroundStyle(DipleColor.textTertiary)
                    .frame(width: 24)

                Text(item.displayTitle)
                    .dipleType(.body)
                    .foregroundStyle(item.isUntitled ? DipleColor.textTertiary : DipleColor.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: DipleSpace.s)

                Text(item.note.updatedAt.formatted(.relative(presentation: .named, unitsStyle: .abbreviated)))
                    .dipleType(.caption)
                    .foregroundStyle(DipleColor.textQuaternary)
                    .lineLimit(1)
            }
            .frame(minHeight: 48)
            .deskRule()
            .contentShape(Rectangle())
        }
        .buttonStyle(.bookCard)
    }

    /// A source is drawn by its cover, the way the library and the board's source headings
    /// draw it: the one row on the Desk that points back into the reading workshop.
    private func sourceRow(_ entry: NotesDesk.SourceEntry) -> some View {
        Button {
            HapticManager.shared.selection()
            open(.source(entry.book.id))
        } label: {
            HStack(spacing: DipleSpace.m) {
                BookCoverView(
                    coverPath: entry.book.coverPath,
                    title: entry.book.title,
                    author: entry.book.author,
                    isCompact: true
                )
                .frame(width: 18, height: 27)
                .frame(width: 24)

                Text(entry.book.title)
                    .dipleType(.body)
                    .foregroundStyle(DipleColor.textPrimary)
                    .lineLimit(1)

                Spacer(minLength: DipleSpace.s)

                Text("\(entry.count)")
                    .dipleType(.footnote, weight: .regular)
                    .monospacedDigit()
                    .foregroundStyle(DipleColor.textTertiary)
            }
            .frame(minHeight: 48)
            .deskRule()
            .contentShape(Rectangle())
        }
        .buttonStyle(.bookCard)
        .accessibilityLabel("\(entry.book.title), \(entry.count) \(entry.count == 1 ? "note" : "notes")")
    }
}

private extension View {
    /// The hairline that ends a Desk row, set in from the glyph column so the rules line up with
    /// the names rather than running under the icons.
    func deskRule() -> some View {
        overlay(alignment: .bottom) {
            Rectangle()
                .fill(DipleColor.hairline)
                .frame(height: DipleStroke.hairline)
                .padding(.leading, 24 + DipleSpace.m)
        }
    }
}
