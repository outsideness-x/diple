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
                // EPUB Navigator
                EPUBNavigatorRepresentable(
                    publication: publication,
                    initialLocation: viewModel.initialLocator,
                    targetLink: viewModel.targetLink,
                    targetLocator: viewModel.targetLocator,
                    highlights: viewModel.highlights,
                    preferences: viewModel.settings.epubPreferences,
                    onLocationChanged: { locator in
                        viewModel.saveLocation(locator)
                        onReadingUpdated()
                    },
                    onSelectionChanged: { selection in
                        viewModel.currentSelection = selection
                    },
                    onCenterTap: {
                        viewModel.toggleOverlay()
                    }
                )
                .ignoresSafeArea()

                // Overlay Controls (Top & Bottom bars)
                if viewModel.isOverlayVisible {
                    VStack {
                        // Top Bar Overlay
                        HStack(spacing: 16) {
                            Button {
                                dismiss()
                            } label: {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))
                            }

                            Text(viewModel.book.title)
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))
                                .lineLimit(1)
                                .truncationMode(.tail)

                            Spacer()

                            Button {
                                viewModel.isOutlinePresented = true
                            } label: {
                                Image(systemName: "list.bullet")
                                    .font(.system(size: 18, weight: .regular))
                                    .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(Color.black.opacity(0.85))

                        Spacer()

                        // Bottom Bar Overlay
                        HStack {
                            let percentage = Int(viewModel.currentProgress * 100)
                            Text("\(percentage)% Progres")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(Color(red: 0.75, green: 0.75, blue: 0.78))

                            Spacer()

                            Button {
                                viewModel.isSettingsPresented = true
                            } label: {
                                Image(systemName: "gearshape")
                                    .font(.system(size: 18, weight: .regular))
                                    .foregroundColor(Color(red: 0.92, green: 0.92, blue: 0.92))
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.vertical, 14)
                        .background(Color.black.opacity(0.85))
                    }
                    .transition(.opacity)
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
        .task {
            await viewModel.openBook()
        }
        .toolbar(.hidden, for: .navigationBar)
        .toolbar(.hidden, for: .tabBar)
        .navigationBarBackButtonHidden(true)
        .sheet(isPresented: $viewModel.isSettingsPresented) {
            ReaderSettingsView(settings: $viewModel.settings)
        }
        .sheet(isPresented: $viewModel.isOutlinePresented) {
            BookOutlineSheetView(
                tableOfContents: viewModel.tableOfContents,
                highlights: viewModel.highlights,
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
                }
            )
        }
    }
}
