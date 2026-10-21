import Foundation
import SwiftSoup

public nonisolated enum FeedFetchError: LocalizedError, Equatable {
    case notAnAddress
    case status(Int)
    case tooLarge
    case noFeed

    public var errorDescription: String? {
        switch self {
        case .notAnAddress:
            return "That doesn’t look like a web address."
        case .status(let code):
            return "The site answered with error \(code)."
        case .tooLarge:
            return "That feed is too large to read."
        case .noFeed:
            return "No feed at that address. Try the site’s home page, or a link ending in /feed."
        }
    }
}

/// Reading a feed over the network, politely.
///
/// Every check sends back the validators of the last answer (`If-None-Match`,
/// `If-Modified-Since`), so a source with nothing new costs a status line instead of the whole
/// document again — most of them, on most checks. Off the main actor throughout: parsing a
/// feed of full essays is real work.
public nonisolated enum FeedFetcher {
    public enum Outcome: Sendable {
        case feed(ParsedFeed, etag: String?, lastModified: String?)
        case notModified
    }

    /// A feed is a few hundred kilobytes at most; past this it is not a feed.
    private static let maximumBytes = 6 * 1024 * 1024

    static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 40
        configuration.httpAdditionalHeaders = [
            // Some hosts answer a client that does not look like a browser with a challenge page
            // instead of the feed — the same reason `LinkImporter` sends the same string.
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1",
            "Accept": "application/rss+xml, application/atom+xml, application/feed+json, application/xml;q=0.9, text/xml;q=0.9, text/html;q=0.8, */*;q=0.5"
        ]
        return URLSession(configuration: configuration)
    }()

    public static func fetch(_ url: URL, etag: String? = nil, lastModified: String? = nil) async throws -> Outcome {
        var request = URLRequest(url: url)
        if let etag { request.setValue(etag, forHTTPHeaderField: "If-None-Match") }
        if let lastModified { request.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since") }

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        if http?.statusCode == 304 { return .notModified }
        if let code = http?.statusCode, !(200..<300).contains(code) { throw FeedFetchError.status(code) }
        guard data.count <= maximumBytes else { throw FeedFetchError.tooLarge }

        let feed = try FeedParser.parse(data, url: response.url ?? url)
        return .feed(
            feed,
            etag: http?.value(forHTTPHeaderField: "ETag"),
            lastModified: http?.value(forHTTPHeaderField: "Last-Modified")
        )
    }

    /// What an address the reader typed turned out to be: a feed, or a page that may name one.
    enum Probe {
        case feed(ParsedFeed, finalURL: URL, etag: String?, lastModified: String?)
        case page(html: String, finalURL: URL)
    }

    /// One request for both questions, so a blog's home page is downloaded once and not once to
    /// learn it is not a feed and again to read its head.
    static func probe(_ url: URL) async throws -> Probe? {
        let (data, response) = try await session.data(from: url)
        let http = response as? HTTPURLResponse
        if let code = http?.statusCode, !(200..<300).contains(code) { throw FeedFetchError.status(code) }
        guard data.count <= maximumBytes else { throw FeedFetchError.tooLarge }
        let finalURL = response.url ?? url

        if let feed = try? FeedParser.parse(data, url: finalURL), !feed.items.isEmpty {
            return .feed(
                feed,
                finalURL: finalURL,
                etag: http?.value(forHTTPHeaderField: "ETag"),
                lastModified: http?.value(forHTTPHeaderField: "Last-Modified")
            )
        }
        guard let html = String(data: data, encoding: .utf8) ?? String(data: data, encoding: .isoLatin1) else {
            return nil
        }
        return .page(html: html, finalURL: finalURL)
    }
}

