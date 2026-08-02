import Foundation
import SwiftSoup

/// Backfills full-text search for articles imported before the FTS index existed.
/// New imports are indexed in the same transaction as their book row and never come here.
public nonisolated final class ArticleSearchIndexer: Sendable {
    public static let shared = ArticleSearchIndexer()

    private init() {}

    public func indexMissingArticles() async -> Int {
        await Task.detached(priority: .utility) {
            guard let books = try? AppDatabase.shared.fetchArticlesMissingTextIndex() else { return 0 }
            var indexed = 0

            for book in books {
                let url = BookStorageService.shared.absoluteURL(for: book.filePath)
                guard let archive = try? Data(contentsOf: url, options: .mappedIfSafe),
                      let xhtml = StoredZIPReader.entry(named: "EPUB/article.xhtml", in: archive),
                      let markup = String(data: xhtml, encoding: .utf8),
                      let document = try? SwiftSoup.parse(markup),
                      let text = try? document.text(),
                      !text.isEmpty
                else { continue }

                do {
                    try AppDatabase.shared.indexArticleText(book: book, text: text)
                    indexed += 1
                } catch {
                    // A single damaged legacy article must not prevent the remaining library
                    // from becoming searchable. It stays missing and will be retried later.
                    continue
                }
            }

            return indexed
        }.value
    }
}
