import SwiftUI

/// The notes workspace: capture, rediscover and develop ideas without leaving reading.
public struct NotesView: View {
    @StateObject private var viewModel = NotesViewModel()
    @AppStorage("diple_notes_layout") private var storedLayout = NoteLayout.cards.rawValue

    /// Ties a card to the page it becomes, so the note expands out of the block the reader
    /// tapped instead of sliding in from the side.
    @Namespace private var cardNamespace

    /// One path for the tab, so a wiki link followed from inside a note pushes onto the same
    /// stack the cards push onto.
    @State private var path = NavigationPath()

    private let columns = [
        GridItem(.adaptive(minimum: 240, maximum: 360), spacing: DipleSpace.m)
    ]

    private enum NoteLayout: String {
        case cards
        case list
    }

    private var layout: NoteLayout {
        get { NoteLayout(rawValue: storedLayout) ?? .cards }
        nonmutating set { storedLayout = newValue.rawValue }
    }

    public init() {}

    public var body: some View {
        NavigationStack(path: $path) {
            ZStack {
                DipleColor.canvas.ignoresSafeArea()

                // Keep one stable root under NavigationStack. The previous empty/workspace
                // swap happened while the first note autosaved (or the last was deleted),
                // invalidating the active destination and making the editor appear to vanish.
                workspace
            }
            .navigationTitle("Notes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(DipleColor.canvas, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        ForEach(NoteSort.allCases) { sort in
                            Button {
                                viewModel.sort = sort
                            } label: {
                                Label(sort.title, systemImage: sort.systemImage)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .dipleIcon(15)
                            .foregroundStyle(DipleColor.textSecondary)
                    }
                    .accessibilityLabel("Sort notes")
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    NavigationLink(value: NoteRoute.new) {
                        Image(systemName: "plus")
                            .dipleIcon(16, weight: .medium)
                            .foregroundStyle(DipleColor.accent)
                    }
                    .buttonStyle(.readerControl)
                    .accessibilityLabel("New note")
                    .accessibilityIdentifier("notes.new")
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

    private var workspace: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: DipleSpace.l, pinnedViews: [.sectionHeaders]) {
                if viewModel.items.isEmpty {
                    emptyState
                } else {
                    workspaceHeader

                    Section {
                        if viewModel.filteredItems.isEmpty {
                            noResults
                        } else {
                            notesContent
                        }
                    } header: {
                        controls
                    }
                }
            }
            .padding(.bottom, DipleSpace.scrollBottom)
        }
        .scrollDismissesKeyboard(.interactively)
    }

