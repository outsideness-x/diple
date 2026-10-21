import XCTest
@testable import diple

/// The feed's reading of the formats real publishers write, and its one rule — three newest a
/// source, nothing counted. Samples are trimmed copies of what Quanta, Our World in Data, Aeon
/// and the arXiv API actually serve.
final class FeedTests: XCTestCase {
    private let base = URL(string: "https://example.org/feed")!

    private func parse(_ xml: String, url: URL? = nil) throws -> ParsedFeed {
        try FeedParser.parse(Data(xml.utf8), url: url ?? base)
    }

    // MARK: - Formats

    func testRSSWithCDATAAndBoilerplateReadsAsDekThenOpening() throws {
        let feed = try parse("""
        <?xml version="1.0" encoding="UTF-8"?><rss version="2.0" xmlns:content="http://purl.org/rss/1.0/modules/content/" xmlns:dc="http://purl.org/dc/elements/1.1/">
        <channel><title>Quanta Magazine</title><link>https://www.quantamagazine.org</link><description>Illuminating science</description>
        <item>
          <title>AI Proved the Quasi-Riemann Hypothesis. What Happens Now?</title>
          <link>https://www.quantamagazine.org/ai-proved-20261019/</link>
          <pubDate>Mon, 19 Oct 2026 15:40:26 +0000</pubDate>
          <dc:creator><![CDATA[Konstantin Kakaes]]></dc:creator>
          <category><![CDATA[Mathematics]]></category>
          <guid isPermaLink="false">https://www.quantamagazine.org/?p=167980</guid>
          <description><![CDATA[Unlike other recent AI proofs, this one has been unpacked by human experts.            <p>The post <a href="https://www.quantamagazine.org/x">AI Proved…</a> first appeared on <a href="https://www.quantamagazine.org">Quanta Magazine</a></p>]]></description>
          <content:encoded><![CDATA[<p>Among the 377 results that OpenAI announced on October 6, one stood out.</p><p><a href="https://www.quantamagazine.org/x">Read more</a></p>]]></content:encoded>
        </item>
        </channel></rss>
        """)
        XCTAssertEqual(feed.title, "Quanta Magazine")
        XCTAssertEqual(feed.siteURL?.absoluteString, "https://www.quantamagazine.org")
        let item = try XCTUnwrap(feed.items.first)
        XCTAssertEqual(item.title, "AI Proved the Quasi-Riemann Hypothesis. What Happens Now?")
        XCTAssertEqual(item.authors, ["Konstantin Kakaes"])
        XCTAssertEqual(item.categories, ["Mathematics"])
        XCTAssertEqual(item.guid, "https://www.quantamagazine.org/?p=167980")
        XCTAssertEqual(item.publishedAt, Date(timeIntervalSince1970: 1_792_424_426))
        // The dek, then the opening the content carries; no WordPress line, no "Read more".
        XCTAssertEqual(item.summary, """
        Unlike other recent AI proofs, this one has been unpacked by human experts.

        Among the 377 results that OpenAI announced on October 6, one stood out.
        """)
        XCTAssertNil(item.characterCount, "a teaser says nothing about the length of the piece")
    }

    func testAtomReadsAuthorsSummaryAndAlternateLink() throws {
        let feed = try parse("""
        <?xml version="1.0" encoding="utf-8"?>
        <feed xmlns="http://www.w3.org/2005/Atom">
        <title>Our World in Data</title>
        <subtitle>Research and data to make progress against the world’s largest problems</subtitle>
        <link type="text/html" rel="alternate" href="https://ourworldindata.org"/>
        <link type="application/atom+xml" rel="self" href="https://ourworldindata.org/atom.xml"/>
        <entry>
          <title><![CDATA[When do people experience mental health conditions for the first time?]]></title>
          <id>https://ourworldindata.org/when-do-people</id>
          <link rel="alternate" href="https://ourworldindata.org/when-do-people"/>
          <published>2026-10-19T00:00:00.000Z</published>
          <author><name>Hannah Ritchie</name></author>
          <summary><![CDATA[Knowing when people are most at risk allows us to offer support.<br><br><a href="https://ourworldindata.org/x"><img src="https://ourworldindata.org/i.png"/></a>]]></summary>
        </entry>
        </feed>
        """)
        XCTAssertEqual(feed.title, "Our World in Data")
        XCTAssertEqual(feed.siteURL?.absoluteString, "https://ourworldindata.org")
        let item = try XCTUnwrap(feed.items.first)
        XCTAssertEqual(item.link?.absoluteString, "https://ourworldindata.org/when-do-people")
        XCTAssertEqual(item.authors, ["Hannah Ritchie"])
        XCTAssertEqual(item.summary, "Knowing when people are most at risk allows us to offer support.")
        XCTAssertEqual(item.publishedAt, Date(timeIntervalSince1970: 1_792_368_000))
    }

