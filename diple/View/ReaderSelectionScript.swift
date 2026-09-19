import Foundation

/// The second half of the selection conversation: the page telling the app when its selection is
/// gone.
///
/// Readium reports a selection (`shouldShowMenuForSelection`) but never reports its absence — the
/// toolkit clears its own `editingActions.selection` and says nothing — so the app could only
/// find out by taking the tap itself, with a transparent layer over the whole page. That layer is
/// what made a selection impossible to adjust: it sat above the web view, so the grab handles at
/// the ends of the passage could not be touched, and a passage that came out a word short had to
/// be dropped and made again.
///
/// A page that says "my selection just collapsed" costs nothing and gives the layer back. WebKit
/// already dismisses a selection when the page is tapped or scrolled — which is also why the same
/// tap does not raise the reader's bars: `gestures.js` reports pointer events as cancelled while a
/// selection is live, so the first tap only takes the selection away, exactly as it did before.
enum ReaderSelectionScript {
    /// The bridge the page posts a collapse on.
    static let messageName = "dipleSelection"

    static var source: String {
        """
        (function () {
            var wasCollapsed = true;

            function onSelectionChange() {
                var selection = window.getSelection();
                var collapsed = !selection
                    || selection.isCollapsed
                    || selection.toString().trim().length === 0;

                // Only the edge matters, and only this one. `selectionchange` fires on every
                // character a drag crosses; the app is told once, when the passage stops
                // existing.
                if (collapsed === wasCollapsed) { return; }
                wasCollapsed = collapsed;
                if (!collapsed) { return; }

                window.webkit.messageHandlers.\(messageName).postMessage({ collapsed: true });
            }

            document.addEventListener("selectionchange", onSelectionChange, false);
        })();
        """
    }
}
