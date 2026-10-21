import Foundation

/// What a feed says, before the rack decides what to keep of it.
public nonisolated struct ParsedFeed: Sendable {
    public var title: String
    public var siteURL: URL?
    public var summary: String?
    public var items: [ParsedFeedItem]
}

/// One entry of a feed, in plain text.
public nonisolated struct ParsedFeedItem: Sendable, Equatable {
    public var guid: String?
    public var title: String
    public var link: URL?
    public var publishedAt: Date?
    public var authors: [String]
    /// Plain paragraphs separated by a blank line; see `FeedText`.
    public var summary: String
    public var characterCount: Int?
    public var categories: [String]
    public var arxivID: String?
    public var pdfURL: URL?

    public init(
        guid: String? = nil,
        title: String,
        link: URL?,
        publishedAt: Date? = nil,
        authors: [String] = [],
        summary: String = "",
        characterCount: Int? = nil,
        categories: [String] = [],
        arxivID: String? = nil,
        pdfURL: URL? = nil
    ) {
        self.guid = guid
        self.title = title
        self.link = link
        self.publishedAt = publishedAt
        self.authors = authors
        self.summary = summary
        self.characterCount = characterCount
        self.categories = categories
        self.arxivID = arxivID
        self.pdfURL = pdfURL
    }
}

public nonisolated enum FeedParseError: LocalizedError {
    case notAFeed

    public var errorDescription: String? {
        "That address answers, but not with a feed."
    }
}

/// Reads the three formats the web still publishes in — RSS (2.0 and the RDF 1.0 some journals
/// keep), Atom, and JSON Feed — into one shape.
///
/// `XMLParser` from Foundation rather than a package: a feed is a small, flat document, and the
/// one thing a streaming parser gets wrong about it — HTML entities XML does not declare — is
/// repaired before a second attempt (`FeedText.declaringHTMLEntities`). Runs off the main actor
/// like every other parser in the app; `FeedStore` calls it from a detached task.
public nonisolated enum FeedParser {
    public static func parse(_ data: Data, url: URL) throws -> ParsedFeed {
        if looksLikeJSON(data) {
            return try parseJSONFeed(data, url: url)
        }

        let first = readXML(data, url: url)
        if first.isFeed, first.completed { return first.feed() }

        // A feed written by hand often carries an HTML entity XML does not know — `&nbsp;` in a
        // title, `&mdash;` in a summary — and the parser stops dead at the first one, keeping
        // whatever came before it. Declared, the same document reads to the end.
        if let text = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1),
           let repairedData = FeedText.declaringHTMLEntities(in: text).data(using: .utf8) {
            let second = readXML(repairedData, url: url)
            if second.isFeed, second.completed || second.items.count >= first.items.count {
                return second.feed()
            }
        }
        if first.isFeed, !first.items.isEmpty { return first.feed() }
        throw FeedParseError.notAFeed
    }

    private static func readXML(_ data: Data, url: URL) -> FeedXMLReader {
        let reader = FeedXMLReader(url: url)
        let parser = XMLParser(data: data)
        parser.delegate = reader
        parser.shouldProcessNamespaces = false
        parser.shouldResolveExternalEntities = false
        reader.completed = parser.parse()
        return reader
    }

    private static func looksLikeJSON(_ data: Data) -> Bool {
        for byte in data.prefix(64) {
            switch byte {
            case 0x20, 0x09, 0x0A, 0x0D, 0xEF, 0xBB, 0xBF: continue  // whitespace, a BOM
            case UInt8(ascii: "{"): return true
            default: return false
            }
        }
        return false
    }

    // MARK: - JSON Feed

    private struct JSONFeed: Decodable {
        struct Author: Decodable { let name: String? }
        struct Item: Decodable {
            let id: String?
            let url: String?
            let external_url: String?
            let title: String?
            let content_html: String?
            let content_text: String?
            let summary: String?
            let date_published: String?
            let date_modified: String?
            let authors: [Author]?
            let author: Author?
            let tags: [String]?
        }
        let version: String?
        let title: String?
        let home_page_url: String?
        let description: String?
        let items: [Item]
    }

    private static func parseJSONFeed(_ data: Data, url: URL) throws -> ParsedFeed {
        guard let feed = try? JSONDecoder().decode(JSONFeed.self, from: data),
              feed.version?.contains("jsonfeed.org") == true
        else { throw FeedParseError.notAFeed }

        let items = feed.items.map { item -> ParsedFeedItem in
            let body = item.content_html.map { FeedText.Body(html: $0) }
                ?? item.content_text.map { FeedText.Body(plain: $0) }
            let summary = item.summary.map { FeedText.Body(plain: $0) }
            let link = (item.url ?? item.external_url).flatMap { URL(string: $0, relativeTo: url)?.absoluteURL }
            return ParsedFeedItem(
                guid: item.id,
                title: FeedText.line(item.title ?? ""),
                link: link,
                publishedAt: (item.date_published ?? item.date_modified).flatMap(FeedDate.parse),
                authors: (item.authors ?? item.author.map { [$0] } ?? []).compactMap(\.name),
                summary: FeedText.summary(preferring: summary, then: body),
                characterCount: body?.fullLength,
                categories: item.tags ?? []
            )
        }
        return ParsedFeed(
            title: FeedText.line(feed.title ?? ""),
            siteURL: feed.home_page_url.flatMap { URL(string: $0) },
            summary: feed.description.map(FeedText.line),
            items: items
        )
    }
}

