import SwiftUI

/// A single search surface over the reader's own notes, saved highlights and library metadata.
/// Results stay grouped by meaning: authored material first, then saved passages, then sources.
public struct GlobalSearchView: View {
    @StateObject private var viewModel = GlobalSearchViewModel()
    @StateObject private var notesViewModel = NotesViewModel()
    /// `nil` is "everything". A scope is a way to read one kind of answer without the others in
    /// the way, not a second query — the search itself already returned every kind.
    @State private var scope: GlobalSearchKind?

    public init() {}

    private func count(of kind: GlobalSearchKind) -> Int {
        viewModel.results.lazy.filter { $0.kind == kind }.count
    }

    private var shownKinds: [GlobalSearchKind] {
        scope.map { [$0] } ?? GlobalSearchKind.allCases
    }

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
                    VStack(spacing: 0) {
                        scopeBar
                        resultsList
                    }
                }
            }
            .navigationTitle("Search")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbar {
                if viewModel.isIndexingArticles || viewModel.isIndexingBookContent {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        ProgressView()
                            .tint(DipleColor.accent)
                            .accessibilityLabel("Indexing your library")
                    }
                }
            }
            .searchable(
                text: $viewModel.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: "Notes, highlights and library"
            )
            // A query is not a sentence. The default sentence capitalisation turned "house"
            // into "House" in the field, and autocorrect is worse than useless over a library
            // that mixes Russian, Korean and English in one index.
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onChange(of: viewModel.query) { _, _ in
                viewModel.scheduleSearch()
                // Clearing the field is starting over. Leaving a scope armed would make the
                // next query silently answer less than it found.
                if viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    scope = nil
                }
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

    /// Sections arrive one after another rather than all at once.
    ///
    /// A query resolves into up to five groups, and dropping them in on the same frame reads
    /// as a flash — the eye gets no order to follow and has to re-scan from the top. Offsetting
    /// each group by a beat gives the list a reading direction, and the delay is small enough
    /// that the whole set is settled well inside the time it takes to look down. It is keyed to
    /// the group's position, not to its arrival, so a section never re-runs its entrance while
    /// the reader keeps typing.
    private func staggerDelay(for kind: GlobalSearchKind) -> Double {
        // A scoped list is one section, and its position in `allCases` is meaningless there:
        // picking "In Books" would otherwise hold the only thing on screen back by four beats
        // for a reading order that no longer exists.
        guard scope == nil else { return 0 }
        return Double(GlobalSearchKind.allCases.firstIndex(of: kind) ?? 0) * 0.045
    }

    /// Narrows the answer, not the query.
    ///
    /// Filtering happens over results already in hand — one query returns every kind, so a
    /// scope costs nothing and cannot disagree with what the index found. A chip whose kind has
    /// no hits is dimmed rather than removed: chips that appear and vanish on each keystroke
    /// make the row jump under the finger that is aiming at one.
    private var scopeBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DipleSpace.s) {
                scopeChip(title: "All", count: viewModel.results.count, kind: nil)

                ForEach(GlobalSearchKind.allCases, id: \.self) { kind in
                    scopeChip(title: kind.title, count: count(of: kind), kind: kind)
                }
            }
            .padding(.horizontal, DipleSpace.xl)
            .padding(.vertical, DipleSpace.s)
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .accessibilityLabel("Search scope")
    }

    private func scopeChip(title: String, count: Int, kind: GlobalSearchKind?) -> some View {
        let isSelected = scope == kind
        let isEmpty = count == 0
        return Button {
            HapticManager.shared.selection()
            withAnimation(DipleMotion.standard) { scope = kind }
        } label: {
            HStack(spacing: DipleSpace.xs) {
                Text(title)
                    .dipleType(.micro, weight: .semibold)
                Text("\(count)")
                    .dipleType(.nano)
                    .monospacedDigit()
            }
            .foregroundStyle(
                isSelected ? DipleColor.textOnAccent
                    : (isEmpty ? DipleColor.textQuaternary : DipleColor.textTertiary)
            )
            .diplePadding(.chip)
            .background(isSelected ? DipleColor.accent : DipleColor.surfaceOverlay)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isEmpty && kind != nil)
        .accessibilityLabel("\(title), \(count) results")
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DipleSpace.xxl) {
                ForEach(shownKinds, id: \.self) { kind in
                    let results = viewModel.results.filter { $0.kind == kind }
                    if !results.isEmpty {
                        VStack(alignment: .leading, spacing: DipleSpace.s) {
                            // With one kind selected the chip above already names it, and a
                            // heading repeating it is a label for a group of one group.
                            if scope == nil {
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
                            }

                            ForEach(results) { result in
                                NavigationLink(value: result) {
                                    GlobalSearchResultRow(result: result)
                                }
                                .buttonStyle(.bookCard)
                            }
                        }
                        .transition(
                            .opacity.combined(with: .offset(y: 8))
                            .animation(DipleMotion.gentle.delay(staggerDelay(for: kind)))
                        )
                    }
                }
            }
            .padding(.horizontal, DipleSpace.xl)
            .padding(.top, DipleSpace.m)
            .padding(.bottom, DipleSpace.scrollBottom)
            // Keyed to the results themselves, so a section entering or leaving as the query
            // narrows is animated, while scrolling an unchanged list is not.
            .animation(DipleMotion.gentle, value: viewModel.results)
        }
    }

    private var searchInvitation: some View {
        VStack(spacing: DipleSpace.xl) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .dipleIcon(30, weight: .light)
                .foregroundStyle(DipleColor.accent)

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
            if let summary = viewModel.quoteSummary(for: result) {
                BookQuotesView(summary: summary)
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
        case .bookContent:
            if let book = viewModel.book(for: result), let locator = result.parsedLocator {
                ReaderContainerView(book: book, startingLocator: locator) {
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
        let text = result.snippet.isEmpty ? result.subtitle : result.snippet
        // A note is indexed as the Markdown it is stored as, so its snippet arrives with the
        // syntax still in it — a result reading `keep it.**memory**` while the note itself and
        // its card on the board both read `memory`. Stripping happens here rather than in the
        // index because the index is what the query matches against.
        return result.kind == .note ? NoteMarkdown.plainText(text) : text
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