    func testArxivAPIEntryCarriesAbstractAuthorsFieldsAndPDF() throws {
        let feed = try parse("""
        <?xml version='1.0' encoding='UTF-8'?>
        <feed xmlns:arxiv="http://arxiv.org/schemas/atom" xmlns="http://www.w3.org/2005/Atom">
          <title>arXiv Query</title>
          <entry>
            <id>http://arxiv.org/abs/2610.28632v1</id>
            <title>Joints, Camera, Action! Co-Generating 3D Motion
          and Video for Arbitrary Rigs</title>
            <updated>2026-10-20T17:59:56Z</updated>
            <link href="https://arxiv.org/abs/2610.28632v1" rel="alternate" type="text/html"/>
            <link href="https://arxiv.org/pdf/2610.28632v1" rel="related" type="application/pdf" title="pdf"/>
            <summary>Video generation models can now depict
        remarkably realistic motion in $O(n \\log n)$ time, p &lt; 0.05.

        A second paragraph.</summary>
            <category term="cs.AI" scheme="http://arxiv.org/schemas/atom"/>
            <category term="cs.CV" scheme="http://arxiv.org/schemas/atom"/>
            <published>2026-10-20T17:59:56Z</published>
            <arxiv:primary_category term="cs.CV"/>
            <author><name>Noam Rotstein</name></author>
            <author><name>Yoad Tewel</name></author>
          </entry>
        </feed>
        """, url: ArxivField.feedURL(for: ["cs.AI"]))
        let item = try XCTUnwrap(feed.items.first)
        XCTAssertEqual(item.title, "Joints, Camera, Action! Co-Generating 3D Motion and Video for Arbitrary Rigs")
        XCTAssertEqual(item.arxivID, "2610.28632v1")
        XCTAssertEqual(item.pdfURL?.absoluteString, "https://arxiv.org/pdf/2610.28632v1")
        XCTAssertEqual(item.link?.absoluteString, "https://arxiv.org/abs/2610.28632v1")
        XCTAssertEqual(item.authors, ["Noam Rotstein", "Yoad Tewel"])
        XCTAssertEqual(item.categories, ["cs.CV", "cs.AI"], "the primary field first")
        // A single line break inside the abstract is the API's wrapping, not a paragraph.
        XCTAssertEqual(item.summary, """
        Video generation models can now depict remarkably realistic motion in $O(n \\log n)$ time, p < 0.05.

        A second paragraph.
        """)
    }

    func testArxivRSSStripsTheAnnouncementAndDropsReplacements() throws {
        let feed = try parse("""
        <?xml version='1.0' encoding='UTF-8'?>
        <rss xmlns:arxiv="http://arxiv.org/schemas/atom" xmlns:dc="http://purl.org/dc/elements/1.1/" version="2.0"><channel>
        <title>cs.AI updates on arXiv.org</title><link>http://rss.arxiv.org/rss/cs.AI</link>
        <item><title>Navalia</title><link>https://arxiv.org/abs/2610.26887</link>
          <description>arXiv:2610.26887v1 Announce Type: new
        Abstract: Large language model agents are evolving.</description>
          <guid isPermaLink="false">oai:arXiv.org:2610.26887v1</guid>
          <category>cs.AI</category>
          <arxiv:announce_type>new</arxiv:announce_type>
          <dc:creator>Hengqi Liu, Ziyuan Liu, Yang Qin</dc:creator>
        </item>
        <item><title>An old paper, revised</title><link>https://arxiv.org/abs/2401.00001</link>
          <description>arXiv:2401.00001v3 Announce Type: replace
        Abstract: Old.</description>
          <arxiv:announce_type>replace</arxiv:announce_type>
        </item>
        </channel></rss>
        """)
        XCTAssertEqual(feed.items.count, 1)
        let item = try XCTUnwrap(feed.items.first)
        XCTAssertEqual(item.summary, "Large language model agents are evolving.")
        XCTAssertEqual(item.authors, ["Hengqi Liu", "Ziyuan Liu", "Yang Qin"])
        XCTAssertEqual(item.arxivID, "2610.26887")
        XCTAssertEqual(item.pdfURL?.absoluteString, "https://arxiv.org/pdf/2610.26887")
    }

