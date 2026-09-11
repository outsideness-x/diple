import SwiftUI

// MARK: - Naming a space

/// Makes a space or changes one: a name and one glyph from the short list.
///
/// The glyph is chosen, not typed and not coloured. Twenty-four monochrome SF Symbols from the
/// same family as the shelf and the page the rest of the app draws in — no emoji and no tints,
/// because the app's colour vocabulary is the accent, destructive and success, and a sidebar of
/// painted folders would be a fourth.
struct NoteSpaceEditor: View {
    let space: NoteSpace?
    let onSave: (String, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name: String
    @State private var symbol: String
    @FocusState private var isNameFocused: Bool

    init(space: NoteSpace? = nil, onSave: @escaping (String, String) -> Void) {
        self.space = space
        self.onSave = onSave
        _name = State(initialValue: space?.name ?? "")
        _symbol = State(initialValue: space?.symbol ?? NoteSpace.defaultSymbol)
    }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private let columns = Array(repeating: GridItem(.flexible(), spacing: DipleSpace.s), count: 6)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: DipleSpace.xl) {
                    HStack(spacing: DipleSpace.m) {
                        Image(systemName: symbol)
                            .dipleIcon(18)
                            .foregroundStyle(DipleColor.textSecondary)
                            .frame(width: 28)
                            .contentTransition(.symbolEffect(.replace))
                        TextField("Name", text: $name)
                            .dipleType(.title)
                            .foregroundStyle(DipleColor.textPrimary)
                            .focused($isNameFocused)
                            .submitLabel(.done)
                            .onSubmit(save)
                            .accessibilityIdentifier("space.name")
                    }
                    .padding(.vertical, DipleSpace.s)
                    .overlay(alignment: .bottom) {
                        Rectangle().fill(DipleColor.hairline).frame(height: DipleStroke.hairline)
                    }

                    LazyVGrid(columns: columns, spacing: DipleSpace.s) {
                        ForEach(NoteSpace.symbols, id: \.self) { candidate in
                            Button {
                                HapticManager.shared.selection()
                                withAnimation(DipleMotion.snappy) { symbol = candidate }
                            } label: {
                                Image(systemName: candidate)
                                    .dipleIcon(17)
                                    .foregroundStyle(candidate == symbol ? DipleColor.accentInk : DipleColor.textSecondary)
                                    .frame(maxWidth: .infinity, minHeight: 48)
                                    .dipleSelected(candidate == symbol, in: RoundedRectangle(cornerRadius: DipleRadius.s))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(candidate)
                            .accessibilityAddTraits(candidate == symbol ? [.isSelected] : [])
                        }
                    }
                }
                .padding(DipleSpace.xl)
            }
            .background(DipleColor.canvas.ignoresSafeArea())
            .navigationTitle(space == nil ? "New space" : "Space")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(space == nil ? "Create" : "Save", action: save)
                        .disabled(!canSave)
                }
            }
            .onAppear { isNameFocused = space == nil }
        }
        .presentationDetents([.medium, .large])
    }

    private func save() {
        guard canSave else { return }
        HapticManager.shared.impact(.light)
        onSave(name, symbol)
        dismiss()
    }
}

// MARK: - Moving notes

/// Where a note goes: the Inbox, one of the spaces, or a space made on the spot.
///
/// Made on the spot because "file this under something new" is the most natural moment to
/// realise a space is missing, and sending the reader back to the Desk to make one first would
/// lose the note they were filing.
struct NoteMoveSheet: View {
    @ObservedObject var model: NotesWorkshopModel
    let items: [NoteItem]

    @Environment(\.dismiss) private var dismiss
    @State private var isCreating = false

    /// The space every chosen note already shares, if they share one.
    private var currentSpaceID: String?? {
        let spaces = Set(items.map(\.note.spaceId))
        return spaces.count == 1 ? spaces.first : nil
    }