/// The XML half: one pass over RSS, RDF or Atom, filling the same fields from whichever names
/// the document uses.
///
/// Names arrive with their prefixes as written (`dc:creator`, `content:encoded`), because the
/// prefixes in real feeds are stable and namespace processing would cost a lookup per element
/// for nothing.
private nonisolated final class FeedXMLReader: NSObject, XMLParserDelegate {
    let url: URL
    var completed = false
    private(set) var isFeed = false

    private var channelTitle = ""
    private var channelLink: URL?
    private var channelSummary: String?

    private(set) var items: [ParsedFeedItem] = []
    private var current: ItemBuilder?

    private var stack: [String] = []
    private var text = ""

    /// Atom's `type="xhtml"` content is markup inside the document rather than escaped text;
    /// it is gathered back into HTML so the paragraphs survive into the summary.
    private var markupRoot: String?
    private var markupDepth = 0
    private var markup = ""

    private struct ItemBuilder {
        var guid: String?
        var title = ""
        var link: URL?
        var published: Date?
        var updated: Date?
        var authors: [String] = []
        var summaryHTML: String?
        var contentHTML: String?
        var categories: [String] = []
        var primaryCategory: String?
        var pdfURL: URL?
        /// arXiv's RSS lists replaced papers beside new ones; a replacement is an old paper.
        var announceType: String?
    }

    init(url: URL) {
        self.url = url
    }

    func feed() -> ParsedFeed {
        ParsedFeed(
            title: FeedText.line(channelTitle),
            siteURL: channelLink,
            summary: channelSummary.map(FeedText.line).flatMap { $0.isEmpty ? nil : $0 },
            items: items
        )
    }

    private func resolve(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed, relativeTo: url)?.absoluteURL
    }

    // MARK: XMLParserDelegate

    func parser(
        _ parser: XMLParser,
        didStartElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?,
        attributes: [String: String] = [:]
    ) {
        if markupRoot != nil {
            markupDepth += 1
            markup += "<\(elementName)>"
            stack.append(elementName)
            return
        }

        stack.append(elementName)
        text = ""

        switch elementName {
        case "rss", "feed", "rdf:RDF", "RDF":
            isFeed = true
        case "item", "entry":
            current = ItemBuilder()
        case "link":
            // Atom names its links in attributes; RSS writes the address as the element's text,
            // which is taken at the end of the element.
            guard let href = attributes["href"], let resolved = resolve(href) else { return }
            let rel = attributes["rel"] ?? "alternate"
            if current != nil {
                if attributes["title"] == "pdf" || attributes["type"] == "application/pdf" {
                    current?.pdfURL = resolved
                } else if rel == "alternate", current?.link == nil {
                    current?.link = resolved
                }
            } else if rel == "alternate", channelLink == nil {
                channelLink = resolved
            }
        case "category":
            if let term = attributes["term"], current != nil {
                current?.categories.append(term)
            }
        case "arxiv:primary_category":
            current?.primaryCategory = attributes["term"]
        case "content", "summary":
            if current != nil, attributes["type"] == "xhtml" {
                markupRoot = elementName
                markupDepth = 0
                markup = ""
            }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if markupRoot != nil {
            markup += FeedText.escapeForMarkup(string)
        } else {
            text += string
        }
    }

    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) {
        guard let string = String(data: CDATABlock, encoding: .utf8) else { return }
        if markupRoot != nil {
            markup += string
        } else {
            text += string
        }
    }

    func parser(
        _ parser: XMLParser,
        didEndElement elementName: String,
        namespaceURI: String?,
        qualifiedName qName: String?
    ) {
        defer { if !stack.isEmpty { stack.removeLast() } }

        if let root = markupRoot {
            if elementName == root, markupDepth == 0 {
                markupRoot = nil
                if root == "content" { current?.contentHTML = markup } else { current?.summaryHTML = markup }
            } else {
                markupDepth -= 1
                markup += "</\(elementName)>"
            }
            return
        }

        let value = text
        text = ""
        let parent = stack.dropLast().last

        if current != nil {
            endItemElement(elementName, value: value, parent: parent)
        } else if parent == "channel" || parent == "feed" {
            switch elementName {
            case "title": channelTitle = value
            case "link": if channelLink == nil { channelLink = resolve(value) }
            case "description", "subtitle": channelSummary = value
            default: break
            }
        }
    }

    private func endItemElement(_ name: String, value: String, parent: String?) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "item", "entry":
            if let built = current, built.announceType?.hasPrefix("replace") != true {
                items.append(finish(built))
            }
            current = nil
        case "arxiv:announce_type":
            current?.announceType = trimmed
        case "title" where parent == "item" || parent == "entry":
            current?.title = value
        case "link":
            if current?.link == nil, let resolved = resolve(trimmed) { current?.link = resolved }
        case "guid", "id":
            if parent == "item" || parent == "entry", !trimmed.isEmpty { current?.guid = trimmed }
        case "pubDate", "published", "dc:date", "issued":
            if current?.published == nil { current?.published = FeedDate.parse(trimmed) }
        case "updated", "modified", "atom:updated":
            current?.updated = FeedDate.parse(trimmed)
        case "description", "summary":
            if current?.summaryHTML == nil { current?.summaryHTML = value }
        case "content:encoded", "content":
            if !trimmed.isEmpty { current?.contentHTML = value }
        case "dc:creator":
            appendAuthors(trimmed)
        case "author" where parent != "entry":
            // RSS writes `author` as `mail@example.com (Name)`; the name is what is printed.
            // Atom's `author` is a container, and its `name` is taken below.
            appendAuthors(trimmed)
        case "name" where parent == "author":
            if !trimmed.isEmpty { current?.authors.append(trimmed) }
        case "category":
            if !trimmed.isEmpty { current?.categories.append(trimmed) }
        default:
            break
        }
    }

    private func appendAuthors(_ byline: String) {
        for name in FeedText.names(in: byline) where !(current?.authors.contains(name) ?? true) {
            current?.authors.append(name)
        }
    }

    private func finish(_ built: ItemBuilder) -> ParsedFeedItem {
        let summary = built.summaryHTML.map { FeedText.Body(html: $0) }
        let content = built.contentHTML.map { FeedText.Body(html: $0) }
        let arxivID = built.link.flatMap(Self.arxivID(in:)) ?? built.guid.flatMap(Self.arxivID(inString:))

        var categories = built.categories
        if let primary = built.primaryCategory {
            categories.removeAll { $0 == primary }
            categories.insert(primary, at: 0)
        }

        var body = summary
        var full = content
        var authors = built.authors.map(FeedText.line).filter { !$0.isEmpty }
        if arxivID != nil, let abstract = built.summaryHTML {
            // An abstract is plain text, not markup: read as HTML, its paragraph breaks
            // collapsed into one and `p < 0.05` began a tag. The arXiv RSS also opens every
            // description with the identifier and the kind of announcement before the abstract.
            body = FeedText.Body(plain: FeedText.arxivAbstract(abstract))
            full = nil
        } else if let paragraphs = body?.paragraphs, let first = paragraphs.first,
                  let split = FeedText.byline(endingDek: first) {
            // A dek that signs itself (`… - by Marc A Moffett`) names the writer for a feed
            // that names them nowhere else.
            body = FeedText.Body(paragraphs: [split.dek] + paragraphs.dropFirst())
            if authors.isEmpty { authors = [split.author] }
        }

        return ParsedFeedItem(
            guid: built.guid,
            title: FeedText.line(built.title),
            link: built.link,
            publishedAt: built.published ?? built.updated,
            authors: authors,
            summary: FeedText.summary(preferring: body, then: full),
            characterCount: (full ?? body)?.fullLength,
            categories: categories,
            arxivID: arxivID,
            pdfURL: built.pdfURL ?? arxivID.flatMap { URL(string: "https://arxiv.org/pdf/\($0)") }
        )
    }

    /// `https://arxiv.org/abs/2610.28632v1` → `2610.28632v1`.
    private static func arxivID(in url: URL) -> String? {
        guard let host = url.host, host.hasSuffix("arxiv.org") else { return nil }
        let parts = url.path.split(separator: "/")
        guard parts.count >= 2, parts[0] == "abs" || parts[0] == "pdf" || parts[0] == "html" else { return nil }
        return parts.dropFirst().joined(separator: "/")
    }

    /// `oai:arXiv.org:2610.26887v1` → `2610.26887v1`.
    private static func arxivID(inString string: String) -> String? {
        guard string.hasPrefix("oai:arXiv.org:") else { return nil }
        return String(string.dropFirst("oai:arXiv.org:".count))
    }
}

