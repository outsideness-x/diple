import SwiftUI
import ReadiumShared
import ReadiumNavigator

public struct ReaderContainerView: View {
    @StateObject private var viewModel: ReaderViewModel
    @Environment(\.dismiss) private var dismiss
    public let onReadingUpdated: () -> Void

    public init(book: Book, onReadingUpdated: @escaping () -> Void) {
        self._viewModel = StateObject(wrappedValue: ReaderViewModel(book: book))
        self.onReadingUpdated = onReadingUpdated
    }

    public var body: some View {
        ZStack {
            // True Black background for reader container
            Color.black.ignoresSafeArea()

            if viewModel.isLoading {
                VStack(spacing: 12) {
                    ProgressView()
                        .tint(.white)
                    Text("Loading book...")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color(red: 0.7, green: 0.7, blue: 0.7))
                }
            } else if let errorMessage = viewModel.errorMessage {
                VStack(spacing: 16) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 32))
                        .foregroundColor(.red)

                    Text(errorMessage)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)

                    Button("Close") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 8)
                    .background(Color.white.opacity(0.2))
                    .cornerRadius(8)
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
                        },
                        onSelectionChanged: { selection in
                            viewModel.currentSelection = selection
                        },
                        onCenterTap: {
                            viewModel.toggleOverlay()
                        },
                        onLinkJump: { originLocator in
                            viewModel.pushBackLocation(originLocator)
                        },
                        onTargetHandled: {
                            viewModel.clearTargetLocator()
                            viewModel.clearTargetLink()
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
                        preferences: viewModel.settings.epubPreferences,
                        onLocationChanged: { locator in
                            viewModel.saveLocation(locator)
                        },
                        onSelectionChanged: { selection in
                            viewModel.currentSelection = selection
                        },
                        onCenterTap: {
                            viewModel.toggleOverlay()
                        },
                        onLinkJump: { originLocator in
                            viewModel.pushBackLocation(originLocator)
                        },
                        onTargetHandled: {
                            viewModel.clearTargetLocator()
                            viewModel.clearTargetLink()
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
                                HStack(spacing: 6) {
                                    Image(systemName: "arrow.uturn.backward")
                                        .font(.system(size: 13, weight: .semibold))
                                    Text("Return to text")
                                        .font(.system(size: 13, weight: .semibold))
                                }
                                .foregroundColor(.black)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 8)
                                .background(Color.dipleAccent)
                                .cornerRadius(20)
                                .shadow(color: Color.black.opacity(0.4), radius: 6, x: 0, y: 3)
                            }
                            Spacer()
                        }
                        .padding(.leading, 20)
                        .padding(.top, viewModel.isOverlayVisible ? 70 : 50)

                        Spacer()
                    }
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.2), value: viewModel.backLocationStack.count)
                }

                // Overlay Controls (Top & Bottom bars)
                if viewModel.isOverlayVisible {
                    VStack {
                        // Top Bar Overlay
                        HStack(spacing: 16) {
                            Button {
                                HapticManager.shared.impact(.light)
                                dismiss()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))
                            }
                            .buttonStyle(.readerControl)

                            Text(viewModel.book.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer()

                            Button {
                                HapticManager.shared.selection()
                                viewModel.isAddBookmarkPresented = true
                            } label: {
                                Image(systemName: viewModel.isCurrentPositionBookmarked ? "bookmark.fill" : "bookmark")
                                    .font(.system(size: 18, weight: .regular))
                                    .foregroundColor(
                                        viewModel.isCurrentPositionBookmarked
                                            ? Color.dipleAccent
                                            : Color(red: 0.92, green: 0.92, blue: 0.92)
                                    )
                            }
                            .buttonStyle(.readerControl)
                            .disabled(!viewModel.canAddBookmark)
                            .opacity(viewModel.canAddBookmark ? 1 : 0.35)
                            .animation(.spring(response: 0.3, dampingFraction: 0.7), value: viewModel.isCurrentPositionBookmarked)

                            Button {
                                HapticManager.shared.selection()
                                viewModel.isOutlinePresented = true
                            } label: {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 18, weight: .regular))
                                    .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))
                            }
                            .buttonStyle(.readerControl)
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(.thinMaterial)
                        .environment(\.colorScheme, .dark)
                        .transition(.move(edge: .top).combined(with: .opacity))

                        Spacer()

                        // Bottom Bar Overlay
                        VStack(spacing: 10) {
                            ReadingProgressSlider(
                                progress: viewModel.currentProgress,
                                isEnabled: viewModel.canSeek,
                                onSeek: { viewModel.seek(toProgress: $0) }
                            )

                            HStack(spacing: 12) {
                                let percentage = Int((viewModel.currentProgress * 100).rounded())
                                Text("\(percentage)%")
                                    .font(.system(size: 13, weight: .semibold))
                                    .foregroundColor(Color.dipleAccent)
                                    .monospacedDigit()
                                    .contentTransition(.numericText())
                                    .animation(.easeOut(duration: 0.2), value: percentage)

                                if let chapter = viewModel.currentLocator?.title,
                                   !chapter.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                                    Text(chapter)
                                        .font(.system(size: 13, weight: .regular))
                                        .foregroundColor(Color(red: 0.7, green: 0.7, blue: 0.74))
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }

                                Spacer(minLength: 0)

                                Button {
                                    HapticManager.shared.selection()
                                    viewModel.isSettingsPresented = true
                                } label: {
                                    Image(systemName: "gearshape")
                                        .font(.system(size: 18, weight: .regular))
                                        .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))
                                }
                                .buttonStyle(.readerControl)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 10)
                        .padding(.bottom, 14)
                        .background(.thinMaterial)
                        .environment(\.colorScheme, .dark)
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

                // Selection Floating Color Bar Overlay
                if viewModel.currentSelection != nil {
                    VStack {
                        Spacer()
                        SelectionColorBarView { hexColor in
                            viewModel.createHighlight(colorHex: hexColor)
                        } onCancel: {
                            viewModel.currentSelection = nil
                        }
                        .padding(.bottom, 40)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .animation(.spring(response: 0.32, dampingFraction: 0.8), value: viewModel.toast)
        .animation(.easeInOut(duration: 0.18), value: viewModel.currentSelection?.locator)
        .task {
            await viewModel.openBook()
        }
        .onDisappear {
            // Persist synchronously first so the library grid reloads an up-to-date row.
            viewModel.flushPendingProgress()
            onReadingUpdated()
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
    }
}
