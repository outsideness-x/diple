import SwiftUI

/// The feed: what the writers and journals the reader follows have published lately.
///
/// A quiet one, by construction rather than by setting. Each source keeps its three newest
/// pieces and nothing older (`FeedRack`), so the whole page is a few days of a few voices and
/// can be read to the end. There is no unread count, no badge on the tab, no bold for new, no
/// notification: a piece looks the same whether it arrived this minute or yesterday, and one
/// that four newer ones have pushed past leaves without being announced. What the reader wants
/// to keep they read or keep, and then it is in the library, where kept things live.
///
/// Days are the only structure — `Today`, `Yesterday`, a weekday — because "what is new" is the
/// one question a feed answers, and a heading per day answers it without a number.
public struct FeedView: View {
    @ObservedObject private var store = FeedStore.shared
    @State private var path = NavigationPath()
    /// The library, to know which pieces are already in it and how far they have been read.
    @State private var library: [Book] = []
    @State private var peeked: FeedItem?
    /// A piece asked for from its sheet, held until the sheet has gone: a push started under a
    /// sheet that is still leaving is dropped by the stack.
    @State private var pendingRoute: FeedOpening?
    @State private var isManagingSources = false
    @Namespace private var opening
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    private var index: FeedLibraryIndex { FeedLibraryIndex(library) }