    func testRDFItemsOutsideTheChannelAreRead() throws {
        let feed = try parse("""
        <?xml version="1.0"?>
        <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#" xmlns="http://purl.org/rss/1.0/" xmlns:dc="http://purl.org/dc/elements/1.1/">
          <channel rdf:about="https://journal.example/"><title>A Journal</title><link>https://journal.example/</link></channel>
          <item rdf:about="https://journal.example/1"><title>First</title><link>https://journal.example/1</link><dc:date>2026-10-01T09:00:00Z</dc:date></item>
        </rdf:RDF>
        """)
        XCTAssertEqual(feed.title, "A Journal")
        XCTAssertEqual(feed.items.map(\.title), ["First"])
        XCTAssertNotNil(feed.items.first?.publishedAt)
    }

    func testJSONFeed() throws {
        let feed = try parse("""
        {"version": "https://jsonfeed.org/version/1.1", "title": "A Blog", "home_page_url": "https://blog.example",
         "items": [{"id": "1", "url": "https://blog.example/1", "title": "On walking", "content_html": "<p>One.</p><p>Two.</p>",
                    "date_published": "2026-10-20T08:00:00+02:00", "authors": [{"name": "Ada"}]}]}
        """)
        XCTAssertEqual(feed.title, "A Blog")
        let item = try XCTUnwrap(feed.items.first)
        XCTAssertEqual(item.summary, "One.\n\nTwo.")
        XCTAssertEqual(item.authors, ["Ada"])
        XCTAssertEqual(item.publishedAt, Date(timeIntervalSince1970: 1_792_476_000))
    }

    /// `&nbsp;` outside CDATA stops `XMLParser` dead; declared as a number, the feed reads on.
    func testHTMLEntitiesOutsideCDATADoNotLoseTheFeed() throws {
        let feed = try parse("""
        <?xml version="1.0"?><rss version="2.0"><channel><title>Notes&nbsp;&mdash; daily</title>
        <item><title>First&nbsp;post</title><link>https://n.example/1</link></item>
        <item><title>Second</title><link>https://n.example/2</link></item>
        </channel></rss>
        """)
        XCTAssertEqual(feed.title, "Notes — daily")
        XCTAssertEqual(feed.items.map(\.title), ["First post", "Second"])
    }

    func testAPageIsNotAFeed() {
        XCTAssertThrowsError(try parse("<!doctype html><html><head><title>Hi</title></head><body>Hi</body></html>"))
    }

    func testDatesInTheDialectsFeedsWrite() {
        XCTAssertNotNil(FeedDate.parse("Wed, 21 Oct 2026 10:01:00 GMT"))
        XCTAssertNotNil(FeedDate.parse("Wed, 21 Oct 2026 00:00:00 -0400"))
        XCTAssertNotNil(FeedDate.parse("21 Oct 2026 10:01:00 +0000"))
        XCTAssertNotNil(FeedDate.parse("2026-10-19T00:00:00.000Z"))
        XCTAssertNotNil(FeedDate.parse("2026-10-19T08:00:00+02:00"))
        XCTAssertNotNil(FeedDate.parse("2026-10-19"))
        XCTAssertNil(FeedDate.parse("yesterday"))
    }

    // MARK: - Text

    func testFurnitureAndSignedDeksLeaveTheWritersWords() {
        let aeon = FeedText.Body(html: """
        <p><img src="x.jpg" alt=""/></p><p>Just as seeing a tree gives you reason to believe it’s there</p><p><em>- by Marc A Moffett</em></p><p><a href="https://aeon.co/x">Read on Aeon</a></p>
        """)
        XCTAssertEqual(aeon.paragraphs, ["Just as seeing a tree gives you reason to believe it’s there"])

        let substack = FeedText.Body(html: "<p>The argument.</p><p>Subscribe now</p><p>Share</p>")
        XCTAssertEqual(substack.paragraphs, ["The argument."])

        XCTAssertEqual(FeedText.Body(html: "<p>By design, the rule is short.</p>").paragraphs,
                       ["By design, the rule is short."], "a sentence that starts with By is not a byline")
        XCTAssertEqual(FeedText.byline(endingDek: "Walk away - by Marc A Moffett")?.author, "Marc A Moffett")
    }

