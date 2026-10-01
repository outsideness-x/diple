import SwiftUI
import Combine

@MainActor
private final class SourceOverviewViewModel: ObservableObject {
    @Published var book: Book
    @Published var highlights: [Highlight] = []
    @Published var highlightTags: [String: [String]] = [:]
    @Published var notes: [NoteItem] = []
    @Published var tags: [String] = []
    @Published var characters: Int?
    @Published var errorMessage: String?

    init(book: Book) {
        self.book = book
        load()
    }

    func load() {
        do {
            book = try AppDatabase.shared.fetchBook(id: book.id) ?? book
            highlights = try AppDatabase.shared.fetchHighlights(forBookId: book.id)
            highlightTags = try AppDatabase.shared.fetchTagsByHighlight(forBookId: book.id)
            tags = try AppDatabase.shared.fetchTags(forBookId: book.id)
            characters = try AppDatabase.shared.contentCharacterCount(
                bookID: book.id,
                isArticle: book.isArticle
            )
            let tagsByNote = try AppDatabase.shared.fetchTagsByNote()
            notes = try AppDatabase.shared.fetchAllNotes()
                .filter { $0.bookId == book.id }
                .map { NoteItem(note: $0, tags: tagsByNote[$0.id] ?? [], book: book) }
        } catch {
            errorMessage = "Failed to load this source: \(error.localizedDescription)"
        }
    }
}

/// The source as a container for reading and thinking. It is deliberately a secondary sheet:
/// tapping a library card still opens reading immediately, while a long press reveals this
/// overview for the less frequent “what have I made from this?” question.
public struct SourceOverviewView: View {
    @StateObject private var viewModel: SourceOverviewViewModel
    @Environment(\.dismiss) private var dismiss
    /// This sheet owns its own stack, so it needs its own path for a wiki link to push onto.
    @State private var path = NavigationPath()
    let onReadingUpdated: () -> Void

    public init(book: Book, onReadingUpdated: @escaping () -> Void) {
        _viewModel = StateObject(wrappedValue: SourceOverviewViewModel(book: book))
        self.onReadingUpdated = onReadingUpdated
    }

