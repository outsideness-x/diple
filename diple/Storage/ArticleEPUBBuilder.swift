import Foundation

/// Packages an extracted article as an EPUB 3 publication.
///
/// The whole point of going through EPUB rather than inventing an article format is that
/// nothing downstream has to know the difference. Highlights anchor to Readium locators,
/// bookmarks, reading progress, the outline, the themes and the font controls all already work
/// against a publication — an article that *is* a publication inherits every one of them, and
/// the Hub lists its quotes beside quotes from books without a single branch.
public nonisolated struct ArticleEPUBBuilder {

    /// A file that goes into the package: images, and nothing else so far.
    public struct Asset: Sendable {
        /// Path inside the `EPUB/` folder, e.g. `images/img-1.jpg`.
        public let path: String
        public let mediaType: String
        public let data: Data

        public init(path: String, mediaType: String, data: Data) {
            self.path = path
            self.mediaType = mediaType
            self.data = data
        }
    }

    public let bookId: String
    public let metadata: ArticleMetadata
    public let sections: [ArticleSection]
    public let bodyXHTML: String
    public let assets: [Asset]
    /// Path of the asset to use as the cover, if the page offered a lead image.
    public let coverPath: String?

    public init(
        bookId: String,
        metadata: ArticleMetadata,
        sections: [ArticleSection],
        bodyXHTML: String,
        assets: [Asset],
        coverPath: String?
    ) {
        self.bookId = bookId
        self.metadata = metadata
        self.sections = sections
        self.bodyXHTML = bodyXHTML
        self.assets = assets
        self.coverPath = coverPath
    }

    public func epubData() throws -> Data {
        var writer = ZIPWriter()

        // The mimetype entry has to be first and uncompressed. `ZIPWriter` only ever stores,
        // so ordering is the only part left to get right.
        try writer.append(path: "mimetype", text: "application/epub+zip")
        try writer.append(path: "META-INF/container.xml", text: Self.containerXML)
        try writer.append(path: "EPUB/package.opf", text: packageOPF())
        try writer.append(path: "EPUB/nav.xhtml", text: navigationXHTML())
        try writer.append(path: "EPUB/article.xhtml", text: articleXHTML())
        try writer.append(path: "EPUB/styles/article.css", text: Self.stylesheet)

        for asset in assets {
            try writer.append(path: "EPUB/\(asset.path)", data: asset.data)
        }

        return try writer.finalize()
    }

    // MARK: - Container

    private static let containerXML = """
        <?xml version="1.0" encoding="UTF-8"?>
        <container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
          <rootfiles>
            <rootfile full-path="EPUB/package.opf" media-type="application/oebps-package+xml"/>
          </rootfiles>
        </container>
        """

    // MARK: - Package document

    private func packageOPF() -> String {
        let language = metadata.language ?? "en"
        var items: [String] = [
            #"<item id="nav" href="nav.xhtml" media-type="application/xhtml+xml" properties="nav"/>"#,
            #"<item id="article" href="article.xhtml" media-type="application/xhtml+xml"/>"#,
            #"<item id="stylesheet" href="styles/article.css" media-type="text/css"/>"#
        ]

        for (index, asset) in assets.enumerated() {
            let id = "asset-\(index + 1)"
            let properties = asset.path == coverPath ? #" properties="cover-image""# : ""
            items.append(
                #"<item id="\#(id)" href="\#(Self.escaped(asset.path))" media-type="\#(asset.mediaType)"\#(properties)/>"#
            )
        }

        var meta: [String] = [
            #"<meta property="dcterms:modified">\#(Self.utcTimestamp(Date()))</meta>"#
        ]
        if let author = metadata.author {
            meta.append("<dc:creator>\(Self.escaped(author))</dc:creator>")
        }
        if let siteName = metadata.siteName {
            meta.append("<dc:publisher>\(Self.escaped(siteName))</dc:publisher>")
        }
        if let published = metadata.publishedAt {
            meta.append("<dc:date>\(Self.utcTimestamp(published))</dc:date>")
        }

        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="pub-id" xml:lang="\(Self.escaped(language))">
              <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
                <dc:identifier id="pub-id">urn:uuid:\(Self.escaped(bookId))</dc:identifier>
                <dc:title>\(Self.escaped(metadata.title))</dc:title>
                <dc:language>\(Self.escaped(language))</dc:language>
                <dc:source>\(Self.escaped(metadata.canonicalURL.absoluteString))</dc:source>
                \(meta.joined(separator: "\n    "))
              </metadata>
              <manifest>
                \(items.joined(separator: "\n    "))
              </manifest>
              <spine>
                <itemref idref="article"/>
              </spine>
            </package>
            """
    }

    // MARK: - Navigation document

    /// The reader's outline sheet reads this. An article is one file, so without headings it
    /// would list a single row saying the title back to you; with them it lists the piece's own
    /// sections, which is what makes the outline worth opening at all.
    private func navigationXHTML() -> String {
        let language = metadata.language ?? "en"
        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="\(Self.escaped(language))" xml:lang="\(Self.escaped(language))">
              <head>
                <meta charset="utf-8"/>
                <title>\(Self.escaped(metadata.title))</title>
              </head>
              <body>
                <nav epub:type="toc" id="toc">
                  <h1>Contents</h1>
            \(navigationList())
                </nav>
              </body>
            </html>
            """
    }

    /// Builds the nested `<ol>`, promoting the article itself to the first entry so that the
    /// outline always has somewhere to send you back to the top.
    private func navigationList() -> String {
        var lines = ["      <ol>"]
        lines.append(#"        <li><a href="article.xhtml">\#(Self.escaped(metadata.title))</a>"#)

        if sections.isEmpty {
            lines.append("        </li>")
        } else {
            lines.append("          <ol>")
            var openSubList = false
            for section in sections {
                let href = "article.xhtml#\(section.id)"
                let label = Self.escaped(section.title)
                if section.level == 1 {
                    if openSubList {
                        lines.append("              </ol>")
                        lines.append("            </li>")
                        openSubList = false
                    } else if lines.last?.hasPrefix("            <li>") == true {
                        lines.append("            </li>")
                    }
                    lines.append(#"            <li><a href="\#(href)">\#(label)</a>"#)
                } else {
                    if !openSubList {
                        lines.append("              <ol>")
                        openSubList = true
                    }
                    lines.append(#"                <li><a href="\#(href)">\#(label)</a></li>"#)
                }
            }
            if openSubList {
                lines.append("              </ol>")
            }
            lines.append("            </li>")
            lines.append("          </ol>")
            lines.append("        </li>")
        }

        lines.append("      </ol>")
        return lines.joined(separator: "\n")
    }

    // MARK: - Article document

    private func articleXHTML() -> String {
        let language = metadata.language ?? "en"
        var header: [String] = []

        if let siteName = metadata.siteName {
            header.append(#"      <p class="diple-source">\#(Self.escaped(siteName))</p>"#)
        }
        header.append(#"      <h1 class="diple-title">\#(Self.escaped(metadata.title))</h1>"#)
        if let author = metadata.author {
            header.append(#"      <p class="diple-byline">\#(Self.escaped(author))</p>"#)
        }

        var facts: [String] = []
        if let published = metadata.publishedAt {
            facts.append(Self.displayDate(published))
        }
        facts.append("\(metadata.readingMinutes) min read")
        header.append(#"      <p class="diple-meta">\#(Self.escaped(facts.joined(separator: " · ")))</p>"#)
        header.append(#"      <hr class="diple-rule"/>"#)

        if let coverPath {
            header.append(#"      <figure class="diple-lead"><img src="\#(Self.escaped(coverPath))" alt=""/></figure>"#)
        }

        let host = metadata.canonicalURL.host ?? metadata.canonicalURL.absoluteString
        let footer = """
                  <p>Saved from <a href="\(Self.escaped(metadata.canonicalURL.absoluteString))">\(Self.escaped(host))</a></p>
            """

        return """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE html>
            <html xmlns="http://www.w3.org/1999/xhtml" xmlns:epub="http://www.idpf.org/2007/ops" lang="\(Self.escaped(language))" xml:lang="\(Self.escaped(language))">
              <head>
                <meta charset="utf-8"/>
                <title>\(Self.escaped(metadata.title))</title>
                <link rel="stylesheet" type="text/css" href="styles/article.css"/>
              </head>
              <body>
                <header class="diple-header">
            \(header.joined(separator: "\n"))
                </header>
                <section class="diple-body">
            \(bodyXHTML)
                </section>
                <footer class="diple-footer">
            \(footer)
                </footer>
              </body>
            </html>
            """
    }

    // MARK: - Stylesheet

    /// Why this stylesheet paints nothing.
    ///
    /// Readium's dark and sepia themes end with `*:not(a) { color: inherit !important;
    /// background-color: transparent !important; }`, and the dark theme adds
    /// `border-color: currentColor !important`. Any colour or fill declared here therefore
    /// survives in exactly one of the reader's three themes, which is worse than never
    /// having it: the article would look considered on a white page and broken on a dark one.
    ///
    /// So the whole design is built from things the themes do not touch — size, weight,
    /// tracking, spacing, and `opacity`. Where a rule or a tint is genuinely needed it is drawn
    /// on a `::before`/`::after` box, because a pseudo-element is not an element and the
    /// `*:not(a)` override does not reach it. One technique, used everywhere, instead of a
    /// different workaround per component.
    private static let stylesheet = """
        /* diple — reading styles for an imported web article. */

        html {
          -webkit-text-size-adjust: 100%;
        }

        body {
          margin: 0;
          padding: 0;
          line-height: 1.62;
          overflow-wrap: break-word;
          word-wrap: break-word;
        }

        /* ---- Title block ---- */

        .diple-header {
          margin: 0 0 2.3em;
        }

        .diple-source {
          margin: 0;
          font-size: 0.72em;
          font-weight: 600;
          letter-spacing: 0.14em;
          text-transform: uppercase;
          opacity: 0.55;
        }

        .diple-title {
          margin: 0.65em 0 0;
          font-size: 2em;
          line-height: 1.14;
          font-weight: 700;
          letter-spacing: -0.021em;
        }

        .diple-byline {
          margin: 0.8em 0 0;
          font-size: 0.92em;
          font-weight: 600;
          opacity: 0.8;
        }

        .diple-meta {
          margin: 0.25em 0 0;
          font-size: 0.8em;
          letter-spacing: 0.012em;
          opacity: 0.52;
        }

        .diple-rule {
          width: 2.4em;
          height: 0;
          margin: 1.6em 0 0;
          border: 0;
          border-top: 2px solid currentColor;
          opacity: 0.32;
        }

        .diple-lead {
          margin: 1.9em 0 0;
        }

        /* ---- Body ---- */

        .diple-body > *:first-child {
          margin-top: 0;
        }

        .diple-body p {
          margin: 0 0 1.15em;
        }

        .diple-body h1,
        .diple-body h2 {
          margin: 2.1em 0 0.55em;
          font-size: 1.4em;
          line-height: 1.26;
          font-weight: 700;
          letter-spacing: -0.014em;
        }

        .diple-body h3 {
          margin: 1.7em 0 0.45em;
          font-size: 1.12em;
          line-height: 1.35;
          font-weight: 700;
          letter-spacing: -0.008em;
        }

        .diple-body h4,
        .diple-body h5,
        .diple-body h6 {
          margin: 1.5em 0 0.4em;
          font-size: 1em;
          font-weight: 700;
        }

        /* A heading stranded at the foot of a page is the most visible way pagination can
           look careless. */
        .diple-body h1,
        .diple-body h2,
        .diple-body h3,
        .diple-body h4 {
          -webkit-column-break-after: avoid;
          break-after: avoid-column;
          page-break-after: avoid;
        }

        ul,
        ol {
          margin: 0 0 1.15em;
          padding-left: 1.35em;
        }

        li {
          margin: 0 0 0.4em;
        }

        li > ul,
        li > ol {
          margin: 0.4em 0 0;
        }

        a {
          text-decoration: underline;
          text-decoration-thickness: 0.055em;
          text-underline-offset: 0.16em;
        }

        sup,
        sub {
          font-size: 0.72em;
          line-height: 0;
        }

        /* ---- Figures ---- */

        img {
          display: block;
          max-width: 100%;
          height: auto;
          margin: 0 auto;
        }

        figure {
          margin: 1.9em 0;
          -webkit-column-break-inside: avoid;
          break-inside: avoid;
          page-break-inside: avoid;
        }

        /* Keeps a tall image on one page instead of letting it be sliced by the column. */
        figure img {
          max-height: 82vh;
          object-fit: contain;
        }

        figcaption {
          margin: 0.7em 0 0;
          font-size: 0.79em;
          line-height: 1.5;
          opacity: 0.58;
        }

        /* ---- Quoted and preformatted blocks ---- */

        blockquote,
        pre {
          position: relative;
          margin: 1.7em 0;
          padding-left: 1.2em;
        }

        blockquote::before,
        pre::before {
          content: "";
          position: absolute;
          left: 0;
          top: 0.18em;
          bottom: 0.18em;
          width: 2px;
          background-color: currentColor;
          opacity: 0.3;
        }

        blockquote {
          font-size: 1.02em;
          line-height: 1.55;
        }

        blockquote p:last-child {
          margin-bottom: 0;
        }

        pre {
          overflow-x: auto;
          font-size: 0.82em;
          line-height: 1.5;
          white-space: pre;
          -webkit-hyphens: none;
          hyphens: none;
        }

        /* `ui-monospace` and `-apple-system` resolve to San Francisco, which has no Hangul and
           turns Korean into tofu — the same trap documented for the reader's body font. Named
           faces only. */
        pre,
        code,
        kbd,
        samp {
          font-family: Menlo, Courier, monospace;
        }

        :not(pre) > code {
          font-size: 0.88em;
          letter-spacing: -0.01em;
        }

        .diple-body hr {
          width: 3.2em;
          height: 0;
          margin: 2.3em auto;
          border: 0;
          border-top: 2px solid currentColor;
          opacity: 0.28;
        }

        /* ---- Tables ---- */

        table {
          width: 100%;
          margin: 1.6em 0;
          border-collapse: collapse;
          font-size: 0.88em;
        }

        th,
        td {
          position: relative;
          padding: 0.5em 0.7em 0.5em 0;
          text-align: left;
          vertical-align: top;
        }

        th::after,
        td::after {
          content: "";
          position: absolute;
          left: 0;
          right: 0;
          bottom: 0;
          height: 1px;
          background-color: currentColor;
          opacity: 0.18;
        }

        th {
          font-weight: 600;
        }

        /* ---- Colophon ---- */

        .diple-footer {
          position: relative;
          margin: 3em 0 0;
          padding-top: 1.4em;
          font-size: 0.8em;
          opacity: 0.6;
        }

        .diple-footer::before {
          content: "";
          position: absolute;
          top: 0;
          left: 0;
          width: 2.4em;
          height: 2px;
          background-color: currentColor;
          opacity: 0.5;
        }

        .diple-footer p {
          margin: 0;
        }
        """

    // MARK: - Formatting helpers

    private static func escaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "'", with: "&apos;")
    }

    /// EPUB wants `CCYY-MM-DDThh:mm:ssZ` exactly — no fractional seconds, no offset.
    private static func utcTimestamp(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        return formatter.string(from: date)
    }

    /// The date printed under the title, in whatever language the reader's device is set to.
    private static func displayDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .long
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }
}