    var body: some View {
        NavigationStack {
            List {
                destination(symbol: "tray", title: "Inbox", isCurrent: currentSpaceID == .some(nil)) {
                    model.move(items, to: nil)
                }

                ForEach(model.spaces) { space in
                    destination(symbol: space.symbol, title: space.name, isCurrent: currentSpaceID == .some(space.id)) {
                        model.move(items, to: space)
                    }
                }

                Button {
                    HapticManager.shared.selection()
                    isCreating = true
                } label: {
                    Label("New space…", systemImage: "plus")
                        .dipleType(.body)
                        .foregroundStyle(DipleColor.accentInk)
                }
                .listRowBackground(DipleColor.surface)
            }
            .scrollContentBackground(.hidden)
            .background(DipleColor.canvas.ignoresSafeArea())
            .navigationTitle(items.count == 1 ? "Move note" : "Move \(items.count) notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(isPresented: $isCreating) {
                NoteSpaceEditor { name, symbol in
                    if let space = model.createSpace(named: name, symbol: symbol) {
                        model.move(items, to: space)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private func destination(
        symbol: String,
        title: String,
        isCurrent: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            HapticManager.shared.impact(.light)
            action()
            dismiss()
        } label: {
            HStack(spacing: DipleSpace.m) {
                Image(systemName: symbol)
                    .dipleIcon(15)
                    .foregroundStyle(DipleColor.textSecondary)
                    .frame(width: 24)
                Text(title)
                    .dipleType(.body)
                    .foregroundStyle(DipleColor.textPrimary)
                Spacer()
                if isCurrent {
                    Image(systemName: "checkmark")
                        .dipleIcon(13, weight: .semibold)
                        .foregroundStyle(DipleColor.accentInk)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .listRowBackground(DipleColor.surface)
        .accessibilityAddTraits(isCurrent ? [.isSelected] : [])
    }
}

// MARK: - Arranging the spaces

/// The spaces in the reader's order, to be dragged into a new one, renamed or deleted.
///
/// A sheet in edit mode rather than drag handles on the Desk itself: the Desk is read far more
/// often than it is rearranged, and a table of contents that grows handles under a stray long
/// press is one that moves when you meant to open it.
struct NotesSpacesEditor: View {
    @ObservedObject var model: NotesWorkshopModel

    @Environment(\.dismiss) private var dismiss
    @State private var editing: NoteSpace?
    @State private var toDelete: NoteSpace?

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.spaces) { space in
                    Button {
                        editing = space
                    } label: {
                        HStack(spacing: DipleSpace.m) {
                            Image(systemName: space.symbol)
                                .dipleIcon(15)
                                .foregroundStyle(DipleColor.textSecondary)
                                .frame(width: 24)
                            Text(space.name)
                                .dipleType(.body)
                                .foregroundStyle(DipleColor.textPrimary)
                            Spacer()
                            let count = model.spaceCounts[space.id] ?? 0
                            if count > 0 {
                                Text("\(count)")
                                    .dipleType(.footnote, weight: .regular)
                                    .monospacedDigit()
                                    .foregroundStyle(DipleColor.textTertiary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(DipleColor.surface)
                }
                .onMove { source, destination in
                    model.moveSpaces(from: source, to: destination)
                }
                .onDelete { offsets in
                    toDelete = offsets.first.map { model.spaces[$0] }
                }
            }
            .environment(\.editMode, .constant(.active))
            .scrollContentBackground(.hidden)
            .background(DipleColor.canvas.ignoresSafeArea())
            .navigationTitle("Spaces")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $editing) { space in
                NoteSpaceEditor(space: space) { name, symbol in
                    model.update(space, name: name, symbol: symbol)
                }
            }
            .spaceDeletionAlert(model: model, space: $toDelete)
        }
    }
}

extension View {
    /// The one question a space asks before it goes, and the number that makes it a real one.
    /// Its notes are never deleted with it; they go back to the Inbox.
    func spaceDeletionAlert(
        model: NotesWorkshopModel,
        space: Binding<NoteSpace?>,
        onDeleted: @escaping () -> Void = {}
    ) -> some View {
        alert(
            "Delete “\(space.wrappedValue?.name ?? "")”?",
            isPresented: Binding(
                get: { space.wrappedValue != nil },
                set: { if !$0 { space.wrappedValue = nil } }
            ),
            presenting: space.wrappedValue
        ) { target in
            Button("Delete", role: .destructive) {
                // The caller leaves first — a page standing on this space must be gone before
                // the space is, or it redraws for a frame as whatever it falls back to.
                onDeleted()
                model.delete(target)
            }
            Button("Cancel", role: .cancel) {}
        } message: { target in
            let count = model.spaceCounts[target.id] ?? 0
            Text(count == 0
                ? "The space is empty."
                : (count == 1 ? "Its note moves to the Inbox." : "Its \(count) notes move to the Inbox."))
        }
    }
}
