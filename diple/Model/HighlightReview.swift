import Foundation
import GRDB

/// The smallest durable state required for spaced resurfacing. One row belongs to one saved
/// passage; the passage itself remains the content and this row only answers when it should
/// return. Using the highlight id as the primary key also gives CloudKit a stable record id.
public struct HighlightReview: Codable, FetchableRecord, PersistableRecord, Equatable, Sendable {
    public var highlightId: String
    public var lastReviewedAt: Date
    public var nextReviewAt: Date
    public var intervalDays: Int
    public var reviewCount: Int

    public init(
        highlightId: String,
        lastReviewedAt: Date,
        nextReviewAt: Date,
        intervalDays: Int,
        reviewCount: Int
    ) {
        self.highlightId = highlightId
        self.lastReviewedAt = lastReviewedAt
        self.nextReviewAt = nextReviewAt
        self.intervalDays = intervalDays
        self.reviewCount = reviewCount
    }
}

public enum HighlightReviewResponse: Sendable {
    case againSoon
    case remembered
}
