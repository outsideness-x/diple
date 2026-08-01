import SwiftUI

/// User notes, laid out as an are.na-style board of blocks.
public struct NotesView: View {
    @StateObject private var viewModel = NotesViewModel()

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: 240), spacing: 12)
    ]

    public init() {}

    public var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

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
            .toolbarBackground(Color.black, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        HapticManager.shared.selection()
                        viewModel.editorTarget = NoteEditorTarget(item: nil)
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(Color.dipleAccent)
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
            HStack(spacing: 8) {
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
            .padding(.horizontal, 20)
            .padding(.vertical, 10)
        }
    }

    @ViewBuilder
    private func chip(for filter: NoteFilter) -> some View {
        let isSelected = viewModel.filter == filter
        switch filter {
        case .all:
            Text("All")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(isSelected ? .black : Color(red: 0.65, green: 0.65, blue: 0.7))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.dipleAccent : Color(red: 0.15, green: 0.15, blue: 0.17))
                .clipShape(Capsule())
        case .tag(let tag):
            TagChipView(label: tag, kind: .text, isSelected: isSelected)
        case .book:
            TagChipView(label: viewModel.title(for: filter), kind: .book, isSelected: isSelected)
        }
    }

    private var board: some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
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
            .padding(.horizontal, 20)
            .padding(.top, 4)
            .padding(.bottom, 32)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            ZStack {
                Circle()
                    .fill(Color.dipleAccent.opacity(0.12))
                    .frame(width: 80, height: 80)

                Image(systemName: "square.grid.2x2")
                    .font(.system(size: 30, weight: .thin))
                    .foregroundColor(Color.dipleAccent)
            }

            VStack(spacing: 8) {
                Text("No Notes Yet")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))

                Text("Write something down and tag it — with your own words, or with a book from your library.")
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(Color(red: 0.55, green: 0.55, blue: 0.58))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Button {
                HapticManager.shared.impact(.light)
                viewModel.editorTarget = NoteEditorTarget(item: nil)
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "plus")
                        .font(.system(size: 14, weight: .semibold))
                    Text("New Note")
                        .font(.system(size: 15, weight: .semibold))
                }
                .foregroundColor(.black)
                .padding(.vertical, 12)
                .padding(.horizontal, 24)
                .background(Color.dipleAccent)
                .cornerRadius(20)
            }
            .buttonStyle(.plain)
            .padding(.top, 8)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
