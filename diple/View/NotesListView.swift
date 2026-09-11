import SwiftUI

/// One place in the notes workshop, as a list: the Inbox, a space, or the notes about a source.
///
/// One view for all three, because they are one kind of page — a name, a count, the notes that
/// stand there, pinned first — and differ only in which notes those are and where a new one
/// goes. Rows are the board's own catalogue entry (`NoteCardView(.row)`): a note looks the same
/// on every page it appears on.
///
/// A `List` rather than a stack in a scroll view, for the swipe actions only a list has.
struct NotesListView: View {
    enum Kind {
        case inbox
        case space(NoteSpace)
        case source(Book)
    }

    @ObservedObject var model: NotesWorkshopModel
    let kind: Kind
    let openNote: (NoteRoute) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var moving: MoveRequest?
    @State private var isEditingSpace = false
    @State private var spaceToDelete: NoteSpace?
    @State private var isFiling = false

    /// The notes on their way to the Move sheet. Wrapped so a sheet can be raised by item.
    private struct MoveRequest: Identifiable {
        let id = UUID()
        let items: [NoteItem]
    }

    private var space: NoteSpace? {
        if case .space(let space) = kind { return model.space(id: space.id) ?? space }
        return nil
    }

    private var items: [NoteItem] {
        switch kind {
        case .inbox:
            return model.inbox
        case .space(let space):
            return NotesDesk.notes(in: space, from: model.items)
        case .source(let book):
            return NotesDesk.notes(about: book.id, from: model.items)
        }
    }

    private var title: String {
        switch kind {
        case .inbox: return "Inbox"
        case .space(let space): return model.space(id: space.id)?.name ?? space.name
        case .source(let book): return book.title
        }
    }

    private var strapline: String? {
        let count = items.count
        guard count > 0 else { return nil }
        return count == 1 ? "1 note" : "\(count) notes"
    }

    var body: some View {
        let items = self.items
        let pinned = items.filter(\.note.isPinned)
        let rest = items.filter { !$0.note.isPinned }

        List {
            DipleMasthead(title: title, strapline: strapline) {
                if let space {
                    Menu {
                        Button {
                            isEditingSpace = true
                        } label: {
                            Label("Name and glyph…", systemImage: "pencil")
                        }
                        Button(role: .destructive) {
                            spaceToDelete = space
                        } label: {
                            Label("Delete space…", systemImage: "trash")
                        }
                    } label: {
                        MastheadGlyph(systemImage: "ellipsis")
                    }
                    .buttonStyle(.readerControl)
                    .accessibilityLabel("Space options")
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: DipleSpace.xl, bottom: DipleSpace.m, trailing: DipleSpace.xl))
            .deskListRow()

            // The way into the filing pass, only where it makes sense: standing in the Inbox with
            // more than one note waiting. A resident control for a ritual performed now and then
            // is the trade the rest of the app refuses.
            if case .inbox = kind, items.count > 1, !model.spaces.isEmpty {
                filingInvitation
                    .listRowInsets(EdgeInsets(top: 0, leading: DipleSpace.xl, bottom: DipleSpace.m, trailing: DipleSpace.xl))
                    .deskListRow()
            }

            if items.isEmpty {
                emptyState
                    .listRowInsets(EdgeInsets(top: DipleSpace.xxl, leading: DipleSpace.xl, bottom: 0, trailing: DipleSpace.xl))
                    .deskListRow()
            }

            if !pinned.isEmpty {
                Text("PINNED")
                    .dipleType(.micro, weight: .semibold)
                    .foregroundStyle(DipleColor.textTertiary)
                    .listRowInsets(EdgeInsets(top: DipleSpace.s, leading: DipleSpace.xl, bottom: 0, trailing: DipleSpace.xl))
                    .deskListRow()
                ForEach(pinned) { item in row(item) }

                if !rest.isEmpty {
                    Color.clear
                        .frame(height: DipleSpace.l)
                        .listRowInsets(EdgeInsets())
                        .deskListRow()
                }
            }

            ForEach(rest) { item in row(item) }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(DipleColor.canvas.ignoresSafeArea())
        .environment(\.defaultMinListRowHeight, 0)
        .contentMargins(.bottom, DipleSpace.scrollBottom + 72, for: .scrollContent)
        .tracksTabBarCollapse()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DipleColor.canvas, for: .navigationBar)
        .sheet(item: $moving) { request in
            NoteMoveSheet(model: model, items: request.items)
        }
        .sheet(isPresented: $isFiling) {
            NotesFilingView(model: model)
        }
        .sheet(isPresented: $isEditingSpace) {
            if let space {
                NoteSpaceEditor(space: space) { name, symbol in
                    model.update(space, name: name, symbol: symbol)
                }
            }
        }
        // Deleting the space this page stands for leaves nothing to stand on: the page goes
        // first, and the notes it held are in the Inbox by the time the Desk is back.
        .spaceDeletionAlert(model: model, space: $spaceToDelete, onDeleted: { dismiss() })
    }

