import SwiftUI

/// What opening a piece of the feed is a route to: the piece, and in which form.
struct FeedOpening: Hashable {
    let itemID: String
    let format: FeedReading.Format
}

/// A piece of the feed on its way into the reader.
///
/// Reading a piece means fetching it, typesetting it as a book and filing it in the library —
/// a few seconds for an essay, longer for a paper with figures. Those seconds are spent on the
/// piece's **title page**, the same one the reader opens every book on (`ReaderTitlePage`): its
/// title and its author in the reader's face, on the reader's page colour, with the short rule
/// between them breathing. When the piece is ready the reader takes over and puts up that same
/// page while it lays out the first screen, so download and opening read as one movement — the
/// row grew into a title page, and the title page became the text.
struct FeedOpeningView: View {
    let item: FeedItem
    let format: FeedReading.Format
    let library: [Book]
    let onReadingUpdated: () -> Void

    @ObservedObject private var settings = AppSettingsManager.shared
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL
    @State private var book: Book?
    @State private var stage: LinkImporter.Stage?
    @State private var failure: String?
    @State private var attempt = 0

    private var chrome: ReaderChrome {
        ReaderChrome.forTheme(settings.settings.readerSettings.theme)
    }

    var body: some View {
        Group {
            if let book {
                ReaderContainerView(book: book, onReadingUpdated: onReadingUpdated)
            } else {
                titlePage
            }
        }
        .task(id: attempt) { await open() }
    }

    private var titlePage: some View {
        ZStack {
            chrome.page.ignoresSafeArea()

            ReaderTitlePage(
                title: item.title,
                author: item.byline,
                font: settings.settings.readerSettings.font,
                chrome: chrome
            )

            VStack(spacing: DipleSpace.l) {
                Spacer()
                if let failure {
                    failureNote(failure)
                } else if let stage {
                    Text(stage.label)
                        .dipleType(.caption)
                        .foregroundStyle(chrome.secondary)
                        .monospacedDigit()
                        .contentTransition(.opacity)
                        .animation(DipleMotion.standard, value: stage)
                }
            }
            .padding(.horizontal, DipleSpace.xxl)
            .padding(.bottom, DipleSpace.xxxl)
        }
        .overlay(alignment: .topLeading) { backButton }
        .toolbar(.hidden, for: .navigationBar)
        .hidesDipleTabBar()
        .environment(\.colorScheme, chrome.colorScheme)
    }

    /// The way back while the piece is still on its way. The reader's own glass circle, in the
    /// same place, so nothing about the top of the screen changes when the text arrives.
    private var backButton: some View {
        Button {
            HapticManager.shared.impact(.light)
            dismiss()
        } label: {
            Image(systemName: "chevron.left")
                .dipleIcon(16)
                .foregroundStyle(chrome.control)
                .frame(width: 44, height: 44)
                .contentShape(Circle())
        }
        .buttonStyle(.readerControl)
        .modifier(ReaderGlassSurface(chrome: chrome, shape: Circle(), material: .regularMaterial))
        .padding(.leading, DipleSpace.l)
        .padding(.top, DipleSpace.s)
        .accessibilityLabel("Back to the feed")
    }

    private func failureNote(_ message: String) -> some View {
        VStack(spacing: DipleSpace.m) {
            Text(message)
                .dipleType(.callout)
                .foregroundStyle(chrome.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: DipleSpace.xl) {
                Button("Try again") {
                    HapticManager.shared.selection()
                    failure = nil
                    attempt += 1
                }
                Button(item.arxivID != nil ? "Open on arXiv" : "Open the website") {
                    openURL(item.link)
                }
            }
            .dipleType(.footnote, weight: .semibold)
            .foregroundStyle(chrome.control)
            .buttonStyle(.readerControl)
        }
        .transition(.opacity)
    }

    private func open() async {
        do {
            let opened = try await FeedReading.book(for: item, format: format, in: library) { stage in
                Task { @MainActor in self.stage = stage }
            }
            HapticManager.shared.impact(.light)
            onReadingUpdated()
            // Without animation: the reader puts up the same title page, and a cross-fade
            // between two identical pages only shows the seam.
            book = opened
        } catch {
            if error is CancellationError { return }
            HapticManager.shared.notification(.error)
            withAnimation(DipleMotion.standard) {
                failure = (error as? LocalizedError)?.errorDescription
                    ?? "This piece couldn’t be fetched just now."
            }
        }
    }
}
