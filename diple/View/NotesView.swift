import SwiftUI

/// User notes, laid out as an are.na-style board of blocks.
public struct NotesView: View {
    @StateObject private var viewModel = NotesViewModel()

    /// Ties a card to the page it becomes, so the note expands out of the block the reader
    /// tapped instead of sliding in from the side.
    @Namespace private var cardNamespace

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 240), spacing: DipleSpace.m)
    ]

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                VStack(spacing: 0) {
                    if viewModel.availableFilters.count > 1 {
                        filterBar
                    }

                    if viewModel.items.isEmpty {
                        emptyState
                    } else {
                        board
                    }
                }
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(value: NoteRoute.new) {
                        Image(systemName: "plus")
                            .dipleIcon(16, weight: .medium)
                            .foregroundStyle(DipleColor.accent)
                    }
                    .simultaneousGesture(TapGesture().onEnded {
                        HapticManager.shared.selection()
                    })
                }
            }
            .navigationDestination(for: NoteRoute.self) { route in
                destination(for: route)
            }
            .alert("Error", isPresented: $viewModel.showErrorAlert) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(viewModel.errorMessage ?? "An unknown error occurred.")
            }
            .alert("Delete Note?", isPresented: $viewModel.showDeleteConfirmation) {
                Button("Delete", role: .destructive) {
                    viewModel.deleteConfirmedNote()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This note will be removed permanently.")
            }
            .onAppear {
                viewModel.load()
            }
        }
    }

    /// A new note has no card on the board, so there is nothing for it to expand out of —
    /// it gets the standard push. `NavigationTransition` has no type eraser, so the two
    /// cases are branched here rather than resolved into one value.
    @ViewBuilder
    private func destination(for route: NoteRoute) -> some View {
        let page = NoteDetailView(
            route: route,
            books: viewModel.books,
            suggestedTags: viewModel.allTags,
            onSave: { note, tags in
                viewModel.save(note, tags: tags)
            },
            onDelete: { item in
                viewModel.delete(item)
            }
        )

        switch route {
        case .existing(let item):
            page.navigationTransition(.zoom(sourceID: item.id, in: cardNamespace))
        case .new:
            page
        }
    }

    private var filterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DipleSpace.s) {
                ForEach(viewModel.availableFilters, id: \.self) { filter in
                    Button {
                        HapticManager.shared.selection()
                        viewModel.filter = filter
                    } label: {
                        chip(for: filter)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DipleSpace.xl)
            .padding(.vertical, DipleSpace.m)
        }
    }

    @ViewBuilder
    private func chip(for filter: NoteFilter) -> some View {
        let isSelected = viewModel.filter == filter
        switch filter {
        case .all:
            Text("All")
                .dipleType(.micro)
                .foregroundColor(isSelected ? .black : DipleColor.textTertiary)
                .diplePadding(.chip)
                .background(isSelected ? DipleColor.accent : DipleColor.surfaceOverlay)
                .clipShape(Capsule())
        case .tag(let tag):
            TagChipView(label: tag, kind: .text, isSelected: isSelected)
        case .book:
            TagChipView(label: viewModel.title(for: filter), kind: .book, isSelected: isSelected)
        }
    }

    private var board: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: DipleSpace.m) {
                ForEach(viewModel.filteredItems) { item in
                    NavigationLink(value: NoteRoute.existing(item)) {
                        NoteCardView(item: item)
                    }
                    .buttonStyle(.bookCard)
                    .matchedTransitionSource(id: item.id, in: cardNamespace)
                    .simultaneousGesture(TapGesture().onEnded {
                        HapticManager.shared.impact(.light)
                    })
                    .contextMenu {
                        Button(role: .destructive) {
                            viewModel.confirmDelete(item)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
            }
            .padding(.horizontal, DipleSpace.xl)
            .padding(.top, DipleSpace.xs)
            .padding(.bottom, DipleSpace.xxxl)
        }
    }

    private var emptyState: some View {
        VStack(spacing: DipleSpace.xl) {
            Spacer()

            ZStack {
                AccentWash()

                Image(systemName: "square.grid.2x2")
                    .dipleIcon(30, weight: .thin)
                    .foregroundStyle(DipleColor.accent)
                    .craftGlow(DipleColor.accent.opacity(0.5), radius: 18)
            }

            VStack(spacing: DipleSpace.s) {
                Text("No Notes Yet")
                    .dipleType(.title)
                    .foregroundStyle(DipleColor.textPrimary)

                Text("Write something down and tag it — with your own words, or with a book from your library.")
                    .dipleType(.callout)
                    .foregroundStyle(DipleColor.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, DipleSpace.xxxl)
            }

            NavigationLink(value: NoteRoute.new) {
                HStack(spacing: DipleSpace.s) {
                    Image(systemName: "plus")
                        .dipleIcon(14, weight: .semibold)
                    Text("New Note")
                        .dipleType(.body, weight: .semibold)
                }
                .foregroundStyle(DipleColor.textOnAccent)
                .diplePadding(.buttonLarge)
                .background(DipleColor.accent, in: Capsule())
                .craftGlow(radius: 16)
            }
            .buttonStyle(.plain)
            .padding(.top, DipleSpace.s)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
