// Measures the ink stroke in a real WebKit, which is the only place it can be measured.
//
// Run:  swiftc -o /tmp/ink-profile Scripts/ink-stroke-profile.swift diple/View/InkHighlightCSS.swift && /tmp/ink-profile
//
// Prints how much of each line is covered at points along the animation, so the easing can
// be chosen by looking at a hand's profile rather than at the name of a curve.

import AppKit
import WebKit

/// Samples the ink stroke in a real WebKit.
///
/// The animation clock is driven by hand through the Web Animations API rather than by waiting:
/// an offscreen web view is throttled — `currentTime` sat at 0 for a second and a half, which
/// reads exactly like a broken animation and is not one — and a harness that has to be
/// foreground to be right is a harness nobody runs twice. Setting `currentTime` is also exact,
/// so the numbers below are the animation's, not the scheduler's.
final class Harness: NSObject, WKNavigationDelegate {
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 380, height: 400))
    var done = false

    func run() {
        web.navigationDelegate = self
        let boxes = (0..<4).map { _ in
            InkHighlightCSS.element(ink: "rgba(255, 214, 10, 0.3)", isFresh: true)
        }.joined()
        let resting = InkHighlightCSS.element(ink: "rgba(255, 214, 10, 0.3)", isFresh: false)
        let html = """
        <!doctype html><html><head><meta charset="utf-8"><style>
        body { margin: 0; }
        #stroke > div, #resting > div { position: absolute; width: 300px; height: 20px; }
        #stroke > div:nth-child(1) { top: 0px } #stroke > div:nth-child(2) { top: 24px }
        #stroke > div:nth-child(3) { top: 48px } #stroke > div:nth-child(4) { top: 72px }
        #resting > div { top: 120px }
        \(InkHighlightCSS.stylesheet)
        </style></head><body><div id="stroke">\(boxes)</div><div id="resting">\(resting)</div></body></html>
        """
        web.loadHTMLString(html, baseURL: nil)
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        let js = """
        (function () {
          const lines = Array.from(document.querySelectorAll('#stroke > div'));
          const at = (t) => lines.map((el) => {
            const a = el.getAnimations()[0];
            if (!a) return "none";
            a.currentTime = t;
            return getComputedStyle(el).backgroundSize;
          });
          const resting = document.querySelector('#resting > div');
          return JSON.stringify({
            t0:   at(0),
            t60:  at(60),
            t130: at(130),
            t260: at(260),
            t1000: at(1000),
            resting: getComputedStyle(resting).backgroundColor + " / size " + getComputedStyle(resting).backgroundSize,
            restingAnimations: resting.getAnimations().length
          });
        })()
        """
        web.evaluateJavaScript(js) { value, error in
            if let error { print("error:", error) }
            if let json = value as? String,
               let data = json.data(using: .utf8),
               let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                for key in ["t0", "t60", "t130", "t260", "t1000"] {
                    let widths: [String] = (parsed[key] as? [String] ?? []).map { value in
                        value.split(separator: " ").first.map(String.init) ?? "?"
                    }
                    print(key.padding(toLength: 6, withPad: " ", startingAt: 0), "lines:", widths.joined(separator: "  "))
                }
                print("resting:", parsed["resting"] as? String ?? "?",
                      "animations:", parsed["restingAnimations"] as? Int ?? -1)
            }
            self.done = true
        }
    }
}

/// Top-level statements are only allowed in a file called `main.swift`, and this file is named
/// after what it does.
@main
enum InkStrokeProfile {
    static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        let harness = Harness()
        harness.run()
        while !harness.done && RunLoop.current.run(mode: .default, before: .distantFuture) {}
    }
}
