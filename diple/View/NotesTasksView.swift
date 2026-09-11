import SwiftUI

/// Every open box in every note, in one list — the Things part of the workshop.
///
/// No new kind of thing: a task is a line of Markdown, found where it was written, and ticking it
/// here rewrites that line in its note exactly as ticking it on the note's page does
/// (`NoteMarkdown.togglingTask(atLine:)`). Grouped by note, because a task means something only
/// next to the thought it came out of; the group's head opens that thought.
///
/// A ticked task stays where it is for a beat, struck through, before the list closes over it:
/// the thumb has to see that it landed.
struct NotesTasksView: View {
    @ObservedObject var model: NotesWorkshopModel
    let openNote: (NoteRoute) -> Void

    @State private var lingering: Set<NotesDesk.TaskKey> = []

    /// How long a ticked task stays on the list before it goes.
    private let lingerFor: Duration = .milliseconds(1200)

    var body: some View {
        let groups = NotesDesk.openTasks(model.items, lingering: lingering)
        let open = groups.reduce(0) { $0 + $1.tasks.filter { !$0.isCompleted }.count }

        ScrollView {
            LazyVStack(alignment: .leading, spacing: DipleSpace.xxl) {
                DipleMasthead(title: "Tasks", strapline: strapline(open: open, isEmpty: groups.isEmpty)) {
                    EmptyView()
                }

                if groups.isEmpty {
                    VStack(alignment: .leading, spacing: DipleSpace.s) {
                        Text("Nothing to do")
                            .dipleType(.editorialTitle)
                            .foregroundStyle(DipleColor.textPrimary)
                        Text("A line that begins with - [ ] in any note is a task, and it collects here.")
                            .dipleType(.callout)
                            .foregroundStyle(DipleColor.textTertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    // A beat late, so the last task has finished leaving before the empty page
                    // arrives: the two cross-fading over each other in the same place printed two
                    // lines of text on top of one another.
                    .transition(.opacity.animation(DipleMotion.gentle.delay(0.3)))
                }

                ForEach(groups) { group in
                    section(group)
                }
            }
            .padding(.horizontal, DipleSpace.xl)
            .padding(.bottom, DipleSpace.scrollBottom + 72)
            .animation(DipleMotion.standard, value: groups)
        }
        .background(DipleColor.canvas.ignoresSafeArea())
        .tracksTabBarCollapse()
        .navigationTitle("")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DipleColor.canvas, for: .navigationBar)
    }

    private func section(_ group: NotesDesk.TaskGroup) -> some View {
        VStack(alignment: .leading, spacing: DipleSpace.s) {
            Button {
                HapticManager.shared.selection()
                openNote(.existing(group.item))
            } label: {
                HStack(spacing: DipleSpace.xs) {
                    Text(group.item.displayTitle)
                        .dipleType(.footnote, weight: .semibold)
                        .foregroundStyle(DipleColor.textSecondary)
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
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityHint("Opens the note")

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
                    .accessibilityHint(task.isCompleted ? "Mark as not done" : "Mark as done")
                }
            }
        }
        .padding(.bottom, DipleSpace.s)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DipleColor.hairline).frame(height: DipleStroke.hairline)
        }
    }

    /// The line under the name. While a ticked task is still lingering it reads "All done"
    /// rather than vanishing: a strapline that disappeared the moment the last box was ticked
    /// took its line of height with it, and the whole page jumped up under the finger.
    private func strapline(open: Int, isEmpty: Bool) -> String? {
        switch open {
        case 0: return isEmpty ? nil : "All done"
        case 1: return "1 open"
        default: return "\(open) open"
        }
    }

    /// Where the note stands, printed small beside its name: the space, or the source.
    private func placeName(of item: NoteItem) -> String? {
        if let id = item.note.spaceId, let space = model.space(id: id) { return space.name }
        return item.book?.title
    }

    private func toggle(_ task: NoteTask, in item: NoteItem) {
        let key = NotesDesk.TaskKey(noteID: item.id, lineIndex: task.lineIndex)
        if task.isCompleted {
            // Unticked while it still lingers: it is simply open again.
            HapticManager.shared.selection()
            lingering.remove(key)
            model.toggleTask(task, in: item)
            return
        }

        HapticManager.shared.impact(.light)
        lingering.insert(key)
        model.toggleTask(task, in: item)
        Task { @MainActor in
            try? await Task.sleep(for: lingerFor)
            withAnimation(DipleMotion.gentle) { _ = lingering.remove(key) }
        }
    }
}
