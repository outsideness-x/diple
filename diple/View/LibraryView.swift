import SwiftUI
import UniformTypeIdentifiers

public struct LibraryView: View {
    @StateObject private var viewModel = LibraryViewModel()
    @State private var isFileImporterPresented = false
    @State private var isLinkImporterPresented = false

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
                    EmptyLibraryView(
                        onImportFile: { isFileImporterPresented = true },
                        onSaveLink: { isLinkImporterPresented = true }
                    )
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: DipleSpace.xxxl) {
                            if let book = viewModel.continueReadingBook {
                                VStack(alignment: .leading, spacing: DipleSpace.m) {
                                    sectionHeading("CONTINUE READING")

                                    NavigationLink(value: book) {
                                        ContinueReadingCard(book: book)
                                    }
                                    .buttonStyle(.bookCard)
                                    .accessibilityHint("Opens at your last reading position")
                                }
                            }

                            VStack(alignment: .leading, spacing: DipleSpace.m) {
                                HStack(alignment: .firstTextBaseline) {
                                    sectionHeading("LIBRARY")

                                    Spacer()

                                    Text("\(viewModel.books.count)")
                                        .dipleType(.micro)
                                        .foregroundStyle(DipleColor.textQuaternary)
                                        .monospacedDigit()
                                }

                                LazyVGrid(columns: columns, spacing: DipleSpace.xxl) {
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
                    Menu {
                        Button {
                            isLinkImporterPresented = true
                        } label: {
                            Label("Save a Link", systemImage: "link")
                        }

                        Button {
                            isFileImporterPresented = true
                        } label: {
                            Label("Import a File", systemImage: "folder")
                        }
                    } label: {
                        Image(systemName: "plus")
                            .dipleIcon(16)
                            .foregroundStyle(DipleColor.accent)
                    }
                    .buttonStyle(.readerControl)
                    .simultaneousGesture(TapGesture().onEnded {
                        HapticManager.shared.selection()
                    })
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
            .sheet(isPresented: $isLinkImporterPresented) {
                ImportLinkSheetView { _ in
                    viewModel.loadBooks()
                }
            }
            .sheet(item: $viewModel.bookToEdit) { book in
                EditBookMetadataView(book: book) { newTitle, newAuthor, coverData in
                    viewModel.updateMetadata(for: book.id, title: newTitle, author: newAuthor, coverData: coverData)
                }
            }
        }
    }

    private func sectionHeading(_ title: String) -> some View {
        Text(title)
            .dipleType(.micro, weight: .semibold)
            .foregroundStyle(DipleColor.textTertiary)
    }
}

/// The one unfinished publication most likely to be opened next. Unlike a grid tile, this is
/// a reading state: cover, identity, progress and a single continuation affordance.
private struct ContinueReadingCard: View {
    let book: Book

    @ScaledMetric(relativeTo: .title3) private var coverWidth: CGFloat = 72

    private var clampedProgress: CGFloat {
        CGFloat(min(max(book.progress, 0), 1))
    }

    var body: some View {
        HStack(spacing: DipleSpace.l) {
            BookCoverView(
                coverPath: book.coverPath,
                title: book.title,
                author: book.author,
                isCompact: true
            )
            .frame(width: coverWidth, height: coverWidth * 1.5)

            VStack(alignment: .leading, spacing: DipleSpace.s) {
                VStack(alignment: .leading, spacing: DipleSpace.xs) {
                    Text(book.title)
                        .dipleType(.headline)
                        .foregroundStyle(DipleColor.textPrimary)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)

                    BookSubtitleView(book: book)
                }

                Spacer(minLength: DipleSpace.xs)

                HStack(spacing: DipleSpace.s) {
                    GeometryReader { geometry in
                        ZStack(alignment: .leading) {
                            Capsule().fill(DipleColor.surfaceOverlay)
                            Capsule()
                                .fill(DipleColor.accent)
                                .frame(width: geometry.size.width * clampedProgress)
                                .craftGlow(DipleColor.accent.opacity(0.5), radius: DipleSpace.xs)
                        }
                    }
                    .frame(height: DipleSpace.xs)

                    Text("\(Int((clampedProgress * 100).rounded()))%")
                        .dipleType(.micro, weight: .semibold)
                        .foregroundStyle(DipleColor.accent)
                        .monospacedDigit()
                }

                HStack(spacing: DipleSpace.xs) {
                    Text("Continue")
                        .dipleType(.footnote, weight: .semibold)
                    Image(systemName: "arrow.right")
                        .dipleIcon(11, weight: .semibold)
                }
                .foregroundStyle(DipleColor.textSecondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(DipleSpace.m)
        .background(alignment: .topTrailing) {
            RadialGradient(
                colors: [DipleColor.accent.opacity(0.12), .clear],
                center: .topTrailing,
                startRadius: 0,
                endRadius: 180
            )
        }
        .craftSurface(DipleColor.surfaceRaised, radius: DipleRadius.l)
        .accessibilityElement(children: .combine)
        .accessibilityValue("\(Int((clampedProgress * 100).rounded())) percent read")
    }
}
