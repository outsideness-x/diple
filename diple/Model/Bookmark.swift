import Foundation
import GRDB
import ReadiumShared

public struct Bookmark: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Hashable, Sendable {
    public var id: String
    public var bookId: String
    public var locator: String
    public var name: String
    public var colorHex: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        bookId: String,
        locator: String,
        name: String,
        colorHex: String = "#DF9BE1",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookId = bookId
        self.locator = locator
        self.name = name
        self.colorHex = colorHex
        self.createdAt = createdAt
    }

    public var parsedLocator: Locator? {
        Locator.from(jsonString: locator)
    }
}
