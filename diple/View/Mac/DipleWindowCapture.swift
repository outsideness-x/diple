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
/// - **The reader does not come out.** Readium's page is a `WKWebView`, which draws out of
///   process, and `drawHierarchy` returns its frame empty: an open book photographs as a blank
///   page under its own chrome. Shelves, boards and the notes columns are all ordinary views.
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

    /// A place in the notes workshop to stand on: `inbox`, `today`, `tasks`, `journal`,
    /// `allNotes`, `trash`, or `space:<name>`. Applied once the workshop has loaded, because a space is known by name
    /// here and by id in the window.
    static var requestedPlace: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["DIPLE_CAPTURE_PLACE"]
        #else
        nil
        #endif
    }

    /// The start of a note's title, to open that note in the editor column.
    static var requestedNote: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["DIPLE_CAPTURE_NOTE"]
        #else
        nil
        #endif
    }

    /// The start of a book's title, to select that book on the shelf so the inspector describes it.
    static var requestedBook: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["DIPLE_CAPTURE_BOOK"]
        #else
        nil
        #endif
    }

    /// The start of a passage's text, to select it on the Highlights board so the inspector shows it.
    static var requestedPassage: String? {
        #if DEBUG
        ProcessInfo.processInfo.environment["DIPLE_CAPTURE_PASSAGE"]
        #else
        nil
        #endif
    }

    /// The window's content size in points, as `1280x800`. macOS restores whatever size the window
    /// last had, so a set of photographs taken on different days would otherwise not share a frame.
    /// App Store frames are 16:10; at @2x, 1440x900 is exactly 2880x1800.
    static var requestedSize: CGSize? {
        #if DEBUG
        guard let raw = ProcessInfo.processInfo.environment["DIPLE_CAPTURE_SIZE"] else { return nil }
        let parts = raw.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        return CGSize(width: parts[0], height: parts[1])
        #else
        nil
        #endif
    }

    static func runIfRequested() {
        guard let filename = requestedFilename else { return }
        Task { @MainActor in
            if let size = requestedSize,
               let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first {
                // A geometry request alone is ignored once macOS has restored a frame; pinning both
                // restrictions to the size is what makes the window give way. Now and then the
                // content lands a titlebar's height low under a black band — take that one again.
                try? await Task.sleep(for: .seconds(1))
                scene.sizeRestrictions?.minimumSize = size
                scene.sizeRestrictions?.maximumSize = size
                let origin = scene.effectiveGeometry.systemFrame.origin
                scene.requestGeometryUpdate(.Mac(systemFrame: CGRect(origin: origin, size: size)))
            }
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
