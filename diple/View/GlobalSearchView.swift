import SwiftUI

/// A single search surface over the reader's own notes, saved highlights and library metadata.
/// Results stay grouped by meaning: authored material first, then saved passages, then sources.
public struct GlobalSearchView: View {
    @StateObject private var viewModel = GlobalSearchViewModel()
    @StateObject private var notesViewModel = NotesViewModel()

    public init() {}

    private var trimmedQuery: String {
        viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                if trimmedQuery.isEmpty {
                    searchInvitation
                } else if viewModel.results.isEmpty {
                    noResults
                } else {
                    resultsList
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                if viewModel.isIndexingArticles {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ProgressView()
                            .tint(DipleColor.accent)
                            .accessibilityLabel("Indexing imported articles")
                    }
                }
            }
            .searchable(
                text: $viewModel.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Notes, highlights and library"
            )
            .onChange(of: viewModel.query) { _, _ in
                viewModel.search()
            }
            .onAppear {
                viewModel.reloadContext()
                notesViewModel.load()
            }
            .navigationDestination(for: GlobalSearchResult.self) { result in
                destination(for: result)
            }
            .alert("Search Error", isPresented: Binding(
                get: { viewModel.errorMessage != nil },
                set: { if !$0 { viewModel.errorMessage = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred.")
            }
        }
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DipleSpace.xxl) {
                ForEach(GlobalSearchKind.allCases, id: \.self) { kind in
                    let results = viewModel.results.filter { $0.kind == kind }
                    if !results.isEmpty {
                        VStack(alignment: .leading, spacing: DipleSpace.s) {
                            HStack(alignment: .firstTextBaseline) {
                                Text(kind.title.uppercased())
                                    .dipleType(.micro, weight: .semibold)
                                    .foregroundStyle(DipleColor.textTertiary)

                                Spacer()

                                Text("\(results.count)")
                                    .dipleType(.nano)
                                    .foregroundStyle(DipleColor.textQuaternary)
                                    .monospacedDigit()
                            }

                            ForEach(results) { result in
                                NavigationLink(value: result) {
                                    GlobalSearchResultRow(result: result)
                                }
                                .buttonStyle(.bookCard)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, DipleSpace.xl)
            .padding(.top, DipleSpace.m)
            .padding(.bottom, DipleSpace.scrollBottom)
        }
    }

    private var searchInvitation: some View {
        VStack(spacing: DipleSpace.xl) {
            Spacer()

            ZStack {
                AccentWash()
                Image(systemName: "magnifyingglass")
                    .dipleIcon(30, weight: .light)
                    .foregroundStyle(DipleColor.accent)
                    .craftGlow(DipleColor.accent.opacity(0.5), radius: 18)
            }

            VStack(spacing: DipleSpace.s) {
                Text("Search Everything")
                    .dipleType(.title)
                    .foregroundStyle(DipleColor.textPrimary)

                Text("Find your notes, saved highlights, books and the text of imported articles in one place.")
                    .dipleType(.callout)
                    .foregroundStyle(DipleColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DipleSpace.xxxl)
            }

            Spacer()
        }
    }

    private var noResults: some View {
        VStack(spacing: DipleSpace.m) {
            Spacer()
            Image(systemName: "text.magnifyingglass")
                .dipleIcon(28, weight: .light)
                .foregroundStyle(DipleColor.textQuaternary)
            Text("Nothing Found")
                .dipleType(.headline)
                .foregroundStyle(DipleColor.textPrimary)
            Text("Try fewer words or a different spelling.")
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
            Spacer()
        }
    }

    @ViewBuilder
    private func destination(for result: GlobalSearchResult) -> some View {
        switch result.kind {
        case .note:
            if let item = notesViewModel.items.first(where: { $0.id == result.entityID }) {
                NoteDetailView(
                    route: .existing(item),
                    books: notesViewModel.books,
                    suggestedTags: notesViewModel.allTags,
                    onSave: { note, tags in
                        let saved = notesViewModel.save(note, tags: tags)
                        if saved { viewModel.search() }
                        return saved
                    },
                    onDelete: { item in
                        notesViewModel.delete(item)
                        viewModel.search()
                    }
                )
            } else {
                unavailableResult
            }
        case .highlight:
            if let book = viewModel.book(for: result) {
                BookQuotesView(book: book)
            } else {
                unavailableResult
            }
        case .book, .article:
            if let book = viewModel.book(for: result) {
                ReaderContainerView(book: book) {
                    viewModel.reloadContext()
                }
            } else {
                unavailableResult
            }
        }
    }

    private var unavailableResult: some View {
        ContentUnavailableView(
            "Result Unavailable",
            systemImage: "questionmark.folder",
            description: Text("It may have been deleted since the search was performed.")
        )
    }
}

private struct GlobalSearchResultRow: View {
    let result: GlobalSearchResult

    private var detail: String {
        result.snippet.isEmpty ? result.subtitle : result.snippet
    }

    var body: some View {
        HStack(alignment: .top, spacing: DipleSpace.m) {
            Image(systemName: result.kind.systemImage)
                .dipleIcon(14, weight: .medium)
                .foregroundStyle(DipleColor.accent)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: DipleSpace.xs) {
                Text(result.title)
                    .dipleType(.body, weight: .semibold)
                    .foregroundStyle(DipleColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                if !detail.isEmpty {
                    Text(detail)
                        .dipleType(result.kind == .book ? .caption : .readingCaption)
                        .readingLineSpacing(for: detail)
                        .foregroundStyle(DipleColor.textSecondary)
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                if !result.subtitle.isEmpty && result.subtitle != detail {
                    Text(result.subtitle)
                        .dipleType(.nano, weight: .medium)
                        .foregroundStyle(DipleColor.textQuaternary)
                        .lineLimit(1)
                }
            }

            Spacer(minLength: DipleSpace.s)

            Image(systemName: "chevron.right")
                .dipleIcon(11, weight: .semibold)
                .foregroundStyle(DipleColor.textQuaternary)
        }
        .padding(DipleSpace.m)
        .craftSurface()
        .accessibilityElement(children: .combine)
    }
}
