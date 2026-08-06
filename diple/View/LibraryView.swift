import SwiftUI
import UniformTypeIdentifiers

public struct LibraryView: View {
    private enum BookPlacement: String, Hashable {
        case continueReading
        case grid
    }

    private struct BookRoute: Hashable {
        let book: Book
        let placement: BookPlacement

        var sourceID: String { "\(placement.rawValue):\(book.id)" }
    }

    @StateObject private var viewModel = LibraryViewModel()
    @State private var isFileImporterPresented = false
    @State private var isLinkImporterPresented = false

    @State private var isAppSettingsPresented = false
    @State private var searchText = ""
    @State private var filter: LibraryFilter = .all
    @State private var sort: LibrarySort = .recentlyOpened
    @Namespace private var bookNamespace
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private let columns = [
        GridItem(.adaptive(minimum: 140, maximum: 180), spacing: 20)
    ]

    public init() {}

    private var visibleBooks: [Book] {
        viewModel.visibleBooks(query: searchText, filter: filter, sort: sort)
    }

    private var isDefaultBrowse: Bool {
        searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && filter == .all
    }

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
                            if isDefaultBrowse, let book = viewModel.continueReadingBook {
                                VStack(alignment: .leading, spacing: DipleSpace.m) {
                                    sectionHeading("CONTINUE READING")

                                    let route = BookRoute(book: book, placement: .continueReading)
                                    NavigationLink(value: route) {
                                        ContinueReadingCard(book: book)
                                    }
                                    .buttonStyle(.bookCard)
                                    .matchedTransitionSource(id: route.sourceID, in: bookNamespace)
                                    .accessibilityHint("Opens at your last reading position")
                                }
                            }

                            if viewModel.books.count > 1 {
                                filterBar
                            }

                            VStack(alignment: .leading, spacing: DipleSpace.m) {
                                HStack(alignment: .firstTextBaseline) {
                                    sectionHeading(isDefaultBrowse ? "LIBRARY" : "RESULTS")

                                    Spacer()

                                    Text("\(visibleBooks.count)")
                                        .dipleType(.micro)
                                        .foregroundStyle(DipleColor.textQuaternary)
                                        .monospacedDigit()

                                    sortMenu
                                }

                                if visibleBooks.isEmpty {
                                    noResults
                                } else {
                                    LazyVGrid(columns: columns, spacing: DipleSpace.xxl) {
                                        ForEach(visibleBooks) { book in
                                            let route = BookRoute(book: book, placement: .grid)
                                            NavigationLink(value: route) {
                                                BookItemView(book: book, onEdit: {
                                                    viewModel.bookToEdit = book
                                                }, onDelete: {
                                                    viewModel.confirmDelete(book)
                                                })
                                            }
                                            .buttonStyle(.bookCard)
                                            .matchedTransitionSource(id: route.sourceID, in: bookNamespace)
                                        }
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
            .navigationTitle("diple.")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(
                text: $searchText,
                placement: .navigationBarDrawer(displayMode: .automatic),
                prompt: "Title, author or source"
            )
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
            .navigationDestination(for: BookRoute.self) { route in
                readerDestination(for: route)
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

    @ViewBuilder
    private func readerDestination(for route: BookRoute) -> some View {
        let reader = ReaderContainerView(book: route.book, onReadingUpdated: {
            viewModel.loadBooks()
        })

        if reduceMotion {
            reader
        } else {
            reader.navigationTransition(.zoom(sourceID: route.sourceID, in: bookNamespace))
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DipleSpace.s) {
                ForEach(LibraryFilter.allCases) { option in
                    Button {
                        HapticManager.shared.selection()
                        withAnimation(DipleMotion.standard) {
                            filter = option
                        }
                    } label: {
                        Text(option.rawValue)
                            .dipleType(.micro)
                            .foregroundStyle(filter == option ? DipleColor.textOnAccent : DipleColor.textTertiary)
                            .diplePadding(.chip)
                            .background(filter == option ? DipleColor.accent : DipleColor.surfaceOverlay)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
        .accessibilityLabel("Library filters")
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort Library", selection: $sort) {
                ForEach(LibrarySort.allCases) { option in
                    Text(option.rawValue).tag(option)
                }
            }
        } label: {
            HStack(spacing: DipleSpace.xs) {
                Image(systemName: "arrow.up.arrow.down")
                    .dipleIcon(10, weight: .semibold)
                Text(sort.compactTitle)
                    .dipleType(.micro, weight: .semibold)
            }
            .foregroundStyle(DipleColor.textSecondary)
            .diplePadding(.chip)
            .background(DipleColor.surfaceOverlay, in: Capsule())
        }
        .buttonStyle(.readerControl)
        .accessibilityLabel("Sort Library")
        .accessibilityValue(sort.rawValue)
    }

    private var noResults: some View {
        VStack(spacing: DipleSpace.m) {
            Image(systemName: "magnifyingglass")
                .dipleIcon(24, weight: .light)
                .foregroundStyle(DipleColor.textQuaternary)

            Text("Nothing Found")
                .dipleType(.headline)
                .foregroundStyle(DipleColor.textPrimary)

            Text("Try another title, author, source or reading status.")
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
                .multilineTextAlignment(.center)

            Button("Clear Search and Filters") {
                searchText = ""
                filter = .all
                HapticManager.shared.selection()
            }
            .dipleType(.footnote, weight: .semibold)
            .foregroundStyle(DipleColor.accent)
            .buttonStyle(.readerControl)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, DipleSpace.xxxl)
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
