import SwiftUI
// Scoped on purpose: a plain `import ReadiumShared` brings its own `Content` into the file and
// breaks every `ViewModifier` in it. See the note on `MarginaliaView`.
import struct ReadiumShared.Locator

/// A page of the notes workshop that is not a note.
public enum NotesPlace: Hashable {
    case inbox
    case space(String)
    /// Notes written about one source, by its book id.
    case source(String)
    case tasks
    /// Every day's page, newest day first.
    case journal
    case allNotes
    /// The All notes board opened with one word already pressed.
    case tag(String)
    case tags
    case trash
}

/// The notes workshop: one stack, the way Things is one list.
///
/// The Desk is its first page, and everything else is one push away from it — a space, the
/// Inbox, a source's notes, the board of all notes. There are no tabs inside the mode: the bar
/// holds only the way back to Reading and the `+`, and a pill of places here would say "there is
/// somewhere else to go" in a workshop that is a single room with shelves.
///
/// Every route of the stack is declared here and nowhere below, because SwiftUI keeps only the
/// declaration nearest the root for a type and drops the rest silently (see "Home и навигация"
/// in CLAUDE.md). The All notes board is embedded for the same reason: it pushes onto this path
/// and lets this view resolve what it pushed.
public struct NotesWorkshopView: View {
    @StateObject private var model = NotesWorkshopModel()
    @State private var path = NavigationPath()
    /// The place each level of the stack stands for, kept beside `path` because a
    /// `NavigationPath` cannot be read back. `nil` is a level pushed by something that is not a
    /// place — a note, a book — which belongs to the place under it. It is what the bar's `+`
    /// asks to know where the new note goes.
    @State private var places: [NotesPlace?] = []
    @State private var editingPassage: PassageItem?
    /// Where to go once the passage sheet has finished closing: a push raised from inside a
    /// sheet lands in a hierarchy that is still tearing that sheet down and is lost.
    @State private var pendingRoute: NoteRoute?
    @State private var pendingReader: (book: Book, locatorJSON: String)?
    /// Counts arrivals from outside the app, and is the note pages' identity.
    ///
    /// An arrival empties the stack and pushes its page in one update, so the new page stands at
    /// the position the old one left — and SwiftUI kept the old page there, with its `@State`:
    /// asked for Today over a blank new note, it showed the blank note under Today's route, marked
    /// Saved. A new count makes it a new page.
    @State private var arrivals = 0

    public init() {}