/// The dates feeds write, which are of two families and many dialects.
public nonisolated enum FeedDate {
    public static func parse(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        for formatter in iso8601 {
            if let date = formatter.date(from: trimmed) { return date }
        }
        for formatter in rfc822 {
            if let date = formatter.date(from: trimmed) { return date }
        }
        return nil
    }

    // Formatters are immutable once configured and safe to read from several threads; they are
    // built once because building one costs more than parsing a whole feed's dates.
    nonisolated(unsafe) private static let iso8601: [ISO8601DateFormatter] = {
        let options: [ISO8601DateFormatter.Options] = [
            [.withInternetDateTime, .withFractionalSeconds],
            [.withInternetDateTime],
            [.withFullDate]
        ]
        return options.map { option in
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = option
            return formatter
        }
    }()

    private static let rfc822: [DateFormatter] = {
        [
            "EEE, d MMM yyyy HH:mm:ss zzz",
            "EEE, d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yyyy HH:mm zzz",
            "EEE, d MMM yyyy HH:mm Z",
            "d MMM yyyy HH:mm:ss zzz",
            "d MMM yyyy HH:mm:ss Z",
            "EEE, d MMM yy HH:mm:ss zzz",
            "EEE, d MMM yyyy",
            "yyyy-MM-dd HH:mm:ss Z",
            "yyyy-MM-dd'T'HH:mm:ssZ"
        ].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = format
            return formatter
        }
    }()
}
