import Foundation
import ReadiumNavigator

/// Coalesces the stream of callbacks one selection drag produces into the single selection it
/// means.
///
/// `shouldShowMenuForSelection` reads as "UIKit is about to show the edit menu, so the gesture is
/// over", and this repository said so in writing. It is not true. Dragging across a paragraph
/// fires it on every change to the selection — and returning `false` to suppress the menu seems
/// to make WebKit ask again — so one ordinary four-line drag fired it eight times. On EPUB, where
/// a selection *is* a highlight, that wrote eight overlapping quotes into the library and struck
/// the Taptic Engine eight times on the way past. The bug was found by driving a real drag on the
/// simulator and counting the rows afterwards; it does not show up by reading the code, because
/// the code is right about everything except how often it is called.
///
/// So the callback is treated as what it is — a stream — and the selection is acted on once it
/// stops moving.
@MainActor
final class SelectionSettle {
    /// Long enough to bridge the gaps inside one drag, which arrive milliseconds apart. Short
    /// enough that the mark still lands under the finger that made it.
    private static let quietPeriod = Duration.milliseconds(220)

    private var task: Task<Void, Never>?

    /// Whether a selection is on the page that the app has not been told about yet.
    ///
    /// The gap is the quiet period above, and something has to know about it: the publication
    /// has a selection from the first callback, while `currentSelection` — and therefore
    /// `hasSelection`, and therefore the request to clear it — only catches up 220 ms later.
    /// Anything that clears the selection because the app does not seem to have one has to wait
    /// this out, or it wipes the selection out from under the finger that is making it. See
    /// `EPUBNavigatorRepresentable.Coordinator.clearSelectionIfNeeded`.
    var isPending: Bool { task != nil }

    /// Runs `action` with the newest selection once the callbacks stop arriving.
    func settle(on selection: Selection, then action: @escaping (Selection) -> Void) {
        task?.cancel()
        task = Task { [weak self] in
            try? await Task.sleep(for: Self.quietPeriod)
            guard !Task.isCancelled else { return }
            self?.task = nil
            action(selection)
        }
    }

    /// The selection is gone — tapped away, or the page turned. Nothing pending should land.
    func cancel() {
        task?.cancel()
        task = nil
    }
}
