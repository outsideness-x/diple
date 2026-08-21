import SwiftUI
import ReadiumShared
import ReadiumNavigator

public struct ReaderContainerView: View {
    @StateObject private var viewModel: ReaderViewModel
    @StateObject private var settingsManager = AppSettingsManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var highlightEditorTarget: HighlightEditorTarget?
    /// The colour the next selection will be marked in — whichever one was chosen last.
    ///
    /// A working habit, not navigation state, so it lives in `@AppStorage` beside the library
    /// and notes layout choices rather than in `ReaderSettings`. Two reasons it does not belong
    /// there: `ReaderSettings` is `Equatable` and every change to it re-submits preferences to
    /// Readium, which recolouring a highlight has no business doing; and it travels through the
    /// CloudKit settings payload, where a per-device marker preference is not worth a field.
    @AppStorage("diple_last_highlight_color") private var lastHighlightColorHex = DipleColor.Highlight.yellow
    public let onReadingUpdated: () -> Void

    public init(book: Book, startingLocator: Locator? = nil, onReadingUpdated: @escaping () -> Void) {
        self._viewModel = StateObject(wrappedValue: ReaderViewModel(book: book, startingLocator: startingLocator))
        self.onReadingUpdated = onReadingUpdated
    }

    /// The chrome follows the page: changing the reader theme re-tints the bars and flips the
    /// controls in the same gesture.
    private var chrome: ReaderChrome {
        ReaderChrome.forTheme(viewModel.settings.theme)
    }

