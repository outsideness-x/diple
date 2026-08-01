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

    public init(
        publication: Publication,
        initialLocation: Locator?,
        targetLink: ReadiumShared.Link? = nil,
        targetLocator: Locator? = nil,
        highlights: [Highlight] = [],
        preferences: EPUBPreferences,
        onLocationChanged: @escaping (Locator) -> Void,
        onSelectionChanged: @escaping (Selection?) -> Void,
        onCenterTap: @escaping () -> Void
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
            applyDecorations(highlights: highlights, to: navigator)
            return navigator
        } catch {
            fatalError("Failed to initialize EPUBNavigatorViewController: \(error)")
        }
    }

    public func updateUIViewController(_ uiViewController: EPUBNavigatorViewController, context: Context) {
        context.coordinator.parent = self
        uiViewController.submitPreferences(preferences)

        if let link = targetLink, context.coordinator.lastHandledLink != link {
            context.coordinator.lastHandledLink = link
            Task {
                _ = await uiViewController.go(to: link)
            }
        }

        if let locator = targetLocator, context.coordinator.lastHandledLocator != locator {
            context.coordinator.lastHandledLocator = locator
            Task {
                _ = await uiViewController.go(to: locator)
            }
        }

        applyDecorations(highlights: highlights, to: uiViewController)
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
        var lastHandledLink: ReadiumShared.Link? = nil
        var lastHandledLocator: Locator? = nil
        var lastHref: AnyURL? = nil

        init(_ parent: EPUBNavigatorRepresentable) {
            self.parent = parent
        }

        public func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
            print("Readium navigator error: \(error)")
        }

        public func navigator(_ navigator: VisualNavigator, locationDidChange locator: Locator) {
            if let previousHref = lastHref, previousHref != locator.href {
                HapticManager.shared.chapterChanged()
            }
            lastHref = locator.href
            parent.onLocationChanged(locator)
        }

        public func navigator(_ navigator: SelectableNavigator, shouldShowMenuForSelection selection: Selection) -> Bool {
            HapticManager.shared.selection()
            parent.onSelectionChanged(selection)
            return true
        }

        public func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
            parent.onSelectionChanged(nil)
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
