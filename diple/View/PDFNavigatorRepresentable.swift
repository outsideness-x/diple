import SwiftUI
import UIKit
import ReadiumShared
import ReadiumNavigator

public struct PDFNavigatorRepresentable: UIViewControllerRepresentable {
    public let publication: Publication
    public let initialLocation: Locator?
    public let targetLink: ReadiumShared.Link?
    public let targetLocator: Locator?
    public let preferences: PDFPreferences
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
        preferences: PDFPreferences = PDFPreferences(),
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

    public func makeUIViewController(context: Context) -> PDFNavigatorViewController {
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
            return navigator
        } catch {
            fatalError("Failed to initialize PDFNavigatorViewController: \(error)")
        }
    }

    public func updateUIViewController(_ uiViewController: PDFNavigatorViewController, context: Context) {
        context.coordinator.parent = self
        uiViewController.submitPreferences(preferences)

        if let link = targetLink {
            Task {
                _ = await uiViewController.go(to: link, options: NavigatorGoOptions(animated: true))
                await MainActor.run {
                    onTargetHandled()
                }
            }
        }

        if let locator = targetLocator {
            Task {
                _ = await uiViewController.go(to: locator, options: NavigatorGoOptions(animated: true))
                await MainActor.run {
                    onTargetHandled()
                }
            }
        }
    }

    public class Coordinator: NSObject, PDFNavigatorDelegate {
        var parent: PDFNavigatorRepresentable
        weak var navigator: PDFNavigatorViewController?
        var lastHref: AnyURL? = nil

        init(_ parent: PDFNavigatorRepresentable) {
            self.parent = parent
        }

        public func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
            print("Readium PDF navigator error: \(error)")
        }

        public func navigator(_ navigator: VisualNavigator, locationDidChange locator: Locator) {
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
