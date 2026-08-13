import SwiftUI
import UniformTypeIdentifiers

/// Home's own screens, as values rather than inline destination views. A view-based
/// `NavigationLink` pushes content the stack's `path` cannot describe, which leaves
/// programmatic and link-driven navigation disagreeing about what is on screen.
public enum HomeRoute: Hashable {
    case allHighlights
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
    @State private var isShowingSettings = false
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
                        welcome
                        quickCapture

                        if let book = library.continueReadingBook {
                            section("CONTINUE") {
                                NavigationLink(value: book) {
                                    HomeContinueReadingCard(book: book)
                                }
                                .buttonStyle(.bookCard)
                                .matchedTransitionSource(id: book.id, in: readingNamespace)
                            }
                        }

                        if highlights.totalQuoteCount > 0 {
                            section("HIGHLIGHTS") {
                                DailyResurfacingCard { path.append($0) }

                                NavigationLink(value: HomeRoute.allHighlights) {
                                    HomeOpenCollectionRow(
                                        title: "All highlights",
                                        detail: "\(highlights.totalQuoteCount) saved passages",
                                        systemImage: "quote.opening"
                                    )
                                }
                                .buttonStyle(.bookCard)
                            }
                        }

                        if !recentNotes.isEmpty {
                            section("RECENT NOTES") {
                                VStack(spacing: DipleSpace.s) {
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

                if library.isImporting {
                    importingOverlay
                }
            }
            .navigationTitle("diple.")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        HapticManager.shared.selection()
                        isShowingSettings = true
                    } label: {
                        Image(systemName: "gearshape")
                            .dipleIcon(16)
                            .foregroundStyle(DipleColor.textSecondary)
                            .frame(width: 44, height: 44)
                    }
                    .buttonStyle(.readerControl)
                    .accessibilityLabel("Settings")
                }
            }
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
            .sheet(isPresented: $isShowingSettings) {
                AppSettingsView()
            }
            .alert("Error", isPresented: $library.showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(library.errorMessage ?? "An unknown error occurred.")
            }
            .onAppear(perform: reload)
        }
    }

    /// Just the date. The rotating aphorism under it ("Return to an idea worth keeping.")
    /// is gone: Notes opened on a near-identical line, and the variant that collided was the
    /// one shown whenever any highlight existed — which is to say almost always, so tabbing
    /// between the two screens read the same sentence twice. It also spent the widest type in
    /// the app on a line that told the reader nothing they could act on. The date stays
    /// because it orients rather than declaims.
    private var welcome: some View {
        Text(dayTitle.uppercased())
            .dipleType(.nano, weight: .semibold)
            .foregroundStyle(DipleColor.accent)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var quickCapture: some View {
        HStack(spacing: DipleSpace.s) {
            HomeQuickAction(title: "Save link", systemImage: "link") {
                isImportingLink = true
            }

            HomeQuickAction(title: "Import", systemImage: "doc.badge.plus") {
                isImportingFile = true
            }

            NavigationLink(value: NoteRoute.new) {
                Label("New note", systemImage: "square.and.pencil")
                    .dipleType(.footnote, weight: .semibold)
                    .foregroundStyle(DipleColor.textOnAccent)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: 44)
                    .background(DipleColor.accent, in: RoundedRectangle(cornerRadius: DipleRadius.m))
            }
            .buttonStyle(.readerControl)
            .accessibilityIdentifier("home.newNote")
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
                .foregroundStyle(DipleColor.accent)

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

private struct HomeQuickAction: View {
    let title: String
    let systemImage: String
    let action: () -> Void

    var body: some View {
        Button {
            HapticManager.shared.selection()
            action()
        } label: {
            Label(title, systemImage: systemImage)
                .dipleType(.footnote, weight: .semibold)
                .foregroundStyle(DipleColor.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: 44)
                .background(DipleColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DipleRadius.m))
                .overlay {
                    RoundedRectangle(cornerRadius: DipleRadius.m)
                        .stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline)
                }
        }
        .buttonStyle(.readerControl)
    }
}

private struct HomeContinueReadingCard: View {
    let book: Book
    @ScaledMetric(relativeTo: .title3) private var coverWidth: CGFloat = 70

    private var progress: Double { min(max(book.progress, 0), 1) }

    var body: some View {
        HStack(spacing: DipleSpace.l) {
            BookCoverView(
                coverPath: book.coverPath,
                title: book.title,
                author: book.author,
                isCompact: true
            )
            .frame(width: min(coverWidth, 104), height: min(coverWidth, 104) * 1.5)

            VStack(alignment: .leading, spacing: DipleSpace.s) {
                Text(book.title)
                    .dipleType(.headline)
                    .foregroundStyle(DipleColor.textPrimary)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)

                BookSubtitleView(book: book)

                Spacer(minLength: DipleSpace.xs)

                ProgressView(value: progress)
                    .tint(DipleColor.accent)

                HStack {
                    Text("\(Int((progress * 100).rounded()))%")
                        .monospacedDigit()
                    Spacer()
                    Label("Continue", systemImage: "arrow.right")
                }
                .dipleType(.footnote, weight: .semibold)
                .foregroundStyle(DipleColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DipleSpace.m)
        .background(alignment: .topTrailing) {
            AccentWash(diameter: 180).offset(x: 56, y: -68)
        }
        .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.l)
        .accessibilityElement(children: .combine)
        .accessibilityHint("Opens at your last reading position")
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
                .foregroundStyle(DipleColor.accent)
                .frame(width: 32, height: 32)
                .background(DipleColor.accentSoft, in: RoundedRectangle(cornerRadius: DipleRadius.s))

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
        .padding(DipleSpace.m)
        .craftSurface()
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
                .foregroundStyle(DipleColor.accent)
                .frame(width: 32, height: 32)
                .background(DipleColor.accentSoft, in: RoundedRectangle(cornerRadius: DipleRadius.s))

            VStack(alignment: .leading, spacing: DipleSpace.xs) {
                Text(title)
                    .dipleType(.body, weight: .semibold)
                    .foregroundStyle(DipleColor.textPrimary)
                Text(detail)
                    .dipleType(.caption)
                    .foregroundStyle(DipleColor.textTertiary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .dipleIcon(10, weight: .semibold)
                .foregroundStyle(DipleColor.textQuaternary)
        }
        .padding(DipleSpace.m)
        .craftSurface()
        .accessibilityElement(children: .combine)
    }
}
