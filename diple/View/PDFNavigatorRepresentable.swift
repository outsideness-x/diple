import SwiftUI
import UIKit
import PDFKit
import OSLog
import ReadiumShared
import ReadiumNavigator

/// Failures the navigators report but cannot act on. `print` does not reach the system log
/// in a shipped build, which is the only place these are ever read from.
enum ReaderLog {
    static let navigator = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "diple",
        category: "navigator"
    )
}

public struct PDFNavigatorRepresentable: UIViewControllerRepresentable {
    public let publication: Publication
    public let initialLocation: Locator?
    public let targetLink: ReadiumShared.Link?
    public let targetLocator: Locator?
    public let preferences: PDFPreferences
    /// See `EPUBNavigatorRepresentable.hasSelection`.
    public let hasSelection: Bool
    public let isLanguageLearningMode: Bool
    public let isOverlayVisible: Bool
    public let onLocationChanged: (Locator) -> Void
    public let onSelectionChanged: (Selection?) -> Void
    /// See `EPUBNavigatorRepresentable.onDismissActions`.
    public let onDismissActions: () -> Bool
    public let onCenterTap: () -> Void
    public let onSentenceTapped: (String) -> Void
    public let onLinkJump: (Locator) -> Void
    public let onTargetHandled: () -> Void
    public let onOpenFailed: (String) -> Void

    public init(
        publication: Publication,
        initialLocation: Locator?,
        targetLink: ReadiumShared.Link? = nil,
        targetLocator: Locator? = nil,
        preferences: PDFPreferences = PDFPreferences(),
        hasSelection: Bool = false,
        isLanguageLearningMode: Bool = false,
        isOverlayVisible: Bool = false,
        onLocationChanged: @escaping (Locator) -> Void,
        onSelectionChanged: @escaping (Selection?) -> Void,
        onDismissActions: @escaping () -> Bool = { false },
        onCenterTap: @escaping () -> Void,
        onSentenceTapped: @escaping (String) -> Void = { _ in },
        onLinkJump: @escaping (Locator) -> Void = { _ in },
        onTargetHandled: @escaping () -> Void = {},
        onOpenFailed: @escaping (String) -> Void = { _ in }
    ) {
        self.publication = publication
        self.initialLocation = initialLocation
        self.targetLink = targetLink
        self.targetLocator = targetLocator
        self.preferences = preferences
        self.hasSelection = hasSelection
        self.isLanguageLearningMode = isLanguageLearningMode
        self.isOverlayVisible = isOverlayVisible
        self.onLocationChanged = onLocationChanged
        self.onSelectionChanged = onSelectionChanged
        self.onDismissActions = onDismissActions
        self.onCenterTap = onCenterTap
        self.onSentenceTapped = onSentenceTapped
        self.onLinkJump = onLinkJump
        self.onTargetHandled = onTargetHandled
        self.onOpenFailed = onOpenFailed
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        let config = PDFNavigatorViewController.Configuration(
            preferences: preferences
        )

        do {
            let navigator = try PDFNavigatorViewController(
                publication: publication,
                initialLocation: initialLocation,
                config: config,
                delegate: context.coordinator
            )
            context.coordinator.navigator = navigator
            context.coordinator.lastPreferences = preferences
            context.coordinator.bindKeyboardPageTurns(to: navigator)
            return navigator
        } catch {
            // See the note in `EPUBNavigatorRepresentable`: a book we cannot render must
            // not take the app down with it.
            Task { @MainActor in
                onOpenFailed("Failed to open this book: \(error.localizedDescription)")
            }
            return UIViewController()
        }
    }

    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard let uiViewController = uiViewController as? PDFNavigatorViewController else { return }
        context.coordinator.parent = self
        
        if context.coordinator.lastPreferences != preferences {
            context.coordinator.lastPreferences = preferences
            uiViewController.submitPreferences(preferences)
        }