    func testSummaryIsCutBetweenParagraphsAndAtAWord() {
        let long = String(repeating: "word ", count: 400)
        let summary = FeedText.summary(preferring: FeedText.Body(paragraphs: ["Opening.", long]), then: nil)
        XCTAssertTrue(summary.hasPrefix("Opening.\n\nword word"))
        XCTAssertTrue(summary.hasSuffix("…"))
        XCTAssertLessThanOrEqual(summary.count, FeedText.summaryLimit + 2)
    }

    // MARK: - The rule

    private func parsed(_ id: String, daysAgo: Double?, now: Date) -> ParsedFeedItem {
        ParsedFeedItem(
            guid: id,
            title: "Piece \(id)",
            link: URL(string: "https://s.example/\(id)"),
            publishedAt: daysAgo.map { now.addingTimeInterval(-$0 * 86_400) }
        )
    }

    func testEachSourceKeepsItsThreeNewestAndRemembersWhatWasRead() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let first = FeedRack.merge(
            sourceID: "s",
            fetched: [parsed("a", daysAgo: 5, now: now), parsed("b", daysAgo: 1, now: now),
                      parsed("c", daysAgo: 3, now: now), parsed("d", daysAgo: 2, now: now)],
            existing: [],
            now: now
        )
        XCTAssertEqual(first.map(\.title), ["Piece b", "Piece d", "Piece c"])