/// From whatever the reader typed — `quantamagazine.org`, a Substack's name, an essay's own
/// address — to the feed that site publishes.
///
/// In the order a person would look: the address may already be a feed; a page names its feed
/// in its `<head>` (`<link rel="alternate">`), which nearly every blog engine writes; failing
/// that, the handful of paths feeds conventionally live at. A few hosts are known well enough to
/// go straight to their feed — a Substack, a Medium author, an arXiv listing.
public nonisolated enum FeedDiscovery {
    public struct Found: Sendable {
        public let feedURL: URL
        public let feed: ParsedFeed
        public let etag: String?
        public let lastModified: String?
        /// Set when the address was an arXiv listing: the fields it names.
        public let arxivFields: [String]?
    }

    public static func find(_ input: String) async throws -> Found {
        guard let url = normalize(input) else { throw FeedFetchError.notAnAddress }

        if let fields = arxivFields(in: url) {
            let feedURL = ArxivField.feedURL(for: fields)
            if case let .feed(feed, etag, lastModified) = try await FeedFetcher.fetch(feedURL) {
                return Found(feedURL: feedURL, feed: feed, etag: etag, lastModified: lastModified, arxivFields: fields)
            }
            throw FeedFetchError.noFeed
        }

        let target = known(url) ?? url
        var pageFailure: Error?
        do {
            switch try await FeedFetcher.probe(target) {
            case let .feed(feed, finalURL, etag, lastModified):
                return Found(feedURL: finalURL, feed: feed, etag: etag, lastModified: lastModified, arxivFields: nil)
            case let .page(html, finalURL):
                if let found = try await firstFeed(in: alternates(inHTML: html, baseURL: finalURL)) { return found }
            case nil:
                break
            }
        } catch {
            // The address itself did not answer. The conventional paths on its host still might,
            // but if they do not either, this is the failure worth reporting.
            pageFailure = error
        }

        let conventional = conventionalPaths.compactMap { URL(string: $0, relativeTo: origin(of: target))?.absoluteURL }
        if let found = try await firstFeed(in: conventional) { return found }

        if let pageFailure { throw pageFailure }
        throw FeedFetchError.noFeed
    }

    private static func firstFeed(in candidates: [URL]) async throws -> Found? {
        for candidate in candidates {
            guard let outcome = try? await FeedFetcher.fetch(candidate),
                  case let .feed(feed, etag, lastModified) = outcome,
                  !feed.items.isEmpty
            else { continue }
            return Found(feedURL: candidate, feed: feed, etag: etag, lastModified: lastModified, arxivFields: nil)
        }
        return nil
    }

    /// Where feeds conventionally live, most common first.
    private static let conventionalPaths = [
        "/feed", "/rss", "/feed.xml", "/atom.xml", "/rss.xml", "/index.xml", "/feed/", "/rss/"
    ]

    /// What people actually type: a bare host gets `https://`, a plain `http://` is raised to
    /// `https://` — the app carries no exception from App Transport Security, so an `http`
    /// address could only fail later, and less clearly.
    public static func normalize(_ raw: String) -> URL? {
        var text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(" ") else { return nil }
        if text.hasPrefix("@") { return nil }
        let lowercased = text.lowercased()
        if !lowercased.hasPrefix("http://") && !lowercased.hasPrefix("https://") {
            guard !lowercased.contains("://") else { return nil }
            text = "https://" + text
        }
        guard var components = URLComponents(string: text),
              let host = components.host,
              host.contains("."), !host.hasPrefix("."), !host.hasSuffix(".")
        else { return nil }
        components.scheme = "https"
        components.fragment = nil
        return components.url
    }

    /// Hosts whose feed is known from the address alone.
    static func known(_ url: URL) -> URL? {
        guard let host = url.host?.lowercased() else { return nil }
        let path = url.path
        if host.hasSuffix(".substack.com"), path.isEmpty || path == "/" {
            return URL(string: "https://\(host)/feed")
        }
        if host == "medium.com" || host == "www.medium.com", path.hasPrefix("/@") {
            let user = path.split(separator: "/").first.map(String.init) ?? ""
            return URL(string: "https://medium.com/feed/\(user)")
        }
        return nil
    }

    /// `arxiv.org/list/cs.AI/recent` → `["cs.AI"]`.
    static func arxivFields(in url: URL) -> [String]? {
        guard let host = url.host?.lowercased(), host == "arxiv.org" || host.hasSuffix(".arxiv.org") else { return nil }
        let parts = url.path.split(separator: "/").map(String.init)
        if parts.count >= 2, parts[0] == "list" {
            return [parts[1]]
        }
        if host == "rss.arxiv.org", parts.count >= 2 {
            return parts[1].split(separator: "+").map(String.init)
        }
        return nil
    }

    /// The feeds a page names in its head, Atom and RSS before JSON.
    static func alternates(inHTML html: String, baseURL: URL) -> [URL] {
        guard let document = try? SwiftSoup.parse(html, baseURL.absoluteString),
              let links = try? document.select("link[rel~=(?i)alternate][href]")
        else { return [] }

        var found: [(rank: Int, url: URL)] = []
        for link in links.array() {
            let type = ((try? link.attr("type")) ?? "").lowercased()
            let rank: Int
            if type.contains("atom") { rank = 0 }
            else if type.contains("rss") { rank = 1 }
            else if type.contains("feed+json") || type.contains("json") { rank = 2 }
            else { continue }
            guard let href = try? link.attr("href"),
                  let url = URL(string: href, relativeTo: baseURL)?.absoluteURL
            else { continue }
            // A comments feed is a feed, but not the one meant.
            if url.absoluteString.lowercased().contains("comments") { continue }
            found.append((rank, upgraded(url)))
        }
        return found.sorted { $0.rank < $1.rank }.map(\.url)
    }

    private static func upgraded(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return url }
        components.scheme = "https"
        return components.url ?? url
    }

    private static func origin(of url: URL) -> URL? {
        var components = URLComponents()
        components.scheme = "https"
        components.host = url.host
        components.port = url.port
        components.path = "/"
        return components.url
    }
}
