import Foundation

/// The one thing the page has to be taught: that tapping an illustration means opening it.
///
/// **Why script injection rather than Readium's own tap.** A tap on an `<img>` reaches the app
/// as an ordinary tap on the page — `findNearestInteractiveElement` in Readium's `dom.js` lists
/// the interactive tags and an image is not one of them — so by the time the app hears about it,
/// the reader's chrome has already been toggled or the page already turned. Readium's input
/// pipeline does carry the element under the pointer, but an observer added by the app is
/// appended *after* the navigator's own, and the navigator's runs first.
///
/// A listener in the **capture** phase on `document` runs before every bubble-phase listener
/// whatever the order of registration, which is exactly what Readium's own listeners are
/// (`gestures.js` registers them on `DOMContentLoaded` with `false`). So this stops the pointer
/// events for an image before they can become a page turn, and leaves every other tap on the
/// page untouched.
enum ReaderFigureScript {
    /// The bridge the page posts an opened figure to.
    static let messageName = "dipleFigure"

    /// Below this an image is a glyph, not a figure: a drop cap, an inline icon, the little
    /// arrow a publisher uses for a bullet. Opening one full-screen would be answering a tap
    /// nobody made.
    private static let minimumFigureSide = 64

    static var source: String {
        """
        (function () {
            var MIN_SIDE = \(minimumFigureSide);

            function figureUnder(target) {
                if (!target || !target.tagName) { return null; }
                if (target.tagName.toLowerCase() !== "img") { return null; }
                var box = target.getBoundingClientRect();
                if (box.width < MIN_SIDE || box.height < MIN_SIDE) { return null; }
                return target;
            }

            function onPointer(event) {
                var image = figureUnder(event.target);
                if (!image) { return; }

                // Readium listens on `document` in the bubble phase; stopping here is what keeps
                // this tap from also turning the page. The default action is left alone — this
                // does not prevent anything the page itself wanted to do.
                event.stopPropagation();

                if (event.type !== "click") { return; }

                window.webkit.messageHandlers.\(messageName).postMessage({
                    src: image.currentSrc || image.src || "",
                    alt: image.getAttribute("alt") || ""
                });
            }

            ["pointerdown", "pointerup", "pointercancel", "click"].forEach(function (name) {
                document.addEventListener(name, onPointer, true);
            });
        })();
        """
    }
}
