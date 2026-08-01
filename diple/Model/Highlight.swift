import Foundation
import GRDB
import ReadiumShared

public struct Highlight: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Hashable {
    public var id: String
    public var bookId: String
    public var locator: String
    public var text: String
    public var colorHex: String
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        bookId: String,
        locator: String,
        text: String,
        colorHex: String = "#FFD60A",
        createdAt: Date = Date()
    ) {
        self.id = id
        self.bookId = bookId
        self.locator = locator
        self.text = text
        self.colorHex = colorHex
        self.createdAt = createdAt
    }

    public var parsedLocator: Locator? {
        if let loc = try? Locator(jsonString: locator) {
            return loc
        }
        return try? Locator(legacyJSONString: locator)
    }
}
