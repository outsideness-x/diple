import SwiftUI

public struct EditBookMetadataView: View {
    public let book: Book
    public let onSave: (String, String?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var author: String

    public init(book: Book, onSave: @escaping (String, String?) -> Void) {
        self.book = book
        self.onSave = onSave
        self._title = State(initialValue: book.title)
        self._author = State(initialValue: book.author ?? "")
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                VStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("BOOK METADATA")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(red: 0.5, green: 0.5, blue: 0.55))
                            .padding(.horizontal, 4)

                        VStack(spacing: 12) {
                            // Title field
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Title")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Color(red: 0.7, green: 0.7, blue: 0.75))

                                TextField("Enter book title", text: $title)
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(Color(red: 0.12, green: 0.12, blue: 0.14))
                                    .cornerRadius(10)
                            }

                            // Author field
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Author")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundColor(Color(red: 0.7, green: 0.7, blue: 0.75))

                                TextField("Enter author name", text: $author)
                                    .font(.system(size: 15, weight: .regular))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(Color(red: 0.12, green: 0.12, blue: 0.14))
                                    .cornerRadius(10)
                            }
                        }
                    }

                    Spacer()
                }
                .padding(.horizontal, 24)
                .padding(.top, 24)
            }
            .navigationTitle("Edit Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        HapticManager.shared.selection()
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .regular))
                    .foregroundColor(Color(red: 0.7, green: 0.7, blue: 0.75))
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedTitle.isEmpty else { return }
                        let trimmedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
                        HapticManager.shared.notification(.success)
                        onSave(trimmedTitle, trimmedAuthor.isEmpty ? nil : trimmedAuthor)
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.4) : Color.dipleAccent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }
}