    public var body: some View {
        ZStack {
            // The page stops at the safe area, so the bands the status bar and the resting
            // progress line occupy are painted here instead — in the page's own ground, so the
            // sheet still runs bezel to bezel and the reader sees one surface. Before a book is
            // open there is no page to match, and the app canvas is the right backdrop for a
            // spinner or an error.
            (viewModel.publication == nil ? DipleColor.canvas : chrome.page)
                .ignoresSafeArea()

            if viewModel.isLoading {
                VStack(spacing: DipleSpace.m) {
                    ProgressView()
                        .tint(DipleColor.accent)
                    Text("Loading book...")
                        .dipleType(.callout, weight: .medium)
                        .foregroundStyle(DipleColor.textSecondary)
                }
            } else if let errorMessage = viewModel.errorMessage {
                VStack(spacing: DipleSpace.l) {
                    Image(systemName: "exclamationmark.triangle")
                        .dipleIcon(32)
                        .foregroundStyle(DipleColor.destructive)

                    Text(errorMessage)
                        .dipleType(.callout, weight: .medium)
                        .foregroundStyle(DipleColor.textPrimary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DipleSpace.xxxl)

                    Button("Close") {
                        dismiss()
                    }
                    .foregroundStyle(DipleColor.textPrimary)
                    .padding(.horizontal, DipleSpace.xl)
                    .padding(.vertical, DipleSpace.s)
                    .background(DipleColor.surfaceOverlay)
                    .cornerRadius(DipleRadius.s)
                }
            } else if let publication = viewModel.publication {
                if viewModel.book.isPDF {
                    PDFNavigatorRepresentable(
                        publication: publication,
                        initialLocation: viewModel.initialLocator,
                        targetLink: viewModel.targetLink,
                        targetLocator: viewModel.targetLocator,
                        preferences: viewModel.settings.pdfPreferences,
                        hasSelection: viewModel.currentSelection != nil,
                        onLocationChanged: { locator in
                            viewModel.saveLocation(locator)
                            ReaderIdleTimerKeeper.shared.poke()
                        },
                        onSelectionChanged: { selection in
                            presentEditor(for: selection)
                            ReaderIdleTimerKeeper.shared.poke()
                        },
                        onCenterTap: {
                            viewModel.toggleOverlay()
                            ReaderIdleTimerKeeper.shared.poke()
                        },
                        onLinkJump: { originLocator in
                            viewModel.pushBackLocation(originLocator)
                        },
                        onTargetHandled: {
                            viewModel.clearTargetLocator()
                            viewModel.clearTargetLink()
                        },
                        onOpenFailed: { message in
                            viewModel.errorMessage = message
                        }
                    )
                    .readerPageArea()
                } else {
                    EPUBNavigatorRepresentable(
                        publication: publication,
                        initialLocation: viewModel.initialLocator,
                        targetLink: viewModel.targetLink,
                        targetLocator: viewModel.targetLocator,
                        highlights: viewModel.highlights,
                        tableOfContents: viewModel.tableOfContents,
                        preferences: viewModel.epubPreferences,
                        rsProperties: viewModel.readiumCSSRSProperties,
                        hasSelection: viewModel.currentSelection != nil,
                        onLocationChanged: { locator in
                            viewModel.saveLocation(locator)
                            ReaderIdleTimerKeeper.shared.poke()
                        },
                        onSelectionChanged: { selection in
                            saveSelectionAsHighlight(selection)
                            ReaderIdleTimerKeeper.shared.poke()
                        },
                        onHighlightActivated: { highlightID, rect in
                            guard let highlight = viewModel.highlights.first(where: { $0.id == highlightID }) else {
                                return
                            }
                            viewModel.activeHighlight = highlight
                            viewModel.activeHighlightRect = rect
                            ReaderIdleTimerKeeper.shared.poke()
                        },
                        onCenterTap: {
                            viewModel.toggleOverlay()
                            ReaderIdleTimerKeeper.shared.poke()
                        },
                        onLinkJump: { originLocator in
                            viewModel.pushBackLocation(originLocator)
                        },
                        onTargetHandled: {
                            viewModel.clearTargetLocator()
                            viewModel.clearTargetLink()
                        },
                        onOpenFailed: { message in
                            viewModel.errorMessage = message
                        }
                    )
                    .readerPageArea()
                }

                // Floating Return-from-Link Back Button
                if !viewModel.backLocationStack.isEmpty {
                    VStack {
                        HStack {
                            Button {
                                HapticManager.shared.impact(.light)
                                viewModel.goBackInHistory()
                            } label: {
                                HStack(spacing: DipleSpace.s) {
                                    Image(systemName: "arrow.uturn.backward")
                                        .dipleIcon(13, weight: .semibold)
                                    Text("Return to text")
                                        .dipleType(.footnote, weight: .semibold)
                                }
                                .foregroundStyle(DipleColor.textOnAccent)
                                .diplePadding(.button)
                                .background(DipleColor.accent, in: Capsule())
                                .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
                            }
                            Spacer()
                        }
                        .padding(.leading, DipleSpace.xl)
                        .padding(.top, viewModel.isOverlayVisible ? 70 : 50)

                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(DipleMotion.gentle, value: viewModel.backLocationStack.count)
                }

                // Overlay Controls (Top & Bottom bars)
                if viewModel.isOverlayVisible {
                    VStack {
                        // Top Bar Overlay
                        HStack(spacing: DipleSpace.l) {
                            Button {
                                HapticManager.shared.impact(.light)
                                dismiss()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .dipleIcon(16)
                                    .foregroundStyle(chrome.control)
                            }
                            .buttonStyle(.readerControl)

                            Text(viewModel.book.title)
                                .dipleType(.body, weight: .semibold)
                                .foregroundStyle(chrome.control)
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer()

                            // Tighter than the outer bar's spacing on purpose: this trio reads
                            // as one tool cluster, and the extra room is what keeps a fourth
                            // control (search) from crowding the title out at large Dynamic
                            // Type sizes.
                            HStack(spacing: DipleSpace.m) {
                                Button {
                                    HapticManager.shared.selection()
                                    viewModel.isSearchPresented = true
                                } label: {
                                    Image(systemName: "magnifyingglass")
                                        .dipleIcon(16, weight: .regular)
                                        .foregroundStyle(chrome.control)
                                }
                                .buttonStyle(.readerControl)

                                Button {
                                    HapticManager.shared.selection()
                                    viewModel.isAddBookmarkPresented = true
                                } label: {
                                    Image(systemName: viewModel.isCurrentPositionBookmarked ? "bookmark.fill" : "bookmark")
                                        .dipleIcon(16, weight: .regular)
                                        .foregroundStyle(
                                            viewModel.isCurrentPositionBookmarked
                                                ? DipleColor.accent
                                                : chrome.control
                                        )
                                }
                                .buttonStyle(.readerControl)
                                .disabled(!viewModel.canAddBookmark)
                                .opacity(viewModel.canAddBookmark ? 1 : 0.35)
                                .animation(DipleMotion.standard, value: viewModel.isCurrentPositionBookmarked)

                                Button {
                                    HapticManager.shared.selection()
                                    viewModel.isOutlinePresented = true
                                } label: {
                                    Image(systemName: "list.bullet")
                                        .dipleIcon(16, weight: .regular)
                                        .foregroundStyle(chrome.control)
                                }
                                .buttonStyle(.readerControl)
                            }
                        }
                        .padding(.horizontal, DipleSpace.xl)
                        .padding(.vertical, DipleSpace.m)
                        .readerBarBackground(chrome, edge: .top)
                        .transition(.move(edge: .top).combined(with: .opacity))

                        Spacer()

                        // Bottom Bar Overlay
                        VStack(spacing: DipleSpace.m) {
                            ReadingProgressSlider(
                                progress: viewModel.currentProgress,
                                isEnabled: viewModel.canSeek,
                                chrome: chrome,
                                onSeek: { viewModel.seek(toProgress: $0) }
                            )

                            HStack(spacing: DipleSpace.m) {
                                let percentage = Int((viewModel.currentProgress * 100).rounded())
                                Text("\(percentage)%")
                                    .dipleType(.footnote, weight: .semibold)
                                    .foregroundStyle(DipleColor.accent)
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                    .animation(DipleMotion.standard, value: percentage)

                                // Time left sits next to the percentage — the same fact, in the
                                // unit a reader actually plans around — and before the chapter
                                // title, which is the one thing here allowed to truncate.
                                if let remaining = ReadingEstimate.remaining(
                                    characters: viewModel.contentCharacters,
                                    progress: viewModel.currentProgress,
                                    // `book.script`, not the publication's own — the bar and
                                    // the shelf must not disagree about the same book. See
                                    // `Book.script`.
                                    script: viewModel.book.script
                                ) {
                                    Text(remaining)
                                        .dipleType(.footnote, weight: .regular)
                                        .foregroundStyle(chrome.secondary)
                                        .lineLimit(1)
                                        .layoutPriority(1)
                                }

                                if let chapter = viewModel.currentLocator?.title,
                                   !chapter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(chapter)
                                        .dipleType(.footnote, weight: .regular)
                                        .foregroundStyle(chrome.secondary)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }

                                Spacer(minLength: 0)

                                Button {
                                    HapticManager.shared.selection()
                                    viewModel.isSettingsPresented = true
                                } label: {
                                    Image(systemName: "gearshape")
                                        .dipleIcon(16, weight: .regular)
                                        .foregroundStyle(chrome.control)
                                }
                                .buttonStyle(.readerControl)
                            }
                        }
                        .padding(.horizontal, DipleSpace.xl)
                        .padding(.top, DipleSpace.m)
                        .padding(.bottom, DipleSpace.m)
                        .readerBarBackground(chrome, edge: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                if let toast = viewModel.toast {
                    VStack {
                        Spacer()
                        ReaderToastView(message: toast, chrome: chrome)
                            .padding(.bottom, viewModel.isOverlayVisible ? 110 : 44)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

            }
        }
        // The bar hangs in an overlay rather than as another child of the ZStack above. A
        // ZStack takes the width of its widest child, and this bar has a floor: five 40pt
        // swatches and two 44pt buttons. On a narrow phone that floor exceeds the screen, and
        // the stack grew to match — taking the navigator with it, so the web view went wider
        // than the display, slid left and reflowed the page on every selection. An overlay is
        // laid out inside its host and cannot resize it.
        .overlay(alignment: .bottom) {
            restingProgressLine
        }
        .overlay {
            selectionLayer
        }
        .animation(DipleMotion.gentle, value: viewModel.toast)
        .animation(DipleMotion.gentle, value: viewModel.isOverlayVisible)
        .animation(DipleMotion.gentle, value: viewModel.currentSelection?.locator)
        .animation(DipleMotion.gentle, value: viewModel.activeHighlight?.id)
        .task {
            await viewModel.openBook()
        }
        .onAppear {
            if settingsManager.settings.keepScreenAwakeWhileReading {
                ReaderIdleTimerKeeper.shared.begin()
            }
        }
        .onDisappear {
            // Persist synchronously first so the library grid reloads an up-to-date row.
            viewModel.flushPendingProgress()
            onReadingUpdated()
            ReaderIdleTimerKeeper.shared.end()
        }
        .onChange(of: scenePhase) { _, newPhase in
            // A stale `isIdleTimerDisabled == true` would otherwise outlive the reader the
            // moment the app leaves the foreground with the screen still lit.
            if newPhase == .active {
                if settingsManager.settings.keepScreenAwakeWhileReading {
                    ReaderIdleTimerKeeper.shared.begin()
                }
            } else {
                ReaderIdleTimerKeeper.shared.end()
                // Leaving the foreground ends the sitting: banking it here is what keeps a
                // session that is never returned to — the app killed in the background — from
                // being lost, and it stops the clock before the time in someone's pocket can
                // be mistaken for slow reading.
                viewModel.flushReadingSpeed()
            }
        }
        .onChange(of: settingsManager.settings.keepScreenAwakeWhileReading) { _, isEnabled in
            if isEnabled {
                ReaderIdleTimerKeeper.shared.begin()
            } else {
                ReaderIdleTimerKeeper.shared.end()
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $viewModel.isSettingsPresented) {
            ReaderSettingsView(settings: $viewModel.settings)
        }
        .sheet(isPresented: $viewModel.isAddBookmarkPresented) {
            let chapterTitle = viewModel.currentLocator?.title ?? "Page \(Int(viewModel.currentProgress * 100))%"
            AddBookmarkSheetView(defaultName: chapterTitle) { name, colorHex in
                viewModel.addBookmark(name: name, colorHex: colorHex)
            }
        }
        .sheet(isPresented: $viewModel.isOutlinePresented) {
            BookOutlineSheetView(
                tableOfContents: viewModel.tableOfContents,
                highlights: viewModel.highlights,
                bookmarks: viewModel.bookmarks,
                onSelectLink: { link in
                    viewModel.navigateToLink(link)
                },
                onSelectHighlight: { highlight in
                    if let locator = highlight.parsedLocator {
                        viewModel.navigateToLocator(locator)
                    }
                },
                onDeleteHighlight: { highlight in
                    viewModel.deleteHighlight(highlight)
                },
                onSelectBookmark: { bookmark in
                    if let locator = bookmark.parsedLocator {
                        viewModel.navigateToLocator(locator)
                    }
                },
                onDeleteBookmark: { bookmark in
                    viewModel.deleteBookmark(bookmark)
                }
            )
        }
        .sheet(isPresented: $viewModel.isSearchPresented) {
            BookSearchSheetView(book: viewModel.book) { hit in
                if let locator = hit.parsedLocator {
                    viewModel.navigateToSearchResult(locator)
                }
            }
        }
        .sheet(item: $highlightEditorTarget, onDismiss: {
            dismissHighlightActions()
        }) { target in
            switch target {
            case .new(_, let quote):
                HighlightEditorView(quote: quote, isExisting: false) { colorHex, comment in
                    viewModel.createHighlight(colorHex: colorHex, comment: comment)
                }
            case .existing(let highlight):
                HighlightEditorView(
                    quote: highlight.text,
                    initialColorHex: highlight.colorHex,
                    initialComment: highlight.comment,
                    isExisting: true,
                    onSave: { colorHex, comment in
                        viewModel.updateHighlight(highlight, colorHex: colorHex, comment: comment)
                    },
                    onDelete: {
                        viewModel.deleteHighlight(highlight)
                    }
                )
            }
        }
    }

    /// Where you are, while the bars are away.
    ///
    /// Tapping the centre hides both bars, which is the right state for reading and also the
    /// state in which the only indication of position disappears. A line on the very bottom edge
    /// keeps the answer available without putting a control back on the page: it is the same
    /// number the bottom bar prints, drawn rather than written.
    ///
    /// **The bottom edge means the edge of the display, not of the safe area.** Placed at the
    /// bottom of the safe rect it floated a home indicator's height above the bezel with page
    /// text still running underneath it — a mark hanging in the middle of the last paragraph
    /// rather than a rule under the page. `ignoresSafeArea` alone does not move a fixed-height
    /// view, so the line rides the bottom of a full-height stack that ignores the inset: the
    /// stack grows into the indicator band and the `Spacer` hands the line the last 3 points of
    /// it. The horizontal inset goes with it so the rule still spans the display in landscape.
    /// The page itself stops above that band (see the navigator), so the two never overlap.
    ///
    /// It hangs in an `.overlay` rather than as another `ZStack` child for the reason recorded
    /// at length above — a sibling can widen the stack and take the navigator with it — and it
    /// takes no touches at all, so a tap here still turns the page. It stands down for a live
    /// selection, whose bar pins to this same edge.
    @ViewBuilder
    private var restingProgressLine: some View {
        if viewModel.publication != nil,
           !viewModel.isOverlayVisible,
           highlightActionsSubject == nil {
            VStack(spacing: 0) {
                Spacer(minLength: 0)

                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(chrome.track)
                        Rectangle()
                            .fill(DipleColor.accent)
                            .frame(width: geo.size.width * min(max(viewModel.currentProgress, 0), 1))
                    }
                }
                .frame(height: DipleStroke.progressLine)
            }
            .ignoresSafeArea(edges: [.horizontal, .bottom])
            .allowsHitTesting(false)
            .transition(.opacity)
            .accessibilityHidden(true)
        }
    }

    /// The quote a live selection stands for, or nil when there is nothing worth acting on.
    private var selectedQuote: String? {
        guard let quote = viewModel.currentSelection?.locator.text.highlight?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !quote.isEmpty
        else { return nil }
        return quote
    }

    /// What the actions bar is currently about, if anything.
    ///
    /// Two shapes reach the same bar. On EPUB it is a highlight the reader tapped, already
    /// saved and already on the page. On PDF there are no decorations to tap, so it is still a
    /// live selection and nothing has been written yet — see `HighlightActionsBar.onDelete`.
    private enum HighlightActionsSubject {
        case saved(Highlight, rect: CGRect?)
        case selection(String)

        var quote: String {
            switch self {
            case let .saved(highlight, _): return highlight.text
            case let .selection(quote): return quote
            }
        }

        var highlight: Highlight? {
            switch self {
            case let .saved(highlight, _): return highlight
            case .selection: return nil
            }
        }

        var rect: CGRect? {
            switch self {
            case let .saved(_, rect): return rect
            case .selection: return nil
            }
        }
    }

    private var highlightActionsSubject: HighlightActionsSubject? {
        if let highlight = viewModel.activeHighlight {
            return .saved(highlight, rect: viewModel.activeHighlightRect)
        }
        if let quote = selectedQuote {
            return .selection(quote)
        }
        return nil
    }

    @ViewBuilder
    private var selectionLayer: some View {
        if let subject = highlightActionsSubject, highlightEditorTarget == nil {
            // This geometry keeps the safe area: `geo.size` is the safe rect, so aligning the
            // bar to its top edge puts it below the Dynamic Island by construction, with no
            // inset arithmetic and nothing tuned to one device. It matters more than tidiness:
            // the island's band takes no touches at all, so a bar drawn under it left every
            // selection in the lower half of a page with controls that could not be hit.
            // The page now measures the same rect, which is what lets `selectionIsInLowerHalf`
            // compare Readium's frame against it directly.
            GeometryReader { geo in
                ZStack {
                    // Dismissing has to consume the tap. Left to fall through it would also
                    // turn the page or toggle the reader's bars, so closing the bar would never
                    // be the only thing that happened. This one layer does span the display.
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { dismissHighlightActions() }
                        .ignoresSafeArea()

                    HighlightActionsBar(
                        chrome: chrome,
                        currentColorHex: subject.highlight?.colorHex,
                        onPickColor: { hex in pickColor(hex, for: subject) },
                        onAddNote: { addNote(to: subject) },
                        onCopy: { UIPasteboard.general.string = subject.quote },
                        onDelete: subject.highlight.map { highlight in
                            {
                                viewModel.deleteHighlight(highlight)
                                viewModel.dismissHighlightActions()
                            }
                        }
                    )
                    .fixedSize()
                    .padding(.vertical, DipleSpace.xl)
                    .frame(
                        width: geo.size.width,
                        height: geo.size.height,
                        alignment: isInLowerHalf(subject.rect, in: geo) ? .top : .bottom
                    )
                }
            }
            .transition(.opacity)
        }
    }

    private func presentEditor(for selection: Selection?) {
        viewModel.currentSelection = selection
    }

    /// The EPUB path: a settled selection *is* the decision, so it is saved on the spot in
    /// whichever colour was used last and the selection gets out of the way.
    ///
    /// Readium reports this through `shouldShowMenuForSelection`, which UIKit calls when it is
    /// about to raise the edit menu — that is, once the gesture has finished, not continuously
    /// while a finger drags. So this fires per completed selection, not per pixel. Clearing the
    /// selection right after takes the handles with it, which means a span cannot be adjusted
    /// afterwards; a wrong one is removed from the bar and made again, which is the trade the
    /// reference app makes too.
    private func saveSelectionAsHighlight(_ selection: Selection?) {
        viewModel.currentSelection = selection
        guard selection != nil, selectedQuote != nil else { return }
        viewModel.createHighlight(colorHex: lastHighlightColorHex, announce: false)
    }

    private func dismissHighlightActions() {
        viewModel.dismissHighlightActions()
        viewModel.currentSelection = nil
    }

    /// Recolours a saved highlight, or — on PDF, where nothing has been written yet — saves the
    /// selection in the colour just chosen. Either way the choice becomes the new default, so
    /// the next passage is marked in the colour this reader actually uses.
    private func pickColor(_ hex: String, for subject: HighlightActionsSubject) {
        lastHighlightColorHex = hex
        switch subject {
        case let .saved(highlight, _):
            viewModel.setHighlightColor(highlight, to: hex)
            viewModel.dismissHighlightActions()
        case .selection:
            viewModel.createHighlight(colorHex: hex)
        }
    }

    private func addNote(to subject: HighlightActionsSubject) {
        switch subject {
        case let .saved(highlight, _):
            viewModel.dismissHighlightActions()
            highlightEditorTarget = .existing(highlight)
        case let .selection(quote):
            highlightEditorTarget = .new(UUID(), quote)
        }
    }

    /// Whether the selection sits in the lower half of the page, which sends the bar to the
    /// top edge — and the other way around.
    ///
    /// The bar goes to the far edge of the page rather than hugging the selection. Readium
    /// reports the bounding rect of the selected characters, and a selection that starts
    /// mid-line shares that line's top edge with words that are not selected, so a bar placed
    /// one gap above the rect still lands on top of readable text. Clearing it would take a
    /// guess at line height, which is a hardcoded padding tuned to one font size. Pinning to
    /// the opposite edge cannot overlap the passage at any size, and it holds still while the
    /// selection handles are dragged instead of hopping from one side to the other.
    /// Readium reports `Selection.frame` "in the coordinate of the navigator view"
    /// (`SelectableNavigator.swift`), and the navigator view is now exactly the safe rect —
    /// `geo` measures the same thing — so the two are already in the same space. This used to
    /// add the insets back, which was right while the navigator spanned the whole display;
    /// doing it now would push the dividing line a status bar's height below the middle of the
    /// page and send half the selections to the wrong edge.
    ///
    /// The rect is the tapped highlight's own bounding box on EPUB and the live selection's on
    /// PDF; with neither — a highlight Readium could not place — the bar takes the bottom edge,
    /// which is where it sat before any of this was measured.
    private func isInLowerHalf(_ rect: CGRect?, in geo: GeometryProxy) -> Bool {
        guard let rect = rect ?? viewModel.currentSelection?.frame else { return false }
        return rect.midY > geo.size.height / 2
    }
}

/// The slice of screen the book is drawn on: everything but the status bar and the home
/// indicator, and the full width regardless.
///
/// The navigator used to take the whole display. In paginated mode Readium insets its own
/// content by the window's safe area and nothing overlapped, but in scroll mode the same inset
/// is `scrollView.contentInset` (`EPUBReflowableSpreadView.swift`), which text scrolls *under*
/// rather than stopping at — so the clock and the battery sat on the middle of a paragraph, and
/// the resting progress line had text running below it. An inset cannot fix that; only a
/// smaller view can, because clipping is what a bounds does and a scroll inset does not.
///
/// Horizontally it still spans the display: the reader's side margins are Readium's
/// `pageMargins`, a typographic measure the reader sets, and letting a landscape notch push
/// them around would put the column somewhere else on each rotation.
private extension View {
    func readerPageArea() -> some View {
        ignoresSafeArea(edges: .horizontal)
    }
}

private enum HighlightEditorTarget: Identifiable {
    case new(UUID, String)
    case existing(Highlight)

    var id: String {
        switch self {
        case .new(let id, _): return "new:\(id.uuidString)"
        case .existing(let highlight): return "existing:\(highlight.id)"
        }
    }
}
