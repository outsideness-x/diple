#if targetEnvironment(macCatalyst)
import SwiftUI
import UniformTypeIdentifiers

/// The two workshops the phone has, as a switch at the top of the desktop sidebar.
///
/// Remembered under the phone's own key (`RootTabView.modeKey`) with the same raw values, and
/// like the phone's it is **not synced**: the mode a Mac was left in is a fact about that desk.
enum MacMode: String {
    case reading
    case notes

    var title: String {
        switch self {
        case .reading: return "Reading"
        case .notes: return "Notes"
        }
    }

    /// The glyphs the phone's mode circle already uses, so the two platforms name the two rooms
    /// the same way.
    var symbol: String {
        switch self {
        case .reading: return "books.vertical"
        case .notes: return "note.text"
        }
    }
}

/// A place in the notes workshop, as the desktop sidebar lists it — the Desk's rows, standing
/// in a column instead of on a page.
enum MacNotesPlace: Hashable {
    case inbox
    case today
    /// Every open box in every note.
    case tasks
    case space(String)
    /// Notes written about one source, by book id.
    case source(String)
    case allNotes
    case journal
    /// Recently deleted.
    case trash
}

// MARK: - Dragging a note

extension UTType {
    /// A note carried by the pointer inside the window. Its own type, declared in Info.plist,
    /// rather than the note's id as text: text would be taken by every field it passed over —
    /// dropped on the editor beside the list, it would type the id into the page.
    static let dipleNoteReference = UTType(exportedAs: "com.chemical-pink.diple.note-reference")
}

/// What a note row gives the pointer: which note, and nothing else. The note itself is read
/// back from the workshop on the drop, so a row dragged while it was being edited files the
/// note as it is now.
nonisolated struct MacNoteReference: Codable, Transferable {
    let id: String

    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: .dipleNoteReference)
    }
}

/// A place in the sidebar a note can be dropped on: a ring while the pointer holds one over it,
/// the same ring that says "this one" everywhere else.
private struct MacNoteDropTarget: ViewModifier {
    let onDrop: ([String]) -> Bool

    @State private var isTargeted = false

    func body(content: Content) -> some View {
        content
            .dipleSelected(
                isTargeted,
                in: RoundedRectangle(cornerRadius: DipleRadius.s, style: .continuous),
                resting: .clear
            )
            .animation(DipleMotion.snappy, value: isTargeted)
            .dropDestination(for: MacNoteReference.self) { references, _ in
                onDrop(references.map(\.id))
            } isTargeted: { targeted in
                isTargeted = targeted
            }
    }
}

// MARK: - The switch

/// Reading | Notes. A ring on the chosen half, the one way this app says "this one"
/// (`dipleSelected`) — not a filled segment, which would be a second vocabulary for selection
/// standing directly above the sidebar's own.
struct MacModeSwitch: View {
    @Binding var mode: MacMode

    var body: some View {
        HStack(spacing: DipleSpace.xs) {
            segment(.reading, shortcut: "⌘1")
            segment(.notes, shortcut: "⌘6")
        }
    }

