import SwiftUI
import UIKit
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
    public let onLocationChanged: (Locator) -> Void
    public let onSelectionChanged: (Selection?) -> Void
    public let onCenterTap: () -> Void
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
        onLocationChanged: @escaping (Locator) -> Void,
        onSelectionChanged: @escaping (Selection?) -> Void,
        onCenterTap: @escaping () -> Void,
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
        self.onLocationChanged = onLocationChanged
        self.onSelectionChanged = onSelectionChanged
        self.onCenterTap = onCenterTap
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

        /// See `EPUBNavigatorRepresentable.Coordinator.clearSelectionIfNeeded`.
        func clearSelectionIfNeeded(_ hasSelection: Bool, in navigator: PDFNavigatorViewController) {
            guard !hasSelection else {
                didClearSelection = false
                return
            }
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
            HapticManager.shared.selection()
            parent.onSelectionChanged(selection)
            return true
        }

        public func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
            parent.onSelectionChanged(nil)

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
    }
}
