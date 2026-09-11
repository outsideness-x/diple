import SwiftUI

/// Top-level shell of the app: two workshops under one roof.
///
/// **Reading** is where books are read and passages kept — Home, the library and Highlights,
/// with search beside them. **Notes** is where the reader thinks and writes. They were one row
/// of four places, and the notes room spoke the reading room's language: a note was filed by
/// the book it came from or it was "unsorted", and a plan, a journal or an idea that was about
/// no book had nowhere to stand. Readwise solved the same problem by splitting into two
/// applications; here it is one application with two modes, and the bridges between them —
/// a note written inside a book, a book linked to a note, a passage expanded into one — cross
/// the modes without noticing them.
///
/// Not a `TabView`. The system bar spans the full width and sits *on* the content rather than
/// over it — on the shelf its "Library" label landed on a book cover, on the board it landed on
/// note text — and it cannot collapse while the reader scrolls, which is the behaviour this
/// shell exists to get. Every root of both modes is held in one `ZStack` instead, all alive, so
/// switching a tab *or a mode* keeps each one's navigation stack and scroll position exactly as
/// `TabView` did — a half-written note survives a trip to the shelf and back.
public struct RootTabView: View {
    /// Which workshop is open.
    public enum Mode: String, Hashable {
        case reading
        case notes

        var title: String {
            switch self {
            case .reading: return "Reading"
            case .notes: return "Notes"
            }
        }

        /// A shelf and a page with writing on it — the same two glyphs the two rooms already had
        /// in the old four-place row, so a reader looking for Notes finds the page they know.
        var symbol: String {
            switch self {
            case .reading: return "books.vertical"
            case .notes: return "note.text"
            }
        }

        var other: Mode { self == .reading ? .notes : .reading }
    }

    public enum Tab: Hashable, CaseIterable {
        case home
        case library
        case highlights
        case notes
        case search

        var title: String {
            switch self {
            case .home: return "Home"
            case .library: return "Library"
            case .highlights: return "Highlights"
            case .notes: return "Notes"
            case .search: return "Search"
            }
        }

        /// One family of metaphors: places made of paper, and a verb.
        var symbol: String {
            switch self {
            case .home: return "house"
            case .library: return "books.vertical"
            case .highlights: return "quote.opening"
            case .notes: return "note.text"
            case .search: return "magnifyingglass"
            }
        }

        var selectedSymbol: String {
            switch self {
            case .home: return "house.fill"
            case .library: return "books.vertical.fill"
            case .highlights: return "quote.opening"
            case .notes: return "note.text"
            case .search: return "magnifyingglass"
            }
        }

        /// The workshop this root belongs to. Notes is the whole of its mode for now — one
        /// stack, the way Things is one list — and everything else is reading.
        var mode: Mode { self == .notes ? .notes : .reading }
    }

    /// Where the open mode is remembered.
    ///
    /// Device-local `UserDefaults`, deliberately not `AppSettings`: that one travels through
    /// CloudKit as a single blob, and the mode a Mac was left in has no business switching the
    /// phone. The app reopens in the workshop it was closed in.
    static let modeKey = "diple_app_mode"

    @State private var mode: Mode = Mode(
        rawValue: UserDefaults.standard.string(forKey: RootTabView.modeKey) ?? ""
    ) ?? .reading
    /// The reading place — or search — that Reading shows. Kept while Notes is open, so going
    /// back lands where the reader left rather than on Home.
    @State private var selection: Tab = .home
    @State private var isBarHidden = false
    @StateObject private var tabBarState = DipleTabBarState()
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public init() {}

    /// The root on screen: the whole of Notes, or whichever reading place is chosen.
    private var activeRoot: Tab { mode == .notes ? .notes : selection }