    public var body: some View {
        NavigationStack(path: $path) {
            NotesDeskView(model: model, open: open, openNote: openNote, openToday: openToday)
                // Set but hidden: it labels the back button of everything pushed from here.
                .navigationTitle("Notes")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar(.hidden, for: .navigationBar)
                .navigationDestination(for: NotesPlace.self) { place in
                    page(for: place)
                }
                .navigationDestination(for: NoteRoute.self) { route in
                    notePage(for: route)
                }
                .navigationDestination(for: MarginaliaRoute.self) { route in
                    switch route {
                    case let .passage(book, locatorJSON):
                        ReaderContainerView(
                            book: book,
                            startingLocator: Locator.from(jsonString: locatorJSON),
                            onReadingUpdated: { model.load() }
                        )
                    }
                }
                .navigationDestination(for: Book.self) { book in
                    ReaderContainerView(book: book, onReadingUpdated: { model.load() })
                }
        }
        .onChange(of: path.count) { _, count in
            if places.count > count {
                places = Array(places.prefix(count))
            } else {
                while places.count < count { places.append(nil) }
            }
        }
        .sheet(item: $editingPassage, onDismiss: consumePending) { passage in
            passageEditor(for: passage)
        }
        .alert("Error", isPresented: $model.showErrorAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "An unknown error occurred.")
        }
        // The bar's `+`. The workshop owns its stack, so it is the one that answers.
        .onReceive(NotificationCenter.default.publisher(for: .dipleComposeNote)) { _ in
            compose()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dipleNotesArrival)) { notification in
            guard let raw = notification.object as? String, let route = DipleShortcut(rawValue: raw) else { return }
            arrive(route)
        }
        .refreshesOnTabActivation { model.load() }
    }

    // MARK: - Navigation

    private func open(_ place: NotesPlace) {
        places.append(place)
        path.append(place)
    }

    private func openNote(_ route: NoteRoute) {
        path.append(route)
    }

    /// A page asked for from outside the app, opened from the Desk rather than from wherever the
    /// stack was left.
    ///
    /// The bar's `+` is contextual because the writer can see where they stand. A button on the
    /// Lock Screen cannot: "New note" pressed there while a space was left open yesterday would
    /// file the thought in that space, out of sight. So an arrival goes where its name says — a new
    /// note waits in the Inbox, Today is today's page — and the page that was open is saved on its
    /// way off the stack like any page that is left.
    private func arrive(_ route: DipleShortcut) {
        arrivals += 1
        places = []
        path = NavigationPath()
        switch route {
        case .newNote:
            openNote(.new)
        case .today:
            openToday()
        case .inbox:
            open(.inbox)
        case .notes:
            break
        }
    }

    /// Today's page: the one already begun, or a fresh one that exists from its first word.
    private func openToday() {
        if let page = model.todayPage() {
            openNote(.existing(page))
        } else {
            openNote(.daily(Note.dailyKey(for: Date())))
        }
    }

    /// The place the reader is standing in, for the `+`: the nearest level of the stack that is
    /// a place, so a note opened from a space still counts as being in that space.
    private var currentPlace: NotesPlace? {
        places.last { $0 != nil } ?? nil
    }

    /// A new note, born where the reader stands — Things' Magic Plus, for pages. In a space it
    /// is filed in that space; on a source's page it is written about that source, with the
    /// source's link and its name as a tag, exactly as the pencil in the reader makes it; anywhere
    /// else it waits in the Inbox.
    private func compose() {
        switch currentPlace {
        case .space(let id):
            if let space = model.space(id: id) {
                openNote(.newInSpace(space))
                return
            }
        case .source(let id):
            if let book = model.book(id: id) {
                openNote(.newFromSource(book))
                return
            }
        case .journal:
            // In the journal, the page to write on is today's.
            openToday()
            return
        default:
            break
        }
        openNote(.new)
    }

    // MARK: - Pages

    @ViewBuilder
    private func page(for place: NotesPlace) -> some View {
        switch place {
        case .inbox:
            NotesListView(model: model, kind: .inbox, openNote: openNote)
        case .space(let id):
            if let space = model.space(id: id) {
                NotesListView(model: model, kind: .space(space), openNote: openNote)
            } else {
                // Deleted from under the page, here or on another device.
                NotesListView(model: model, kind: .inbox, openNote: openNote)
            }
        case .source(let id):
            if let book = model.book(id: id) {
                NotesListView(model: model, kind: .source(book), openNote: openNote)
            } else {
                NotesListView(model: model, kind: .inbox, openNote: openNote)
            }
        case .tasks:
            NotesTasksView(model: model, openNote: openNote)
        case .journal:
            NotesListView(model: model, kind: .journal, openNote: openNote)
        case .allNotes:
            MarginaliaView(
                door: .notes,
                embedding: MarginaliaEmbedding(title: "All notes", path: $path)
            )
        case .tag(let tag):
            MarginaliaView(
                door: .notes,
                embedding: MarginaliaEmbedding(title: "#\(tag)", path: $path, initialTag: tag)
            )
        case .tags:
            NotesTagsView(model: model, open: open)
        case .trash:
            NotesTrashView(model: model)
        }
    }

    /// The one note editor in the app, given everything the workshop holds — every note for its
    /// wiki links, every passage for its Connections, the whole vocabulary for its tag menu.
    ///
    /// Pushed the ordinary way, the `+`'s page included. It was meant to zoom out of the `+`, and
    /// that was tried: with the bar as the source the page grew out of the middle of the screen
    /// (the bar is outside the stack, where a zoom does not look for its source), and with an
    /// invisible stand-in in each page's corner the source was found but the zoom stalled for a
    /// second before snapping to its end. Both seen frame by frame on the simulator. A push that
    /// always works beats a flourish that sometimes hangs.
    private func notePage(for route: NoteRoute) -> some View {
        NoteDetailView(
            route: route,
            books: model.books,
            suggestedTags: model.tagVocabulary,
            allNotes: model.items,
            passages: model.passages,
            onSave: { note, tags in model.save(note, tags: tags) },
            onDelete: { model.trash([$0]) },
            onOpenNote: { openNote(.existing($0)) },
            onOpenPassage: { editingPassage = $0 }
        )
        .id(arrivals)
    }

    // MARK: - A passage, from a note's Connections

    /// The reader's own passage editor, not a second one — the same sheet the board opens.
    private func passageEditor(for passage: PassageItem) -> some View {
        HighlightEditorView(
            quote: passage.highlight.text,
            initialColorHex: passage.highlight.colorHex,
            initialComment: passage.comment,
            initialTags: passage.tags,
            tagSuggestions: model.passageTagVocabulary,
            isExisting: true,
            sourceTitle: passage.book?.title ?? passage.highlight.bookTitle,
            onSave: { colorHex, comment, tags in
                model.savePassage(passage, colorHex: colorHex, comment: comment, tags: tags)
            },
            onDelete: { model.deletePassage(passage) },
            onOpenInSource: openInSource(for: passage),
            onExpandIntoNote: { pendingRoute = .newFromPassage(passage) }
        )
    }

    private func openInSource(for passage: PassageItem) -> (() -> Void)? {
        guard let book = passage.book, passage.highlight.parsedLocator != nil else { return nil }
        return { pendingReader = (book, passage.highlight.locator) }
    }

    private func consumePending() {
        if let route = pendingRoute {
            pendingRoute = nil
            openNote(route)
        } else if let reader = pendingReader {
            pendingReader = nil
            path.append(MarginaliaRoute.passage(book: reader.book, locatorJSON: reader.locatorJSON))
        }
    }
}

