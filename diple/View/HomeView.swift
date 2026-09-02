import SwiftUI
import UniformTypeIdentifiers
import ReadiumShared

/// Home's own screens, as values rather than inline destination views. A view-based
/// `NavigationLink` pushes content the stack's `path` cannot describe, which leaves
/// programmatic and link-driven navigation disagreeing about what is on screen.
public enum HomeRoute: Hashable {
    case allHighlights
    /// A saved passage, opened where it was written rather than in a list of passages.
    /// The locator travels as its stored JSON because `Locator` is not `Hashable`, and a
    /// navigation value must be.
    case passage(book: Book, locatorJSON: String)
}

/// The useful front door to diple: resume something, capture something, or return to an idea.
///
/// Library/Highlights/Notes used to be four equally weighted databases. Home turns the same
/// data into a next-action surface without duplicating persistence or inventing a second state
/// model: the existing view models remain the source of truth for every section and route.
public struct HomeView: View {
    @StateObject private var library = LibraryViewModel()
    @StateObject private var highlights = HubViewModel()
    @StateObject private var notes = NotesViewModel()

    @State private var isImportingFile = false
    @State private var isImportingLink = false
    /// Every push in this tab goes through one path. A screen deeper in the stack cannot
    /// register a route of its own: SwiftUI keeps only the declaration closest to the root
    /// for a given type and drops the rest, which is exactly how the Highlights rows went
    /// dead. One path here also lets a callback-driven card push the same route a
    /// `NavigationLink` uses, instead of needing a parallel binding for the same type.
    @State private var path = NavigationPath()
    @Namespace private var readingNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    private var recentNotes: [NoteItem] {
        Array(notes.items.sorted { $0.note.updatedAt > $1.note.updatedAt }.prefix(3))
    }

