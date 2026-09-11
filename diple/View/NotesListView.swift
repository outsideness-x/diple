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
                EmptyView()
            }
            .listRowInsets(EdgeInsets(top: 0, leading: DipleSpace.xl, bottom: DipleSpace.m, trailing: DipleSpace.xl))
            .deskListRow()

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
    }

    private func row(_ item: NoteItem) -> some View {
        Button {
            HapticManager.shared.selection()
            openNote(.existing(item))
        } label: {
            NoteCardView(item: item, style: .row)
        }
        .buttonStyle(.bookCard)
        .listRowInsets(EdgeInsets(top: 0, leading: DipleSpace.xl, bottom: 0, trailing: DipleSpace.xl))
        .deskListRow()
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