    public var body: some View {
        ZStack(alignment: .bottom) {
            tabContent

            if !isBarHidden {
                DipleTabBar(
                    mode: mode,
                    selection: $selection,
                    isCollapsed: tabBarState.isCollapsed,
                    onSwitchMode: switchMode,
                    onCompose: compose
                )
                .padding(.bottom, DipleSpace.s)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onDipleTabBarHiddenChange { hidden in
            withAnimation(DipleMotion.gentle) { isBarHidden = hidden }
        }
        .environment(\.dipleTabBarState, tabBarState)
        .tint(DipleColor.accent)
        .onChange(of: selection) { _, _ in
            tabBarState.reset()
        }
        .onChange(of: mode) { _, newMode in
            tabBarState.reset()
            UserDefaults.standard.set(newMode.rawValue, forKey: Self.modeKey)
        }
        // The daily notification and the widget both land on the day's passage, which stands at
        // the top of its own room — a reading room, so they open Reading whichever mode was up.
        .onReceive(NotificationCenter.default.publisher(for: .dipleOpenDailyResurfacing)) { _ in
            mode = .reading
            selection = .highlights
        }
        // The Home Screen quick actions lead into Notes. A cold launch hands the shortcut over
        // before this view exists, so `onAppear` collects it as well.
        .onReceive(NotificationCenter.default.publisher(for: .dipleShortcut)) { _ in
            if let shortcut = DipleShortcut.consume() { perform(shortcut) }
        }
        .onAppear {
            if DailyResurfacingService.shared.consumeOpenRequest() {
                mode = .reading
                selection = .highlights
            }
            if let shortcut = DipleShortcut.consume() { perform(shortcut) }
        }
    }

    private func perform(_ shortcut: DipleShortcut) {
        mode = .notes
        guard shortcut == .newNote else { return }
        // One turn of the run loop later. On a cold launch the notes stack is being built in
        // this same pass, and a request posted before it is listening would be a page nobody
        // opens.
        Task { @MainActor in
            await Task.yield()
            NotificationCenter.default.post(name: .dipleComposeNote, object: nil)
        }
    }

    /// Every root of both modes stays in the tree. Hiding by opacity rather than rebuilding is
    /// what keeps a half-written note, a scrolled shelf and a pushed detail screen where the
    /// reader left them; `allowsHitTesting` stops the hidden roots from swallowing touches, and
    /// `accessibilityHidden` stops VoiceOver from reading five screens at once.
    private var tabContent: some View {
        ZStack {
            tabRoot(.home) { HomeView() }
            tabRoot(.library) { LibraryView() }
            tabRoot(.highlights) { MarginaliaView(door: .highlights) }
            tabRoot(.search) { GlobalSearchView() }
            tabRoot(.notes) { NotesWorkshopView() }
        }
    }

    @ViewBuilder
    private func tabRoot<Content: View>(
        _ tab: Tab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        let isActive = activeRoot == tab
        // A change of mode is a change of workshop, not of place, and it should read as one: the
        // other mode's roots stand a hair smaller, so switching settles the new one forward
        // instead of only cross-fading it. Places within one mode keep their plain cross-fade —
        // the same room, a different wall.
        let isInOpenMode = tab.mode == mode
        content()
            .environment(\.dipleTabIsActive, isActive)
            .opacity(isActive ? 1 : 0)
            .scaleEffect(isInOpenMode || reduceMotion ? 1 : 0.98)
            .allowsHitTesting(isActive)
            .accessibilityHidden(!isActive)
            .zIndex(isActive ? 1 : 0)
    }

    private func switchMode() {
        HapticManager.shared.impact(.light)
        withAnimation(reduceMotion ? nil : DipleMotion.gentle) {
            mode = mode.other
        }
    }

    /// The verb of the notes mode. The board owns its own navigation stack, so the request is
    /// posted rather than reached for — the same arrangement the shell already uses to open the
    /// day's passage.
    private func compose() {
        HapticManager.shared.selection()
        NotificationCenter.default.post(name: .dipleComposeNote, object: nil)
    }
}

extension Notification.Name {
    /// The bar's `+` in Notes was pressed: start a new note in the notes stack.
    static let dipleComposeNote = Notification.Name("diple.composeNote")
}
