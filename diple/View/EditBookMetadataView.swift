import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

public struct EditBookMetadataView: View {
    public let book: Book
    public let onSave: (String, String?, Data?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var author: String
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    @State private var previewUIImage: UIImage? = nil
    @State private var isFileImporterPresented = false

    public init(book: Book, onSave: @escaping (String, String?, Data?) -> Void) {
        self.book = book
        self.onSave = onSave
        self._title = State(initialValue: book.title)
        self._author = State(initialValue: book.author ?? "")
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 24) {
                        // Cover Preview & Custom Cover Buttons
                        VStack(spacing: 14) {
                            ZStack {
                                if let uiImage = previewUIImage {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 90, height: 135)
                                        .cornerRadius(8)
                                        .clipped()
                                } else {
                                    BookCoverView(coverPath: book.coverPath, title: title, author: author)
                                        .frame(width: 90, height: 135)
                                }
                            }

                            HStack(spacing: 12) {
                                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                    HStack(spacing: 6) {
                                        Image(systemName: "photo")
                                            .font(.system(size: 13))
                                        Text("Photos")
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    .foregroundColor(Color.dipleAccent)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color(red: 0.14, green: 0.14, blue: 0.16))
                                    .cornerRadius(8)
                                }

                                Button {
                                    HapticManager.shared.selection()
                                    isFileImporterPresented = true
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: "folder")
                                            .font(.system(size: 13))
                                        Text("Files")
                                            .font(.system(size: 13, weight: .medium))
                                    }
                                    .foregroundColor(Color(red: 0.85, green: 0.85, blue: 0.88))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 8)
                                    .background(Color(red: 0.14, green: 0.14, blue: 0.16))
                                    .cornerRadius(8)
                                }
                            }
                        }
                        .padding(.top, 12)

                        // METADATA SECTION
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
                }
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
                        onSave(trimmedTitle, trimmedAuthor.isEmpty ? nil : trimmedAuthor, selectedImageData)
                        dismiss()
                    }
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.4) : Color.dipleAccent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: selectedPhotoItem) { newItem in
                Task {
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        await MainActor.run {
                            self.selectedImageData = data
                            self.previewUIImage = uiImage
                            HapticManager.shared.selection()
                        }
                    }
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                if case .success(let urls) = result, let url = urls.first {
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer { if accessing { url.stopAccessingSecurityScopedResource() } }
                    if let data = try? Data(contentsOf: url), let uiImage = UIImage(data: data) {
                        self.selectedImageData = data
                        self.previewUIImage = uiImage
                        HapticManager.shared.selection()
                    }
                }
            }
        }
    }
}