    public var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: DipleSpace.xxl) {
                        identity

                        if LibraryStatusFilter.finished.includes(viewModel.book) {
                            NavigationLink {
                                SecondReadView(book: viewModel.book) {
                                    viewModel.load()
                                    onReadingUpdated()
                                }
                            } label: {
                                SecondReadEntryView(fragmentCount: viewModel.highlights.count)
                            }
                            .buttonStyle(.bookCard)
                        }

                        actions

                        // The same rows Highlights sets its two halves in. These were cards —
                        // `QuoteCardView` for passages, a boxed row with an icon for notes —
                        // so a passage was one object on this page and another one tab away.
                        // The rows leave out the book's name: the whole page is that book.
                        if !viewModel.highlights.isEmpty {
                            section("Highlights", count: viewModel.highlights.count) {
                                ForEach(viewModel.highlights.prefix(3)) { highlight in
                                    PassageRowView(
                                        passage: PassageItem(
                                            highlight: highlight,
                                            tags: viewModel.highlightTags[highlight.id] ?? [],
                                            book: viewModel.book
                                        ),
                                        showsSource: false
                                    )
                                }

                                if viewModel.highlights.count > 3 {
                                    NavigationLink {
                                        BookQuotesView(summary: summary)
                                    } label: {
                                        collectionLink("All \(viewModel.highlights.count) highlights")
                                    }
                                    .buttonStyle(.readerControl)
                                }
                            }
                        }

                        if !viewModel.notes.isEmpty {
                            section("Notes", count: viewModel.notes.count) {
                                ForEach(viewModel.notes.prefix(3)) { item in
                                    NavigationLink(value: NoteRoute.existing(item)) {
                                        NoteCardView(item: item, style: .row, showsSource: false)
                                    }
                                    .buttonStyle(.bookCard)
                                }
                            }
                        }

                        if viewModel.highlights.isEmpty && viewModel.notes.isEmpty {
                            VStack(alignment: .leading, spacing: DipleSpace.s) {
                                Text("Nothing captured yet")
                                    .dipleType(.headline)
                                    .foregroundStyle(DipleColor.textPrimary)
                                Text("Start reading, then highlight a passage or write a note. Everything from this source will collect here.")
                                    .dipleType(.callout)
                                    .foregroundStyle(DipleColor.textTertiary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(DipleSpace.l)
                            .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.l)
                        }
                    }
                    .padding(.horizontal, DipleSpace.xl)
                    .padding(.top, DipleSpace.l)
                    .padding(.bottom, DipleSpace.scrollBottom)
                }
            }
            .navigationTitle("Source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .foregroundStyle(DipleColor.accentInk)
                }
            }
            .navigationDestination(for: Book.self) { book in
                ReaderContainerView(book: book) {
                    viewModel.load()
                    onReadingUpdated()
                }
            }
            .navigationDestination(for: NoteRoute.self) { route in
                NoteDetailView(
                    route: route,
                    books: [viewModel.book],
                    suggestedTags: Array(Set(viewModel.notes.flatMap(\.tags))).sorted(),
                    allNotes: viewModel.notes,
                    passages: viewModel.highlights.map {
                        PassageItem(
                            highlight: $0,
                            tags: viewModel.highlightTags[$0.id] ?? [],
                            book: viewModel.book
                        )
                    },
                    onSave: { note, tags in
                        do {
                            try AppDatabase.shared.saveNote(note, tags: tags)
                            viewModel.load()
                            return true
                        } catch {
                            viewModel.errorMessage = "Failed to save note: \(error.localizedDescription)"
                            return false
                        }
                    },
                    onDelete: { item in
                        try? AppDatabase.shared.trashNote(id: item.id)
                        viewModel.load()
                    },
                    onOpenNote: { path.append(NoteRoute.existing($0)) }
                )
            }
            .alert("Source error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred.")
            }
        }
        .presentationDetents([.large])
    }

    private var identity: some View {
        HStack(alignment: .top, spacing: DipleSpace.l) {
            BookCoverView(
                coverPath: viewModel.book.coverPath,
                title: viewModel.book.title,
                author: viewModel.book.author,
                isCompact: true
            )
            .frame(width: 74, height: 111)

            VStack(alignment: .leading, spacing: DipleSpace.s) {
                // The kind only when it is the exception — the rule the library and the front
                // page follow. "BOOK" in the accent over every book's title was a label on the
                // one fact the cover beside it already states.
                if viewModel.book.sourceKind != .epub {
                    Text(viewModel.book.sourceKind.title)
                        .dipleType(.nano, weight: .semibold)
                        .foregroundStyle(DipleColor.accentInk)
                }
                Text(viewModel.book.title)
                    .dipleType(.editorialLead)
                    .foregroundStyle(DipleColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                BookSubtitleView(book: viewModel.book)
                if !viewModel.tags.isEmpty {
                    // The one screen that answers "what is this source and what have I made
                    // from it", so the shelf it was put on belongs here too.
                    FlowLayout(spacing: DipleSpace.xs) {
                        ForEach(viewModel.tags, id: \.self) { tag in
                            TagChipView(label: tag, kind: .text)
                        }
                    }
                }
                if isStarted {
                    progressRule
                        .padding(.top, DipleSpace.xs)
                }
                if let readingLine {
                    Text(readingLine)
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)
                        .monospacedDigit()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var actions: some View {
        HStack(spacing: DipleSpace.s) {
            NavigationLink(value: viewModel.book) {
                Label(viewModel.book.progress > 0.001 ? "Continue" : "Start reading", systemImage: "book.pages")
                    .dipleType(.footnote, weight: .semibold)
                    .foregroundStyle(DipleColor.textOnAccent)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(DipleColor.accent, in: RoundedRectangle(cornerRadius: DipleRadius.m))
            }
            .buttonStyle(.readerControl)

            NavigationLink(value: NoteRoute.newFromSource(viewModel.book)) {
                Label("New note", systemImage: "square.and.pencil")
                    .dipleType(.footnote, weight: .semibold)
                    .foregroundStyle(DipleColor.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .background(DipleColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DipleRadius.m))
                    .overlay {
                        RoundedRectangle(cornerRadius: DipleRadius.m)
                            .stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline)
                    }
            }
            .buttonStyle(.readerControl)
        }
    }

    private func section<Content: View>(
        _ title: String,
        count: Int,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: DipleSpace.m) {
            HStack {
                Text(title)
                    .dipleSectionHeading()
                Spacer()
                Text("\(count)")
                    .dipleType(.micro)
                    .foregroundStyle(DipleColor.textQuaternary)
                    .monospacedDigit()
            }
            content()
        }
    }

    /// The way on to the rest, set as a line of type at the foot of the rows rather than as a
    /// card under them — a card at the end of a column of rows reads as one more entry.
    private func collectionLink(_ title: String) -> some View {
        HStack(spacing: DipleSpace.xs) {
            Text(title)
                .dipleType(.footnote, weight: .semibold)
                .monospacedDigit()
            Image(systemName: "chevron.right")
                .dipleIcon(9, weight: .semibold)
        }
        .foregroundStyle(DipleColor.accentInk)
        .padding(.vertical, DipleSpace.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var isStarted: Bool {
        viewModel.book.progress > 0.001
    }

    /// The figure under the rule, and what it is a figure of.
    ///
    /// This used to print the whole length on its own — `8 h 20 min` — under a bar half
    /// full, one screen after the front page had said `4 h 5 min left` about the same book.
    /// Two numbers for one book, and nothing saying which was which. Now it is the library
    /// row's rule: what is left once started, the length before that; and it says so —
    /// `43% · 4 h 5 min left`, `8 h 20 min to read`.
    private var readingLine: String? {
        let progress = min(max(viewModel.book.progress, 0), 1)
        if isStarted {
            let percent = "\(Int((progress * 100).rounded()))%"
            guard let left = ReadingEstimate.remaining(
                characters: viewModel.characters,
                progress: progress,
                script: viewModel.book.script
            ) else { return percent }
            return "\(percent) · \(left)"
        }
        return ReadingEstimate.total(
            characters: viewModel.characters,
            script: viewModel.book.script
        ).map { "\($0) to read" }
    }

    /// The library row's rule — hairline and accent ink — in place of a system progress bar,
    /// which was the one stock control on the page.
    private var progressRule: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Rectangle().fill(DipleColor.hairline)
                Rectangle()
                    .fill(DipleColor.accentInk)
                    .frame(width: geometry.size.width * min(max(viewModel.book.progress, 0), 1))
            }
        }
        .frame(height: DipleStroke.regular)
        .accessibilityHidden(true)
    }

    private var summary: BookQuoteSummary {
        BookQuoteSummary(
            bookId: viewModel.book.id,
            title: viewModel.book.title,
            author: viewModel.book.author,
            book: viewModel.book,
            quoteCount: viewModel.highlights.count
        )
    }
}
