import SwiftUI
import ReadiumShared
import ReadiumNavigator
// The system translator, and the one platform fork in this file.
//
// Not a version fork: the app already deploys to iOS 18, well past the 17.4 that
// `translationPresentation` needs, so there is no `#available` anywhere and no third-party
// fallback. This is a *platform* fork, and it is not optional — `Translation.framework` has
// no Mac Catalyst slice in the SDK at all (`MacOSX.sdk/System/iOSSupport` does not contain
// it), and the SwiftUI overlay that carries the modifier is marked
// `@available(macCatalyst, unavailable)` outright. On Catalyst the import will not resolve,
// so the reader is built without the button rather than with a dead one.
#if !targetEnvironment(macCatalyst)
import Translation
#endif

public struct ReaderContainerView: View {
    @StateObject private var viewModel: ReaderViewModel
    @StateObject private var settingsManager = AppSettingsManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @State private var highlightEditorTarget: HighlightEditorTarget?
    /// The passage handed to the system translator, copied out of the selection **before**
    /// anything can clear it.
    ///
    /// `translationPresentation` takes a plain `String`, not a binding, and it reads it while
    /// the sheet is coming up — by which time the selection that the words came from may be
    /// gone. Holding the text here rather than reaching back through `currentSelection` is
    /// what makes the sheet survive the selection it was raised from.
    @State private var translationText = ""
    @State private var isTranslationPresented = false
    /// The colour the next selection will be marked in — whichever one was chosen last.
    ///
    /// A working habit, not navigation state, so it lives in `@AppStorage` beside the library
    /// and notes layout choices rather than in `ReaderSettings`. Two reasons it does not belong
    /// there: `ReaderSettings` is `Equatable` and every change to it re-submits preferences to
    /// Readium, which recolouring a highlight has no business doing; and it travels through the
    /// CloudKit settings payload, where a per-device marker preference is not worth a field.
    @AppStorage("diple_last_highlight_color") private var lastHighlightColorHex = DipleColor.Highlight.yellow
    /// The note currently open over the page, if any.
    ///
    /// A sheet rather than a push: the reader hides the navigation bar and owns the whole
    /// screen, and a note is something you step aside to write and then come back from — the
    /// page has to still be there underneath, at the same place, when it closes.
    @State private var noteRoute: NoteRoute?
    /// A note chosen inside the outline sheet, held until that sheet is actually gone.
    ///
    /// Raising the second sheet from the row's own action presents it into a hierarchy that is
    /// still dismissing the first, and it is dropped. `onDismiss` is the moment the screen is
    /// free again.
    @State private var pendingNoteRoute: NoteRoute?
    /// Where a wiki link followed from inside the open note pushes to.
    @State private var notePath = NavigationPath()
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

