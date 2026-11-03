import Foundation

/// Teaches a spread's web view how to locate and visually mark the prose sentence under a tap
/// when language-learning mode is active.
///
/// The DOM side does what only the layout engine can do:
/// 1. Verify that the tap landed on an actual rendered glyph (and not in the page margins,
///    inter-paragraph space, or blank paper past the end of a short line).
/// 2. Flatten the enclosing prose block across inline markup (`<em>`, `<span>`, `<q>`, drop caps)
///    while skipping footnote reference markers (`epub:type="noteref"`, numeric `<sup>`s) and
///    ruby furigana (`<rt>`, `<rp>`), keeping an exact UTF-16 code-unit map back to each `Text`
///    node.
/// 3. Paint the sentence span returned by `SentenceTokenizer` as a non-interactive decoration
///    layer with inline `!important` styles (for the same ReadiumCSS reason documented in
///    `InkHighlightCSS`) without touching `window.getSelection()`, so a single tap never raises
///    the selection handles or the highlight actions bar.
enum ReaderSentenceScript {
    static var source: String {
        """
        (function () {
            var LAYER_ID = "diple-sentence-highlight-layer";
            var H_SLOP = 16;
            var V_SLOP = 10;
            var lastPointer = null;
            var activeSegments = [];

            function recordPointer(event) {
                if (event.pointerType === "mouse" && event.button !== 0) { return; }
                lastPointer = {
                    x: event.clientX,
                    y: event.clientY,
                    time: Date.now()
                };
            }

            document.addEventListener("pointerdown", recordPointer, true);
            document.addEventListener("pointerup", recordPointer, true);

            function clearHighlight() {
                var existing = document.getElementById(LAYER_ID);
                if (existing && existing.parentNode) {
                    existing.parentNode.removeChild(existing);
                }
            }

            document.addEventListener("selectionchange", function () {
                var sel = window.getSelection();
                if (sel && !sel.isCollapsed && sel.toString().trim().length > 0) {
                    clearHighlight();
                }
            }, false);

            window.addEventListener("resize", clearHighlight, false);

            function isInteractiveOrSkippedTarget(el) {
                if (!el || !el.closest) { return false; }
                var hit = el.closest(
                    'a[href], button, input, select, textarea, video, audio, img, svg, canvas, ' +
                    '[data-activable="1"], .diple-living-margin-marker'
                );
                if (hit) { return true; }
                return isExcludedFromProse(el);
            }

            function isExcludedFromProse(node) {
                var el = (node && node.nodeType === Node.ELEMENT_NODE) ? node : (node ? node.parentElement : null);
                while (el && el !== document.body && el !== document.documentElement) {
                    var tag = el.tagName ? el.tagName.toLowerCase() : "";
                    if (tag === "rt" || tag === "rp" || tag === "script" || tag === "style" || tag === "aside") {
                        return true;
                    }
                    if (el.id === LAYER_ID || el.dataset && el.dataset.group) {
                        return true;
                    }
                    var epubType = (el.getAttribute("epub:type") || "").toLowerCase();
                    var role = (el.getAttribute("role") || "").toLowerCase();
                    var cls = (el.className && typeof el.className === "string") ? el.className.toLowerCase() : "";
                    if (
                        epubType.indexOf("noteref") !== -1 ||
                        epubType.indexOf("footnote") !== -1 ||
                        epubType.indexOf("endnote") !== -1 ||
                        role.indexOf("noteref") !== -1 ||
                        role.indexOf("footnote") !== -1 ||
                        role.indexOf("endnote") !== -1
                    ) {
                        return true;
                    }
                    if (tag === "sup" || (tag === "a" && (cls.indexOf("footnote") !== -1 || cls.indexOf("noteref") !== -1 || cls.indexOf("fn") !== -1))) {
                        var t = (el.textContent || "").trim();
                        if (/^[\\[\\(]?(\\d+[a-z]?|[*†‡§‖#]+)[\\]\\)]?$/i.test(t)) {
                            return true;
                        }
                    }
                    el = el.parentElement;
                }
                return false;
            }

            var SEMANTIC_BLOCKS = {
                p: true, li: true, blockquote: true, dd: true, dt: true,
                h1: true, h2: true, h3: true, h4: true, h5: true, h6: true,
                figcaption: true, td: true, th: true, pre: true
            };

            var INLINE_DISPLAYS = {
                "inline": true,
                "inline-block": true,
                "inline-flex": true,
                "contents": true,
                "ruby": true,
                "ruby-base": true,
                "ruby-text": true
            };

            function isBlockElement(el) {
                if (!el || el.nodeType !== Node.ELEMENT_NODE) { return false; }
                var tag = el.tagName ? el.tagName.toLowerCase() : "";
                if (SEMANTIC_BLOCKS[tag]) { return true; }
                if (tag === "body" || tag === "article" || tag === "section" || tag === "main") { return true; }
                var disp = window.getComputedStyle(el).display || "inline";
                return !INLINE_DISPLAYS[disp];
            }

            function findProseBlock(startNode) {
                var el = (startNode && startNode.nodeType === Node.ELEMENT_NODE)
                    ? startNode
                    : (startNode ? startNode.parentElement : null);
                while (el && el !== document.body && el !== document.documentElement) {
                    var tag = el.tagName ? el.tagName.toLowerCase() : "";
                    if (SEMANTIC_BLOCKS[tag]) { return el; }
                    if (isBlockElement(el)) { return el; }
                    el = el.parentElement;
                }
                return document.body;
            }

            function rectDistSq(rect, x, y) {
                var dx = 0;
                if (x < rect.left) { dx = rect.left - x; }
                else if (x > rect.right) { dx = x - rect.right; }
                var dy = 0;
                if (y < rect.top) { dy = rect.top - y; }
                else if (y > rect.bottom) { dy = y - rect.bottom; }
                if (dx > H_SLOP || dy > V_SLOP) { return Infinity; }
                return dx * dx + dy * dy;
            }

            function charHitInTextNode(textNode, index, x, y) {
                var val = textNode.nodeValue || "";
                if (index < 0 || index >= val.length) { return Infinity; }
                var r = document.createRange();
                r.setStart(textNode, index);
                r.setEnd(textNode, index + 1);
                var rects = r.getClientRects();
                var best = Infinity;
                for (var i = 0; i < rects.length; i++) {
                    var cr = rects[i];
                    if (cr.width <= 0 && cr.height <= 0) { continue; }
                    var d = rectDistSq(cr, x, y);
                    if (d < best) { best = d; }
                }
                return best;
            }

            function findTappedChar(x, y) {
                if (document.caretRangeFromPoint) {
                    var caret = document.caretRangeFromPoint(x, y);
                    if (caret && caret.startContainer) {
                        var container = caret.startContainer;
                        var offset = caret.startOffset;
                        if (container.nodeType === Node.TEXT_NODE && !isExcludedFromProse(container)) {
                            var candidates = [offset, offset - 1, offset + 1];
                            var bestIdx = -1;
                            var bestDist = Infinity;
                            for (var c = 0; c < candidates.length; c++) {
                                var d = charHitInTextNode(container, candidates[c], x, y);
                                if (d < bestDist) {
                                    bestDist = d;
                                    bestIdx = candidates[c];
                                }
                            }
                            if (bestIdx !== -1) {
                                return { node: container, offset: bestIdx };
                            }
                        }
                    }
                }

                var hitEl = document.elementFromPoint(x, y);
                if (!hitEl) { return null; }
                var block = findProseBlock(hitEl);
                if (!block) { return null; }

                var walker = document.createTreeWalker(block, NodeFilter.SHOW_TEXT, null);
                var bestNode = null;
                var bestOffset = -1;
                var bestScore = Infinity;
                var node;
                while ((node = walker.nextNode())) {
                    if (isExcludedFromProse(node)) { continue; }
                    var len = (node.nodeValue || "").length;
                    if (len === 0) { continue; }
                    var nr = document.createRange();
                    nr.selectNodeContents(node);
                    var nbox = nr.getBoundingClientRect();
                    if (rectDistSq(nbox, x, y) === Infinity) { continue; }
                    for (var i = 0; i < len; i++) {
                        var score = charHitInTextNode(node, i, x, y);
                        if (score < bestScore) {
                            bestScore = score;
                            bestNode = node;
                            bestOffset = i;
                            if (score === 0) { break; }
                        }
                    }
                    if (bestScore === 0) { break; }
                }

                if (bestNode && bestOffset !== -1) {
                    return { node: bestNode, offset: bestOffset };
                }
                return null;
            }

            function buildBlockModel(block, targetNode, targetOffset) {
                var segments = [];
                var textParts = [];
                var totalLen = 0;
                var resolvedOffset = -1;

                function walk(node) {
                    if (!node) { return; }
                    if (node.nodeType === Node.TEXT_NODE) {
                        if (isExcludedFromProse(node)) { return; }
                        var raw = node.nodeValue || "";
                        if (raw.length === 0) { return; }
                        // Replace source-code newlines/tabs/NBSP with regular spaces so UTF-16
                        // code-unit length stays identical to `raw.length`.
                        var clean = raw.replace(/[\\r\\n\\t\\u00A0]/g, " ");
                        var start = totalLen;
                        var end = start + clean.length;
                        segments.push({
                            node: node,
                            textStart: start,
                            textEnd: end
                        });
                        if (node === targetNode) {
                            resolvedOffset = start + Math.min(Math.max(targetOffset, 0), clean.length);
                        }
                        textParts.push(clean);
                        totalLen = end;
                        return;
                    }

                    if (node.nodeType !== Node.ELEMENT_NODE) { return; }
                    var tag = node.tagName ? node.tagName.toLowerCase() : "";
                    if (tag === "br") {
                        textParts.push("\\n");
                        totalLen += 1;
                        return;
                    }
                    if (isExcludedFromProse(node)) { return; }
                    var style = window.getComputedStyle(node);
                    if (style.display === "none" || style.visibility === "hidden") { return; }

                    var isChildBlock = (node !== block) && isBlockElement(node);
                    if (isChildBlock && totalLen > 0) {
                        textParts.push("\\n");
                        totalLen += 1;
                    }

                    var children = node.childNodes;
                    for (var i = 0; i < children.length; i++) {
                        walk(children[i]);
                    }

                    if (isChildBlock && totalLen > 0) {
                        textParts.push("\\n");
                        totalLen += 1;
                    }
                }

                walk(block);
                return {
                    text: textParts.join(""),
                    offset: resolvedOffset,
                    segments: segments
                };
            }

            function resolveLang(el) {
                var cur = el;
                while (cur && cur.nodeType === Node.ELEMENT_NODE) {
                    var lang = cur.getAttribute("lang") || cur.getAttribute("xml:lang");
                    if (lang && lang.trim().length > 0) { return lang.trim(); }
                    cur = cur.parentElement;
                }
                var docLang = document.documentElement
                    ? (document.documentElement.getAttribute("lang") || document.documentElement.getAttribute("xml:lang"))
                    : "";
                return docLang || "";
            }

            function mergeLineRects(rects) {
                if (rects.length <= 1) { return rects; }
                var sorted = rects.slice().sort(function (a, b) {
                    if (Math.abs(a.top - b.top) > 5) { return a.top - b.top; }
                    return a.left - b.left;
                });
                var merged = [sorted[0]];
                for (var i = 1; i < sorted.length; i++) {
                    var cur = sorted[i];
                    var prev = merged[merged.length - 1];
                    var sameLine = Math.abs(cur.top - prev.top) <= 6 && Math.abs(cur.bottom - prev.bottom) <= 6;
                    var touches = cur.left <= prev.right + 8 && cur.right >= prev.left - 8;
                    if (sameLine && touches) {
                        var left = Math.min(prev.left, cur.left);
                        var top = Math.min(prev.top, cur.top);
                        var right = Math.max(prev.right, cur.right);
                        var bottom = Math.max(prev.bottom, cur.bottom);
                        merged[merged.length - 1] = {
                            left: left,
                            top: top,
                            right: right,
                            bottom: bottom,
                            width: right - left,
                            height: bottom - top
                        };
                    } else {
                        merged.push(cur);
                    }
                }
                return merged;
            }

            window.__dipleSentenceHitTest = function (fallbackX, fallbackY) {
                clearHighlight();
                activeSegments = [];

                var sel = window.getSelection();
                if (sel && !sel.isCollapsed && sel.toString().trim().length > 0) {
                    return null;
                }

                var now = Date.now();
                var useLast = lastPointer && (now - lastPointer.time < 900);
                var x = useLast ? lastPointer.x : fallbackX;
                var y = useLast ? lastPointer.y : fallbackY;

                var hitEl = document.elementFromPoint(x, y);
                if (!hitEl || isInteractiveOrSkippedTarget(hitEl)) {
                    return null;
                }

                var hit = findTappedChar(x, y);
                if (!hit || !hit.node) {
                    return null;
                }

                var block = findProseBlock(hit.node);
                if (!block) {
                    return null;
                }

                var model = buildBlockModel(block, hit.node, hit.offset);
                if (!model || model.offset < 0 || model.text.trim().length === 0) {
                    return null;
                }

                activeSegments = model.segments;
                return {
                    text: model.text,
                    offset: model.offset,
                    lang: resolveLang(block)
                };
            };

            window.__dipleHighlightSentenceRange = function (utf16Start, utf16End, isNight) {
                clearHighlight();
                if (!activeSegments || activeSegments.length === 0 || utf16End <= utf16Start) {
                    return null;
                }

                var rawRects = [];
                for (var i = 0; i < activeSegments.length; i++) {
                    var seg = activeSegments[i];
                    if (seg.textEnd <= utf16Start || seg.textStart >= utf16End) { continue; }
                    var nodeLen = (seg.node.nodeValue || "").length;
                    var s = Math.max(0, utf16Start - seg.textStart);
                    var e = Math.min(nodeLen, utf16End - seg.textStart);
                    if (e <= s) { continue; }
                    var r = document.createRange();
                    r.setStart(seg.node, s);
                    r.setEnd(seg.node, e);
                    var clientRects = r.getClientRects();
                    for (var j = 0; j < clientRects.length; j++) {
                        var cr = clientRects[j];
                        if (cr.width > 0.5 && cr.height > 0.5) {
                            rawRects.push({
                                left: cr.left,
                                top: cr.top,
                                right: cr.right,
                                bottom: cr.bottom,
                                width: cr.width,
                                height: cr.height
                            });
                        }
                    }
                }

                if (rawRects.length === 0) { return null; }

                var lineRects = mergeLineRects(rawRects);
                var scrollingElement = document.scrollingElement || document.documentElement;
                var xOffset = scrollingElement ? scrollingElement.scrollLeft : 0;
                var yOffset = scrollingElement ? scrollingElement.scrollTop : 0;

                var fill = isNight ? "rgba(229, 184, 82, 0.22)" : "rgba(212, 162, 58, 0.24)";
                var rule = isNight ? "rgba(229, 184, 82, 0.64)" : "rgba(176, 122, 24, 0.68)";

                var layer = document.createElement("div");
                layer.id = LAYER_ID;
                layer.style.cssText = "position: absolute !important; left: 0 !important; top: 0 !important; width: 0 !important; height: 0 !important; pointer-events: none !important; z-index: 2 !important;";

                for (var k = 0; k < lineRects.length; k++) {
                    var rect = lineRects[k];
                    var box = document.createElement("div");
                    box.style.cssText =
                        "position: absolute !important; " +
                        "pointer-events: none !important; " +
                        "box-sizing: border-box !important; " +
                        "border-radius: 3px !important; " +
                        "left: " + (rect.left + xOffset - 1) + "px !important; " +
                        "top: " + (rect.top + yOffset) + "px !important; " +
                        "width: " + (rect.width + 2) + "px !important; " +
                        "height: " + rect.height + "px !important; " +
                        "background-color: " + fill + " !important; " +
                        "border-bottom: 1.5px solid " + rule + " !important;";
                    layer.appendChild(box);
                }

                if (document.body) {
                    document.body.appendChild(layer);
                }
                return true;
            };

            window.__dipleClearSentenceHighlight = clearHighlight;
        })();
        """
    }
}
