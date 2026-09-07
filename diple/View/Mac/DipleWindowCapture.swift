#if targetEnvironment(macCatalyst)
import SwiftUI

/// Photographs the desktop's own key window, because nothing else on this machine can.
///
/// `screencapture` answers "could not create image from display" without Screen Recording
/// permission, and driving System Events through `osascript` is refused as well — so an agent
/// or a CI job working on the Mac layout has no way to see what it built. Every desktop change
/// before this one was verified by reading the code and hoping.
///
/// So the app takes the picture itself. DEBUG only, and inert unless `DIPLE_CAPTURE` names a
/// file. Three things about it are not obvious and each one costs a build cycle to rediscover:
///
/// - The app is sandboxed, so **only `NSTemporaryDirectory()` inside its own container** is
///   writable. A `try?` write anywhere else fails silently and leaves you looking for a file
///   that was never going to appear.
/// - `applicationDidBecomeActive` on a `@UIApplicationDelegateAdaptor` delegate is never
///   called here, so the hook hangs off the SwiftUI scene's `scenePhase` instead.
/// - **A Debug build needs well over ten seconds to settle.** Shot earlier, the sidebar has
///   updated and the middle column still shows the previous shelf — which reads exactly like a
///   state bug and is not one.
///
/// `DIPLE_CAPTURE_SOURCE` names the shelf to open at. A `MacCommand` posted from in here is the
/// other way to drive the shell, but the shelf has to be set before the first render for the
/// columns to agree by the time the shutter opens.
enum DipleWindowCapture {
    /// The file to write, relative to the app container's tmp directory. `nil` disables the
    /// whole thing, which is every run that is not someone looking at the desktop.
    static var requestedFilename: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["DIPLE_CAPTURE"]
        #else
        nil
        #endif
    }

    /// Which shelf the window should open at, for a capture that wants one particular screen.
    static var requestedSource: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["DIPLE_CAPTURE_SOURCE"]
        #else
        nil
        #endif
    }

    static func runIfRequested() {
        guard let filename = requestedFilename else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(14))
            guard let window = UIApplication.shared.connectedScenes
                .compactMap({ ($0 as? UIWindowScene)?.keyWindow })
                .first else { exit(2) }
            let image = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
                window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
            }
            let url = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(filename)
            try? image.pngData()?.write(to: url)
            exit(0)
        }
    }
}
#endif
