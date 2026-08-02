import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

public struct EditBookMetadataView: View {
    public let book: Book
    public let onSave: (String, String?, Data?) -> Bool

    @Environment(\.dismiss) private var dismiss
    @State private var title: String
    @State private var author: String
    @State private var selectedPhotoItem: PhotosPickerItem? = nil
    @State private var selectedImageData: Data? = nil
    @State private var previewUIImage: UIImage? = nil
    @State private var isFileImporterPresented = false

    public init(book: Book, onSave: @escaping (String, String?, Data?) -> Bool) {
        self.book = book
        self.onSave = onSave
        self._title = State(initialValue: book.title)
        self._author = State(initialValue: book.author ?? "")
    }

    public var body: some View {
        NavigationStack {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: DipleSpace.xxl) {
                        // Cover Preview & Custom Cover Buttons
                        VStack(spacing: DipleSpace.m) {
                            ZStack {
                                if let uiImage = previewUIImage {
                                    Image(uiImage: uiImage)
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(width: 90, height: 135)
                                        .cornerRadius(DipleRadius.s)
                                        .clipped()
                                } else {
                                    BookCoverView(coverPath: book.coverPath, title: title, author: author)
                                        .frame(width: 90, height: 135)
                                }
                            }

                            HStack(spacing: DipleSpace.m) {
                                PhotosPicker(selection: $selectedPhotoItem, matching: .images) {
                                    HStack(spacing: DipleSpace.s) {
                                        Image(systemName: "photo")
                                            .dipleIcon(13)
                                        Text("Photos")
                                            .dipleType(.footnote)
                                    }
                                    .foregroundStyle(DipleColor.accent)
                                    .padding(.horizontal, DipleSpace.m)
                                    .padding(.vertical, DipleSpace.s)
                                    .background(DipleColor.surfaceOverlay)
                                    .cornerRadius(DipleRadius.s)
                                }

                                Button {
                                    HapticManager.shared.selection()
                                    isFileImporterPresented = true
                                } label: {
                                    HStack(spacing: DipleSpace.s) {
                                        Image(systemName: "folder")
                                            .dipleIcon(13)
                                        Text("Files")
                                            .dipleType(.footnote)
                                    }
                                    .foregroundStyle(DipleColor.textSecondary)
                                    .padding(.horizontal, DipleSpace.m)
                                    .padding(.vertical, DipleSpace.s)
                                    .background(DipleColor.surfaceOverlay)
                                    .cornerRadius(DipleRadius.s)
                                }
                            }
                        }
                        .padding(.top, DipleSpace.m)

                        // METADATA SECTION
                        VStack(alignment: .leading, spacing: DipleSpace.l) {
                            Text("BOOK METADATA")
                                .dipleType(.micro, weight: .semibold)
                                .foregroundStyle(DipleColor.textTertiary)
                                .padding(.horizontal, DipleSpace.xs)

                            VStack(spacing: DipleSpace.m) {
                                // Title field
                                VStack(alignment: .leading, spacing: DipleSpace.s) {
                                    Text("Title")
                                        .dipleType(.footnote)
                                        .foregroundStyle(DipleColor.textSecondary)

                                    TextField("Enter book title", text: $title)
                                        .dipleType(.body)
                                        .foregroundColor(.white)
                                        .diplePadding(.field)
                                        .background(DipleColor.surfaceRaised)
                                        .cornerRadius(DipleRadius.m)
                                }

                                // Author field
                                VStack(alignment: .leading, spacing: DipleSpace.s) {
                                    Text("Author")
                                        .dipleType(.footnote)
                                        .foregroundStyle(DipleColor.textSecondary)

                                    TextField("Enter author name", text: $author)
                                        .dipleType(.body)
                                        .foregroundColor(.white)
                                        .diplePadding(.field)
                                        .background(DipleColor.surfaceRaised)
                                        .cornerRadius(DipleRadius.m)
                                }
                            }
                        }

                        Spacer()
                    }
                    .padding(.horizontal, DipleSpace.xxl)
                }
            }
            .navigationTitle("Edit Metadata")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Cancel") {
                        HapticManager.shared.selection()
                        dismiss()
                    }
                    .dipleType(.body)
                    .foregroundStyle(DipleColor.textSecondary)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Save") {
                        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
                        guard !trimmedTitle.isEmpty else { return }
                        let trimmedAuthor = author.trimmingCharacters(in: .whitespacesAndNewlines)
                        if onSave(trimmedTitle, trimmedAuthor.isEmpty ? nil : trimmedAuthor, selectedImageData) {
                            HapticManager.shared.notification(.success)
                            dismiss()
                        } else {
                            HapticManager.shared.notification(.error)
                        }
                    }
                    .dipleType(.body, weight: .semibold)
                    .foregroundColor(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? Color.gray.opacity(0.4) : DipleColor.accent)
                    .disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .onChange(of: selectedPhotoItem) { _, newItem in
                Task { @MainActor in
                    if let data = try? await newItem?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        self.selectedImageData = data
                        self.previewUIImage = uiImage
                        HapticManager.shared.selection()
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