    /// What the bottom bar prints after the figures: the chapter, or the book when the
    /// publication names no chapter. One line, always populated, and never the same string
    /// twice on one screen — see the note where the top bar's title used to be.
    private var placeLine: String {
        let chapter = viewModel.currentLocator?.title?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return chapter.isEmpty ? viewModel.book.title : chapter
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
                    Text("Loading book…")
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
                    .dipleType(.body, weight: .medium)
                    .foregroundStyle(DipleColor.textPrimary)
                    .diplePadding(.buttonLarge)
                    .craftSurface(DipleColor.surfaceOverlay, radius: DipleRadius.s)
                    .buttonStyle(.readerControl)
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
                            beginPendingSelection(selection)
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
                            viewModel.finishTargetNavigation()
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
                        freshHighlightID: viewModel.freshHighlightID,
                        livingMarginAnnotations: livingMarginAnnotationsForCurrentPlatform,
                        tableOfContents: viewModel.tableOfContents,
                        preferences: viewModel.epubPreferences,
                        rsProperties: viewModel.readiumCSSRSProperties,
                        hasSelection: viewModel.currentSelection != nil,
                        onLocationChanged: { locator in
                            viewModel.saveLocation(locator)
                            ReaderIdleTimerKeeper.shared.poke()
                        },
                        onSelectionChanged: { selection in
                            beginPendingSelection(selection)
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
                        onLivingMarginActivated: { highlightID in
                            viewModel.toggleLivingMargin(id: highlightID)
                            ReaderIdleTimerKeeper.shared.poke()
                        },
                        onLivingMarginsEdgeSwipe: {
                            viewModel.openNearestLivingMargin()
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
                            viewModel.finishTargetNavigation()
                        },
                        onOpenFailed: { message in
                            viewModel.errorMessage = message
                        }
                    )
                    .readerPageArea()
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
                            .accessibilityLabel("Close book")

                            // No title here. It was printed twice on one screen — at the top
                            // of this bar and again, truncated, at the end of the bottom one —
                            // and this is the copy that says least: the reader opened the book
                            // a moment ago and knows which one it is. What they can lose track
                            // of is where they are inside it, and that is what the bottom bar
                            // reports. Dropping it also gives the four tools their room back.
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
                                .accessibilityLabel("Search in book")

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
                                .accessibilityLabel(
                                    viewModel.isCurrentPositionBookmarked
                                        ? "This page is bookmarked"
                                        : "Bookmark this page"
                                )
                                .disabled(!viewModel.canAddBookmark)
                                .opacity(viewModel.canAddBookmark ? 1 : 0.35)
                                .animation(DipleMotion.standard, value: viewModel.isCurrentPositionBookmarked)

                                // A thought about the book, written in the book.
                                //
                                // It belongs in this cluster and not with the settings at the
                                // bottom: search, bookmark and contents are all about the text
                                // and what has been made from it, which is what a note is. It
                                // always writes rather than showing a list first — having a
                                // thought and wanting to keep it is one intention, and the
                                // notes already written are one segment away in the sheet
                                // beside it.
                                Button {
                                    HapticManager.shared.selection()
                                    noteRoute = .newFromSource(viewModel.book)
                                } label: {
                                    Image(systemName: "square.and.pencil")
                                        .dipleIcon(16, weight: .regular)
                                        .foregroundStyle(chrome.control)
                                }
                                .buttonStyle(.readerControl)
                                .accessibilityLabel("Write a note in this book")
                                .accessibilityIdentifier("reader.newNote")

                                Button {
                                    HapticManager.shared.selection()
                                    viewModel.isOutlinePresented = true
                                } label: {
                                    Image(systemName: "list.bullet")
                                        .dipleIcon(16, weight: .regular)
                                        .foregroundStyle(chrome.control)
                                }
                                .buttonStyle(.readerControl)
                                .accessibilityLabel("Contents, highlights, notes and bookmarks")
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
                                    // Chrome ink, not accent. A number is a fact, not an
                                    // action, and the accent in this bar is already spent on
                                    // the line that fills to exactly this value.
                                    .foregroundStyle(chrome.control)
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

                                // Where in the book, in one place: the chapter when the
                                // publication names one, the book itself when it does not — so
                                // the line is always there and never doubles the top bar.
                                Text(placeLine)
                                    .dipleType(.footnote, weight: .regular)
                                    .foregroundStyle(chrome.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.tail)

                                Spacer(minLength: 0)

                                // The way back, in chrome rather than over the text.
                                //
                                // The floating pill is the quick undo; this is the guarantee.
                                // Tapping the centre of any page raises this bar, so a reader
                                // who never noticed the pill — or who has read past the moment
                                // it spoke — still has a route back that costs the page
                                // nothing, and it can be explicit about both directions.
                                //
                                // Dimmed rather than withdrawn when a direction has nothing in
                                // it, following the bookmark control above: a pair that keeps
                                // its shape is easier to aim at than one that reflows the row
                                // every time the trail changes depth.
                                if viewModel.trail.canGoBack || viewModel.trail.canGoForward {
                                    Button {
                                        HapticManager.shared.selection()
                                        viewModel.goBackInHistory()
                                    } label: {
                                        Image(systemName: "arrow.uturn.backward")
                                            .dipleIcon(16, weight: .regular)
                                            .foregroundStyle(chrome.control)
                                    }
                                    .buttonStyle(.readerControl)
                                    .accessibilityLabel("Go back to where you were reading")
                                    .disabled(!viewModel.trail.canGoBack)
                                    .opacity(viewModel.trail.canGoBack ? 1 : 0.35)

                                    Button {
                                        HapticManager.shared.selection()
                                        viewModel.goForwardInHistory()
                                    } label: {
                                        Image(systemName: "arrow.uturn.forward")
                                            .dipleIcon(16, weight: .regular)
                                            .foregroundStyle(chrome.control)
                                    }
                                    .buttonStyle(.readerControl)
                                    .accessibilityLabel("Go forward to where you jumped from")
                                    .disabled(!viewModel.trail.canGoForward)
                                    .opacity(viewModel.trail.canGoForward ? 1 : 0.35)
                                }

                                Button {
                                    HapticManager.shared.selection()
                                    viewModel.isSettingsPresented = true
                                } label: {
                                    Image(systemName: "gearshape")
                                        .dipleIcon(16, weight: .regular)
                                        .foregroundStyle(chrome.control)
                                }
                                .buttonStyle(.readerControl)
                                .accessibilityLabel("Reading settings")
                            }
                        }
                        .padding(.horizontal, DipleSpace.xl)
                        .padding(.top, DipleSpace.m)
                        .padding(.bottom, DipleSpace.m)
                        .readerBarBackground(chrome, edge: .bottom)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }

                // The bottom of the page, as one stack.
                //
                // The toast and the way back are both anchored to this edge, and two
                // independent bottom paddings are a promise that they will not meet — one that
                // an accessibility type size, or a longer message, breaks silently. Stacking
                // them makes the separation a fact of the layout instead. The cost is that the
                // toast now rides on top of the pill when there is one, a few points higher
                // than it used to sit; a message that moves is better than two that overlap.
                VStack(spacing: DipleSpace.s) {
                    Spacer(minLength: 0)

                    if let toast = viewModel.toast {
                        ReaderToastView(message: toast, chrome: chrome)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }

                    if let offer = trailOffer {
                        ReadingTrailPill(
                            direction: offer.direction,
                            destination: offer.destination,
                            chrome: chrome,
                            action: {
                                switch offer.direction {
                                case .back: viewModel.goBackInHistory()
                                case .forward: viewModel.goForwardInHistory()
                                }
                            }
                        )
                        // Trailing, and the pill decides its own width: a chapter name is as
                        // long as the publisher made it, and a control that spanned the page
                        // would be the slab this design exists to avoid.
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .transition(.opacity)
                    }
                }
                .readerBottomBand(isOverlayVisible: viewModel.isOverlayVisible)

            }

            if let colophon = viewModel.finishedColophon {
                FinishedColophonView(
                    colophon: colophon,
                    chrome: chrome,
                    onFinish: viewModel.finishReading,
                    onOpenSecondRead: viewModel.finishAndOpenSecondRead,
                    onKeepReading: viewModel.keepReading
                )
                .transition(.opacity)
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
        .overlay {
            livingMarginLayer
        }
        .animation(DipleMotion.gentle, value: viewModel.toast)
        .animation(DipleMotion.gentle, value: viewModel.isOverlayVisible)
        // Here rather than on the offer itself. `.animation(value:)` attached to a view that
        // only exists while the value is true cannot drive its own insertion — the transition
        // has nothing animating it back to identity. Every other conditional child in this
        // view (the colophon, the bars) is animated from this stack; the offer was the one
        // that was not, and only got its slide because a neighbouring value happened to change
        // at the same moment.
        .animation(DipleMotion.gentle, value: viewModel.isTrailLabelVisible)
        .animation(DipleMotion.gentle, value: viewModel.trail)
        .animation(DipleMotion.gentle, value: viewModel.currentSelection?.locator)
        .animation(DipleMotion.gentle, value: viewModel.activeHighlight?.id)
        .animation(DipleMotion.gentle, value: viewModel.finishedColophon != nil)
        .animation(livingMarginAnimation, value: viewModel.activeLivingMarginID != nil)
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
        // CloudKit continues to sync the existing Highlight row. An open page only needs to
        // rebuild its projection when that row changes; there is no Living Margins sync model.
        .onReceive(NotificationCenter.default.publisher(for: .dipleRemoteDataDidChange)) { _ in
            viewModel.loadHighlights()
            viewModel.loadNotes()
        }
        .onReceive(NotificationCenter.default.publisher(for: .dipleDataDidRestore)) { _ in
            viewModel.loadHighlights()
            viewModel.loadNotes()
        }
        .macReaderKeyboard(
            onClose: { dismiss() },
            onFind: { viewModel.isSearchPresented = true }
        )
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        // The app draws its own tab bar now, and a bar the app draws has to be told.
        .hidesDipleTabBar()
        .navigationBarBackButtonHidden(true)
        .navigationDestination(isPresented: $viewModel.isSecondReadPresented) {
            SecondReadView(book: viewModel.book, onReadingUpdated: onReadingUpdated)
                .toolbar(.visible, for: .navigationBar)
        }
        .sheet(isPresented: $viewModel.isSettingsPresented) {
            ReaderSettingsView(settings: $viewModel.settings)
        }
        .sheet(isPresented: $viewModel.isAddBookmarkPresented) {
            let chapterTitle = viewModel.currentLocator?.title ?? "Page \(Int(viewModel.currentProgress * 100))%"
            AddBookmarkSheetView(defaultName: chapterTitle) { name, colorHex in
                viewModel.addBookmark(name: name, colorHex: colorHex)
            }
        }
        .sheet(isPresented: $viewModel.isOutlinePresented, onDismiss: {
            if let pending = pendingNoteRoute {
                pendingNoteRoute = nil
                noteRoute = pending
            }
        }) {
            BookOutlineSheetView(
                tableOfContents: viewModel.tableOfContents,
                positions: viewModel.positions,
                progress: viewModel.currentProgress,
                highlights: viewModel.highlights,
                notes: viewModel.notes.forThisBook,
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
                onSelectNote: { item in
                    pendingNoteRoute = .existing(item)
                },
                onDeleteNote: { item in
                    viewModel.deleteNote(item)
                },
                onNewNote: {
                    pendingNoteRoute = .newFromSource(viewModel.book)
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
                    viewModel.navigateToLocator(locator)
                }
            }
        }
        // On the reader, deliberately, and never on the bar.
        //
        // The bar exists only while there is something selected or tapped, and every route
        // into translation ends by clearing one of those — so a presentation attached to it
        // would be torn out of the hierarchy in the same update that raised it, and the sheet
        // would come up and collapse again. This container outlives all of that.
        .translationTarget(isPresented: $isTranslationPresented, text: translationText)
        // The one note editor in the app, raised over the page.
        //
        // `NoteDetailView` itself rather than a reader-sized version of it: two note editors
        // drift, and a rule fixed in one stays broken in the other. Everything it needs —
        // the whole library's notes for wiki links, every source for the picker, every tag
        // for suggestions — comes from `viewModel.notes`, so the note written here is the
        // same note, written the same way, as one started on the board.
        .sheet(item: $noteRoute, onDismiss: {
            notePath = NavigationPath()
            viewModel.announceSavedNote()
        }) { route in
            NavigationStack(path: $notePath) {
                notePage(for: route)
                    .navigationDestination(for: NoteRoute.self) { pushed in
                        notePage(for: pushed)
                    }
            }
        }
        .sheet(item: $highlightEditorTarget, onDismiss: {
            dismissHighlightActions()
        }) { target in
            switch target {
            case .existing(let highlight):
                HighlightEditorView(
                    quote: highlight.text,
                    initialColorHex: highlight.colorHex,
                    initialComment: highlight.comment,
                    initialTags: viewModel.highlightTags[highlight.id] ?? [],
                    tagSuggestions: viewModel.highlightTagSuggestions,
                    isExisting: true,
                    onSave: { colorHex, comment, tags in
                        viewModel.updateHighlight(highlight, colorHex: colorHex, comment: comment, tags: tags)
                    },
                    onDelete: {
                        viewModel.deleteHighlight(highlight)
                    }
                )
            }
        }
    }

    /// A note page wired to this book, wherever it is reached from — raised from the page,
    /// opened out of the outline sheet, or followed through a `[[Wiki link]]` from either.
    @ViewBuilder
    private func notePage(for route: NoteRoute) -> some View {
        NoteDetailView(
            route: route,
            books: viewModel.notes.books,
            suggestedTags: viewModel.notes.tagSuggestions,
            allNotes: viewModel.notes.all,
            onSave: { note, tags in viewModel.saveNote(note, tags: tags) },
            onDelete: { item in viewModel.deleteNote(item) },
            onOpenNote: { notePath.append(NoteRoute.existing($0)) }
        )
    }

    private var livingMarginAnimation: Animation {
        reduceMotion
            ? .easeOut(duration: 0.14)
            : .spring(response: 0.38, dampingFraction: 0.92)
    }

    private var livingMarginTransition: AnyTransition {
        reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity)
    }

    /// Living Margins launches on the native iOS reader first. Keeping the gate at the reader
    /// boundary prevents markers from being submitted on Catalyst while preserving one semantic
    /// projection and no platform-specific persistence.
    private var livingMarginAnnotationsForCurrentPlatform: [LivingMarginAnnotation] {
        #if targetEnvironment(macCatalyst)
        []
        #else
        viewModel.livingMarginAnnotations
        #endif
    }

    /// An overlay constrained by the reader's existing bounds, so revealing a margin never
    /// changes the navigator's width or asks the book to reflow. The clear remainder consumes a
    /// tap solely to close; the page stays visually undimmed underneath it.
    @ViewBuilder
    private var livingMarginLayer: some View {
        #if !targetEnvironment(macCatalyst)
        if viewModel.finishedColophon == nil,
           let annotation = viewModel.activeLivingMargin {
            GeometryReader { geometry in
                let ratio: CGFloat = dynamicTypeSize.isAccessibilitySize ? 0.82 : 0.66
                let proposed = max(236, geometry.size.width * ratio)
                let panelWidth = max(0, min(430, min(proposed, geometry.size.width - 52)))

                HStack(spacing: 0) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture { viewModel.closeLivingMargin() }
                        .accessibilityHidden(true)

                    LivingMarginPanel(
                        annotation: annotation,
                        chrome: chrome,
                        reduceMotion: reduceMotion,
                        onClose: { viewModel.closeLivingMargin() },
                        onNext: {
                            HapticManager.shared.selection()
                            viewModel.advanceLivingMargin()
                        },
                        onPrevious: {
                            HapticManager.shared.selection()
                            viewModel.retreatLivingMargin()
                        },
                        onEdit: {
                            guard let highlight = viewModel.highlightForActiveLivingMargin() else {
                                viewModel.closeLivingMargin()
                                return
                            }
                            highlightEditorTarget = .existing(highlight)
                        }
                    )
                    .frame(width: panelWidth)
                }
            }
            .transition(livingMarginTransition)
            .zIndex(10)
        }
        #endif
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
           viewModel.finishedColophon == nil,
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

    /// What the floating way back is currently offering, if anything.
    ///
    /// Back wins wherever it exists: a reader with somewhere behind them is the one who might
    /// be lost, and that is the case this control is for. Forward appears only once the trail
    /// behind has been walked out, where it is the single tap that undoes an overshoot — one
    /// reflex tap past the note being read is the commonest mistake in the reader, and before
    /// there was a forward step it cost a hunt through the text for the marker.
    ///
    /// It stands down for anything that owns the page more than it does: a live selection,
    /// whose bar takes the same edge, an open margin, whose panel covers this corner, and the
    /// final page. It stands down for the raised bars too — those carry the same pair of
    /// controls in chrome, and one way back at a time is enough.
    private var trailOffer: (direction: ReadingTrailPill.Direction, destination: String?)? {
        guard viewModel.publication != nil,
              viewModel.finishedColophon == nil,
              !viewModel.isOverlayVisible,
              highlightActionsSubject == nil,
              viewModel.activeLivingMargin == nil
        else { return nil }

        if viewModel.trail.canGoBack {
            return (.back, viewModel.isTrailLabelVisible ? viewModel.backDestinationLabel : nil)
        }
        if viewModel.trail.canGoForward {
            return (.forward, viewModel.isTrailLabelVisible ? viewModel.forwardDestinationLabel : nil)
        }
        return nil
    }

    /// What the actions bar is currently about, if anything.
    ///
    /// Three shapes reach the same bar and only two matter to it. A selection that has been
    /// made but not decided on is `pending`; a highlight is `committed` whether it was saved a
    /// moment ago or tapped a week later, and whether it is on an EPUB — where the decoration
    /// is what got tapped — or on a PDF, where there is no decoration to tap and the bar has
    /// simply stayed open on the row it just wrote.
    private enum HighlightActionsSubject {
        /// A live selection. **Nothing has been written for it**: no row, no decoration, no
        /// entry in the sync outbox. It disappears without trace if the reader taps away.
        case pending(quote: String, rect: CGRect?)
        /// A highlight that exists, and the box it occupies on the page if that is known.
        case committed(Highlight, rect: CGRect?)

        var quote: String {
            switch self {
            case let .pending(quote, _): return quote
            case let .committed(highlight, _): return highlight.text
            }
        }

        var highlight: Highlight? {
            switch self {
            case .pending: return nil
            case let .committed(highlight, _): return highlight
            }
        }

        var rect: CGRect? {
            switch self {
            case let .pending(_, rect): return rect
            case let .committed(_, rect): return rect
            }
        }

        var barMode: HighlightActionsBar.Mode {
            switch self {
            case .pending: return .pending
            case let .committed(highlight, _): return .committed(colorHex: highlight.colorHex)
            }
        }
    }

    /// A saved highlight wins over a live selection: committing one clears the other inside a
    /// single update, and for the frame in between the bar must already be reading as saved.
    private var highlightActionsSubject: HighlightActionsSubject? {
        if let highlight = viewModel.activeHighlight {
            return .committed(highlight, rect: viewModel.activeHighlightRect)
        }
        if let selection = viewModel.currentSelection {
            return .pending(quote: selection.quote, rect: selection.frame)
        }
        return nil
    }

    @ViewBuilder
    private var selectionLayer: some View {
        if viewModel.finishedColophon == nil,
           let subject = highlightActionsSubject,
           highlightEditorTarget == nil {
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
                        mode: subject.barMode,
                        canTranslate: !subject.quote.isEmpty,
                        onPickColor: { hex in pickColor(hex, for: subject) },
                        onTranslate: translateAction(for: subject),
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

    /// A settled selection raises the bar and **writes nothing**.
    ///
    /// This is the whole of the pending state. `SelectionSettle` has already collapsed the
    /// stream of callbacks one drag produces into a single report — `shouldShowMenuForSelection`
    /// is a stream, not a "gesture finished", and reading it as the latter is what once wrote
    /// eight overlapping quotes per paragraph — but a drag that *stops* and carries on still
    /// arrives here twice, and now that costs nothing: the second report replaces the first
    /// snapshot. Nothing has to be de-duplicated afterwards because nothing was saved in
    /// between.
    ///
    /// `@MainActor` and a written-out body rather than `flatMap(PendingSelection.init)`:
    /// `Selection` is main-actor-isolated, so passing that initialiser as a function value to
    /// a nonisolated `flatMap` was the one concurrency warning left in the app. Every caller is
    /// a navigator callback already on the main actor, so the annotation states what was true.
    @MainActor
    private func beginPendingSelection(_ selection: Selection?) {
        guard let selection else {
            viewModel.currentSelection = nil
            return
        }
        viewModel.currentSelection = PendingSelection(selection)
    }

    private func dismissHighlightActions() {
        viewModel.dismissHighlightActions()
        viewModel.currentSelection = nil
    }

    /// The tap that either saves the passage or recolours it. Either way the choice becomes the
    /// new default, so the next passage is marked in the colour this reader actually uses.
    private func pickColor(_ hex: String, for subject: HighlightActionsSubject) {
        lastHighlightColorHex = hex
        switch subject {
        case let .committed(highlight, _):
            // A second colour on a highlight that already exists changes the one row. It never
            // adds another — the reader is looking at a mark they made, not at a new passage.
            viewModel.setHighlightColor(highlight, to: hex)
            viewModel.dismissHighlightActions()

        case let .pending(_, rect):
            // Saving, and staying: the note that was dimmed a second ago is the commonest next
            // tap, and closing the bar to reopen it would cost the reader the passage. The bar
            // is not dismissed and not re-presented, so its `appeared` state survives and the
            // entrance spring does not play a second time.
            //
            // The rect has to be carried across by hand. `createHighlight` clears the
            // selection — that is what takes the blue span and its handles off the page and
            // lets the decoration show through — so by the next render there is no selection
            // left to ask for a frame, and a bar that fell back to the default would jump to
            // the bottom edge from under the finger that was still on it.
            guard let created = viewModel.createHighlight(colorHex: hex, announce: false) else { return }
            viewModel.activeHighlight = created
            viewModel.activeHighlightRect = rect
        }
    }

    /// Only ever reachable from `committed` — a thought needs something to hang on, so the bar
    /// dims this button in `pending` and takes its hit-testing away with it.
    private func addNote(to subject: HighlightActionsSubject) {
        guard case let .committed(highlight, _) = subject else { return }
        viewModel.dismissHighlightActions()
        highlightEditorTarget = .existing(highlight)
    }

    /// Hands the passage to the system translator, in either state.
    ///
    /// The text is copied into `@State` here, at the moment of the tap, while the selection is
    /// provably still up. `nil` on Mac Catalyst, where the framework does not exist and the
    /// glyph is therefore not drawn at all.
    private func translateAction(for subject: HighlightActionsSubject) -> (() -> Void)? {
#if targetEnvironment(macCatalyst)
        return nil
#else
        // Non-nil even for an empty passage: `canTranslate` greys the glyph out instead of
        // taking it out of the row, so the four controls beside it do not shuffle.
        let quote = subject.quote
        return {
            translationText = quote
            isTranslationPresented = true
        }
#endif
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
    /// The rect is the live selection's own bounding box while the bar is pending, the tapped
    /// decoration's once it is committed, and the selection's again for the one it was
    /// committed *from* — `pickColor` copies it across so the bar does not move when the
    /// passage is saved under the reader's finger. With none of those — a highlight Readium
    /// could not place — the bar takes the bottom edge, which is where it sat before any of
    /// this was measured.
    private func isInLowerHalf(_ rect: CGRect?, in geo: GeometryProxy) -> Bool {
        guard let rect else { return false }
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

    /// `translationPresentation` where the framework exists, and the view untouched where it
    /// does not.
    ///
    /// The fork lives in a modifier of its own because `#if` inside a `some View` chain has to
    /// repeat every modifier below it in both branches, which is how one of the two halves
    /// quietly stops matching the other.
    @ViewBuilder
    func translationTarget(isPresented: Binding<Bool>, text: String) -> some View {
#if targetEnvironment(macCatalyst)
        self
#else
        translationPresentation(isPresented: isPresented, text: text)
#endif
    }
}

private extension View {
    /// What the keyboard does while a book is open, on the Mac.
    ///
    /// Page turns are **not** here — Readium's `DirectionalNavigationAdapter`, bound inside the
    /// navigator's representable, owns the arrows and the space bar because the web view is
    /// first responder by then and eats them before a SwiftUI shortcut is consulted. What is
    /// left are the two things the page itself has no opinion about: leaving the book, and
    /// looking inside it.
    ///
    /// Escape is a button rather than a menu item because nothing else in the app binds it and
    /// a full-window presentation is what the Mac has always used it to leave. `.opacity(0)`
    /// rather than `.hidden()`: a hidden view is out of the hierarchy and its shortcut is never
    /// registered.
    ///
    /// ⌘F arrives as a *command* rather than a shortcut declared here, so it cannot compete
    /// with the same key in the menu bar. The shell ignores it while a book is open and the
    /// reader only exists while one is, so exactly one of the two answers each press.
    @ViewBuilder
    func macReaderKeyboard(
        onClose: @escaping () -> Void,
        onFind: @escaping () -> Void
    ) -> some View {
#if targetEnvironment(macCatalyst)
        background {
            Button("Close book", action: onClose)
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0)
                .frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
        .onReceive(NotificationCenter.default.publisher(for: .dipleMacCommand)) { note in
            switch MacCommand(note) {
            case .findInBook, .findInColumn: onFind()
            default: break
            }
        }
#else
        self
#endif
    }
}

/// A highlight the reader is writing a thought against.
///
/// Only ever an existing one. The bar's note button is dimmed while nothing is saved, so the
/// editor is never the thing that *creates* a highlight — the colour swatch is, and by the
/// time a thought can be written the row is already there.
private enum HighlightEditorTarget: Identifiable {
    case existing(Highlight)

    var id: String {
        switch self {
        case .existing(let highlight): return "existing:\(highlight.id)"
        }
    }
}
