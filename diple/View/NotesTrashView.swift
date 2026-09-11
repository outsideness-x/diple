import SwiftUI

/// Recently deleted: what was thrown away in the last thirty days, and the way back.
///
/// Deleting a note stopped asking the moment this page existed — a question in front of an act
/// that can be undone is only a delay. The questions moved here, in front of the two acts that
/// cannot: deleting one note for good, and emptying the page.
struct NotesTrashView: View {
    @ObservedObject var model: NotesWorkshopModel

    @State private var toDelete: NoteItem?
    @State private var isConfirmingEmpty = false

    var body: some View {
        List {
            DipleMasthead(title: "Recently deleted", strapline: strapline) {
                if !model.trashed.isEmpty {
                    Button {
                        HapticManager.shared.selection()
                        isConfirmingEmpty = true
                    } label: {
                        Text("Empty")
                            .dipleType(.footnote, weight: .semibold)
                            .foregroundStyle(DipleColor.destructive)
                            .frame(minWidth: 44, minHeight: 44)
                    }
                    .buttonStyle(.readerControl)
                }
            }
            .listRowInsets(EdgeInsets(top: 0, leading: DipleSpace.xl, bottom: DipleSpace.m, trailing: DipleSpace.xl))
            .deskListRow()

            if model.trashed.isEmpty {
                Text("Deleted notes stay here for thirty days, then go for good.")
                    .dipleType(.callout)
                    .foregroundStyle(DipleColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .listRowInsets(EdgeInsets(top: DipleSpace.l, leading: DipleSpace.xl, bottom: 0, trailing: DipleSpace.xl))
                    .deskListRow()
            }

            ForEach(model.trashed) { item in
                row(item)
                    .listRowInsets(EdgeInsets(top: 0, leading: DipleSpace.xl, bottom: 0, trailing: DipleSpace.xl))
                    .deskListRow()
                    .swipeActions(edge: .leading, allowsFullSwipe: true) {
                        Button {
                            HapticManager.shared.impact(.light)
                            model.restore(item)
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        .tint(DipleColor.accent)
                    }
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        Button(role: .destructive) {
                            toDelete = item
                        } label: {
                            Label("Delete now", systemImage: "trash")
                        }
                        // The shell's accent tint would otherwise paint it blue; see NotesListView.
                        .tint(DipleColor.destructive)
                    }
                    .contextMenu {
                        Button {
                            model.restore(item)
                        } label: {
                            Label("Restore", systemImage: "arrow.uturn.backward")
                        }
                        Button(role: .destructive) {
                            toDelete = item
                        } label: {
                            Label("Delete now", systemImage: "trash")
                        }
                    }
            }
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

    private var strapline: String? {
        let count = model.trashed.count
        guard count > 0 else { return nil }
        return count == 1 ? "1 note" : "\(count) notes"
    }

    /// Not a link: a note in the bin is not opened, it is brought back or let go. The row says
    /// which it was and how long is left before the choice is made for the reader.
    private func row(_ item: NoteItem) -> some View {
        VStack(alignment: .leading, spacing: DipleSpace.xs) {
            Text(item.displayTitle)
                .dipleType(.headline)
                .foregroundStyle(DipleColor.textSecondary)
                .lineLimit(2)
            Text(dateline(item))
                .dipleType(.caption)
                .foregroundStyle(DipleColor.textTertiary)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DipleSpace.m)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DipleColor.hairline).frame(height: DipleStroke.hairline)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityHint("Swipe right to restore")
    }

    private func dateline(_ item: NoteItem) -> String {
        guard let trashedAt = item.note.trashedAt else { return "" }
        let deleted = trashedAt.formatted(.relative(presentation: .named, unitsStyle: .wide))
        // Rounded up: a note deleted a minute ago has thirty days, not twenty-nine and change.
        let remaining = trashedAt.addingTimeInterval(Note.trashRetention).timeIntervalSinceNow
        let days = max(0, Int((remaining / 86_400).rounded(.up)))
        let left = days <= 1 ? (remaining > 0 ? "1 day left" : "goes today") : "\(days) days left"
        return "Deleted \(deleted) · \(left)"
    }
}
