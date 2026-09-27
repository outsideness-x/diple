import SwiftUI

/// Everything written about one book, raised over its page: the list the note pages stand on.
///
/// The reader's pencil used to open a blank note and nothing else. A second thought about the
/// same book meant a second blank page with no sign the first existed, and the only way back to
/// either was the third segment of the contents sheet — a book could have many notes, and the
/// reader could not find their way among them from where the notes were written.
///
/// So the pencil opens this list with a new page already on top of it. Writing is still one tap
/// — the thought arrives at an open page — and the notes already written are exactly one Back
/// away, under the book's own name. Each note page carries its own pencil too, so a run of
/// thoughts is written as a run of notes without leaving the book.
struct BookNotebookView: View {
    let book: Book
    /// This book's notes, most recently touched first — the same rows the contents sheet and the
    /// notes half of Highlights hold.
    let notes: [NoteItem]
    let onOpen: (NoteItem) -> Void
    let onNewNote: () -> Void
    let onDelete: (NoteItem) -> Void

    @Environment(\.dismiss) private var dismiss
    /// The note a trash tap is asking about. Writing cannot be made again the way a passage can
    /// be marked again, so it is asked about here as everywhere else.
    @State private var noteToDelete: NoteItem?

    private var countLine: String {
        switch notes.count {
        case 0: return "No notes yet"
        case 1: return "1 note"
        default: return "\(notes.count) notes"
        }
    }

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DipleSpace.m) {
                header
                    .padding(.bottom, DipleSpace.s)

                newNoteButton

                if notes.isEmpty {
                    Text("A note written here is filed under this book and carries its name as a tag. It waits in Highlights, under Notes, with everything else you have written.")
                        .dipleType(.footnote, weight: .regular)
                        .foregroundStyle(DipleColor.textTertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, DipleSpace.s)
                } else {
                    ForEach(notes) { item in
                        NoteOutlineRowView(
                            item: item,
                            onSelect: { onOpen(item) },
                            onDelete: { noteToDelete = item }
                        )
                    }
                }
            }
            .padding(.horizontal, DipleSpace.xl)
            .padding(.top, DipleSpace.m)
            .padding(.bottom, DipleSpace.xxxl)
        }
        .background(DipleColor.canvas.ignoresSafeArea())
        // What a note page pushed from here labels its way back with.
        .navigationTitle("Notes")
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(DipleColor.canvas, for: .navigationBar)
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
                    .foregroundStyle(DipleColor.accentInk)
            }
        }
        .animation(DipleMotion.standard, value: notes)
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
                onDelete(item)
                noteToDelete = nil
            }
            Button("Cancel", role: .cancel) { noteToDelete = nil }
        } message: { _ in
            Text("This note will be deleted.")
        }
    }

    /// Whose notebook this is. The book's name is set in the editorial face, as a work's title
    /// is everywhere else in the app; the count under it is what the list below is about to say.
    private var header: some View {
        VStack(alignment: .leading, spacing: DipleSpace.xs) {
            Text("NOTES ON")
                .dipleType(.nano)
                .foregroundStyle(DipleColor.accentInk)
            Text(book.title)
                .dipleType(.editorialTitle)
                .foregroundStyle(DipleColor.textPrimary)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
            Text(countLine)
                .dipleType(.footnote, weight: .regular)
                .foregroundStyle(DipleColor.textTertiary)
                .monospacedDigit()
        }
        .accessibilityElement(children: .combine)
    }

    /// At the head of the list rather than only in an empty one: a reader who came back to
    /// re-read a thought is the likeliest person to have another. The same control the contents
    /// sheet's Notes segment has, so the two ways into these notes look like one.
    private var newNoteButton: some View {
        Button {
            HapticManager.shared.selection()
            onNewNote()
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
        .accessibilityIdentifier("reader.notebook.newNote")
    }
}

/// A page of a book's notebook.
///
/// Every page carries a token of its own, and the page view takes its identity from it
/// (`.id(token)`). `NoteRoute.newFromSource` is equal for every new note about one book, so a
/// second one asked for while the first is on screen would set the path to the value it already
/// holds; and even with a different route, a page that replaces the one on top stands at the
/// same position, where SwiftUI keeps the old view's `@State` — the first note's words, and the
/// id its autosave writes to.
struct BookNotebookPage: Hashable {
    let route: NoteRoute
    let token = UUID()
}
