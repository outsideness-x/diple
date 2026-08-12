import SwiftUI
import ReadiumShared
import ReadiumNavigator

public struct ReaderContainerView: View {
    @StateObject private var viewModel: ReaderViewModel
    @StateObject private var settingsManager = AppSettingsManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
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
                if viewModel.book.filePath.lowercased().hasSuffix(".pdf") {
                    PDFNavigatorRepresentable(
                        publication: publication,
                        initialLocation: viewModel.initialLocator,
                        targetLink: viewModel.targetLink,
                        targetLocator: viewModel.targetLocator,
                        preferences: viewModel.settings.pdfPreferences,
                        onLocationChanged: { locator in
                            viewModel.saveLocation(locator)
                            ReaderIdleTimerKeeper.shared.poke()
                        },
                        onSelectionChanged: { selection in
                            viewModel.currentSelection = selection
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
                        onLocationChanged: { locator in
                            viewModel.saveLocation(locator)
                            ReaderIdleTimerKeeper.shared.poke()
                        },
                        onSelectionChanged: { selection in
                            viewModel.currentSelection = selection
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
                                if !viewModel.book.isArticle {
                                    Button {
                                        HapticManager.shared.selection()
                                        viewModel.isSearchPresented = true
                                    } label: {
                                        Image(systemName: "magnifyingglass")
                                            .dipleIcon(16, weight: .regular)
                                            .foregroundStyle(chrome.control)
                                    }
                                    .buttonStyle(.readerControl)
                                }

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

                // Selection Floating Color Bar Overlay.
                //
                // Carried by a flexible `Color.clear` and attached as its overlay, because a
                // `ZStack` sizes itself to its widest child: the bar's row of fixed circles
                // and its `fixedSize` label give it a minimum width that a narrow phone or a
                // large Dynamic Type size pushes past the screen, and as a plain sibling that
                // minimum widened the stack — and with it the navigator — so the page reflowed
                // under the reader every time a sentence was selected. An overlay is laid out
                // inside its host and can never resize it.
                if viewModel.currentSelection != nil {
                    Color.clear
                        .allowsHitTesting(false)
                        .overlay(alignment: .bottom) {
                            SelectionColorBarView { hexColor in
                                viewModel.createHighlight(colorHex: hexColor)
                            } onCancel: {
                                viewModel.currentSelection = nil
                            }
                            .padding(.bottom, DipleSpace.scrollBottom)
                        }
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
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
    }
}
