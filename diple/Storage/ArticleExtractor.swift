import Foundation
import SwiftSoup

/// Everything about an article that is not its body text.
public nonisolated struct ArticleMetadata: Sendable {
    public var title: String
    public var author: String?
    public var siteName: String?
    public var publishedAt: Date?
    /// BCP 47 tag from the page, handed to the EPUB so the reader hyphenates in the right
    /// language and so Korean and Russian pick the right font stack.
    public var language: String?
    public var canonicalURL: URL
    public var leadImageURL: URL?
    public var wordCount: Int

    /// Rounded up, never zero: "1 min read" on a very short piece is honest, "0 min" is not.
    public var readingMinutes: Int {
        max(1, Int((Double(wordCount) / 220.0).rounded(.up)))
    }
}

/// One image the article body points at, waiting to be downloaded.
public nonisolated struct ArticleImageSlot: Sendable {
    /// Position in the body, and the handle the body markup refers to it by.
    public let index: Int
    public let url: URL
}

/// A heading inside the article, so the reader's outline lists real sections instead of a
/// single "the whole thing" row.
public nonisolated struct ArticleSection: Sendable {
    public let id: String
    public let title: String
    public let level: Int
}

public nonisolated enum ArticleExtractionError: LocalizedError {
    case notHTML
    case noReadableContent

    public var errorDescription: String? {
        switch self {
        case .notHTML:
            return "That link doesn't point to a web page."
        case .noReadableContent:
            return "No readable article was found on that page."
        }
    }
}