    private var workspaceHeader: some View {
        VStack(alignment: .leading, spacing: DipleSpace.l) {
            VStack(alignment: .leading, spacing: DipleSpace.xs) {
                Text("CONTINUE THINKING")
                    .dipleType(.nano, weight: .semibold)
                    .foregroundStyle(DipleColor.accent)

                Text("Return to the idea, not the filing system.")
                    .dipleType(.title)
                    .foregroundStyle(DipleColor.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        }
        .padding(.horizontal, DipleSpace.xl)
        .padding(.top, DipleSpace.m)
    }

    private var controls: some View {
        VStack(spacing: DipleSpace.m) {
            HStack(spacing: DipleSpace.s) {
                HStack(spacing: DipleSpace.s) {
                    Image(systemName: "magnifyingglass")
                        .dipleIcon(14)
                        .foregroundStyle(DipleColor.textQuaternary)

                    TextField("Search every note", text: $viewModel.query)
                        .dipleType(.callout)
                        .foregroundStyle(DipleColor.textPrimary)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("notes.search")

                    if !viewModel.query.isEmpty {
                        Button {
                            viewModel.query = ""
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .dipleIcon(13)
                                .foregroundStyle(DipleColor.textQuaternary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear search")
                    }
                }
                .diplePadding(.field)
                .background(DipleColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DipleRadius.m))
                .overlay(
                    RoundedRectangle(cornerRadius: DipleRadius.m)
                        .stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline)
                )

                Button {
                    HapticManager.shared.selection()
                    withAnimation(DipleMotion.snappy) {
                        layout = layout == .cards ? .list : .cards
                    }
                } label: {
                    Image(systemName: layout == .cards ? "rectangle.grid.1x2" : "square.grid.2x2")
                        .dipleIcon(15)
                        .foregroundStyle(DipleColor.textSecondary)
                        .frame(width: 36, height: 36)
                        .background(DipleColor.surfaceRaised, in: RoundedRectangle(cornerRadius: DipleRadius.m))
                        .overlay(
                            RoundedRectangle(cornerRadius: DipleRadius.m)
                                .stroke(DipleColor.hairline, lineWidth: DipleStroke.hairline)
                        )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(layout == .cards ? "Show as list" : "Show as cards")
            }

            filterBar
        }
        .padding(.horizontal, DipleSpace.xl)
        .padding(.top, DipleSpace.l)
        .padding(.bottom, DipleSpace.m)
        .background(.ultraThinMaterial)
        .background(DipleColor.canvas.opacity(0.88))
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
            allNotes: viewModel.items,
            onSave: { note, tags in
                viewModel.save(note, tags: tags)
            },
            onDelete: { item in
                viewModel.delete(item)
            },
            onOpenNote: { path.append(NoteRoute.existing($0)) }
        )

        switch route {
        case .existing(let item):
            page.navigationTransition(.zoom(sourceID: item.id, in: cardNamespace))
        case .new, .newFromSource:
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
        }
        .contentMargins(.horizontal, 0, for: .scrollContent)
    }

    @ViewBuilder
    private func chip(for filter: NoteFilter) -> some View {
        let isSelected = viewModel.filter == filter
        switch filter {
        case .all:
            filterChip("All", systemImage: "tray.full", isSelected: isSelected)
        case .recent:
            filterChip("This week", systemImage: "clock", isSelected: isSelected)
        case .linked:
            filterChip("From library", systemImage: "book.closed", isSelected: isSelected)
        case .untagged:
            filterChip("Unsorted", systemImage: "tray", isSelected: isSelected)
        case .tag(let tag):
            TagChipView(label: tag, kind: .text, isSelected: isSelected)
        case .book:
            TagChipView(label: viewModel.title(for: filter), kind: .book, isSelected: isSelected)
        }
    }

    private func filterChip(_ title: String, systemImage: String, isSelected: Bool) -> some View {
        Label(title, systemImage: systemImage)
            .dipleType(.micro)
            .foregroundColor(isSelected ? DipleColor.textOnAccent : DipleColor.textTertiary)
            .diplePadding(.chip)
            .background(isSelected ? DipleColor.accent : DipleColor.surfaceOverlay)
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var notesContent: some View {
        if layout == .cards {
            LazyVGrid(columns: columns, alignment: .leading, spacing: DipleSpace.m) {
                noteLinks
            }
            .padding(.horizontal, DipleSpace.xl)
        } else {
            LazyVStack(spacing: DipleSpace.s) {
                noteLinks
            }
            .padding(.horizontal, DipleSpace.xl)
        }
    }

    private var noteLinks: some View {
        ForEach(viewModel.filteredItems) { item in
            NavigationLink(value: NoteRoute.existing(item)) {
                NoteCardView(item: item, style: layout == .cards ? .card : .row)
            }
            .buttonStyle(.bookCard)
            .matchedTransitionSource(id: item.id, in: cardNamespace)
            .contextMenu {
                Button {
                    UIPasteboard.general.string = item.note.body
                } label: {
                    Label("Copy text", systemImage: "doc.on.doc")
                }

                Button(role: .destructive) {
                    viewModel.confirmDelete(item)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
            }
        }
    }

    private var noResults: some View {
        VStack(spacing: DipleSpace.m) {
            Image(systemName: viewModel.query.isEmpty ? "line.3.horizontal.decrease.circle" : "text.magnifyingglass")
                .dipleIcon(24, weight: .light)
                .foregroundStyle(DipleColor.accent)
            Text(viewModel.query.isEmpty ? "Nothing in this view" : "No matching notes")
                .dipleType(.headline)
                .foregroundStyle(DipleColor.textPrimary)
            Text(viewModel.query.isEmpty ? "Choose another filter or create a note here." : "Try a title, phrase, tag, author or book.")
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
                .multilineTextAlignment(.center)
            if !viewModel.query.isEmpty {
                Button("Clear search") { viewModel.query = "" }
                    .dipleType(.footnote, weight: .semibold)
                    .foregroundStyle(DipleColor.accent)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, DipleSpace.xl)
        .padding(.vertical, DipleSpace.xxxl)
    }

    private var emptyState: some View {
        VStack(spacing: DipleSpace.xl) {
            ZStack {
                AccentWash(diameter: 190)
                Image(systemName: "note.text")
                .dipleIcon(30, weight: .thin)
                .foregroundStyle(DipleColor.accent)
            }

            VStack(spacing: DipleSpace.s) {
                Text("Write the first note")
                    .dipleType(.title)
                    .foregroundStyle(DipleColor.textPrimary)

                Text("Start with the thought itself. You can connect a source or add tags when they become useful.")
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
            .accessibilityIdentifier("notes.new")
            .padding(.top, DipleSpace.s)

        }
        .frame(maxWidth: .infinity)
        .containerRelativeFrame(.vertical, alignment: .center) { length, _ in
            max(length - DipleSpace.scrollBottom, 420)
        }
    }
}
