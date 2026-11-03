import SwiftUI

/// Picks one library item to tag a note with.
public struct BookTagPickerView: View {
    public let books: [Book]
    public let selectedBookId: String?
    public let onSelect: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    /// See `LibraryRowView`: the thumbnail tracks the text size next to it.
    @ScaledMetric(relativeTo: .subheadline) private var thumbnailWidth: CGFloat = 36

    public init(books: [Book], selectedBookId: String?, onSelect: @escaping (String?) -> Void) {
        self.books = books
        self.selectedBookId = selectedBookId
        self.onSelect = onSelect
    }

    private var filteredBooks: [Book] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return books }
        return books.filter { book in
            book.title.localizedCaseInsensitiveContains(trimmed)
                || (book.author?.localizedCaseInsensitiveContains(trimmed) ?? false)
        }
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                if books.isEmpty {
                    DipleEmptyText(
                        title: "Your library is empty",
                        message: "Add a book or an article before linking a note to a source."
                    )
                } else {
                    ScrollView {
                        LazyVStack(spacing: DipleSpace.s) {
                            DipleSearchField(
                                text: $query,
                                prompt: "Search library",
                                identifier: "bookTagPicker.search"
                            )
                            .padding(.bottom, DipleSpace.xs)

                            if filteredBooks.isEmpty {
                                DipleEmptyText(
                                    title: "Nothing matches “\(query)”",
                                    message: "Try another title or author."
                                )
                            } else {
                                ForEach(filteredBooks) { book in
                                    Button {
                                        HapticManager.shared.impact(.light)
                                        onSelect(book.id)
                                        dismiss()
                                    } label: {
                                        row(for: book)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, DipleSpace.xl)
                        .padding(.vertical, DipleSpace.m)
                    }
                }
            }
            .navigationTitle("Tag a book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .dipleType(.body)
                        .foregroundStyle(DipleColor.textTertiary)
                }

                if selectedBookId != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Clear") {
                            HapticManager.shared.selection()
                            onSelect(nil)
                            dismiss()
                        }
                        .dipleType(.body, weight: .semibold)
                        .foregroundStyle(DipleColor.accentInk)
                    }
                }
            }
        }
    }

    private func row(for book: Book) -> some View {
        let isSelected = book.id == selectedBookId
        return HStack(spacing: DipleSpace.m) {
            BookCoverView(coverPath: book.coverPath, title: book.title, author: book.author, isCompact: true)
                .frame(width: thumbnailWidth, height: thumbnailWidth * 1.5)

            VStack(alignment: .leading, spacing: DipleSpace.xs) {
                Text(book.title)
                    .dipleType(.editorialItem)
                    .foregroundStyle(DipleColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(book.author ?? "Unknown author")
                    .dipleType(.micro, weight: .regular)
                    .foregroundStyle(DipleColor.textTertiary)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if isSelected {
                Image(systemName: "checkmark")
                    .dipleIcon(13, weight: .semibold)
                    .foregroundStyle(DipleColor.accentInk)
            }
        }
        .padding(DipleSpace.m)
        .craftSurface()
        .dipleSelected(isSelected, in: RoundedRectangle(cornerRadius: DipleRadius.m))
    }
}