    private var dayTitle: String {
        Date.now.formatted(.dateTime.weekday(.wide).month(.wide).day())
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: DipleSpace.xxxl) {
                        masthead

                        // No heading over the lead. A newspaper does not label its lead
                        // story, and this one was labelled twice over: the section said
                        // CONTINUE and the block's own accent disc says the same thing in the
                        // one place a thumb can act on it. The headings that remain sit over
                        // *collections*, where they say which collection.
                        if let book = library.continueReadingBook {
                            NavigationLink(value: book) {
                                SourceLeadView(book: book, characters: library.charactersByBook[book.id])
                            }
                            .buttonStyle(.bookCard)
                            .matchedTransitionSource(id: book.id, in: readingNamespace)
                        }

                        if highlights.totalQuoteCount > 0 {
                            section("HIGHLIGHTS") {
                                DailyResurfacingCard { openResurfaced($0) }

                                NavigationLink(value: HomeRoute.allHighlights) {
                                    HomeOpenCollectionRow(
                                        title: "All highlights",
                                        detail: "\(highlights.totalQuoteCount) saved passages",
                                        systemImage: "quote.opening"
                                    )
                                    // Home is where a reader lands after closing a book, so
                                    // this is the count most likely to have moved while they
                                    // were away. Rolling it says what changed in the time they
                                    // were reading.
                                    .animation(DipleMotion.standard, value: highlights.totalQuoteCount)
                                }
                                .buttonStyle(.bookCard)
                            }
                        }

                        if !recentNotes.isEmpty {
                            section("RECENT NOTES") {
                                VStack(spacing: 0) {
                                    ForEach(recentNotes) { item in
                                        NavigationLink(value: NoteRoute.existing(item)) {
                                            HomeRecentNoteRow(item: item)
                                        }
                                        .buttonStyle(.bookCard)
                                    }
                                }
                            }
                        }

                        if library.books.isEmpty && notes.items.isEmpty && highlights.totalQuoteCount == 0 {
                            firstStep
                        }
                    }
                    .padding(.horizontal, DipleSpace.xl)
                    .padding(.top, DipleSpace.l)
                    .padding(.bottom, DipleSpace.scrollBottom)
                }
                .tracksTabBarCollapse()

                if library.isImporting {
                    importingOverlay
                }
            }
            // The title stays set even though the bar is hidden: it is what a pushed screen
            // labels its own back button with.
            .navigationTitle("diple.")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: Book.self) { book in
                readerDestination(for: book)
            }
            .navigationDestination(for: NoteRoute.self) { route in
                NoteDetailView(
                    route: route,
                    books: notes.books,
                    suggestedTags: notes.allTags,
                    allNotes: notes.items,
                    onSave: { note, tags in notes.save(note, tags: tags) },
                    onDelete: { notes.delete($0) },
                    onOpenNote: { path.append(NoteRoute.existing($0)) }
                )
            }
            .navigationDestination(for: BookQuoteSummary.self) { summary in
                BookQuotesView(summary: summary)
            }
            .navigationDestination(for: HomeRoute.self) { route in
                switch route {
                case .allHighlights:
                    HubView(path: $path)
                case let .passage(book, locatorJSON):
                    passageDestination(book: book, locatorJSON: locatorJSON)
                }
            }
            .fileImporter(
                isPresented: $isImportingFile,
                allowedContentTypes: [.epub, .pdf],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    if let url = urls.first { library.importBook(from: url) }
                case .failure(let error):
                    library.errorMessage = "Import failed: \(error.localizedDescription)"
                    library.showErrorAlert = true
                }
            }
            .sheet(isPresented: $isImportingLink) {
                ImportLinkSheetView { _ in reload() }
            }
            .alert("Error", isPresented: $library.showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(library.errorMessage ?? "An unknown error occurred.")
            }
            .refreshesOnTabActivation(reload)
        }
    }

    /// The masthead.
    ///
    /// The shared component now, not a local one: three roots opening three different ways read
    /// as three applications. What stays particular to Home is that this is the one place the
    /// wordmark is printed at all, and the one strapline that is a date rather than a count.
    ///
    /// The rotating aphorism that used to sit here is still gone, for the reason recorded when
    /// it went: Notes opened on a near-identical line, and it spent the widest type in the app
    /// on something nobody could act on. The date stays because it orients rather than declaims.
    ///
    /// **The three capture buttons are gone from the page.** They were three utility rectangles
    /// of equal weight in the second-best band of the front page — the one place a reading app
    /// should be showing something to read — and the library already carried the identical menu
    /// under a `+`. One affordance in the head, in both places, says the same thing and gives
    /// the lead its band back.
    private var masthead: some View {
        DipleMasthead(title: "diple.", strapline: dayTitle, isWordmark: true) {
            Menu {
                Button {
                    isImportingLink = true
                } label: {
                    Label("Save a link", systemImage: "link")
                }

                Button {
                    isImportingFile = true
                } label: {
                    Label("Import a file", systemImage: "doc.badge.plus")
                }

                Button {
                    path.append(NoteRoute.new)
                } label: {
                    Label("New note", systemImage: "square.and.pencil")
                }
            } label: {
                MastheadGlyph(systemImage: "plus")
            }
            .buttonStyle(.readerControl)
            .accessibilityLabel("Add to your library")
            .accessibilityIdentifier("home.add")
            .simultaneousGesture(TapGesture().onEnded {
                HapticManager.shared.selection()
            })

            MastheadButton(systemImage: "gearshape", label: "Settings") {
                // The shell presents Settings, not this screen: a sheet owned here would be
                // torn down the moment an accent is chosen inside it. See `dipleApp`.
                NotificationCenter.default.post(name: .dipleOpenSettings, object: nil)
            }
        }
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            Text(title)
                .dipleType(.micro, weight: .semibold)
                .foregroundStyle(DipleColor.textTertiary)
            content()
        }
    }

    private var firstStep: some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            Image(systemName: "arrow.down.left.and.arrow.up.right")
                .dipleIcon(22, weight: .light)
                .foregroundStyle(DipleColor.textTertiary)

            Text("Start with something real")
                .dipleType(.headline)
                .foregroundStyle(DipleColor.textPrimary)

            Text("Save an article or import a book. Your place, highlights and notes stay together from the first page.")
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DipleSpace.l)
        .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.l)
    }

    private var importingOverlay: some View {
        ZStack {
            DipleColor.canvas.opacity(0.78).ignoresSafeArea()
            VStack(spacing: DipleSpace.m) {
                ProgressView().tint(DipleColor.accent)
                Text("Adding to your library…")
                    .dipleType(.callout, weight: .medium)
                    .foregroundStyle(DipleColor.textPrimary)
            }
            .padding(DipleSpace.xxl)
            .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.l)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Adding to your library")
    }

    private func reload() {
        library.loadBooks()
        highlights.load()
        notes.load()
    }

    /// Where a resurfaced quote goes when it is tapped.
    ///
    /// Into the book, at the passage — the point of resurfacing is to return to an idea in its
    /// place, and a list of quotes is not its place. A quote whose book has been deleted still
    /// exists (see the highlights section of CLAUDE.md) and has nowhere to open, so it falls
    /// back to the group it belongs to.
    ///
    /// The two branches append **concrete** types rather than one erased value. `NavigationPath`
    /// keys its destinations on the dynamic type of what was appended, so an `AnyHashable`
    /// wrapping a `BookQuoteSummary` is looked up as `AnyHashable` — matching nothing, and
    /// SwiftUI renders its yellow "no destination" placeholder instead of the screen.
    private func openResurfaced(_ item: DailyResurfacingItem) {
        if let book = item.summary.book, item.quote.parsedLocator != nil {
            path.append(HomeRoute.passage(book: book, locatorJSON: item.quote.locator))
        } else {
            path.append(item.summary)
        }
    }

    @ViewBuilder
    private func passageDestination(book: Book, locatorJSON: String) -> some View {
        ReaderContainerView(
            book: book,
            startingLocator: Locator.from(jsonString: locatorJSON),
            onReadingUpdated: reload
        )
    }

    @ViewBuilder
    private func readerDestination(for book: Book) -> some View {
        let reader = ReaderContainerView(book: book, onReadingUpdated: reload)

        if reduceMotion {
            reader
        } else {
            reader.navigationTransition(.zoom(sourceID: book.id, in: readingNamespace))
        }
    }
}

