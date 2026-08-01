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

    public init(
        publication: Publication,
        initialLocation: Locator?,
        targetLink: ReadiumShared.Link? = nil,
        targetLocator: Locator? = nil,
        preferences: PDFPreferences = PDFPreferences(),
        onLocationChanged: @escaping (Locator) -> Void,
        onSelectionChanged: @escaping (Selection?) -> Void,
        onCenterTap: @escaping () -> Void
    ) {
        self.publication = publication
        self.initialLocation = initialLocation
        self.targetLink = targetLink
        self.targetLocator = targetLocator
        self.preferences = preferences
        self.onLocationChanged = onLocationChanged
        self.onSelectionChanged = onSelectionChanged
        self.onCenterTap = onCenterTap
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
    }

    public class Coordinator: NSObject, PDFNavigatorDelegate {
        var parent: PDFNavigatorRepresentable
        weak var navigator: PDFNavigatorViewController?
        var lastHandledLink: ReadiumShared.Link? = nil
        var lastHandledLocator: Locator? = nil
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
