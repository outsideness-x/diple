import SwiftUI

/// Search inside the book currently open in the reader. A `.sheet` rather than a page pushed
/// onto the reader's own stack — it needs its own dismiss and its own `NavigationStack` for
/// `.searchable`, exactly like `GlobalSearchView`, but scoped to one book's `bookContent` chunks
/// instead of the whole library (see `AppDatabase.searchBookContent`).
///
/// `DipleColor` plus `.presentationBackground(.regularMaterial)` — the same recipe
/// `BookOutlineSheetView` already uses — is what makes this read correctly over a light, sepia
/// or dark page: the sheet is an opaque material stacked above everything, so it never needs to
/// know the reader's own page theme the way the top/bottom chrome bars do.
public struct BookSearchSheetView: View {
    @StateObject private var viewModel: ReaderSearchViewModel
    @Environment(\.dismiss) private var dismiss

    public let onSelect: (BookSearchHit) -> Void

    public init(book: Book, onSelect: @escaping (BookSearchHit) -> Void) {
        self._viewModel = StateObject(wrappedValue: ReaderSearchViewModel(book: book))
        self.onSelect = onSelect
    }

    private var trimmedQuery: String {
        viewModel.query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                if viewModel.isIndexed == false {
                    indexingState
                } else if trimmedQuery.isEmpty {
                    invitationState
                } else if viewModel.results.isEmpty {
                    noResultsState
                } else {
                    resultsList
                }
            }
            .navigationTitle(viewModel.sourceTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        HapticManager.shared.selection()
                        dismiss()
                    }
                    .dipleType(.body, weight: .medium)
                    .foregroundStyle(DipleColor.textPrimary)
                }
            }
            .searchable(
                text: $viewModel.query,
                placement: .navigationBarDrawer(displayMode: .always),
                prompt: viewModel.searchPrompt
            )
            // Searching a book's text is a Cmd+F, not a sentence: neither capitalisation nor
            // autocorrect belongs on a term being matched against the page.
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .onChange(of: viewModel.query) { _, _ in
                viewModel.scheduleSearch()
            }
        }
        .presentationBackground(.regularMaterial)
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    private var resultsList: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DipleSpace.xxl) {
                ForEach(viewModel.groupedResults) { group in
                    VStack(alignment: .leading, spacing: DipleSpace.s) {
                        HStack(alignment: .firstTextBaseline) {
                            Text(group.title.uppercased())
                                .dipleType(.micro, weight: .semibold)
                                .foregroundStyle(DipleColor.textTertiary)
                                .lineLimit(1)

                            Spacer()

                            Text("\(group.hits.count)")
                                .dipleType(.nano)
                                .monospacedDigit()
                                .foregroundStyle(DipleColor.textQuaternary)
                                .monospacedDigit()
                        }

                        VStack(spacing: 0) {
                            ForEach(group.hits) { hit in
                                Button {
                                    HapticManager.shared.selection()
                                    onSelect(hit)
                                    dismiss()
                                } label: {
                                    BookSearchHitRow(hit: hit)
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

    private var invitationState: some View {
        VStack(spacing: DipleSpace.xl) {
            Spacer()

            Image(systemName: "magnifyingglass")
                .dipleIcon(30, weight: .light)
                .foregroundStyle(DipleColor.accentInk)

            VStack(spacing: DipleSpace.s) {
                Text(viewModel.invitationTitle)
                    .dipleType(.title)
                    .foregroundStyle(DipleColor.textPrimary)

                Text("Find every passage that mentions a word or phrase, and jump straight to it.")
                    .dipleType(.callout)
                    .foregroundStyle(DipleColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DipleSpace.xxxl)
            }

            Spacer()
        }
    }

    private var noResultsState: some View {
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

    private var indexingState: some View {
        VStack(spacing: DipleSpace.m) {
            Spacer()
            ProgressView()
                .tint(DipleColor.accent)
            Text("Preparing Search…")
                .dipleType(.headline)
                .foregroundStyle(DipleColor.textPrimary)
            Text("This only happens once — search will be instant after.")
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, DipleSpace.xxxl)
            Spacer()
        }
    }
}

private struct BookSearchHitRow: View {
    let hit: BookSearchHit

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// A concordance gives more measure to what follows the keyword: that context more often
    /// resolves the sense of an occurrence. This is a proportion of the available measure,
    /// not padding tuned for one screen.
    private static let beforeColumn = 0.4

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                MatchedSnippetText(hit: hit)
            } else if let concordance = hit.concordance {
                concordanceRow(concordance)
            } else {
                MatchedSnippetText(hit: hit)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, DipleSpace.m)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DipleColor.hairline)
                .frame(height: DipleStroke.hairline)
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(accessibilityText))
    }

    /// The hidden line supplies the role's natural Dynamic Type height; its overlay can then
    /// measure the full row width without a fixed frame or a guessed vertical dimension.
    private func concordanceRow(
        _ concordance: (before: String, match: String, after: String)
    ) -> some View {
        Text(" ")
            .dipleType(.readingCaption)
            .hidden()
            .frame(maxWidth: .infinity)
            .overlay {
                GeometryReader { proxy in
                    HStack(spacing: 0) {
                        Text(concordance.before)
                            .dipleType(.readingCaption, weight: .regular)
                            .foregroundStyle(DipleColor.textTertiary)
                            .lineLimit(1)
                            .truncationMode(.head)
                            .frame(
                                width: proxy.size.width * Self.beforeColumn,
                                alignment: .trailing
                            )

                        (
                            Text(concordance.match)
                                .foregroundColor(DipleColor.textPrimary)
                                .fontWeight(.semibold)
                            + Text(concordance.after)
                                .foregroundColor(DipleColor.textTertiary)
                                .fontWeight(.regular)
                        )
                        .dipleType(.readingCaption)
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
    }

    private var accessibilityText: String {
        if let concordance = hit.concordance {
            return concordance.before + concordance.match + concordance.after
        }
        return hit.segments.map(\.text).joined()
    }
}

/// Renders a `bookContent` snippet with its matched span bolded, by splitting on the sentinel
/// markers `AppDatabase.searchBookContent` asked SQLite's `snippet()` to wrap the match in.
///
/// Built from `Text` concatenation rather than `AttributedString`: the per-run modifiers that
/// survive `+` (`.font`, `.tracking`, `.foregroundColor`) are exactly the ones `.dipleType`
/// itself applies, so this reproduces `.dipleType(.readingCaption)` per run instead of
/// introducing a second way to size reading text.
private struct MatchedSnippetText: View {
    let hit: BookSearchHit

    var body: some View {
        assembledText
            .dipleType(.readingCaption)
            .readingLineSpacing(for: hit.snippet)
            .multilineTextAlignment(.leading)
            .lineLimit(4)
    }

    /// Plain `Text`, not `some View`: the per-run weight and colour survive concatenation, then
    /// the shared type role is applied once to the assembled phrase in `body`.
    private var assembledText: Text {
        hit.segments.reduce(Text("")) { partial, segment in
            var run = Text(segment.text)
                .fontWeight(segment.isMatch ? .semibold : .regular)
            run = segment.isMatch
                ? run.foregroundColor(DipleColor.textPrimary)
                : run.foregroundColor(DipleColor.textTertiary)
            return partial + run
        }
    }
}
