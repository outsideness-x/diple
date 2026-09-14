#if targetEnvironment(macCatalyst)
import SwiftUI

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
    case space(String)
    /// Notes written about one source, by book id.
    case source(String)
    case allNotes
    case journal
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

    var body: some View {
        List(selection: $place) {
            Section {
                row(.inbox, symbol: "tray", title: "Inbox", count: model.inbox.count)
                row(.today, symbol: "sun.max", title: "Today")
            }

            Section {
                ForEach(model.spaces) { space in
                    row(
                        .space(space.id),
                        symbol: space.symbol,
                        title: space.name,
                        count: model.spaceCounts[space.id] ?? 0
                    )
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
    let onSelect: (NoteItem) -> Void
    let onCreate: () -> Void

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
                            }
                        }
                    }
                    .padding(.horizontal, DipleSpace.l)
                    .padding(.vertical, DipleSpace.m)
                }
            }
        }
        .background(DipleColor.canvas)
    }
}

// MARK: - The editor column, empty

/// What stands where the page will be before one is chosen.
struct MacNotesPlaceholder: View {
    private static let shortcuts: [(key: String, label: String)] = [
        ("⌘N", "New note here"),
        ("⌘8", "Today’s page"),
        ("⌘F", "Find in this list"),
        ("⌘1", "Back to reading")
    ]

    var body: some View {
        VStack(spacing: DipleSpace.l) {
            Image(systemName: "note.text")
                .dipleIcon(28, weight: .light)
                .foregroundStyle(DipleColor.textQuaternary)

            Text("Choose a note")
                .dipleType(.title, weight: .semibold)
                .foregroundStyle(DipleColor.textSecondary)

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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(DipleColor.surface)
    }
}
#endif