        var known = first
        known[0].keptBookID = "book-b"
        let later = now.addingTimeInterval(86_400)
        let second = FeedRack.merge(
            sourceID: "s",
            fetched: [parsed("e", daysAgo: 0, now: later), parsed("b", daysAgo: 2, now: later),
                      parsed("d", daysAgo: 3, now: later), parsed("c", daysAgo: 4, now: later)],
            existing: known,
            now: later
        )
        XCTAssertEqual(second.map(\.title), ["Piece e", "Piece b", "Piece d"], "c leaves, unannounced")
        XCTAssertEqual(second[1].keptBookID, "book-b")
        XCTAssertEqual(second[1].firstSeenAt, now, "a piece seen before keeps the day it arrived")
        XCTAssertEqual(second[0].firstSeenAt, later)
    }

    func testAPaperListedTwiceIsOneEntry() {
        let now = Date()
        var older = ParsedFeedItem(guid: nil, title: "Paper", link: URL(string: "https://arxiv.org/abs/2610.1v1"))
        older.arxivID = "2610.1v1"
        var newer = older
        newer.arxivID = "2610.1v2"
        newer.link = URL(string: "https://arxiv.org/abs/2610.1v2")
        let kept = FeedRack.merge(sourceID: "x", fetched: [newer, older], existing: [], now: now)
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(kept.first?.arxivID, "2610.1v2")
    }

    func testAFutureDateIsFiledWhenThePieceArrived() {
        let now = Date()
        let item = FeedRack.merge(
            sourceID: "s",
            fetched: [ParsedFeedItem(title: "Early", link: URL(string: "https://s.example/e"), publishedAt: now.addingTimeInterval(86_400 * 3))],
            existing: [],
            now: now
        )[0]
        XCTAssertEqual(item.filedAt, now)
    }

    func testDaysKeepASourcesOwnOrderWithinADay() {
        let calendar = Calendar(identifier: .gregorian)
        let noon = calendar.date(from: DateComponents(year: 2026, month: 10, day: 20, hour: 12))!
        func item(_ id: String, source: String, rank: Int, hoursEarlier: Double) -> FeedItem {
            FeedItem(
                id: id, sourceID: source, title: id, link: URL(string: "https://x.example/\(id)")!,
                publishedAt: noon.addingTimeInterval(-hoursEarlier * 3600), authors: [], summary: "",
                characterCount: nil, categories: [], arxivID: nil, pdfURL: nil,
                firstSeenAt: noon.addingTimeInterval(86_400 * 2), rank: rank, keptBookID: nil
            )
        }
        let days = FeedRack.days([
            item("arxiv-2", source: "arxiv", rank: 1, hoursEarlier: 0),
            item("blog-old", source: "blog", rank: 0, hoursEarlier: 30),
            item("arxiv-1", source: "arxiv", rank: 0, hoursEarlier: 0),
            item("blog-new", source: "blog", rank: 0, hoursEarlier: 1)
        ], calendar: calendar)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].items.map(\.id), ["arxiv-1", "arxiv-2", "blog-new"])
        XCTAssertEqual(days[1].items.map(\.id), ["blog-old"])
    }

    // MARK: - Finding a feed

    func testAPageNamesItsFeedInItsHead() {
        let page = URL(string: "http://www.experimental-history.com/")!
        let found = FeedDiscovery.alternates(inHTML: """
        <html><head>
        <link rel="alternate" type="application/rss+xml" title="Comments" href="/comments/feed">
        <link rel="alternate" type="application/rss+xml" href="http://www.experimental-history.com/feed">
        <link rel="alternate" type="application/atom+xml" href="/atom.xml">
        <link rel="stylesheet" href="/s.css">
        </head><body></body></html>
        """, baseURL: page)
        // Relative to the page, then raised to https like every address the app fetches.
        XCTAssertEqual(found.map(\.absoluteString), [
            "https://www.experimental-history.com/atom.xml",
            "https://www.experimental-history.com/feed"
        ])
    }

    func testAddressesAsPeopleTypeThem() {
        XCTAssertEqual(FeedDiscovery.normalize("quantamagazine.org")?.absoluteString, "https://quantamagazine.org")
        XCTAssertEqual(FeedDiscovery.normalize("http://paulgraham.com/rss.html")?.absoluteString, "https://paulgraham.com/rss.html")
        XCTAssertNil(FeedDiscovery.normalize("not an address"))
        XCTAssertEqual(FeedDiscovery.known(URL(string: "https://noahpinion.substack.com")!)?.absoluteString,
                       "https://noahpinion.substack.com/feed")
        XCTAssertEqual(FeedDiscovery.known(URL(string: "https://medium.com/@someone")!)?.absoluteString,
                       "https://medium.com/feed/@someone")
        XCTAssertEqual(FeedDiscovery.arxivFields(in: URL(string: "https://arxiv.org/list/cs.CL/recent")!), ["cs.CL"])
    }

    func testArxivFieldsReadAsWordsAndBuildOneQuery() {
        XCTAssertEqual(ArxivField.name(for: "cs.CV"), "Computer vision")
        XCTAssertEqual(ArxivField.name(for: "cond-mat.mtrl-sci"), "Materials science")
        XCTAssertEqual(ArxivField.name(for: "cond-mat.new-field"), "Condensed matter", "the archive, when the field is unknown")
        XCTAssertEqual(ArxivField.title(for: ["cs.AI", "cs.LG"]), "arXiv · AI, Machine learning")
        let query = URLComponents(url: ArxivField.feedURL(for: ["cs.AI", "cs.LG"]), resolvingAgainstBaseURL: false)
        XCTAssertEqual(query?.host, "export.arxiv.org")
        XCTAssertEqual(query?.queryItems?.first { $0.name == "search_query" }?.value, "cat:cs.AI OR cat:cs.LG")
        XCTAssertEqual(query?.queryItems?.first { $0.name == "sortBy" }?.value, "submittedDate")
    }

    @MainActor
    func testALibraryRowIsFoundByAddressOrArxivNumber() {
        let essay = Book(id: "e", title: "Essay", filePath: "Books/e/a.epub", sourceURL: "https://www.aeon.co/essays/x/")
        let paper = Book(id: "p", title: "Paper", filePath: "Books/p/a.epub", sourceURL: "https://arxiv.org/html/2610.28632v1")
        let index = FeedLibraryIndex([essay, paper])
        func item(link: String, arxivID: String? = nil) -> FeedItem {
            FeedItem(
                id: link, sourceID: "s", title: "t", link: URL(string: link)!, publishedAt: nil, authors: [],
                summary: "", characterCount: nil, categories: [], arxivID: arxivID, pdfURL: nil,
                firstSeenAt: Date(), rank: 0, keptBookID: nil
            )
        }
        XCTAssertEqual(index.book(for: item(link: "http://aeon.co/essays/x"))?.id, "e")
        XCTAssertEqual(index.book(for: item(link: "https://arxiv.org/abs/2610.28632v2", arxivID: "2610.28632v2"))?.id, "p")
        XCTAssertNil(index.book(for: item(link: "https://aeon.co/essays/y")))
    }

    func testEveryRecommendationIsAnHTTPSFeed() {
        XCTAssertEqual(FeedRecommendation.all.count, 6)
        for recommendation in FeedRecommendation.all {
            XCTAssertEqual(recommendation.feedURL.scheme, "https", recommendation.title)
        }
        XCTAssertEqual(FeedRecommendation.all.filter(\.isArxiv).count, 1)
    }
}