        context.coordinator.clearSelectionIfNeeded(hasSelection, in: uiViewController)
        context.coordinator.navigate(to: targetLink, or: targetLocator, in: uiViewController)
    }

    public class Coordinator: NSObject, PDFNavigatorDelegate {
        var parent: PDFNavigatorRepresentable
        weak var navigator: PDFNavigatorViewController?
        var lastHref: AnyURL? = nil
        var lastPreferences: PDFPreferences? = nil
        private var didClearSelection = false
        private var inFlightTarget: NavigationTarget? = nil
        private let selectionSettle = SelectionSettle()
        /// See `EPUBNavigatorRepresentable.Coordinator.bindKeyboardPageTurns`.
        private var directionalNavigation: DirectionalNavigationAdapter?

        /// Arrow keys and the space bar, on the Mac. Same reasoning, same policy and the same
        /// deliberate silence on pointer events as the EPUB navigator's — see
        /// `EPUBNavigatorRepresentable.Coordinator.bindKeyboardPageTurns`.
        func bindKeyboardPageTurns(to navigator: PDFNavigatorViewController) {
            #if targetEnvironment(macCatalyst)
            let adapter = DirectionalNavigationAdapter(
                pointerPolicy: .init(types: []),
                keyboardPolicy: .init(handleArrowKeys: true, handleSpaceKey: true),
                animatedTransition: true
            )
            adapter.bind(to: navigator)
            directionalNavigation = adapter
            #endif
        }

        /// See `EPUBNavigatorRepresentable.Coordinator.clearSelectionIfNeeded`.
        func clearSelectionIfNeeded(_ hasSelection: Bool, in navigator: PDFNavigatorViewController) {
            guard !hasSelection else {
                didClearSelection = false
                return
            }
            guard !selectionSettle.isPending else { return }
            guard !didClearSelection else { return }
            didClearSelection = true
            navigator.clearSelection()
        }

        private enum NavigationTarget: Equatable {
            case link(ReadiumShared.Link)
            case locator(Locator)
        }

        init(_ parent: PDFNavigatorRepresentable) {
            self.parent = parent
        }

        /// See the note in `EPUBNavigatorRepresentable.Coordinator.navigate(to:or:in:)`.
        func navigate(
            to link: ReadiumShared.Link?,
            or locator: Locator?,
            in navigator: PDFNavigatorViewController
        ) {
            let target: NavigationTarget?
            if let link {
                target = .link(link)
            } else if let locator {
                target = .locator(locator)
            } else {
                target = nil
            }

            guard let target, target != inFlightTarget else { return }
            inFlightTarget = target

            Task { @MainActor [weak self] in
                switch target {
                case let .link(link):
                    _ = await navigator.go(to: link, options: NavigatorGoOptions(animated: true))
                case let .locator(locator):
                    _ = await navigator.go(to: locator, options: NavigatorGoOptions(animated: true))
                }
                self?.inFlightTarget = nil
                self?.parent.onTargetHandled()
            }
        }

        public func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
            ReaderLog.navigator.error("PDF navigator error: \(error, privacy: .public)")
        }

        /// - Important: The parameter type must be `Navigator`, not `VisualNavigator`.
        ///   See the note in `EPUBNavigatorRepresentable.Coordinator`.
        public func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
            if let previousHref = lastHref, previousHref != locator.href {
                HapticManager.shared.chapterChanged()
            }
            lastHref = locator.href
            parent.onLocationChanged(locator)
        }

        public func navigator(_ navigator: VisualNavigator, shouldNavigateToLink link: ReadiumShared.Link) -> Bool {
            if let current = navigator.currentLocation {
                parent.onLinkJump(current)
            }
            return true
        }

        public func navigator(_ navigator: SelectableNavigator, shouldShowMenuForSelection selection: Selection) -> Bool {
            // One report per drag rather than one per pixel of it — see `SelectionSettle`.
            // Nothing is saved automatically on PDF, but the bar and the haptic answered the
            // same stream and flickered with it.
            selectionSettle.settle(on: selection) { [weak self] settled in
                HapticManager.shared.selection()
                self?.parent.onSelectionChanged(settled)
            }
            return false
        }

        public func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
            selectionSettle.cancel()

            // See `EPUBNavigatorRepresentable.Coordinator.pageWasTapped`: a tap that closes the
            // actions bar closes it and does nothing else.
            if parent.onDismissActions() { return }

            parent.onSelectionChanged(nil)

            #if !targetEnvironment(macCatalyst)
            if parent.isLanguageLearningMode,
               !parent.isOverlayVisible,
               let rootView = navigator.view,
               let sentence = Self.extractPDFSentence(at: point, in: rootView) {
                HapticManager.shared.selection()
                parent.onSentenceTapped(sentence)
                return
            }
            #endif

            if parent.preferences.scroll == true {
                parent.onCenterTap()
                return
            }

            guard let view = navigator.view else { return }
            let width = view.bounds.width
            guard width > 0 else { return }

            let fraction = point.x / width
            if fraction < 0.33 {
                Task {
                    _ = await navigator.goBackward()
                }
            } else if fraction > 0.66 {
                Task {
                    _ = await navigator.goForward()
                }
            } else {
                parent.onCenterTap()
            }
        }

        private static func extractPDFSentence(at point: CGPoint, in rootView: UIView) -> String? {
            guard let pdfView = firstPDFView(in: rootView) else { return nil }
            let pdfPoint = pdfView.convert(point, from: rootView)
            guard let page = pdfView.page(for: pdfPoint, nearest: false),
                  let rawPageText = page.string,
                  !rawPageText.isEmpty
            else {
                return nil
            }

            let pagePoint = pdfView.convert(pdfPoint, to: page)
            let charIndex = page.characterIndex(at: pagePoint)
            guard charIndex >= 0, charIndex < rawPageText.utf16.count else { return nil }

            let charBounds = page.characterBounds(at: charIndex)
            guard charBounds.insetBy(dx: -16, dy: -12).contains(pagePoint) else {
                return nil
            }

            // Unwrap soft line breaks inside paragraphs while preserving double-newline breaks.
            let unwrapped = unwrapPDFLineBreaks(in: rawPageText)
            return SentenceTokenizer.sentence(in: unwrapped, atUTF16Offset: charIndex)?.text
        }

        /// Replaces single `\n` / `\r` characters with spaces while leaving double newlines intact,
        /// preserving the exact UTF-16 length of the page string so `charIndex` still maps 1-to-1.
        private static func unwrapPDFLineBreaks(in text: String) -> String {
            var chars = Array(text.utf16)
            let newline: UInt16 = 0x000A
            let carriage: UInt16 = 0x000D
            let space: UInt16 = 0x0020
            let count = chars.count
            for i in 0 ..< count {
                guard chars[i] == newline || chars[i] == carriage else { continue }
                let prevIsBreak = (i > 0) && (chars[i - 1] == newline || chars[i - 1] == carriage)
                let nextIsBreak = (i + 1 < count) && (chars[i + 1] == newline || chars[i + 1] == carriage)
                if !prevIsBreak && !nextIsBreak {
                    chars[i] = space
                }
            }
            return String(utf16CodeUnits: chars, count: chars.count)
        }

        private static func firstPDFView(in view: UIView) -> PDFView? {
            if let pdfView = view as? PDFView {
                return pdfView
            }
            for subview in view.subviews {
                if let found = firstPDFView(in: subview) {
                    return found
                }
            }
            return nil
        }
    }
}
