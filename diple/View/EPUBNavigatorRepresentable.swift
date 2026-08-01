import SwiftUI
import UIKit
import ReadiumShared
import ReadiumNavigator

public struct EPUBNavigatorRepresentable: UIViewControllerRepresentable {
    public let publication: Publication
    public let initialLocation: Locator?
    public let targetLink: ReadiumShared.Link?
    public let preferences: EPUBPreferences
    public let onLocationChanged: (Locator) -> Void
    public let onCenterTap: () -> Void

    public init(
        publication: Publication,
        initialLocation: Locator?,
        targetLink: ReadiumShared.Link? = nil,
        preferences: EPUBPreferences,
        onLocationChanged: @escaping (Locator) -> Void,
        onCenterTap: @escaping () -> Void
    ) {
        self.publication = publication
        self.initialLocation = initialLocation
        self.targetLink = targetLink
        self.preferences = preferences
        self.onLocationChanged = onLocationChanged
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
    }

    public class Coordinator: NSObject, EPUBNavigatorDelegate {
        var parent: EPUBNavigatorRepresentable
        weak var navigator: EPUBNavigatorViewController?
        var lastHandledLink: ReadiumShared.Link? = nil

        init(_ parent: EPUBNavigatorRepresentable) {
            self.parent = parent
        }

        public func navigator(_ navigator: Navigator, presentError error: NavigatorError) {
            print("Readium navigator error: \(error)")
        }

        public func navigator(_ navigator: VisualNavigator, locationDidChange locator: Locator) {
            parent.onLocationChanged(locator)
        }

        public func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) {
            guard let view = navigator.view else { return }
            let width = view.bounds.width
            guard width > 0 else { return }

            let fraction = point.x / width
            if fraction < 0.33 {
                // Left third -> Go back
                Task {
                    _ = await navigator.goBackward()
                }
            } else if fraction > 0.66 {
                // Right third -> Go forward
                Task {
                    _ = await navigator.goForward()
                }
            } else {
                // Center third -> Toggle UI
                parent.onCenterTap()
            }
        }
    }
}