    private func segment(_ option: MacMode, shortcut: String) -> some View {
        let isSelected = mode == option
        return Button {
            guard mode != option else { return }
            withAnimation(DipleMotion.snappy) { mode = option }
        } label: {
            Label(option.title, systemImage: option.symbol)
                .dipleType(.footnote, weight: isSelected ? .semibold : .regular)
                .foregroundStyle(isSelected ? DipleColor.textPrimary : DipleColor.textTertiary)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, DipleSpace.s)
                .dipleSelected(
                    isSelected,
                    in: RoundedRectangle(cornerRadius: DipleRadius.s, style: .continuous),
                    resting: DipleColor.surfaceOverlay
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(option.title) (\(shortcut))")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

// MARK: - The sidebar

/// The notes workshop's places, in the Desk's order: Inbox, Today and Tasks first, then the
/// spaces the writer made, the sources written about, and the whole collection last.
///
/// A place with nothing in it prints no number rather than a zero — the rule the Desk's rows
/// follow — and a section with nothing in it is not drawn.
struct MacNotesSidebar: View {
    @ObservedObject var model: NotesWorkshopModel
    @Binding var place: MacNotesPlace?
    let onNewSpace: () -> Void
    /// Notes dropped on a place: the Inbox (`nil`) or a space. Answers whether they were taken.
    let onDrop: ([String], NoteSpace?) -> Bool
    let onEditSpace: (NoteSpace) -> Void
    let onArrangeSpaces: () -> Void
    let onDeleteSpace: (NoteSpace) -> Void

    var body: some View {
        List(selection: $place) {
            Section {
                row(.inbox, symbol: "tray", title: "Inbox", count: model.inbox.count)
                    .modifier(MacNoteDropTarget { ids in onDrop(ids, nil) })
                row(.today, symbol: "sun.max", title: "Today")
                row(.tasks, symbol: "checklist", title: "Tasks", count: model.openTaskCount)
            }

            Section {
                ForEach(model.spaces) { space in
                    row(
                        .space(space.id),
                        symbol: space.symbol,
                        title: space.name,
                        count: model.spaceCounts[space.id] ?? 0
                    )
                    .modifier(MacNoteDropTarget { ids in onDrop(ids, space) })
                    // The phone keeps these in a sheet behind "Edit" so the Desk cannot grow
                    // handles under a stray press; a pointer has no stray press, and the menu
                    // under the right click is where a desktop keeps what a row can be asked.
                    .contextMenu {
                        Button {
                            onEditSpace(space)
                        } label: {
                            Label("Name and glyph…", systemImage: "pencil")
                        }
                        if model.spaces.count > 1 {
                            Button {
                                onArrangeSpaces()
                            } label: {
                                Label("Arrange spaces…", systemImage: "arrow.up.arrow.down")
                            }
                        }
                        Divider()
                        Button(role: .destructive) {
                            onDeleteSpace(space)
                        } label: {
                            Label("Delete space…", systemImage: "trash")
                        }
                    }
                }
                // Quieter than a space and not a place: it makes one. Last, where the new space
                // will stand.
                Button(action: onNewSpace) {
                    HStack(spacing: DipleSpace.s) {
                        Image(systemName: "plus")
                            .dipleIcon(12)
                            .frame(width: 18)
                        Text("New space")
                            .dipleType(.footnote)
                        Spacer()
                    }
                    .foregroundStyle(DipleColor.textTertiary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } header: {
                Text("Spaces")
            }

            if !model.sources.isEmpty {
                Section {
                    ForEach(model.sources) { entry in
                        row(
                            .source(entry.book.id),
                            symbol: "book.closed",
                            title: entry.book.title,
                            count: entry.count
                        )
                    }
                } header: {
                    Text("From reading")
                }
            }

            Section {
                if !model.journal.isEmpty {
                    row(.journal, symbol: "book.pages", title: "Journal", count: model.journal.count)
                }
                row(.allNotes, symbol: "rectangle.stack", title: "All notes", count: model.items.count)
                // Only while there is something in it, as on the Desk — or while the window
                // stands in it, so emptying the bin does not pull the row out from under the
                // selection that is showing it.
                if !model.trashed.isEmpty || place == .trash {
                    row(.trash, symbol: "trash", title: "Recently deleted", count: model.trashed.count)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
    }

    private func row(
        _ target: MacNotesPlace,
        symbol: String,
        title: String,
        count: Int = 0
    ) -> some View {
        HStack(spacing: DipleSpace.s) {
            Image(systemName: symbol)
                .dipleIcon(13)
                .frame(width: 18)
            Text(title)
                .dipleType(.footnote)
                .lineLimit(1)
            Spacer()
            if count > 0 {
                Text("\(count)")
                    .dipleType(.nano)
                    .foregroundStyle(DipleColor.textQuaternary)
                    .monospacedDigit()
            }
        }
        .foregroundStyle(place == target ? DipleColor.textPrimary : DipleColor.textSecondary)
        .tag(target)
    }
}

// MARK: - The list

/// The middle column of the notes workshop: one place's notes, in the workshop's one order.
///
/// Rows are the phone's catalogue entry (`NoteCardView(.row)`), so a note looks the same in a
/// column on the desk as on a page in the hand; the desktop adds only what a pointer expects —
/// a hover wash and the accent ring on the note the editor is showing.
struct MacNotesList: View {
    let title: String
    let notes: [NoteItem]
    let selectedID: String?
    let empty: (symbol: String, title: String, message: String)
    @Binding var query: String
    @Binding var searchFocusRequest: MacSearchTarget?
    /// Where a note can be filed from its row's menu.
    let spaces: [NoteSpace]
    let onSelect: (NoteItem) -> Void
    let onCreate: () -> Void
    let onSetPinned: (NoteItem, Bool) -> Void
    /// A row filed from its menu: to the Inbox (`nil`) or a space.
    let onMove: (NoteItem, NoteSpace?) -> Void
    let onMoveToNewSpace: (NoteItem) -> Void
    /// To Recently deleted, without asking: it is thirty days from gone, one row down the sidebar.
    let onTrash: (NoteItem) -> Void

    private var visible: [NoteItem] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? notes : NotesDesk.search(trimmed, in: notes)
    }

    var body: some View {
        VStack(spacing: 0) {
            MacColumnHeader(
                title: title,
                count: notes.count,
                query: $query,
                prompt: "Find a note",
                searchIdentifier: "mac.notes.search",
                focusRequest: $searchFocusRequest,
                focusTarget: .notes
            ) {
                MacPrimaryButton(title: "New note", shortcutHint: "⌘N", action: onCreate)
            }

            if visible.isEmpty {
                if query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    MacEmptyCollection(icon: empty.symbol, title: empty.title, message: empty.message)
                } else {
                    MacEmptyCollection(
                        icon: "text.magnifyingglass",
                        title: "No notes match",
                        message: "Every word has to appear in the note, its tags or its source.",
                        actionTitle: "Clear the search",
                        actionIcon: "xmark",
                        action: { query = "" }
                    )
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: DipleSpace.xs) {
                        ForEach(visible) { item in
                            MacSelectableRow(isSelected: selectedID == item.id, radius: DipleRadius.s, isBordered: false) {
                                onSelect(item)
                            } content: {
                                NoteCardView(item: item, style: .row)
                                    .padding(.horizontal, DipleSpace.m)
                                    .overlay(alignment: .topTrailing) {
                                        if item.note.pinnedAt != nil { pinMark }
                                    }
                            }
                            .draggable(MacNoteReference(id: item.id)) {
                                dragPreview(of: item)
                            }
                            .contextMenu { menu(for: item) }
                        }
                    }
                    .padding(.horizontal, DipleSpace.l)
                    .padding(.vertical, DipleSpace.m)
                }
            }
        }
        .background(DipleColor.canvas)
    }

    /// Pinned notes stand first in every list, and on a desk the order alone does not say why.
    /// Quiet, in the corner: the mark answers the question, it does not ask to be pressed.
    private var pinMark: some View {
        Image(systemName: "pin.fill")
            .dipleIcon(10, weight: .medium)
            .foregroundStyle(DipleColor.textQuaternary)
            .padding(DipleSpace.m)
            .accessibilityLabel("Pinned")
    }

    /// The title alone under the pointer: the row at full width would cover the sidebar it is
    /// being carried to.
    private func dragPreview(of item: NoteItem) -> some View {
        Label(item.displayTitle, systemImage: "note.text")
            .dipleType(.footnote, weight: .medium)
            .foregroundStyle(DipleColor.textPrimary)
            .lineLimit(1)
            .padding(.horizontal, DipleSpace.m)
            .padding(.vertical, DipleSpace.s)
            .background(DipleColor.surfaceRaised, in: Capsule())
    }

    /// Pin, Move and Delete, as the phone's row offers them under a long press.
    @ViewBuilder
    private func menu(for item: NoteItem) -> some View {
        let isPinned = item.note.pinnedAt != nil
        Button {
            onSetPinned(item, !isPinned)
        } label: {
            Label(isPinned ? "Unpin" : "Pin", systemImage: isPinned ? "pin.slash" : "pin")
        }

        Menu {
            moveDestination("Inbox", symbol: "tray", isCurrent: item.note.spaceId == nil) {
                onMove(item, nil)
            }
            ForEach(spaces) { space in
                moveDestination(space.name, symbol: space.symbol, isCurrent: item.note.spaceId == space.id) {
                    onMove(item, space)
                }
            }
            Divider()
            Button {
                onMoveToNewSpace(item)
            } label: {
                Label("New space…", systemImage: "plus")
            }
        } label: {
            Label("Move to", systemImage: "folder")
        }

        Divider()
        Button(role: .destructive) {
            onTrash(item)
        } label: {
            Label("Delete", systemImage: "trash")
        }
    }

    private func moveDestination(
        _ title: String,
        symbol: String,
        isCurrent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: isCurrent ? "checkmark" : symbol)
        }
        .disabled(isCurrent)
    }
}

// MARK: - The editor column, empty

/// What stands where the page will be before one is chosen.
struct MacNotesPlaceholder: View {
    /// Standing in Recently deleted, where nothing opens: a note there is brought back or let go.
    var inTrash = false

    private static let shortcuts: [(key: String, label: String)] = [
        ("⌘N", "New note here"),
        ("⌘8", "Today’s page"),
        ("⌘F", "Find in this list"),
        ("⌘1", "Back to reading")
    ]

    var body: some View {
        VStack(spacing: DipleSpace.l) {
            Image(systemName: inTrash ? "trash" : "note.text")
                .dipleIcon(28, weight: .light)
                .foregroundStyle(DipleColor.textQuaternary)

            Text(inTrash ? "Nothing opens here" : "Choose a note")
                .dipleType(.title, weight: .semibold)
                .foregroundStyle(DipleColor.textSecondary)

            if inTrash {
                Text("A deleted note is restored or let go. Right-click one for both.")
                    .dipleType(.footnote)
                    .foregroundStyle(DipleColor.textTertiary)
                    .multilineTextAlignment(.center)
            } else {
                VStack(alignment: .leading, spacing: DipleSpace.s) {
                    ForEach(Self.shortcuts, id: \.key) { shortcut in
                        HStack(spacing: DipleSpace.m) {
                            Text(shortcut.key)
                                .dipleType(.micro, weight: .semibold)
                                .foregroundStyle(DipleColor.textTertiary)
                                .frame(width: 32, alignment: .trailing)
                            Text(shortcut.label)
                                .dipleType(.footnote)
                                .foregroundStyle(DipleColor.textTertiary)
                        }
                    }
                }
            }
        }
        .padding(DipleSpace.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DipleColor.surface)
    }
}
// MARK: - Tasks

/// Every open box in every note, in the middle column — the phone's Tasks page on the desk.
///
/// The same `NotesDesk.openTasks` and the same pause: a ticked task stays, struck through, for
/// the beat it takes to see it land, then the list closes over it. Ticking rewrites the line in
/// its note (`NotesWorkshopModel.toggleTask`) exactly as ticking it on the page does, and a page
/// open beside the list takes the new text (`MacNoteInspector`). A group's head opens its note in
/// the editor and leaves the window standing in Tasks.
struct MacTasksList: View {
    @ObservedObject var model: NotesWorkshopModel
    let selectedID: String?
    let onSelect: (NoteItem) -> Void

    @State private var lingering: Set<NotesDesk.TaskKey> = []

    /// How long a ticked task stays on the list before it goes — the phone's number.
    private let lingerFor: Duration = .milliseconds(1200)

    var body: some View {
        let groups = NotesDesk.openTasks(model.items, lingering: lingering)
        let open = groups.reduce(0) { $0 + $1.tasks.filter { !$0.isCompleted }.count }

        VStack(spacing: 0) {
            MacColumnHeader(title: "Tasks", count: open > 0 ? open : nil) {
                EmptyView()
            }

            if groups.isEmpty {
                MacEmptyCollection(
                    icon: "checklist",
                    title: "Nothing to do",
                    message: "A line that begins with - [ ] in any note is a task, and it collects here."
                )
                // A beat late, so the last task has finished leaving first.
                .transition(.opacity.animation(DipleMotion.gentle.delay(0.3)))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DipleSpace.l) {
                        ForEach(groups) { group in
                            section(group)
                        }
                    }
                    .padding(.horizontal, DipleSpace.xxl)
                    .padding(.vertical, DipleSpace.l)
                    .animation(DipleMotion.standard, value: groups)
                }
            }
        }
        .background(DipleColor.canvas)
    }

    private func section(_ group: NotesDesk.TaskGroup) -> some View {
        let isSelected = selectedID == group.item.id
        return VStack(alignment: .leading, spacing: DipleSpace.s) {
            Button {
                onSelect(group.item)
            } label: {
                HStack(spacing: DipleSpace.xs) {
                    Text(group.item.displayTitle)
                        .dipleType(.footnote, weight: .semibold)
                        .foregroundStyle(isSelected ? DipleColor.textPrimary : DipleColor.textSecondary)
                        .lineLimit(1)
                    Image(systemName: "chevron.right")
                        .dipleIcon(9, weight: .semibold)
                        .foregroundStyle(DipleColor.textQuaternary)
                    Spacer(minLength: DipleSpace.s)
                    if let place = placeName(of: group.item) {
                        Text(place)
                            .dipleType(.caption)
                            .foregroundStyle(DipleColor.textQuaternary)
                            .lineLimit(1)
                    }
                }
                .padding(.vertical, DipleSpace.xs)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Open the note")

            VStack(alignment: .leading, spacing: DipleSpace.xs) {
                ForEach(group.tasks, id: \.lineIndex) { task in
                    Button {
                        toggle(task, in: group.item)
                    } label: {
                        NoteTaskRow(
                            task: task,
                            lineSpacing: ReaderScript.detect(in: task.text).swiftUILineSpacing
                        )
                    }
                    .buttonStyle(.plain)
                    .transition(.opacity.combined(with: .move(edge: .top)))
                    .accessibilityAddTraits(task.isCompleted ? [.isButton, .isSelected] : .isButton)
                }
            }
        }
        .padding(.bottom, DipleSpace.m)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DipleColor.hairline).frame(height: DipleStroke.hairline)
        }
    }

