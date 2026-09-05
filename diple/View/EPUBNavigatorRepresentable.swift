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
    /// The one passage marked a moment ago, whose ink is still wet. See `InkHighlight`.
    public let freshHighlightID: String?
    public let livingMarginAnnotations: [LivingMarginAnnotation]
    public let tableOfContents: [ReadiumShared.Link]
    public let preferences: EPUBPreferences
    /// Line-breaking rules for the book's script. Not a user preference, so it travels
    /// separately from `preferences` and is read only when the navigator is created.
    public let rsProperties: CSSRSProperties
    /// Whether the app still considers a selection active. Dropping it clears the
    /// publication's own selection too, so dismissing the highlight bar takes the blue
    /// selection and the system edit menu with it.
    public let hasSelection: Bool
    public let onLocationChanged: (Locator) -> Void
    public let onSelectionChanged: (Selection?) -> Void
    public let onHighlightActivated: (String, CGRect?) -> Void
    public let onLivingMarginActivated: (String) -> Void
    public let onLivingMarginsEdgeSwipe: () -> Void
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
        freshHighlightID: String? = nil,
        livingMarginAnnotations: [LivingMarginAnnotation] = [],
        tableOfContents: [ReadiumShared.Link] = [],
        preferences: EPUBPreferences,
        rsProperties: CSSRSProperties = CSSRSProperties(),
        hasSelection: Bool = false,
        onLocationChanged: @escaping (Locator) -> Void,
        onSelectionChanged: @escaping (Selection?) -> Void,
        onHighlightActivated: @escaping (String, CGRect?) -> Void = { _, _ in },
        onLivingMarginActivated: @escaping (String) -> Void = { _ in },
        onLivingMarginsEdgeSwipe: @escaping () -> Void = {},
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
        self.freshHighlightID = freshHighlightID
        self.livingMarginAnnotations = livingMarginAnnotations
        self.tableOfContents = tableOfContents
        self.preferences = preferences
        self.rsProperties = rsProperties
        self.hasSelection = hasSelection
        self.onLocationChanged = onLocationChanged
        self.onSelectionChanged = onSelectionChanged
        self.onHighlightActivated = onHighlightActivated
        self.onLivingMarginActivated = onLivingMarginActivated
        self.onLivingMarginsEdgeSwipe = onLivingMarginsEdgeSwipe
        self.onCenterTap = onCenterTap
        self.onLinkJump = onLinkJump
        self.onTargetHandled = onTargetHandled
        self.onOpenFailed = onOpenFailed
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    public func makeUIViewController(context: Context) -> UIViewController {
        var decorationTemplates = HTMLDecorationTemplate.defaultTemplates()
        decorationTemplates[.livingMargin] = .livingMarginMarker()
        // The reader's own marks are drawn rather than switched on; see `InkHighlight`. Only
        // the highlight style is replaced — underline keeps Readium's, since nothing in diple
        // uses it and a second hand-written template would be a second thing to maintain.
        decorationTemplates[.highlight] = InkHighlight.template(defaultTint: .systemYellow)
        let config = EPUBNavigatorViewController.Configuration(
            preferences: preferences,
            // In continuous scroll mode reading is vertical, so a horizontal swipe silently
            // skipping a chapter is never what the reader meant. Chapters are changed by
            // pulling past the end of the text instead (see ChapterPullTransitionController).
            disablePageTurnsWhileScrolling: true,
            // Declared once, for every family the picker offers rather than only the selected
            // one: this is read when the navigator is built, and a live switch goes through
            // `submitPreferences`, which never revisits it.
            decorationTemplates: decorationTemplates,
            fontFamilyDeclarations: ReaderFontDeclarations.all,
            readiumCSSRSProperties: rsProperties
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
            context.coordinator.lastFreshHighlightID = freshHighlightID
            context.coordinator.lastLivingMarginAnnotations = livingMarginAnnotations
            context.coordinator.syncScrollTransition(for: navigator)
            #if !targetEnvironment(macCatalyst)
            context.coordinator.installLivingMarginsEdgePan(on: navigator.view)
            #endif
            applyDecorations(highlights: highlights, to: navigator)
            applyLivingMarginDecorations(livingMarginAnnotations, to: navigator)
            navigator.observeDecorationInteractions(inGroup: "highlights") { [weak coordinator = context.coordinator] event in
                // `rect` is the decoration's bounding box in the navigator's own coordinate
                // space — the same space `Selection.frame` arrived in — so the actions bar can
                // pick the far edge of the page from it exactly as the selection bar used to.
                coordinator?.activateHighlight(id: event.decoration.id, rect: event.rect)
            }
            navigator.observeDecorationInteractions(inGroup: "living-margins") { [weak coordinator = context.coordinator] event in
                coordinator?.activateLivingMargin(id: event.decoration.id)
            }
            context.coordinator.bindKeyboardPageTurns(to: navigator)
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
        } else if context.coordinator.lastFreshHighlightID != freshHighlightID {
            // The ink dried. Nothing about the passage changed, but what is being drawn did.
            context.coordinator.lastFreshHighlightID = freshHighlightID
            applyDecorations(highlights: highlights, to: uiViewController)
        }

        if context.coordinator.lastLivingMarginAnnotations != livingMarginAnnotations {
            context.coordinator.lastLivingMarginAnnotations = livingMarginAnnotations
            applyLivingMarginDecorations(livingMarginAnnotations, to: uiViewController)
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
                style: .highlight(tint: uiColor),
                // Freshness rides on the decoration rather than on the template, because the
                // template is built once and the passage that was just marked changes with
                // every mark. `userInfo` is the field Readium leaves to the app for exactly
                // this. See `InkHighlight` for why it must stop being fresh.
                userInfo: h.id == freshHighlightID ? [InkHighlight.freshKey: true] : [:]
            )
        }
        navigator.apply(decorations: decorations, in: "highlights")
    }

    private func applyLivingMarginDecorations(
        _ annotations: [LivingMarginAnnotation],
        to navigator: EPUBNavigatorViewController
    ) {
        navigator.apply(
            decorations: LivingMarginMarkerDecorations.make(from: annotations),
            in: "living-margins"
        )
    }

    public class Coordinator: NSObject, EPUBNavigatorDelegate, SelectableNavigatorDelegate, UIGestureRecognizerDelegate {
        var parent: EPUBNavigatorRepresentable
        weak var navigator: EPUBNavigatorViewController?
        /// Retained for as long as the navigator is: unbinding happens in its `deinit`.
        /// Catalyst only — see `bindKeyboardPageTurns`.
        private var directionalNavigation: DirectionalNavigationAdapter?
        var lastFreshHighlightID: String? = nil
        var lastHref: AnyURL? = nil
        var lastPreferences: EPUBPreferences? = nil
        var lastHighlights: [Highlight]? = nil
        var lastLivingMarginAnnotations: [LivingMarginAnnotation]? = nil
        private var didClearSelection = false
        private let selectionSettle = SelectionSettle()
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

        func activateHighlight(id: String, rect: CGRect?) {
            HapticManager.shared.selection()
            parent.onSelectionChanged(nil)
            parent.onHighlightActivated(id, rect)
        }

        func activateLivingMargin(id: String) {
            HapticManager.shared.impact(.light)
            parent.onSelectionChanged(nil)
            parent.onLivingMarginActivated(id)
        }

        /// The right-edge recognizer lives on the navigator itself, not in a transparent SwiftUI
        /// strip above it. It therefore participates in UIKit's gesture arbitration and can fail
        /// a vertical movement without stealing scrolling, selection or Readium's page taps.
        /// Arrow keys and the space bar turn pages, on the Mac.
        ///
        /// Readium's own adapter rather than a `keyboardShortcut` in SwiftUI, and not because
        /// it is shorter: once the page is drawn, the web view is first responder, and it
        /// consumes arrow keys for its own scrolling before any shortcut registered further up
        /// the chain is consulted. The adapter observes the navigator's input pipeline, which
        /// is downstream of that, and it already knows the publication's reading progression —
        /// so ← turns the right way in a right-to-left book without this file deciding what
        /// "forward" means.
        ///
        /// Pointer events are switched off deliberately. The adapter can also turn pages on a
        /// click near the viewport edge, but a click already means something here — the tap
        /// delegate toggles the reader's chrome — and two meanings for one click on a page is
        /// how a reader loses the controls they were reaching for.
        func bindKeyboardPageTurns(to navigator: EPUBNavigatorViewController) {
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

        func installLivingMarginsEdgePan(on view: UIView) {
            let recognizer = UIScreenEdgePanGestureRecognizer(
                target: self,
                action: #selector(handleLivingMarginsEdgePan(_:))
            )
            recognizer.edges = .right
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            view.addGestureRecognizer(recognizer)
        }

        @objc private func handleLivingMarginsEdgePan(_ recognizer: UIScreenEdgePanGestureRecognizer) {
            guard recognizer.state == .ended else { return }
            let translation = recognizer.translation(in: recognizer.view)
            let velocity = recognizer.velocity(in: recognizer.view)
            guard translation.x < -44,
                  abs(translation.x) > abs(translation.y),
                  velocity.x < 0
            else { return }
            HapticManager.shared.impact(.light)
            parent.onLivingMarginsEdgeSwipe()
        }

        public func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
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

        /// A typographic margin, and nothing else.
        ///
        /// Readium's own default is `max(window.safeAreaInsets, config.contentInset)` — it reads
        /// the *window's* insets deliberately, so an app's bars cannot shrink the margin it
        /// keeps for the notch (`EPUBNavigatorViewController.spreadViewContentInset`). The
        /// navigator's view no longer reaches the notch: `readerPageArea()` hands it the safe
        /// rect, because in scroll mode Readium's inset is a scroll inset and text slides under
        /// it instead of stopping. Left to the default, the same 59 pt would then be spent
        /// twice — once by the frame and once inside it — which in paginated mode is a fifth of
        /// the page given to blank paper.
        ///
        /// Returning a value here takes precedence over the whole computation
        /// (`VisualNavigatorDelegate.navigatorContentInset`), so what is left is the reason a
        /// content inset exists at all once the hardware is accounted for: room to breathe above
        /// the first line and below the last. It is the app's own gutter, not a number picked to
        /// look right on one handset.
        public func navigatorContentInset(_ navigator: VisualNavigator) -> UIEdgeInsets? {
            UIEdgeInsets(top: DipleSpace.xl, left: 0, bottom: DipleSpace.xl, right: 0)
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
            // The publication provably has a selection at this instant, whatever SwiftUI has
            // observed, so this is the honest place to re-arm the latch.
            //
            // It mattered more than it looks under save-on-selection, where `currentSelection`
            // was set and cleared inside one synchronous block and the view could skip the
            // render in which `hasSelection` was true — a latch armed only on that render
            // stayed shut, and the blue span and its handles were left sitting on a passage
            // that had already been saved. Deferred creation leaves the selection standing, so
            // that render does happen now; re-arming here is simply still correct, and cheaper
            // to keep than to reason about removing.
            didClearSelection = false
            // Once the drag settles, not on every report of it — see `SelectionSettle`. The
            // haptic waits with it: struck per callback it was a rattle, struck here it is the
            // one tap that says the passage is kept.
            selectionSettle.settle(on: selection) { [weak self] settled in
                HapticManager.shared.selection()
                self?.parent.onSelectionChanged(settled)
            }
            return false
        }

        public func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
            selectionSettle.cancel()
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

extension Decoration.Style.Id {
    /// Kept outside Readium's two built-in styles so the note marker can have its own HTML
    /// template without changing the appearance or activation area of the highlight beneath it.
    static let livingMargin = Decoration.Style.Id(rawValue: "living-margin")
}

/// Turns semantic note anchors into Readium decorations. The locator is copied verbatim and no
/// CGRect enters the model, which is the contract rotation and font-size tests lock down.
enum LivingMarginMarkerDecorations {
    static func make(from annotations: [LivingMarginAnnotation]) -> [Decoration] {
        annotations.map { annotation in
            Decoration(
                id: annotation.id,
                locator: annotation.locator,
                style: Decoration.Style(id: .livingMargin)
            )
        }
    }
}

private extension HTMLDecorationTemplate {
    /// A 44-point activation lane with a much smaller handwritten diple inside it. Readium
    /// places the full-width anchor at the locator's vertical range; CSS spends only the right
    /// page margin, so the marker travels with text without covering it.
    static func livingMarginMarker() -> HTMLDecorationTemplate {
        let label = String(
            localized: "Note attached",
            comment: "VoiceOver label for a Living Margins marker"
        ).livingMarginHTMLEscaped
        let hint = String(
            localized: "Show note",
            comment: "VoiceOver action hint for a Living Margins marker"
        ).livingMarginHTMLEscaped

        return HTMLDecorationTemplate(
            layout: .bounds,
            width: .page,
            element:
                """
                <div class="diple-living-margin-anchor">
                    <button class="diple-living-margin-marker" type="button"
                            data-activable="1" aria-label="\(label)" aria-description="\(hint)"></button>
                </div>
                """,
            stylesheet:
                """
                .diple-living-margin-anchor {
                    position: relative;
                    box-sizing: border-box;
                    overflow: visible;
                    pointer-events: none;
                    color: inherit;
                }

                .diple-living-margin-marker {
                    -webkit-appearance: none;
                    appearance: none;
                    position: absolute;
                    box-sizing: border-box;
                    width: 44px;
                    height: 44px;
                    right: max(2px, env(safe-area-inset-right));
                    top: -13px;
                    margin: 0;
                    padding: 0;
                    border: 0;
                    border-radius: 0;
                    background: transparent;
                    color: inherit;
                    opacity: 0.48;
                    pointer-events: auto;
                    transform: rotate(-2deg);
                    transition: opacity 120ms ease-out, transform 120ms ease-out;
                }

                .diple-living-margin-marker::before,
                .diple-living-margin-marker::after {
                    content: "";
                    position: absolute;
                    display: block;
                    height: 1.25px;
                    border-radius: 999px;
                    background: currentColor;
                    transform-origin: center;
                }

                .diple-living-margin-marker::before {
                    width: 18px;
                    right: 6px;
                    top: 17px;
                    transform: rotate(-28deg);
                }

                .diple-living-margin-marker::after {
                    width: 14px;
                    right: 9px;
                    top: 25px;
                    transform: rotate(28deg);
                }

                .diple-living-margin-marker:active {
                    opacity: 0.78;
                    transform: rotate(-2deg) scale(0.92);
                }

                @media (prefers-contrast: more) {
                    .diple-living-margin-marker { opacity: 0.78; }
                    .diple-living-margin-marker::before,
                    .diple-living-margin-marker::after { height: 1.75px; }
                }

                @media (prefers-reduced-motion: reduce) {
                    .diple-living-margin-marker { transition: none; }
                }
                """
        )
    }
}

private extension String {
    var livingMarginHTMLEscaped: String {
        replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
