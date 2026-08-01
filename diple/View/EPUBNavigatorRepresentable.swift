import SwiftUI
import UIKit
import ReadiumShared
import ReadiumNavigator

public struct EPUBNavigatorRepresentable: UIViewControllerRepresentable {
    public let publication: Publication
    public let initialLocation: Locator?
    public let targetLink: ReadiumShared.Link?
    public let targetLocator: Locator?
    public let highlights: [Highlight]
    public let preferences: EPUBPreferences
    public let onLocationChanged: (Locator) -> Void
    public let onSelectionChanged: (Selection?) -> Void
    public let onCenterTap: () -> Void
    public let onLinkJump: (Locator) -> Void
    public let onTargetHandled: () -> Void

    public init(
        publication: Publication,
        initialLocation: Locator?,
        targetLink: ReadiumShared.Link? = nil,
        targetLocator: Locator? = nil,
        highlights: [Highlight] = [],
        preferences: EPUBPreferences,
        onLocationChanged: @escaping (Locator) -> Void,
        onSelectionChanged: @escaping (Selection?) -> Void,
        onCenterTap: @escaping () -> Void,
        onLinkJump: @escaping (Locator) -> Void = { _ in },
        onTargetHandled: @escaping () -> Void = {}
    ) {
        self.publication = publication
        self.initialLocation = initialLocation
        self.targetLink = targetLink
        self.targetLocator = targetLocator
        self.highlights = highlights
        self.preferences = preferences
        self.onLocationChanged = onLocationChanged
        self.onSelectionChanged = onSelectionChanged
        self.onCenterTap = onCenterTap
        self.onLinkJump = onLinkJump
        self.onTargetHandled = onTargetHandled
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIViewController(context: Context) -> EPUBNavigatorViewController {
        let config = EPUBNavigatorViewController.Configuration(
            preferences: preferences
        )

        do {
            let navigator = try EPUBNavigatorViewController(
                publication: publication,
                initialLocation: initialLocation,
                config: config
            )
            navigator.delegate = context.coordinator
            context.coordinator.navigator = navigator
            context.coordinator.lastPreferences = preferences
            context.coordinator.lastHighlights = highlights
            context.coordinator.setupScrollObserver(for: navigator)
            applyDecorations(highlights: highlights, to: navigator)
            return navigator
        } catch {
            fatalError("Failed to initialize EPUBNavigatorViewController: \(error)")
        }
    }

    public func updateUIViewController(_ uiViewController: EPUBNavigatorViewController, context: Context) {
        context.coordinator.parent = self
        
        if context.coordinator.lastPreferences != preferences {
            context.coordinator.lastPreferences = preferences
            uiViewController.submitPreferences(preferences)
        }
        
        context.coordinator.setupScrollObserver(for: uiViewController)
        context.coordinator.navigate(to: targetLink, or: targetLocator, in: uiViewController)

        if context.coordinator.lastHighlights != highlights {
            context.coordinator.lastHighlights = highlights
            applyDecorations(highlights: highlights, to: uiViewController)
        }
    }

    private func applyDecorations(highlights: [Highlight], to navigator: EPUBNavigatorViewController) {
        let decorations = highlights.compactMap { h -> Decoration? in
            guard let locator = h.parsedLocator else { return nil }
            let uiColor: UIColor
            if let readiumColor = ReadiumNavigator.Color(hex: h.colorHex) {
                uiColor = readiumColor.uiColor
            } else {
                uiColor = .yellow
            }
            return Decoration(
                id: h.id,
                locator: locator,
                style: .highlight(tint: uiColor)
            )
        }
        navigator.apply(decorations: decorations, in: "highlights")
    }

    public class Coordinator: NSObject, EPUBNavigatorDelegate, SelectableNavigatorDelegate {
        var parent: EPUBNavigatorRepresentable
        weak var navigator: EPUBNavigatorViewController?
        var lastHref: AnyURL? = nil
        var lastPreferences: EPUBPreferences? = nil
        var lastHighlights: [Highlight]? = nil
        private var scrollObserver: NSKeyValueObservation?
        private var hasTriggeredChapterTransition = false
        private var inFlightTarget: NavigationTarget? = nil

        private enum NavigationTarget: Equatable {
            case link(ReadiumShared.Link)
            case locator(Locator)
        }

        init(_ parent: EPUBNavigatorRepresentable) {
            self.parent = parent
        }

        /// `updateUIViewController` runs on every SwiftUI update — including the ones caused
        /// by reading progress ticking forward — so an unguarded `go(to:)` here would restart
        /// the same jump dozens of times and fight the user's scrolling.
        func navigate(
            to link: ReadiumShared.Link?,
            or locator: Locator?,
            in navigator: EPUBNavigatorViewController
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

        func setupScrollObserver(for navigator: EPUBNavigatorViewController) {
            scrollObserver?.invalidate()
            scrollObserver = nil

            guard parent.preferences.scroll == true,
                  let scrollView = findScrollView(in: navigator.view) else { return }

            scrollObserver = scrollView.observe(\.contentOffset, options: [.new]) { [weak self] sv, _ in
                guard let self = self, let nav = self.navigator else { return }
                let currentOffsetY = sv.contentOffset.y
                let maxOffsetY = max(0, sv.contentSize.height - sv.bounds.height)

                if currentOffsetY > maxOffsetY + 55 {
                    if !self.hasTriggeredChapterTransition {
                        self.hasTriggeredChapterTransition = true
                        HapticManager.shared.chapterChanged()
                        Task { @MainActor in
                            _ = await nav.goForward(options: NavigatorGoOptions(animated: true))
                        }
                    }
                } else if currentOffsetY < -55 {
                    if !self.hasTriggeredChapterTransition {
                        self.hasTriggeredChapterTransition = true
                        HapticManager.shared.chapterChanged()
                        Task { @MainActor in
                            _ = await nav.goBackward(options: NavigatorGoOptions(animated: true))
                        }
                    }
                } else if currentOffsetY >= -10 && currentOffsetY <= maxOffsetY + 10 {
                    self.hasTriggeredChapterTransition = false
                }
            }
        }

        private func findScrollView(in view: UIView) -> UIScrollView? {
            if let sv = view as? UIScrollView {
                return sv
            }
            for subview in view.subviews {
                if let sv = findScrollView(in: subview) {
                    return sv
                }
            }
            return nil
        }

        public func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
            print("Readium navigator error: \(error)")
        }

        /// - Important: The parameter type must be `Navigator`, not `VisualNavigator`.
        ///   `locationDidChange` is declared on `NavigatorDelegate`; declaring it with a
        ///   narrower type silently creates an unrelated method and Readium keeps calling
        ///   the empty default implementation, so no location is ever reported.
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

        public func navigator(_ navigator: Navigator, shouldNavigateToNoteAt link: ReadiumShared.Link, content: String, referrer: String?) -> Bool {
            if let current = (navigator as? VisualNavigator)?.currentLocation {
                parent.onLinkJump(current)
            }
            return true
        }

        public func navigator(_ navigator: Navigator, didJumpTo locator: Locator) {
            // Internal jump occurred
        }

        public func navigator(_ navigator: SelectableNavigator, shouldShowMenuForSelection selection: Selection) -> Bool {
            HapticManager.shared.selection()
            parent.onSelectionChanged(selection)
            return true
        }

        public func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
            parent.onSelectionChanged(nil)

            // In continuous scroll mode, horizontal tap gestures MUST NOT turn pages.
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