    /// Where the note stands, small beside its name: the space, or the source.
    private func placeName(of item: NoteItem) -> String? {
        if let id = item.note.spaceId, let space = model.space(id: id) { return space.name }
        return item.book?.title
    }

    private func toggle(_ task: NoteTask, in item: NoteItem) {
        let key = NotesDesk.TaskKey(noteID: item.id, lineIndex: task.lineIndex)
        guard !task.isCompleted else {
            // Unticked while it still lingers: it is simply open again.
            lingering.remove(key)
            model.toggleTask(task, in: item)
            return
        }
        lingering.insert(key)
        model.toggleTask(task, in: item)
        Task { @MainActor in
            try? await Task.sleep(for: lingerFor)
            withAnimation(DipleMotion.gentle) { _ = lingering.remove(key) }
        }
    }
}

// MARK: - Recently deleted

/// What was deleted in the last thirty days, and the way back — the phone's page, on the desk.
///
/// Deleting a note on the Mac stopped asking the moment this column existed. The questions stand
/// here instead, in front of the two acts that cannot be undone: deleting one for good, and
/// emptying the bin. A row is not opened; it is restored or let go.
struct MacTrashList: View {
    @ObservedObject var model: NotesWorkshopModel

    @State private var toDelete: NoteItem?
    @State private var isConfirmingEmpty = false