    /// A note, and the three things done to one without opening it: pin it, move it, delete it.
    ///
    /// Pinning is the leading swipe, in the accent, because it is the one that keeps something
    /// close; deleting is the trailing full swipe, because it can be undone for thirty days and
    /// so does not need to be hard to reach. Move stands beside it. The context menu says all
    /// three in words, for the reader who does not swipe.
    private func row(_ item: NoteItem) -> some View {
        let isPinned = item.note.isPinned
        return Button {
            HapticManager.shared.selection()
            openNote(.existing(item))
        } label: {
            NoteCardView(item: item, style: .row)
        }
        .buttonStyle(.bookCard)
        .listRowInsets(EdgeInsets(top: 0, leading: DipleSpace.xl, bottom: 0, trailing: DipleSpace.xl))
        .deskListRow()
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            Button {
                HapticManager.shared.impact(.light)
                model.setPinned(!isPinned, item)
            } label: {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
            }
            .tint(DipleColor.accent)
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                HapticManager.shared.impact(.light)
                model.trash([item])
            } label: {
                Label("Delete", systemImage: "trash")
            }
            // Explicit: the shell sets the accent as the app's tint, and a swipe button takes
            // the environment's tint over its own role — a blue Delete, seen on the simulator.
            .tint(DipleColor.destructive)
            Button {
                moving = MoveRequest(items: [item])
            } label: {
                Label("Move", systemImage: "folder")
            }
            .tint(Color(uiColor: .systemGray))
        }
        .contextMenu {
            Button {
                model.setPinned(!isPinned, item)
            } label: {
                Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
            }
            Button {
                moving = MoveRequest(items: [item])
            } label: {
                Label("Move to…", systemImage: "folder")
            }
            Button(role: .destructive) {
                model.trash([item])
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    private var filingInvitation: some View {
        Button {
            HapticManager.shared.selection()
            isFiling = true
        } label: {
            HStack(spacing: DipleSpace.m) {
                Image(systemName: "tray.and.arrow.down")
                    .dipleIcon(15, weight: .medium)
                    .foregroundStyle(DipleColor.accentInk)
                VStack(alignment: .leading, spacing: DipleSpace.xs) {
                    Text("Sort these out")
                        .dipleType(.body, weight: .semibold)
                        .foregroundStyle(DipleColor.textPrimary)
                    Text("One at a time, into your spaces.")
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: DipleSpace.s)
                Image(systemName: "chevron.right")
                    .dipleIcon(11, weight: .semibold)
                    .foregroundStyle(DipleColor.textQuaternary)
            }
            .padding(DipleSpace.m)
            .craftSurface(DipleColor.surface)
        }
        .buttonStyle(.bookCard)
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: DipleSpace.s) {
            Text(emptyTitle)
                .dipleType(.editorialTitle)
                .foregroundStyle(DipleColor.textPrimary)
            Text(emptyDetail)
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyTitle: String {
        switch kind {
        case .inbox: return "Nothing waiting"
        case .space: return "An empty space"
        case .source: return "No notes about this yet"
        }
    }

    private var emptyDetail: String {
        switch kind {
        case .inbox:
            return "What you jot down with + waits here until it has a place."
        case .space:
            return "Press + to write the first note that belongs here."
        case .source:
            return "Press + to write one, or tap the pencil while reading."
        }
    }
}

extension View {
    /// A row of a workshop list: on the canvas, with the list's own separator off — the entries
    /// draw their own rule, as they do everywhere else in the app.
    func deskListRow() -> some View {
        listRowSeparator(.hidden)
            .listRowBackground(DipleColor.canvas)
    }
}
