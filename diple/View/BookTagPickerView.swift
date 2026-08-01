import SwiftUI

/// Picks one library item to tag a note with.
public struct BookTagPickerView: View {
    public let books: [Book]
    public let selectedBookId: String?
    public let onSelect: (String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String = ""

    /// See `HubBookRowView`: the thumbnail tracks the text size next to it.
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
                Color.black.ignoresSafeArea()

                if books.isEmpty {
                    Text("Your library is empty.")
                        .font(.system(size: 14, weight: .regular))
                        .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.58))
                } else {
                    ScrollView {
                        LazyVStack(spacing: 8) {
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
                        .padding(.horizontal, 20)
                        .padding(.vertical, 12)
                    }
                }
            }
            .searchable(text: $query, prompt: "Search library")
            .navigationTitle("Tag a Book")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") { dismiss() }
                        .foregroundColor(Color(red: 0.6, green: 0.6, blue: 0.65))
                }

                if selectedBookId != nil {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Clear") {
                            HapticManager.shared.selection()
                            onSelect(nil)
                            dismiss()
                        }
                        .foregroundColor(Color.dipleAccent)
                    }
                }
            }
        }
    }

    private func row(for book: Book) -> some View {
        HStack(spacing: 12) {
            BookCoverView(coverPath: book.coverPath, title: book.title, author: book.author, isCompact: true)
                .frame(width: thumbnailWidth, height: thumbnailWidth * 1.5)

            VStack(alignment: .leading, spacing: 3) {
                Text(book.title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Text(book.author ?? "Unknown Author")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.58))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            if book.id == selectedBookId {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color.dipleAccent)
            }
        }
        .padding(10)
        .background(Color(red: 0.08, green: 0.08, blue: 0.1))
        .cornerRadius(10)
    }
}