    var body: some View {
        VStack(spacing: 0) {
            MacColumnHeader(
                title: "Recently deleted",
                count: model.trashed.isEmpty ? nil : model.trashed.count
            ) {
                if !model.trashed.isEmpty {
                    Button {
                        isConfirmingEmpty = true
                    } label: {
                        Text("Empty")
                            .dipleType(.footnote, weight: .semibold)
                            .foregroundStyle(DipleColor.destructive)
                            .lineLimit(1)
                            .fixedSize()
                    }
                    .buttonStyle(.plain)
                    .help("Delete every note here for good")
                }
            }

            if model.trashed.isEmpty {
                MacEmptyCollection(
                    icon: "trash",
                    title: "Nothing deleted",
                    message: "Deleted notes stay here for thirty days, then go for good."
                )
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(model.trashed) { item in
                            row(item)
                        }
                    }
                    .padding(.horizontal, DipleSpace.xxl)
                    .padding(.vertical, DipleSpace.m)
                }
            }
        }
        .background(DipleColor.canvas)
        .alert(
            "Delete for good?",
            isPresented: Binding(get: { toDelete != nil }, set: { if !$0 { toDelete = nil } }),
            presenting: toDelete
        ) { item in
            Button("Delete", role: .destructive) { model.deleteForever([item]) }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("This note cannot be restored afterwards.")
        }
        .alert("Empty Recently deleted?", isPresented: $isConfirmingEmpty) {
            Button("Delete \(model.trashed.count)", role: .destructive) {
                model.deleteForever(model.trashed)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.trashed.count == 1
                ? "The note here will be deleted and cannot be restored."
                : "All \(model.trashed.count) notes here will be deleted and cannot be restored.")
        }
    }

    /// The name, when it went and what is left — and Restore in plain sight. On the phone the
    /// way back is a swipe; a pointer has no swipe, and a way back hidden under a right click is
    /// one the reader who deleted by mistake would not find.
    private func row(_ item: NoteItem) -> some View {
        HStack(alignment: .center, spacing: DipleSpace.m) {
            VStack(alignment: .leading, spacing: DipleSpace.xs) {
                Text(item.displayTitle)
                    .dipleType(.headline)
                    .foregroundStyle(DipleColor.textSecondary)
                    .lineLimit(2)
                // Two lines, not one: beside Restore in a narrow column the days left — the
                // half of the line that matters — were the half cut off.
                Text(NotesTrashView.dateline(item))
                    .dipleType(.caption)
                    .foregroundStyle(DipleColor.textTertiary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button {
                model.restore(item)
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
                    .dipleType(.footnote, weight: .medium)
                    .foregroundStyle(DipleColor.textSecondary)
                    .lineLimit(1)
                    .fixedSize()
                    .diplePadding(.chip)
                    .overlay(Capsule().stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline))
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, DipleSpace.m)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DipleColor.hairline).frame(height: DipleStroke.hairline)
        }
        .contentShape(Rectangle())
        .contextMenu {
            Button {
                model.restore(item)
            } label: {
                Label("Restore", systemImage: "arrow.uturn.backward")
            }
            Button(role: .destructive) {
                toDelete = item
            } label: {
                Label("Delete now…", systemImage: "trash")
            }
        }
    }
}
#endif
