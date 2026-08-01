import SwiftUI

/// User notes, laid out as an are.na-style board of blocks.
public struct NotesView: View {
    @StateObject private var viewModel = NotesViewModel()

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
                    Button {
                        HapticManager.shared.selection()
                        viewModel.editorTarget = NoteEditorTarget(item: nil)
                    } label: {
                        Image(systemName: "plus")
                            .dipleIcon(16, weight: .medium)
                            .foregroundStyle(DipleColor.accent)
                    }
                }
            }
            .sheet(item: $viewModel.editorTarget) { target in
                NoteEditorView(
                    target: target,
                    books: viewModel.books,
                    suggestedTags: viewModel.allTags
                ) { note, tags in
                    viewModel.save(note, tags: tags)
                }
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
                    Button {
                        HapticManager.shared.impact(.light)
                        viewModel.editorTarget = NoteEditorTarget(item: item)
                    } label: {
                        NoteCardView(item: item)
                    }
                    .buttonStyle(.plain)
                    .contextMenu {
                        Button {
                            viewModel.editorTarget = NoteEditorTarget(item: item)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }

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
                Circle()
                    .fill(DipleColor.accent.opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: "square.grid.2x2")
                    .dipleIcon(30, weight: .thin)
                    .foregroundStyle(DipleColor.accent)
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

            Button {
                HapticManager.shared.impact(.light)
                viewModel.editorTarget = NoteEditorTarget(item: nil)
            } label: {
                HStack(spacing: DipleSpace.s) {
                    Image(systemName: "plus")
                        .dipleIcon(14, weight: .semibold)
                    Text("New Note")
                        .dipleType(.body, weight: .semibold)
                }
                .foregroundStyle(DipleColor.textOnAccent)
                .diplePadding(.buttonLarge)
                .background(DipleColor.accent, in: Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, DipleSpace.s)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
