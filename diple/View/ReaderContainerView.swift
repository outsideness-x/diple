import SwiftUI
import ReadiumShared
import ReadiumNavigator

public struct ReaderContainerView: View {
    @StateObject private var viewModel: ReaderViewModel
    @StateObject private var settingsManager = AppSettingsManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @State private var highlightEditorTarget: HighlightEditorTarget?
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
            DipleColor.canvas.ignoresSafeArea()

            if viewModel.isLoading {
                VStack(spacing: DipleSpace.m) {
                    ProgressView()
                        .tint(.white)
                    Text("Loading book...")
                        .dipleType(.callout, weight: .medium)
                        .foregroundStyle(DipleColor.textSecondary)
                }
            } else if let errorMessage = viewModel.errorMessage {
                VStack(spacing: DipleSpace.l) {
                    Image(systemName: "exclamationmark.triangle")
                        .dipleIcon(32)
                        .foregroundColor(.red)

                    Text(errorMessage)
                        .dipleType(.callout, weight: .medium)
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, DipleSpace.xxxl)

                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, DipleSpace.xl)
                    .padding(.vertical, DipleSpace.s)
                    .background(Color.white.opacity(0.2))
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
                    .ignoresSafeArea()
                } else {
                    EPUBNavigatorRepresentable(
                        publication: publication,
                        initialLocation: viewModel.initialLocator,
                        targetLink: viewModel.targetLink,
                        targetLocator: viewModel.targetLocator,
                        highlights: viewModel.highlights,
                        tableOfContents: viewModel.tableOfContents,
                        preferences: viewModel.epubPreferences,
                        hasSelection: viewModel.currentSelection != nil,
                        onLocationChanged: { locator in
                            viewModel.saveLocation(locator)
                            ReaderIdleTimerKeeper.shared.poke()
                        },
                        onSelectionChanged: { selection in
                            presentEditor(for: selection)
                            ReaderIdleTimerKeeper.shared.poke()
                        },
                        onHighlightActivated: { highlightID in
                            guard let highlight = viewModel.highlights.first(where: { $0.id == highlightID }) else {
                                return
                            }
                            highlightEditorTarget = .existing(highlight)
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
                    .ignoresSafeArea()
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
                        ReaderToastView(message: toast)
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
        .overlay {
            selectionLayer
        }
        .animation(DipleMotion.gentle, value: viewModel.toast)
        .animation(DipleMotion.gentle, value: viewModel.currentSelection?.locator)
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
            viewModel.currentSelection = nil
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

    /// The quote a live selection stands for, or nil when there is nothing worth acting on.
    private var selectedQuote: String? {
        guard let quote = viewModel.currentSelection?.locator.text.highlight?
            .trimmingCharacters(in: .whitespacesAndNewlines),
              !quote.isEmpty
        else { return nil }
        return quote
    }

    @ViewBuilder
    private var selectionLayer: some View {
        if let quote = selectedQuote, highlightEditorTarget == nil {
            GeometryReader { geo in
                // Dismissing has to consume the tap. Left to fall through it would also turn
                // the page or toggle the reader's bars, so closing the bar would never be the
                // only thing that happened.
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture { viewModel.currentSelection = nil }

                let bar = ReaderSelectionBar(
                    chrome: chrome,
                    onPickColor: { hex in viewModel.createHighlight(colorHex: hex) },
                    onAddNote: { highlightEditorTarget = .new(UUID(), quote) },
                    onCopy: { UIPasteboard.general.string = quote }
                )
                .fixedSize()

                bar
                    .padding(.vertical, DipleSpace.xl)
                    .frame(
                        width: geo.size.width,
                        height: geo.size.height,
                        alignment: selectionIsInLowerHalf(geo) ? .top : .bottom
                    )
            }
            .ignoresSafeArea()
            .transition(.opacity)
        }
    }

    private func presentEditor(for selection: Selection?) {
        viewModel.currentSelection = selection
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
    private func selectionIsInLowerHalf(_ geo: GeometryProxy) -> Bool {
        guard let frame = viewModel.currentSelection?.frame else { return false }
        return frame.midY > geo.size.height / 2
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
