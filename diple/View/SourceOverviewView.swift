import SwiftUI
import Combine

@MainActor
private final class SourceOverviewViewModel: ObservableObject {
    @Published var highlights: [Highlight] = []
    @Published var notes: [NoteItem] = []
    @Published var tags: [String] = []
    @Published var characters: Int?
    @Published var errorMessage: String?

    let book: Book

    init(book: Book) {
        self.book = book
        load()
    }

    func load() {
        do {
            highlights = try AppDatabase.shared.fetchHighlights(forBookId: book.id)
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
                        actions

                        if !viewModel.highlights.isEmpty {
                            section("HIGHLIGHTS", count: viewModel.highlights.count) {
                                ForEach(viewModel.highlights.prefix(3)) { highlight in
                                    QuoteCardView(quote: highlight)
                                }

                                if viewModel.highlights.count > 3 {
                                    NavigationLink {
                                        BookQuotesView(summary: summary)
                                    } label: {
                                        collectionLink("See all highlights")
                                    }
                                    .buttonStyle(.bookCard)
                                }
                            }
                        }

                        if !viewModel.notes.isEmpty {
                            section("NOTES", count: viewModel.notes.count) {
                                ForEach(viewModel.notes.prefix(3)) { item in
                                    NavigationLink(value: NoteRoute.existing(item)) {
                                        SourceNoteRow(item: item)
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
                        .foregroundStyle(DipleColor.accent)
                }
            }
            .navigationDestination(for: Book.self) { book in
                ReaderContainerView(book: book, onReadingUpdated: onReadingUpdated)
            }
            .navigationDestination(for: NoteRoute.self) { route in
                NoteDetailView(
                    route: route,
                    books: [viewModel.book],
                    suggestedTags: Array(Set(viewModel.notes.flatMap(\.tags))).sorted(),
                    allNotes: viewModel.notes,
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
                        try? AppDatabase.shared.deleteNote(id: item.id)
                        viewModel.load()
                    },
                    onOpenNote: { path.append(NoteRoute.existing($0)) }
                )
            }
            .alert("Source Error", isPresented: Binding(
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
                Text(viewModel.book.sourceKind.title)
                    .dipleType(.nano, weight: .semibold)
                    .foregroundStyle(DipleColor.accent)
                Text(viewModel.book.title)
                    .dipleType(.title)
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
                if viewModel.book.progress > 0.001 {
                    ProgressView(value: min(max(viewModel.book.progress, 0), 1))
                        .tint(DipleColor.accent)
                }
                // The whole length rather than what is left: this screen is about what the
                // source *is*, and the reader's position through it is one line above.
                if let total = ReadingEstimate.total(
                    characters: viewModel.characters,
                    script: viewModel.book.script
                ) {
                    Text(total)
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)
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
                    .dipleType(.micro, weight: .semibold)
                    .foregroundStyle(DipleColor.textTertiary)
                Spacer()
                Text("\(count)")
                    .dipleType(.micro)
                    .foregroundStyle(DipleColor.textQuaternary)
                    .monospacedDigit()
            }
            content()
        }
    }

    private func collectionLink(_ title: String) -> some View {
        HStack {
            Text(title)
                .dipleType(.footnote, weight: .semibold)
                .foregroundStyle(DipleColor.textSecondary)
            Spacer()
            Image(systemName: "chevron.right")
                .dipleIcon(10, weight: .semibold)
                .foregroundStyle(DipleColor.textQuaternary)
        }
        .padding(DipleSpace.m)
        .craftSurface()
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

private struct SourceNoteRow: View {
    let item: NoteItem

    var body: some View {
        HStack(alignment: .top, spacing: DipleSpace.m) {
            Image(systemName: "note.text")
                .dipleIcon(13, weight: .semibold)
                .foregroundStyle(DipleColor.accent)
            VStack(alignment: .leading, spacing: DipleSpace.xs) {
                Text(item.displayTitle)
                    .dipleType(.body, weight: .semibold)
                    .foregroundStyle(DipleColor.textPrimary)
                let preview = NoteMarkdown.plainText(item.note.body)
                if !preview.isEmpty {
                    Text(preview)
                        .dipleType(.caption)
                        .foregroundStyle(DipleColor.textTertiary)
                        .lineLimit(2)
                }
            }
            Spacer(minLength: DipleSpace.s)
            Image(systemName: "chevron.right")
                .dipleIcon(10, weight: .semibold)
                .foregroundStyle(DipleColor.textQuaternary)
        }
        .padding(DipleSpace.m)
        .craftSurface()
        .accessibilityElement(children: .combine)
    }
}
