import SwiftUI
import UniformTypeIdentifiers

public struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @State private var isFileImporterPresented = false

    @State private var isAppSettingsPresented = false

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 20)
    ]

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                if viewModel.books.isEmpty {
                    EmptyLibraryView {
                        isFileImporterPresented = true
                    }
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, spacing: 24) {
                            ForEach(viewModel.books) { book in
                                NavigationLink(value: book) {
                                    BookItemView(book: book, onEdit: {
                                        viewModel.bookToEdit = book
                                    }, onDelete: {
                                        viewModel.confirmDelete(book)
                                    })
                                }
                                .buttonStyle(.bookCard)
                            }
                        }
                        .padding(.horizontal, DipleSpace.xl)
                        .padding(.top, DipleSpace.l)
                        .padding(.bottom, DipleSpace.scrollBottom)
                    }
                }

                if viewModel.isImporting {
                    ZStack {
                        DipleColor.canvas.opacity(0.75).ignoresSafeArea()
                        VStack(spacing: DipleSpace.m) {
                            ProgressView()
                                .tint(DipleColor.accent)
                            Text("Importing book...")
                                .dipleType(.callout, weight: .medium)
                                .foregroundStyle(DipleColor.textPrimary)
                        }
                        .padding(DipleSpace.xxl)
                        .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.l)
                    }
                }
            }
            .navigationTitle("diple")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button {
                        HapticManager.shared.selection()
                        isAppSettingsPresented = true
                    } label: {
                        Image(systemName: "gearshape")
                            .dipleIcon(16)
                            .foregroundStyle(DipleColor.textSecondary)
                    }
                    .buttonStyle(.readerControl)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        HapticManager.shared.selection()
                        isFileImporterPresented = true
                    } label: {
                        Image(systemName: "plus")
                            .dipleIcon(16)
                            .foregroundStyle(DipleColor.accent)
                    }
                    .buttonStyle(.readerControl)
                }
            }
            .fileImporter(
                isPresented: $isFileImporterPresented,
                allowedContentTypes: [.epub, .pdf],
                allowsMultipleSelection: false
            ) { result in
                switch result {
                case .success(let urls):
                    guard let url = urls.first else { return }
                    viewModel.importBook(from: url)
                case .failure(let error):
                    viewModel.errorMessage = "Import failed: \(error.localizedDescription)"
                    viewModel.showErrorAlert = true
                }
            }
            .alert("Error", isPresented: $viewModel.showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred.")
            }
            .alert("Delete Book?", isPresented: $viewModel.showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    viewModel.deleteConfirmedBook()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                if let book = viewModel.bookToDelete {
                    Text("Are you sure you want to delete '\(book.title)'? This will remove the book file and metadata.")
                }
            }
            .navigationDestination(for: Book.self) { book in
                ReaderContainerView(book: book, onReadingUpdated: {
                    viewModel.loadBooks()
                })
            }
            .sheet(isPresented: $isAppSettingsPresented) {
                AppSettingsView()
            }
            .sheet(item: $viewModel.bookToEdit) { book in
                EditBookMetadataView(book: book) { newTitle, newAuthor, coverData in
                    viewModel.updateMetadata(for: book.id, title: newTitle, author: newAuthor, coverData: coverData)
                }
            }
        }
    }
}