/// Turns a fetched web page into the pieces an EPUB needs.
///
/// The body extraction follows the Readability approach: score every block of prose by how
/// much of it reads like prose, hand that score up to its ancestors, and keep the subtree that
/// wins. Scoring is used rather than a list of site-specific selectors because the selector
/// list is only ever correct for the sites somebody remembered to add.
///
/// The DOM is kept alive after extraction on purpose. Images cannot be resolved to local file
/// names until they have actually been downloaded, and a download can fail; rendering last
/// means a failed image is simply dropped from the markup instead of leaving a broken box on
/// the page.
public nonisolated final class ArticleExtractor {

    /// Blocks whose class or id says "this is not the article". Substring matching rather than
    /// a regular expression: every one of these is a literal, and a literal list stays
    /// readable and cannot fail to compile at runtime.
    private static let negativeHints = [
        "-ad-", "advert", "banner", "breadcrumb", "byline", "comment", "cookie", "disclaimer",
        "disqus", "footer", "gdpr", "masthead", "menu", "meta-", "newsletter", "paywall",
        "popup", "promo", "related", "share", "sidebar", "signup", "social", "sponsor",
        "subscribe", "toolbar", "widget"
    ]

    /// Words that mark a block as the article even when a negative hint also matches — a
    /// container called `post-body-with-comments` is still the post body.
    private static let positiveHints = [
        "article", "articlebody", "body", "content", "entry", "hentry", "main", "post",
        "prose", "story", "text"
    ]

    /// Non-whitelisted tags that stand for a block of the page, and so become a paragraph
    /// rather than being unwrapped into the text around them.
    private static let promotableToParagraph: Set<String> = [
        "div", "section", "article", "main", "center", "details", "summary"
    ]

    /// Only these tags may be deleted for matching a negative hint.
    ///
    /// Without this restriction the hint list reaches inside sentences. Towards Data Science
    /// wraps phrases in `<mdspan class="mdspan-comment">`, which matches `comment` — the first
    /// import of the sample article silently lost "It's likely that" and "heard about" from its
    /// opening line, and read as though the author had written it that way. A class name is a
    /// statement about a *block* of the page; on a run of inline text it is a coincidence.
    private static let removableByHint: Set<String> = [
        "div", "section", "aside", "nav", "header", "footer", "form", "ul", "ol", "dl",
        "table", "figure", "p", "h1", "h2", "h3", "h4", "h5", "h6"
    ]

    /// Containers that state outright what they hold. Checked before the scoring result and
    /// preferred when they carry nearly as much text, because a hand-authored wrapper reliably
    /// includes the figures and pull quotes that scoring tends to leave behind.
    private static let semanticSelectors = [
        "[itemprop=articleBody]",
        "article .entry-content",
        ".entry-content",
        ".post-content",
        ".article-content",
        ".article-body",
        ".post-body",
        "article",
        "main"
    ]

    /// Tags that survive into the EPUB. Anything else is unwrapped, keeping its children — a
    /// whitelist rather than a blacklist, because pages invent elements faster than anyone can
    /// enumerate them, and an unknown tag in the output is an unstyled tag.
    private static let allowedTags: Set<String> = Set([
        "p", "h1", "h2", "h3", "h4", "h5", "h6", "ul", "ol", "li", "blockquote", "pre", "code",
        "figure", "figcaption", "img", "a", "em", "strong", "i", "b", "u", "s", "sup", "sub",
        "br", "hr", "table", "thead", "tbody", "tfoot", "tr", "td", "th", "caption", "dl",
        "dt", "dd", "mark", "small", "cite", "q", "abbr", "time", "kbd", "samp", "var"
    ]).union(mathMLTags)

    /// MathML, kept whole rather than unwrapped.
    ///
    /// Unwrapping a formula does not degrade it, it destroys it: `<msup><mi>x</mi><mn>2</mn>`
    /// becomes the two characters `x2`, and a page of physics becomes a page of run-together
    /// letters that still reads like prose to everything downstream. WebKit has rendered
    /// MathML natively since long before this app's iOS 18 floor, and ReadiumCSS already ships
    /// a `math { font-family: … }` rule, so the formula only has to survive the sanitiser to
    /// arrive as a formula.
    static let mathMLTags: Set<String> = [
        "math", "semantics", "mrow", "mi", "mo", "mn", "ms", "mtext", "mspace", "msub", "msup",
        "msubsup", "munder", "mover", "munderover", "mfrac", "msqrt", "mroot", "mstyle",
        "merror", "mpadded", "mphantom", "mfenced", "menclose", "mtable", "mtr", "mtd",
        "mlabeledtr", "maction", "mmultiscripts", "mprescripts", "none", "malignmark",
        "maligngroup", "mglyph"
    ]

    /// Attributes MathML is allowed to keep. The list is shared by every element rather than
    /// written per tag: these are presentation attributes of one notation, and a formula that
    /// loses `stretchy` or `columnalign` is misdrawn rather than merely unstyled.
    private static let mathMLAttributes: Set<String> = [
        "display", "xmlns", "mathvariant", "mathsize", "displaystyle", "scriptlevel",
        "stretchy", "symmetric", "largeop", "movablelimits", "accent", "accentunder", "form",
        "lspace", "rspace", "linethickness", "notation", "open", "close", "separators",
        "columnalign", "rowalign", "columnspan", "rowspan", "columnspacing", "rowspacing",
        "align", "width", "height", "depth", "dir", "fence", "separator", "voffset"
    ]

    /// Tags removed outright, contents and all.
    ///
    /// `annotation` and `annotation-xml` are here, not merely off the whitelist: a LaTeXML page
    /// carries the TeX source of every formula inside `<semantics>` next to the MathML that
    /// draws it, and unwrapping it printed each formula twice — once as glyphs and once as
    /// `\mathcal{A}_{R}=\{a_{1},\ldots,a_{N}\}`. It is markup meant for a machine, and the
    /// only correct amount of it on the page is none.
    private static let strippedTags = [
        "script", "style", "noscript", "iframe", "form", "input", "textarea",
        "select", "button", "svg", "canvas", "audio", "video", "source", "track", "template",
        "link", "meta", "nav", "aside", "footer", "header", "dialog", "ins", "fieldset",
        "label", "annotation", "annotation-xml"
    ]

    /// Attributes kept per tag. Everything else goes: classes, inline styles, tracking data
    /// attributes, and the width/height pairs that fight the reader's own layout.
    private static let allowedAttributes: [String: Set<String>] = [
        "a": ["href"],
        "img": ["src", "alt"],
        "td": ["colspan", "rowspan"],
        "th": ["colspan", "rowspan"],
        "time": ["datetime"]
    ]

    private let document: Document
    private let root: Element
    private let requestURL: URL

    public let metadata: ArticleMetadata
    public let images: [ArticleImageSlot]
    public let sections: [ArticleSection]
    /// Clean prose after page chrome and the duplicate leading headline have been removed.
    public let searchableText: String

    // MARK: - Extraction

    public init(html: String, url: URL) throws {
        let document = try SwiftSoup.parse(html, url.absoluteString)
        self.document = document
        self.requestURL = url

        guard let body = document.body() else { throw ArticleExtractionError.notHTML }

        let head = Self.readHead(document: document, requestURL: url)

        try Self.stripNoise(in: body)
        guard let candidate = try Self.findContentRoot(in: body) else {
            throw ArticleExtractionError.noReadableContent
        }
        self.root = candidate

        self.images = try Self.normalizeImages(in: candidate, leadImageURL: head.leadImageURL)
        try Self.pruneToWhitelist(in: candidate)
        try Self.unwrapEquationTables(in: candidate)
        try Self.stripAttributes(in: candidate)
        try Self.namespaceMath(in: candidate)
        try Self.removeEmptyElements(in: candidate)

        let text = try candidate.text()
        guard text.count >= 200 else { throw ArticleExtractionError.noReadableContent }

        var metadata = head
        if metadata.title.isEmpty {
            metadata.title = try candidate.select("h1").first()?.text() ?? url.absoluteString
        }
        metadata.wordCount = text.split(whereSeparator: { $0 == " " || $0.isNewline }).count
        self.metadata = metadata

        // The page usually opens with its own headline. The EPUB prints the title in a header
        // block of its own, so leaving that one in place would show the title twice.
        try Self.removeLeadingTitleHeading(in: candidate, matching: metadata.title)
        self.sections = try Self.markSections(in: candidate)
        try Self.removeDeadFragmentLinks(in: candidate)
        self.searchableText = try candidate.text()
    }

    // MARK: - Rendering

    /// The article body as an XHTML fragment.
    ///
    /// `resolvedImages` maps a slot index to the path the image ended up at inside the EPUB.
    /// A slot missing from the map failed to download, and its `<img>` — together with an
    /// enclosing `<figure>` that would otherwise be left holding only a caption — is dropped.
    public func bodyXHTML(resolvedImages: [Int: String]) throws -> String {
        for slot in images {
            guard let element = try root.select("img[data-diple-image=\(slot.index)]").first() else {
                continue
            }
            if let path = resolvedImages[slot.index] {
                _ = try element.attr("src", path)
                _ = try element.removeAttr("data-diple-image")
            } else {
                let figure = Self.enclosingFigure(of: element)
                try (figure ?? element).remove()
            }
        }

        // XML syntax is what makes this XHTML rather than HTML: void elements close
        // themselves, and only the four entities XML defines survive by name.
        document.outputSettings()
            .syntax(syntax: .xml)
            .escapeMode(Entities.EscapeMode.xhtml)
            .prettyPrint(pretty: false)

        return try root.html()
    }

    private static func enclosingFigure(of image: Element) -> Element? {
        guard let parent = image.parent() else { return nil }
        return parent.tagNameNormal() == "figure" ? parent : nil
    }

    // MARK: - Head metadata

    private static func readHead(document: Document, requestURL: URL) -> ArticleMetadata {
        let siteName = meta(document, property: "og:site_name")
        var title = meta(document, property: "og:title")
            ?? meta(document, name: "twitter:title")
            ?? (try? document.title())
            ?? ""
        title = trimSiteSuffix(from: title, siteName: siteName ?? requestURL.host)

        let canonical = absoluteURL(
            (try? document.select("link[rel=canonical]").first()?.attr("abs:href")) ?? nil,
            relativeTo: requestURL
        ) ?? absoluteURL(meta(document, property: "og:url"), relativeTo: requestURL)
            ?? requestURL

        return ArticleMetadata(
            title: title.trimmingCharacters(in: .whitespacesAndNewlines),
            author: readAuthor(document),
            siteName: siteName ?? requestURL.host,
            publishedAt: readPublishedDate(document),
            language: readLanguage(document),
            canonicalURL: canonical,
            leadImageURL: absoluteURL(
                meta(document, property: "og:image") ?? meta(document, name: "twitter:image"),
                relativeTo: requestURL
            ),
            wordCount: 0
        )
    }

    /// A page title is very often `Real Title | Site Name`, and the site name is already shown
    /// separately on the card. Dropping it keeps a library grid from reading as one long
    /// column of the same publication name.
    private static func trimSiteSuffix(from title: String, siteName: String?) -> String {
        guard let siteName, !siteName.isEmpty else { return title }
        for separator in [" | ", " – ", " — ", " - ", " · ", " :: "] {
            let suffix = separator + siteName
            if title.lowercased().hasSuffix(suffix.lowercased()) {
                return String(title.dropLast(suffix.count))
            }
        }
        return title
    }

    private static func readAuthor(_ document: Document) -> String? {
        let candidates: [String?] = [
            meta(document, name: "author"),
            meta(document, property: "article:author"),
            meta(document, name: "twitter:data1"),
            try? document.select("[rel=author]").first()?.text(),
            try? document.select("[itemprop=author] [itemprop=name]").first()?.text(),
            try? document.select(".byline-name, .author-name, .p-author").first()?.text()
        ]

        for candidate in candidates {
            guard let value = candidate?.trimmingCharacters(in: .whitespacesAndNewlines),
                  !value.isEmpty,
                  value.count <= 120,
                  // `article:author` is a profile link on many sites, which is not a name.
                  !value.lowercased().hasPrefix("http")
            else { continue }
            return value
        }
        return nil
    }

    private static func readPublishedDate(_ document: Document) -> Date? {
        let raw: [String?] = [
            meta(document, property: "article:published_time"),
            meta(document, property: "og:article:published_time"),
            meta(document, name: "date"),
            try? document.select("time[datetime]").first()?.attr("datetime")
        ]

        let full = ISO8601DateFormatter()
        full.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        let dateOnly = ISO8601DateFormatter()
        dateOnly.formatOptions = [.withFullDate]

        for value in raw.compactMap({ $0 }) where !value.isEmpty {
            if let date = full.date(from: value) ?? plain.date(from: value) ?? dateOnly.date(from: value) {
                return date
            }
        }
        return nil
    }

    private static func readLanguage(_ document: Document) -> String? {
        if let lang = try? document.select("html").first()?.attr("lang"), !lang.isEmpty {
            return lang
        }
        // `og:locale` is underscored (`en_US`); BCP 47 wants a hyphen.
        if let locale = meta(document, property: "og:locale"), !locale.isEmpty {
            return locale.replacingOccurrences(of: "_", with: "-")
        }
        return nil
    }

    private static func meta(_ document: Document, property: String) -> String? {
        nonEmpty(try? document.select("meta[property=\(property)]").first()?.attr("content"))
    }

    private static func meta(_ document: Document, name: String) -> String? {
        nonEmpty(try? document.select("meta[name=\(name)]").first()?.attr("content"))
    }

    private static func nonEmpty(_ value: String??) -> String? {
        guard let value = value ?? nil else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func absoluteURL(_ value: String?, relativeTo base: URL) -> URL? {
        guard let value, !value.isEmpty else { return nil }
        return URL(string: value, relativeTo: base)?.absoluteURL
    }

    // MARK: - Noise removal

    private static func stripNoise(in body: Element) throws {
        try liftEmbeddedImages(in: body)

        for tag in strippedTags {
            for element in try body.select(tag) where element.parent() != nil {
                try element.remove()
            }
        }

        for element in try body.select("[aria-hidden=true], [hidden], [role=navigation], [role=banner], [role=complementary]")
        where element.parent() != nil {
            try element.remove()
        }

        // Class- and id-based removal runs before scoring, so a sidebar full of teaser
        // paragraphs cannot out-score the article it sits next to.
        for element in try body.select("*") where element.parent() != nil {
            guard removableByHint.contains(element.tagNameNormal()) else { continue }
            let hint = hints(for: element)
            guard containsAny(hint, negativeHints), !containsAny(hint, positiveHints) else { continue }
            try element.remove()
        }
    }

    /// Turns the other ways a page can point at a picture into an `<img>`, then drops the
    /// wrappers that are left.
    ///
    /// arXiv's LaTeXML output publishes every plotted figure as
    /// `<object type="image/svg+xml" data="…svg">`, so an `<object>` deleted with its contents
    /// took all seven figures of a paper with it and left the captions behind, describing
    /// nothing. `<picture>` is the same mistake in the opposite direction — it is a *wrapper*
    /// around an ordinary `<img>`, and removing it contents-and-all threw away the image it
    /// exists to select. It is now simply unwrapped by the whitelist pass, and only its
    /// `<source>` children are dropped.
    private static func liftEmbeddedImages(in body: Element) throws {
        for element in try body.select("object, embed") where element.parent() != nil {
            let type = (try element.attr("type")).lowercased()
            let source = element.tagNameNormal() == "object"
                ? try element.attr("data")
                : try element.attr("src")

            guard type.hasPrefix("image/") || isImagePath(source) else {
                try element.remove()
                continue
            }

            let image = try element.ownerDocument()?.createElement("img")
            guard let image else {
                try element.remove()
                continue
            }
            // `absUrl` resolves against the document's base, exactly as `<img src>` would.
            let absolute = element.tagNameNormal() == "object"
                ? try element.absUrl("data")
                : try element.absUrl("src")
            _ = try image.attr("src", absolute.isEmpty ? source : absolute)
            if let alt = try? element.attr("alt"), !alt.isEmpty {
                _ = try image.attr("alt", alt)
            }
            try element.replaceWith(image)
        }
    }

    private static func isImagePath(_ value: String) -> Bool {
        let path = (URL(string: value)?.path ?? value).lowercased()
        return [".svg", ".png", ".jpg", ".jpeg", ".gif", ".webp"].contains { path.hasSuffix($0) }
    }

    private static func hints(for element: Element) -> String {
        let className = (try? element.attr("class")) ?? ""
        return (className + " " + element.id()).lowercased()
    }

    private static func containsAny(_ haystack: String, _ needles: [String]) -> Bool {
        needles.contains { haystack.contains($0) }
    }

    // MARK: - Content scoring

    private static func findContentRoot(in body: Element) throws -> Element? {
        let scored = try scoredCandidate(in: body)
        let semantic = try semanticCandidate(in: body)

        switch (scored, semantic) {
        case let (scored?, semantic?):
            let scoredLength = try scored.text().count
            let semanticLength = try semantic.text().count
            // The hand-authored container wins ties and near-ties: it is the one that also
            // holds the figures, captions and pull quotes, which score poorly as prose but are
            // very much part of the article.
            return Double(semanticLength) >= Double(scoredLength) * 0.75 ? semantic : scored
        case let (scored?, nil):
            return scored
        case let (nil, semantic?):
            return semantic
        case (nil, nil):
            return nil
        }
    }

    private static func semanticCandidate(in body: Element) throws -> Element? {
        for selector in semanticSelectors {
            guard let element = try body.select(selector).first() else { continue }
            if try element.text().count >= 400 { return element }
        }
        return nil
    }

    /// Readability's scoring: prose blocks earn points, ancestors collect what their
    /// descendants earned at a discount per level, and the best-scoring ancestor is the
    /// article.
    private static func scoredCandidate(in body: Element) throws -> Element? {
        var scores: [ObjectIdentifier: Double] = [:]
        var elements: [ObjectIdentifier: Element] = [:]

        for block in try body.select("p, pre, td, blockquote") {
            let text = try block.text()
            guard text.count >= 25 else { continue }

            // Length and punctuation are the two cheap signals that separate written prose
            // from a stack of labels and link text.
            var score = 1.0
            score += Double(text.filter { $0 == "," || $0 == "，" || $0 == "、" }.count)
            score += min(Double(text.count) / 100.0, 3.0)

            var ancestor = block.parent()
            var level = 0
            while let current = ancestor, level < 3, current !== body.ownerDocument() {
                let key = ObjectIdentifier(current)
                if elements[key] == nil {
                    elements[key] = current
                    scores[key] = baseScore(for: current)
                }
                let divider = level == 0 ? 1.0 : (level == 1 ? 2.0 : 6.0)
                scores[key, default: 0] += score / divider

                ancestor = current.parent()
                level += 1
            }
        }

        var best: (element: Element, score: Double)? = nil
        for (key, element) in elements {
            guard let raw = scores[key] else { continue }
            // A block that is mostly anchors is a navigation list, however long it is.
            let final = raw * (1.0 - (try linkDensity(of: element)))
            if best == nil || final > (best?.score ?? 0) {
                best = (element, final)
            }
        }

        guard var candidate = best?.element, var bestScore = best?.score else { return nil }

        // Climb while the parent scores at least as well. The scoring loop credits the
        // immediate wrapper of each paragraph most heavily, which on many sites is a column
        // div holding half the article; the parent that holds all of it scores lower per
        // paragraph but higher in total.
        while let parent = candidate.parent(), parent !== body {
            let key = ObjectIdentifier(parent)
            guard let raw = scores[key] else { break }
            let final = raw * (1.0 - (try linkDensity(of: parent)))
            guard final >= bestScore else { break }
            candidate = parent
            bestScore = final
        }

        return candidate
    }

    private static func baseScore(for element: Element) -> Double {
        var score: Double
        switch element.tagNameNormal() {
        case "div", "section", "article", "main": score = 5
        case "pre", "td", "blockquote": score = 3
        case "address", "ol", "ul", "dl", "dd", "dt", "li", "form": score = -3
        case "h1", "h2", "h3", "h4", "h5", "h6", "th": score = -5
        default: score = 0
        }

        let hint = hints(for: element)
        if containsAny(hint, positiveHints) { score += 25 }
        if containsAny(hint, negativeHints) { score -= 25 }
        return score
    }

    private static func linkDensity(of element: Element) throws -> Double {
        let total = try element.text().count
        guard total > 0 else { return 0 }
        var linked = 0
        for anchor in try element.select("a") {
            linked += try anchor.text().count
        }
        return min(Double(linked) / Double(total), 1.0)
    }

    // MARK: - Images

    /// Resolves every usable image to an absolute URL and tags it with the slot the downloader
    /// will fill. Lazy-loading attributes are checked before `src`, because on a lazy-loading
    /// page `src` is a placeholder and the real image is parked in a data attribute.
    private static func normalizeImages(in root: Element, leadImageURL: URL?) throws -> [ArticleImageSlot] {
        var slots: [ArticleImageSlot] = []
        var seen: Set<String> = []
        // The lead image is rendered in the title block; keeping the page's own copy as well
        // would open every article with the same picture twice.
        if let leadImageURL { seen.insert(imageIdentity(of: leadImageURL)) }

        for image in try root.select("img") where image.parent() != nil {
            guard let url = try resolvedImageURL(for: image) else {
                try (enclosingFigure(of: image) ?? image).remove()
                continue
            }

            guard seen.insert(imageIdentity(of: url)).inserted else {
                try (enclosingFigure(of: image) ?? image).remove()
                continue
            }

            let slot = ArticleImageSlot(index: slots.count, url: url)
            slots.append(slot)
            _ = try image.attr("data-diple-image", String(slot.index))
            _ = try image.attr("src", url.absoluteString)
        }

        return slots
    }

    /// A key that is equal for two URLs pointing at the same picture in different renditions.
    ///
    /// The sample article is the ordinary case: `og:image` is
    /// `…_1472x986-copy.jpg` on the site's own host, while the body carries
    /// `…_1472x986-1024x686.webp` from the CDN. Comparing URLs finds nothing in common and the
    /// piece opens with its lead picture printed twice. Stripping the rendition suffixes that
    /// WordPress and its imitators append leaves the same stem for both.
    ///
    /// Short stems (`image`, `cover`, `1`) are too generic to be identity, so those fall back
    /// to the full URL — a false merge silently deletes a real figure, which is much worse than
    /// a duplicate.
    static func imageIdentity(of url: URL) -> String {
        var stem = url.deletingPathExtension().lastPathComponent.lowercased()

        // Two passes: a name can carry both a rendition and a marker, in either order.
        for _ in 0..<2 {
            if let range = stem.range(of: "-[0-9]{2,5}x[0-9]{2,5}$", options: .regularExpression) {
                stem.removeSubrange(range)
            }
            for suffix in ["-copy", "-scaled", "-thumbnail", "-large", "-medium", "-small"]
            where stem.hasSuffix(suffix) {
                stem.removeLast(suffix.count)
            }
        }

        return stem.count >= 12 ? stem : url.absoluteString.lowercased()
    }

    private static func resolvedImageURL(for image: Element) throws -> URL? {
        // A spacer or a tracking pixel announces itself in its own attributes.
        if let width = Int(try image.attr("width")), width > 0, width <= 4 { return nil }
        if let height = Int(try image.attr("height")), height > 0, height <= 4 { return nil }

        for attribute in ["data-src", "data-original", "data-lazy-src", "src"] {
            let raw = try image.attr(attribute)
            guard !raw.isEmpty, !raw.hasPrefix("data:") else { continue }
            let absolute = try image.absUrl(attribute)
            if let url = URL(string: absolute.isEmpty ? raw : absolute),
               url.scheme == "http" || url.scheme == "https" {
                return url
            }
        }

        // `srcset` is a list of `url descriptor` pairs; the last entry is the widest.
        for attribute in ["srcset", "data-srcset"] {
            let raw = try image.attr(attribute)
            guard !raw.isEmpty else { continue }
            let best = raw
                .split(separator: ",")
                .compactMap { $0.trimmingCharacters(in: .whitespaces).split(separator: " ").first }
                .last
            if let best, let url = URL(string: String(best), relativeTo: URL(string: image.getBaseUri()))?.absoluteURL,
               url.scheme == "http" || url.scheme == "https" {
                return url
            }
        }

        return nil
    }

    // MARK: - Structural cleanup

    private static func pruneToWhitelist(in root: Element) throws {
        // Deepest first, so unwrapping a wrapper never invalidates a node still to be visited.
        for element in try root.select("*").array().reversed() where element.parent() != nil {
            guard element !== root else { continue }
            let tag = element.tagNameNormal()
            guard !allowedTags.contains(tag) else { continue }

            // A bare div of running text is a paragraph that was never marked up as one;
            // unwrapping it would merge it into whatever came before.
            //
            // Only a block-level container earns that promotion. Doing it for any unknown tag
            // puts a `<p>` inside a `<p>`: Towards Data Science wraps phrases in `<mdspan>`,
            // and promoting those split the opening sentence into three paragraphs.
            if promotableToParagraph.contains(tag),
               try isInlineOnlyBlock(element),
               try !element.text().isEmpty {
                _ = try element.tagName("p")
                continue
            }
            _ = try element.unwrap()
        }
    }

    /// Turns a table that is really a display equation back into a block of prose.
    ///
    /// LaTeX-to-HTML converters lay every numbered and centred formula out as a one-row table:
    /// an empty padding cell, the formula, another empty cell, and sometimes `(3)` in a fourth.
    /// Kept as a table it inherits the full-width rules and the cell hairlines meant for data,
    /// so a paper's every equation arrived underlined and stretched across the measure.
    ///
    /// The test is structural, not a class name: a table with no header cells whose cells hold
    /// block-level math is a layout, because a real data table does not set its cells in
    /// display style. Each row becomes one paragraph, the padding cells go, and a short
    /// non-mathematical cell — the equation number — is kept at the end of its own row, since
    /// the prose around it refers to it.
    private static func unwrapEquationTables(in root: Element) throws {
        for table in try root.select("table").array().reversed() where table.parent() != nil {
            guard try table.select("th").isEmpty(),
                  try !table.select("math[display=block]").isEmpty()
            else { continue }

            var paragraphs: [Element] = []
            for row in try table.select("tr") {
                guard let paragraph = try root.ownerDocument()?.createElement("p") else { continue }
                for cell in try row.select("td") {
                    guard try !cell.text().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                        || !cell.select("math").isEmpty()
                    else { continue }
                    for node in cell.getChildNodes() {
                        try paragraph.appendChild(node)
                    }
                }
                if try !paragraph.text().trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                    || !paragraph.select("math").isEmpty() {
                    paragraphs.append(paragraph)
                }
            }

            guard let first = paragraphs.first else {
                try table.remove()
                continue
            }
            try table.replaceWith(first)
            var previous = first
            for paragraph in paragraphs.dropFirst() {
                try previous.after(paragraph)
                previous = paragraph
            }
        }
    }

    /// Declares the MathML namespace on every formula.
    ///
    /// The body is serialised as XHTML, where an element belongs to the namespace it declares
    /// and to nothing else. An HTML parser puts a bare `<math>` in the MathML namespace by
    /// rule; an XML one puts it in whatever its ancestors declare, which here is XHTML — the
    /// formula would arrive as a tree of unknown inline elements and render as run-together
    /// letters, which is the exact failure the whitelist change was made to fix.
    private static func namespaceMath(in root: Element) throws {
        for math in try root.select("math") {
            _ = try math.attr("xmlns", mathMLNamespace)
        }
    }

    static let mathMLNamespace = "http://www.w3.org/1998/Math/MathML"

    /// Unwraps links that point inside the document at an anchor no longer there.
    ///
    /// Every `id` in the body is stripped except the ones `markSections` writes, so a paper's
    /// `Cited by: §1.1` and its footnote markers all became links to nothing. A link that does
    /// nothing when tapped is worse than the words alone, and the words are what was being
    /// said.
    private static func removeDeadFragmentLinks(in root: Element) throws {
        // Compared as strings rather than looked up with a `#id` selector: a LaTeXML anchor is
        // `#S1.SS1.p1.1`, and every dot in it would be read as a class by the CSS parser.
        var liveIDs: Set<String> = []
        for element in try root.select("[id]") {
            liveIDs.insert(try element.attr("id"))
        }

        for anchor in try root.select("a") where anchor.parent() != nil {
            let href = try anchor.attr("href")
            guard href.hasPrefix("#") else { continue }
            let fragment = String(href.dropFirst())
            if fragment.isEmpty || !liveIDs.contains(fragment) {
                _ = try anchor.unwrap()
            }
        }
    }

    private static func isInlineOnlyBlock(_ element: Element) throws -> Bool {
        let blockChildren = try element.select("p, div, section, ul, ol, blockquote, pre, figure, table, h1, h2, h3, h4, h5, h6")
        return blockChildren.isEmpty()
    }

    private static func stripAttributes(in root: Element) throws {
        for element in try root.select("*") {
            let tag = element.tagNameNormal()
            let allowed = mathMLTags.contains(tag)
                ? mathMLAttributes
                : (allowedAttributes[tag] ?? [])
            // The downloader's own handle has to survive until the images are resolved.
            let keep = allowed.union(tag == "img" ? ["data-diple-image"] : [])
            guard let attributes = element.getAttributes() else { continue }
            for name in attributes.asList().map({ $0.getKey() }) where !keep.contains(name.lowercased()) {
                _ = try element.removeAttr(name)
            }
        }

        // An anchor with nowhere to go is decoration left over from a widget.
        for anchor in try root.select("a") where anchor.parent() != nil {
            if (try anchor.attr("href")).isEmpty {
                _ = try anchor.unwrap()
            }
        }
    }

    /// `<mprescripts/>`, `<none/>` and `<mspace/>` carry no text and are not media, but a
    /// formula that loses them is drawn wrong — they are position, not decoration. MathML is
    /// therefore skipped wholesale rather than each void element being listed.
    private static func removeEmptyElements(in root: Element) throws {
        let selfContained: Set<String> = ["img", "br", "hr", "td", "th"]
        for element in try root.select("*").array().reversed() where element.parent() != nil {
            let tag = element.tagNameNormal()
            guard element !== root, !selfContained.contains(tag), !mathMLTags.contains(tag)
            else { continue }
            let hasText = !(try element.text()).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let hasMedia = !(try element.select("img, br, hr").isEmpty())
            if !hasText && !hasMedia {
                try element.remove()
            }
        }
    }

    /// Drops the article's own headline when it opens the body and repeats the title. Only the
    /// first heading is considered: a later section that happens to be named after the piece
    /// is a real section and has to stay.
    private static func removeLeadingTitleHeading(in root: Element, matching title: String) throws {
        guard let heading = try root.select("h1, h2").first() else { return }
        let normalizedTitle = normalizedForComparison(title)
        guard !normalizedTitle.isEmpty,
              normalizedForComparison(try heading.text()) == normalizedTitle
        else { return }
        try heading.remove()
    }

    private static func normalizedForComparison(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .components(separatedBy: .alphanumerics.inverted)
            .joined()
    }

    /// Gives every heading an anchor and reports them, so the EPUB navigation document can
    /// list the article's own sections.
    private static func markSections(in root: Element) throws -> [ArticleSection] {
        var sections: [ArticleSection] = []
        for heading in try root.select("h1, h2, h3") {
            let title = try heading.text().trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty else { continue }
            let id = "section-\(sections.count + 1)"
            _ = try heading.attr("id", id)

            // The article's own `h1` repeats the title we already print in the header block,
            // so it is levelled with the section headings rather than competing with it.
            let level = heading.tagNameNormal() == "h3" ? 2 : 1
            sections.append(ArticleSection(id: id, title: title, level: level))
        }
        return sections
    }
}