private struct HomeRecentNoteRow: View {
    let item: NoteItem

    private var preview: String {
        item.previewText
    }

    var body: some View {
        HStack(alignment: .top, spacing: DipleSpace.m) {
            Image(systemName: "note.text")
                .dipleIcon(13, weight: .semibold)
                .foregroundStyle(DipleColor.textTertiary)
                .frame(width: 32, height: 32)
                .background(DipleColor.surfaceOverlay, in: RoundedRectangle(cornerRadius: DipleRadius.s))

            VStack(alignment: .leading, spacing: DipleSpace.xs) {
                Text(item.displayTitle)
                    .dipleType(.body, weight: .semibold)
                    .foregroundStyle(DipleColor.textPrimary)
                    .lineLimit(1)

                if !preview.isEmpty {
                    Text(preview)
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }
            }

            Spacer(minLength: DipleSpace.s)

            Image(systemName: "chevron.right")
                .dipleIcon(10, weight: .semibold)
                .foregroundStyle(DipleColor.textQuaternary)
                .padding(.top, DipleSpace.s)
        }
        .padding(.vertical, DipleSpace.m)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DipleColor.hairline)
                .frame(height: DipleStroke.hairline)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}

private struct HomeOpenCollectionRow: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: DipleSpace.m) {
            Image(systemName: systemImage)
                .dipleIcon(14, weight: .semibold)
                .foregroundStyle(DipleColor.textTertiary)
                .frame(width: 32, height: 32)
                .background(DipleColor.surfaceOverlay, in: RoundedRectangle(cornerRadius: DipleRadius.s))

            VStack(alignment: .leading, spacing: DipleSpace.xs) {
                Text(title)
                    .dipleType(.body, weight: .semibold)
                    .foregroundStyle(DipleColor.textPrimary)
                Text(detail)
                    .dipleType(.caption)
                    .foregroundStyle(DipleColor.textTertiary)
                    .monospacedDigit()
                    .contentTransition(.numericText())
            }

            Spacer()

            Image(systemName: "chevron.right")
                .dipleIcon(10, weight: .semibold)
                .foregroundStyle(DipleColor.textQuaternary)
        }
        .padding(.vertical, DipleSpace.m)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DipleColor.hairline)
                .frame(height: DipleStroke.hairline)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