    public var body: some View {
        NavigationStack(path: $path) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    masthead

                    if store.sources.isEmpty {
                        welcome
                    } else {
                        feed
                        foot
                    }
                }
                .padding(.horizontal, DipleSpace.xl)
                .padding(.top, DipleSpace.l)
                .padding(.bottom, DipleSpace.scrollBottom)
                .frame(maxWidth: 720)
                .frame(maxWidth: .infinity)
            }
            .refreshable { await store.check() }
            .tracksTabBarCollapse()
            .background(DipleColor.canvas.ignoresSafeArea())
            // Kept for the back button of anything pushed from here; the bar itself is hidden,
            // as on every root with a masthead.
            .navigationTitle("Feed")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar(.hidden, for: .navigationBar)
            .navigationDestination(for: FeedOpening.self) { route in
                destination(for: route)
            }
            .sheet(item: $peeked, onDismiss: {
                guard let route = pendingRoute else { return }
                pendingRoute = nil
                path.append(route)
            }) { item in
                FeedItemSheet(
                    item: item,
                    source: store.source(id: item.sourceID),
                    book: index.book(for: item),
                    isKeeping: store.keeping.contains(item.id),
                    onRead: { format in read(item, format: format) },
                    onKeep: { store.keep(item, library: library) }
                )
            }
            .sheet(isPresented: $isManagingSources) {
                FeedSourcesSheet()
            }
        }
        // On the stack, not its root, for the reason Home gives: a book closing back onto this
        // page reports through `onReadingUpdated` once it has landed.
        .refreshesOnTabActivation {
            reloadLibrary()
            Task { await store.checkIfStale() }
        }
        .onReceive(NotificationCenter.default.publisher(for: .dipleSourceDidImport)) { _ in
            reloadLibrary()
        }
    }

    // MARK: - Head

    private var masthead: some View {
        DipleMasthead(title: "Feed", strapline: strapline) {
            MastheadButton(systemImage: "plus", label: "Sources") {
                isManagingSources = true
            }
            .accessibilityIdentifier("feed.sources")
        }
    }

    private var strapline: String? { store.statusLine }

    // MARK: - The feed

    @ViewBuilder
    private var feed: some View {
        let days = FeedRack.days(store.items)
        if days.isEmpty {
            Text(store.isChecking ? "Fetching the newest pieces…" : "Nothing yet. The newest pieces arrive here as your sources publish them.")
                .dipleType(.callout)
                .foregroundStyle(DipleColor.textTertiary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, DipleSpace.xxl)
        }
        ForEach(Array(days.enumerated()), id: \.element.id) { offset, day in
            Text(day.title())
                .dipleSectionHeading()
                .padding(.top, offset == 0 ? DipleSpace.xxl : DipleSpace.xxxl)
                .padding(.bottom, DipleSpace.xs)
                .accessibilityAddTraits(.isHeader)

            ForEach(day.items) { item in
                row(item)
            }
        }
    }

    private func row(_ item: FeedItem) -> some View {
        Button {
            HapticManager.shared.selection()
            peeked = item
        } label: {
            FeedItemRow(
                item: item,
                source: store.source(id: item.sourceID),
                book: index.book(for: item),
                isKeeping: store.keeping.contains(item.id)
            )
        }
        .buttonStyle(.bookCard)
        .matchedTransitionSource(id: item.id, in: opening)
        .contextMenu { menu(for: item) }
        .accessibilityIdentifier("feed.item.\(item.id)")
        .transition(reduceMotion ? .opacity : .asymmetric(
            insertion: .opacity.combined(with: .offset(y: -DipleSpace.s)),
            removal: .opacity
        ))
    }

    @ViewBuilder
    private func menu(for item: FeedItem) -> some View {
        Button {
            read(item, format: .best)
        } label: {
            Label(item.arxivID != nil ? "Read the paper" : "Read", systemImage: "book")
        }
        if item.arxivID != nil {
            Button {
                read(item, format: .pdf)
            } label: {
                Label("Read the PDF", systemImage: "doc.richtext")
            }
        }
        if index.book(for: item) == nil {
            Button {
                store.keep(item, library: library)
            } label: {
                Label("Keep for later", systemImage: "tray.and.arrow.down")
            }
        }
        ShareLink(item: item.link) {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        Button {
            UIPasteboard.general.url = item.link
        } label: {
            Label("Copy link", systemImage: "link")
        }
        if let source = store.source(id: item.sourceID) {
            Divider()
            Button(role: .destructive) {
                HapticManager.shared.impact(.medium)
                store.unfollow(source.id)
            } label: {
                Label("Unfollow \(source.isArxiv ? "arXiv" : source.title)", systemImage: "minus.circle")
            }
        }
    }

    // MARK: - Before anything is followed

    /// The first page, before the reader follows anything: what the feed is, in two sentences,
    /// and six sources worth starting with — each a tap from following.
    private var welcome: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: DipleSpace.s) {
                Text("A quiet feed")
                    .dipleType(.editorialTitle)
                    .foregroundStyle(DipleColor.textPrimary)
                Text("Follow a few writers and journals. Each keeps its three newest pieces here; older ones leave on their own, and nothing is ever counted.")
                    .dipleType(.callout)
                    .foregroundStyle(DipleColor.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.top, DipleSpace.xxl)
            .padding(.bottom, DipleSpace.xxl)

            recommendations(FeedRecommendation.all)

            addYourOwn
                .padding(.top, DipleSpace.l)
        }
    }

    // MARK: - Foot

    /// Where the feed ends: the rule it keeps, said once, and the sources diple suggests that
    /// the reader does not follow yet.
    private var foot: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(spacing: DipleSpace.m) {
                Rectangle()
                    .fill(DipleColor.hairline)
                    .frame(width: 32, height: DipleStroke.hairline)
                Text("Each source keeps its three newest pieces. Older ones leave on their own.")
                    .dipleType(.micro, weight: .regular)
                    .foregroundStyle(DipleColor.textQuaternary)
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, DipleSpace.xxxl)

            let suggested = store.unfollowedRecommendations
            if !suggested.isEmpty {
                Text("Worth following")
                    .dipleSectionHeading()
                    .padding(.top, DipleSpace.xxxl)
                    .padding(.bottom, DipleSpace.xs)
                recommendations(suggested)
            }

            addYourOwn
                .padding(.top, DipleSpace.l)
        }
    }

    private func recommendations(_ list: [FeedRecommendation]) -> some View {
        ForEach(list) { recommendation in
            FeedRecommendationRow(recommendation: recommendation)
                .transition(.opacity)
        }
    }

    private var addYourOwn: some View {
        Button {
            HapticManager.shared.selection()
            isManagingSources = true
        } label: {
            HStack(spacing: DipleSpace.s) {
                Image(systemName: "plus")
                    .dipleIcon(12, weight: .semibold)
                Text("Follow your own — a blog, a newsletter, any feed")
                    .dipleType(.footnote, weight: .medium)
            }
            .foregroundStyle(DipleColor.textSecondary)
            .padding(.vertical, DipleSpace.m)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.readerControl)
        .accessibilityIdentifier("feed.addOwn")
    }

    // MARK: - Reading

    private func read(_ item: FeedItem, format: FeedReading.Format) {
        let route = FeedOpening(itemID: item.id, format: format)
        if peeked != nil {
            pendingRoute = route
            peeked = nil
        } else {
            path.append(route)
        }
    }

    @ViewBuilder
    private func destination(for route: FeedOpening) -> some View {
        if let item = store.item(id: route.itemID) {
            let view = FeedOpeningView(
                item: item,
                format: route.format,
                library: library,
                onReadingUpdated: reloadLibrary
            )
            if reduceMotion {
                view
            } else {
                view.navigationTransition(.zoom(sourceID: item.id, in: opening))
            }
        }
    }

    private func reloadLibrary() {
        library = (try? AppDatabase.shared.fetchAllBooks()) ?? []
    }
}
