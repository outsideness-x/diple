import Foundation
import SwiftSoup

/// The words of a feed, without its markup and without the furniture publishers put around them.
///
/// A feed's description is written for a feed reader of 2005: HTML, a "Read more" link, a line
/// of WordPress boilerplate ("The post … appeared first on …"), a "Subscribe now" button. What
/// the reader is shown is the opening of the piece in plain paragraphs, which `IssueSheet` sets
/// in the work's own face. Everything here is pure and runs off the main actor.
public nonisolated enum FeedText {
    /// One piece of text a feed carries — a description or the content — read into paragraphs.
    public struct Body: Sendable, Equatable {
        public let paragraphs: [String]

        public init(paragraphs: [String]) {
            self.paragraphs = paragraphs
        }

        public init(html: String) {
            self.init(paragraphs: FeedText.paragraphs(fromHTML: html))
        }

        /// Plain text: a blank line ends a paragraph, a single line break does not — the arXiv
        /// API wraps its abstracts at eighty columns.
        public init(plain: String) {
            let blocks = plain
                .replacingOccurrences(of: "\r\n", with: "\n")
                .components(separatedBy: "\n\n")
                .map(FeedText.line)
                .filter { !$0.isEmpty }
            self.init(paragraphs: FeedText.withoutFurniture(blocks))
        }

        public var plainText: String { paragraphs.joined(separator: "\n\n") }

        public var isEmpty: Bool { paragraphs.isEmpty }

        /// The length of the whole piece, when this body plainly is the whole piece.
        ///
        /// Under three thousand characters it is taken for a teaser — the first paragraph and a
        /// link, which is what most magazines put in their feeds — and says nothing about length.
        public var fullLength: Int? {
            let count = paragraphs.reduce(0) { $0 + $1.count }
            return count >= 3_000 ? count : nil
        }
    }

    /// The most a summary carries: enough to know what the piece is about and whether to read
    /// it — a magazine's dek and the opening paragraphs — and never the whole essay a feed
    /// sometimes ships.
    static let summaryLimit = 1_600

    /// A paper's abstract is the thing itself, and is given whole up to this.
    static let abstractLimit = 4_000

    /// What the sheet prints: the description first — usually a dek written for exactly this —
    /// then, when the description is thin, the opening of the content, so a newsletter whose
    /// description is a one-line subtitle still says what the piece is about.
    public static func summary(preferring first: Body?, then second: Body?) -> String {
        var paragraphs = first?.paragraphs ?? []
        let opening = paragraphs.joined(separator: " ")
        if opening.count < 280, let second {
            for paragraph in second.paragraphs {
                // The dek is often the content's first sentence over again.
                if !opening.isEmpty, paragraph.hasPrefix(opening) || opening.hasPrefix(paragraph) { continue }
                paragraphs.append(paragraph)
            }
        }
        return limited(paragraphs, to: summaryLimit)
    }

    /// Paragraphs up to `limit` characters, cut between paragraphs where possible and at a word
    /// otherwise, with an ellipsis where something was left out.
    static func limited(_ paragraphs: [String], to limit: Int) -> String {
        var kept: [String] = []
        var used = 0
        for paragraph in paragraphs {
            if used + paragraph.count <= limit {
                kept.append(paragraph)
                used += paragraph.count
                continue
            }
            // Room for a meaningful part of the next paragraph, or none at all.
            let room = limit - used
            if room > 160 || kept.isEmpty {
                kept.append(cut(paragraph, at: max(room, 160)))
            }
            break
        }
        return kept.joined(separator: "\n\n")
    }

    /// The words of `text` up to `length` characters, ending on a whole word and an ellipsis.
    static func cut(_ text: String, at length: Int) -> String {
        guard text.count > length else { return text }
        let prefix = text.prefix(length)
        let end = prefix.lastIndex(where: { $0 == " " }) ?? prefix.endIndex
        let words = prefix[..<end].trimmingCharacters(in: .whitespacesAndNewlines.union(.punctuationCharacters))
        return words + "…"
    }

    /// A title or a name: entities decoded, any markup dropped, all whitespace one space.
    public static func line(_ text: String) -> String {
        var value = text
        if value.contains("<") || value.contains("&") {
            if let parsed = try? SwiftSoup.parseBodyFragment(value, "").text() {
                value = parsed
            }
        }
        return collapse(value)
    }

    static func collapse(_ text: String) -> String {
        text
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    // MARK: - HTML

    /// Elements whose text is not the writer's prose: media, captions, code that runs, the
    /// numbers of footnote references.
    private static let skipped: Set<String> = [
        "script", "style", "noscript", "img", "figure", "picture", "svg", "video", "audio",
        "iframe", "object", "embed", "form", "button", "input", "table", "sup", "math"
    ]

    /// Elements that end one paragraph and begin another.
    private static let blocks: Set<String> = [
        "p", "div", "li", "ul", "ol", "blockquote", "h1", "h2", "h3", "h4", "h5", "h6",
        "pre", "dd", "dt", "dl", "section", "article", "header", "footer", "hr", "tr"
    ]

    /// HTML read into paragraphs by walking it, rather than by selecting `p`: a magazine's dek
    /// often stands as bare text before the first `<p>`, and a selector would drop exactly the
    /// sentence the editor wrote for this.
    static func paragraphs(fromHTML html: String) -> [String] {
        guard let document = try? SwiftSoup.parseBodyFragment(html, ""), let body = document.body() else {
            return withoutFurniture([collapse(html)].filter { !$0.isEmpty })
        }

        var paragraphs: [String] = []
        var pending = ""

        func flush() {
            let text = collapse(pending)
            if !text.isEmpty { paragraphs.append(text) }
            pending = ""
        }

        func walk(_ node: Node) {
            for child in node.getChildNodes() {
                if let text = child as? TextNode {
                    pending += text.getWholeText()
                } else if let element = child as? Element {
                    let tag = element.tagName().lowercased()
                    if skipped.contains(tag) { continue }
                    if tag == "br" {
                        pending += " "
                    } else if blocks.contains(tag) {
                        flush()
                        walk(element)
                        flush()
                    } else {
                        walk(element)
                    }
                }
            }
        }

        walk(body)
        flush()
        return withoutFurniture(paragraphs)
    }

    // MARK: - Furniture

    /// Whole paragraphs that are the publisher's, not the writer's — and the byline a feed sets
    /// as a paragraph of its own (`- by Marc A Moffett`), which the sheet prints in its own
    /// place from the feed's author field.
    private static let furniture: [NSRegularExpression] = [
        #"^the post .+ (first )?appeared (first )?on .+$"#,
        #"^(read|continue reading)( more| the rest| the full (story|article|essay))?\W*$"#,
        #"^read on [^.]{1,60}$"#,
        #"^(subscribe( now)?|share|leave a comment|upgrade to paid|give a gift subscription|comments?)\W*$"#,
        #"^[-–—]\s*by\s+[^.]{2,80}$"#
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }
        // Case matters here: `By Ada Lovelace` is a byline, `By design` is a sentence.
        + [#"^By\s+\p{Lu}[\p{L}.'’-]+(\s+\p{Lu}[\p{L}.'’-]+){0,4}$"#]
            .compactMap { try? NSRegularExpression(pattern: $0) }

    /// The same, as a tail on the writer's last sentence: Aeon's ` - by Marc Moffett Read on
    /// Aeon`, a link-text `Read more »`.
    private static let tails: [NSRegularExpression] = [
        #"\s*(read on [^.]{1,60}|read more\W*|continue reading\W*)$"#
    ].compactMap { try? NSRegularExpression(pattern: $0, options: [.caseInsensitive]) }

    static func withoutFurniture(_ paragraphs: [String]) -> [String] {
        paragraphs.compactMap { paragraph in
            let whole = NSRange(paragraph.startIndex..., in: paragraph)
            if furniture.contains(where: { $0.firstMatch(in: paragraph, range: whole) != nil }) {
                return nil
            }
            var text = paragraph
            for tail in tails {
                let range = NSRange(text.startIndex..., in: text)
                text = tail.stringByReplacingMatches(in: text, range: range, withTemplate: "")
            }
            text = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        }
    }

    /// A dek that ends by naming its writer — `… gives you reason to walk away - by Marc A
    /// Moffett` — split into the dek and the name, for a feed that names its writers nowhere
    /// else.
    static func byline(endingDek dek: String) -> (dek: String, author: String)? {
        guard let regex = try? NSRegularExpression(pattern: #"\s+[-–—]\s+by\s+([^.]{2,80})$"#),
              let match = regex.firstMatch(in: dek, range: NSRange(dek.startIndex..., in: dek)),
              let nameRange = Range(match.range(at: 1), in: dek),
              let whole = Range(match.range, in: dek)
        else { return nil }
        return (String(dek[..<whole.lowerBound]), String(dek[nameRange]))
    }

    // MARK: - Names, arXiv, entities

    /// The people a byline names. RSS writes `editor@example.com (Ada Lovelace)`; arXiv's
    /// `dc:creator` lists every author in one string.
    static func names(in text: String) -> [String] {
        var value = line(text)
        if let open = value.firstIndex(of: "("), let close = value.lastIndex(of: ")"), open < close,
           value[..<open].contains("@") {
            value = String(value[value.index(after: open)..<close])
        }
        return value
            .components(separatedBy: ", ")
            .flatMap { $0.components(separatedBy: " and ") }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty && !$0.contains("@") }
    }

    /// An arXiv RSS description without the line before the abstract:
    /// `arXiv:2610.26887v1 Announce Type: new Abstract: Large language model…`.
    static func arxivAbstract(_ text: String) -> String {
        var value = text
        if let regex = try? NSRegularExpression(pattern: #"^arXiv:\S+\s+Announce Type:\s*\S+\s*"#) {
            value = regex.stringByReplacingMatches(in: value, range: NSRange(value.startIndex..., in: value), withTemplate: "")
        }
        if value.hasPrefix("Abstract:") {
            value = String(value.dropFirst("Abstract:".count)).trimmingCharacters(in: .whitespaces)
        }
        return value
    }

    /// Text gathered back into markup (Atom's XHTML content) must not turn a `<` in a sentence
    /// into a tag.
    static func escapeForMarkup(_ text: String) -> String {
        text
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }

    /// The document with every HTML-only entity written as the number XML understands.
    ///
    /// XML knows five named entities; a feed written through an HTML template uses dozens, and
    /// `XMLParser` stops at the first one it does not know. Inside CDATA they are harmless and
    /// left alone — this rewrites the whole document, and in CDATA a numeric reference reads
    /// the same once `line` or the HTML walk decodes it.
    static func declaringHTMLEntities(in document: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: "&([A-Za-z][A-Za-z0-9]{1,31});") else { return document }
        let source = document as NSString
        var result = ""
        var cursor = 0
        for match in regex.matches(in: document, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: cursor, length: match.range.location - cursor))
            let name = source.substring(with: match.range(at: 1))
            if ["amp", "lt", "gt", "quot", "apos"].contains(name) {
                result += "&\(name);"
            } else if let scalar = htmlEntities[name] {
                result += "&#\(scalar);"
            } else {
                // Unknown: keep the text visible rather than lose the document to it.
                result += "&amp;\(name);"
            }
            cursor = match.range.location + match.range.length
        }
        result += source.substring(from: cursor)
        return result
    }

    private static let htmlEntities: [String: Int] = [
        "nbsp": 160, "iexcl": 161, "cent": 162, "pound": 163, "euro": 8364, "yen": 165,
        "sect": 167, "copy": 169, "laquo": 171, "raquo": 187, "reg": 174, "deg": 176,
        "plusmn": 177, "middot": 183, "para": 182, "frac12": 189, "frac14": 188, "frac34": 190,
        "times": 215, "divide": 247, "iquest": 191, "trade": 8482, "hellip": 8230,
        "ndash": 8211, "mdash": 8212, "lsquo": 8216, "rsquo": 8217, "sbquo": 8218,
        "ldquo": 8220, "rdquo": 8221, "bdquo": 8222, "prime": 8242, "Prime": 8243,
        "bull": 8226, "dagger": 8224, "Dagger": 8225, "permil": 8240, "lsaquo": 8249,
        "rsaquo": 8250, "thinsp": 8201, "ensp": 8194, "emsp": 8195, "zwnj": 8204, "zwj": 8205,
        "shy": 173, "larr": 8592, "rarr": 8594, "uarr": 8593, "darr": 8595, "harr": 8596,
        "minus": 8722, "le": 8804, "ge": 8805, "ne": 8800, "asymp": 8776, "infin": 8734,
        "alpha": 945, "beta": 946, "gamma": 947, "delta": 948, "epsilon": 949, "lambda": 955,
        "mu": 956, "pi": 960, "sigma": 963, "omega": 969, "Delta": 916, "Sigma": 931,
        "Omega": 937, "agrave": 224, "aacute": 225, "acirc": 226, "atilde": 227, "auml": 228,
        "aring": 229, "aelig": 230, "ccedil": 231, "egrave": 232, "eacute": 233, "ecirc": 234,
        "euml": 235, "igrave": 236, "iacute": 237, "icirc": 238, "iuml": 239, "ntilde": 241,
        "ograve": 242, "oacute": 243, "ocirc": 244, "otilde": 245, "ouml": 246, "oslash": 248,
        "ugrave": 249, "uacute": 250, "ucirc": 251, "uuml": 252, "yacute": 253, "yuml": 255,
        "szlig": 223, "Agrave": 192, "Aacute": 193, "Acirc": 194, "Auml": 196, "Aring": 197,
        "AElig": 198, "Ccedil": 199, "Egrave": 200, "Eacute": 201, "Ecirc": 202, "Iacute": 205,
        "Ntilde": 209, "Oacute": 211, "Ouml": 214, "Oslash": 216, "Uacute": 218, "Uuml": 220,
        "oelig": 339, "OElig": 338, "scaron": 353, "Scaron": 352, "zcaron": 382, "Zcaron": 381
    ]
}
