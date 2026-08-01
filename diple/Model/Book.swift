import Foundation
import GRDB

public struct Book: Codable, FetchableRecord, PersistableRecord, Identifiable, Equatable, Hashable {
    public var id: String
    public var title: String
    public var author: String?
    public var filePath: String
    public var coverPath: String?
    public var addedAt: Date
    public var lastOpenedAt: Date?
    public var progress: Double
    public var locator: String?

    public init(
        id: String = UUID().uuidString,
        title: String,
        author: String? = nil,
        filePath: String,
        coverPath: String? = nil,
        addedAt: Date = Date(),
        lastOpenedAt: Date? = nil,
        progress: Double = 0.0,
        locator: String? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.filePath = filePath
        self.coverPath = coverPath
        self.addedAt = addedAt
        self.lastOpenedAt = lastOpenedAt
        self.progress = progress
        self.locator = locator
    }
}
