import SwiftUI
import UIKit
import OSLog
import WebKit
import ReadiumShared
import ReadiumNavigator

public struct EPUBNavigatorRepresentable: UIViewControllerRepresentable {
    public let publication: Publication
    public let initialLocation: Locator?
    public let targetLink: ReadiumShared.Link?
    public let targetLocator: Locator?
    public let highlights: [Highlight]
    public let tableOfContents: [ReadiumShared.Link]
    public let preferences: EPUBPreferences
    /// Whether the app still considers a selection active. Dropping it clears the
    /// publication's own selection too, so dismissing the highlight bar takes the blue
    /// selection and the system edit menu with it.
    public let hasSelection: Bool
    public let onLocationChanged: (Locator) -> Void
    public let onSelectionChanged: (Selection?) -> Void
    public let onHighlightActivated: (String) -> Void
    public let onCenterTap: () -> Void
    public let onLinkJump: (Locator) -> Void
    public let onTargetHandled: () -> Void
    public let onOpenFailed: (String) -> Void

    public init(
        publication: Publication,
        initialLocation: Locator?,
        targetLink: ReadiumShared.Link? = nil,
        targetLocator: Locator? = nil,
        highlights: [Highlight] = [],
        tableOfContents: [ReadiumShared.Link] = [],
        preferences: EPUBPreferences,
        hasSelection: Bool = false,
        onLocationChanged: @escaping (Locator) -> Void,
        onSelectionChanged: @escaping (Selection?) -> Void,
        onHighlightActivated: @escaping (String) -> Void = { _ in },
        onCenterTap: @escaping () -> Void,
        onLinkJump: @escaping (Locator) -> Void = { _ in },
        onTargetHandled: @escaping () -> Void = {},
        onOpenFailed: @escaping (String) -> Void = { _ in }
    ) {
        self.publication = publication
        self.initialLocation = initialLocation
        self.targetLink = targetLink
        self.targetLocator = targetLocator
        self.highlights = highlights
        self.tableOfContents = tableOfContents
        self.preferences = preferences
        self.hasSelection = hasSelection
        self.onLocationChanged = onLocationChanged
        self.onSelectionChanged = onSelectionChanged
        self.onHighlightActivated = onHighlightActivated
        self.onCenterTap = onCenterTap
        self.onLinkJump = onLinkJump
        self.onTargetHandled = onTargetHandled
        self.onOpenFailed = onOpenFailed
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        let config = EPUBNavigatorViewController.Configuration(
            preferences: preferences,
            // In continuous scroll mode reading is vertical, so a horizontal swipe silently
            // skipping a chapter is never what the reader meant. Chapters are changed by
            // pulling past the end of the text instead (see ChapterPullTransitionController).
            disablePageTurnsWhileScrolling: true
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
            context.coordinator.syncScrollTransition(for: navigator)
            applyDecorations(highlights: highlights, to: navigator)
            navigator.observeDecorationInteractions(inGroup: "highlights") { [weak coordinator = context.coordinator] event in
                coordinator?.activateHighlight(id: event.decoration.id)
            }
            return navigator
        } catch {
            // Trapping here would crash the app on a book it simply cannot render.
            // `ReaderViewModel` already rejects restricted publications, so this is a
            // last resort: hand back an empty controller and surface the failure.
            Task { @MainActor in
                onOpenFailed("Failed to open this book: \(error.localizedDescription)")
            }
            return UIViewController()
        }
    }

    public func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard let uiViewController = uiViewController as? EPUBNavigatorViewController else { return }
        context.coordinator.parent = self

        if context.coordinator.lastPreferences != preferences {
            context.coordinator.lastPreferences = preferences
            uiViewController.submitPreferences(preferences)
        }
        
        context.coordinator.syncScrollTransition(for: uiViewController)
        context.coordinator.clearSelectionIfNeeded(hasSelection, in: uiViewController)
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
        private var didClearSelection = false
        private var pullTransition: ChapterPullTransitionController? = nil
        private var inFlightTarget: NavigationTarget? = nil

        /// Reading-order resources rarely carry a title; the table of contents does. Its
        /// entries often point at a fragment inside the resource, so they are keyed by the
        /// bare resource URL.
        private lazy var chapterTitles: [AnyURL: String] = {
            func flatten(_ links: [ReadiumShared.Link]) -> [AnyURL: String] {
                links.reduce(into: [AnyURL: String]()) { result, link in
                    if let title = link.title?.trimmingCharacters(in: .whitespacesAndNewlines),
                       !title.isEmpty {
                        result[link.url().removingQuery().removingFragment()] = title
                    }
                    result.merge(flatten(link.children)) { existing, _ in existing }
                }
            }
            return flatten(parent.tableOfContents)
        }()

        private enum NavigationTarget: Equatable {
            case link(ReadiumShared.Link)
            case locator(Locator)
        }

        init(_ parent: EPUBNavigatorRepresentable) {
            self.parent = parent
        }

        func activateHighlight(id: String) {
            HapticManager.shared.selection()
            parent.onSelectionChanged(nil)
            parent.onHighlightActivated(id)
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

        /// Mirrors the app's selection state back into the publication. `clearSelection()`
        /// evaluates JavaScript in every loaded spread, and `updateUIViewController` runs on
        /// every SwiftUI update, so the request is latched: it fires once per transition into
        /// "nothing selected" rather than on every progress tick.
        func clearSelectionIfNeeded(_ hasSelection: Bool, in navigator: EPUBNavigatorViewController) {
            guard !hasSelection else {
                didClearSelection = false
                return
            }
            guard !didClearSelection else { return }
            didClearSelection = true
            navigator.clearSelection()
        }

        func syncScrollTransition(for navigator: EPUBNavigatorViewController) {
            let controller = pullTransition ?? {
                let controller = ChapterPullTransitionController(navigator: navigator)
                pullTransition = controller
                return controller
            }()

            controller.chapterTitleProvider = { [weak self] href in
                self?.chapterTitles[href]
            }
            controller.setEnabled(parent.preferences.scroll == true)
            controller.refreshAttachments()
        }

        public func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
            ReaderLog.navigator.error("EPUB navigator error: \(error, privacy: .public)")
        }

        public func navigator(_ navigator: EPUBNavigatorViewController, setupUserScripts userContentController: WKUserContentController) {
            // Called while a new spread web view is being built. It is not in the view
            // hierarchy yet, so pick it up on the next runloop turn.
            DispatchQueue.main.async { [weak self] in
                self?.pullTransition?.refreshAttachments()
            }
        }

        /// - Important: The parameter type must be `Navigator`, not `VisualNavigator`.
        ///   `locationDidChange` is declared on `NavigatorDelegate`; declaring it with a
        ///   narrower type silently creates an unrelated method and Readium keeps calling
        ///   the empty default implementation, so no location is ever reported.
        public func navigator(_ navigator: Navigator, locationDidChange locator: Locator) {
            // In scroll mode the chapter haptic fires the moment the pull is released, which
            // is both earlier and more precise than reacting to the resulting href change.
            if parent.preferences.scroll != true,
               let previousHref = lastHref, previousHref != locator.href {
                HapticManager.shared.chapterChanged()
            }
            if lastHref != locator.href {
                pullTransition?.refreshAttachments()
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
            return false
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
