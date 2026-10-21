import Foundation
import Combine

/// A local assembly buffer, independent of the library and of any particular note.
/// Snapshots keep a collected quotation usable even if its source is later removed.
public struct QuoteClip: Codable, Identifiable, Equatable, Sendable {
    public let id: String
    public let text: String
    public let source: String?
    public let colorHex: String
    public var usedInNoteID: String?

    public init(passage: PassageItem) {
        id = passage.id
        text = passage.highlight.text
        source = passage.book?.title ?? passage.highlight.bookTitle
        colorHex = passage.highlight.colorHex
    }

    public var markdown: String {
        var lines = text.components(separatedBy: .newlines).map { "> " + $0 }
        if let source, !source.isEmpty {
            lines.append("> — " + source.components(separatedBy: .newlines).joined(separator: " "))
        }
        return lines.joined(separator: "\n")
    }
}

@MainActor
public final class QuoteTray: ObservableObject {
    public static let shared = QuoteTray(defaults: .standard)
    @Published public private(set) var clips: [QuoteClip]
    private let defaults: UserDefaults
    private static let storageKey = "diple_quote_tray_v1"

    public init(defaults: UserDefaults) {
        self.defaults = defaults
        clips = defaults.data(forKey: Self.storageKey)
            .flatMap { try? JSONDecoder().decode([QuoteClip].self, from: $0) } ?? []
    }

    public var pending: [QuoteClip] { clips.filter { $0.usedInNoteID == nil } }
    public func contains(_ id: String) -> Bool { pending.contains { $0.id == id } }

    public func collect(_ passages: [PassageItem]) {
        for passage in passages where !passage.highlight.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let index = clips.firstIndex(where: { $0.id == passage.id }) {
                // Collecting the same highlight again refreshes it, without a duplicate card.
                clips[index] = QuoteClip(passage: passage)
            } else {
                clips.append(QuoteClip(passage: passage))
            }
        }
        persist()
    }

    public func remove(_ id: String) {
        clips.removeAll { $0.id == id }
        persist()
    }

    public func markUsed(_ id: String, in noteID: String) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[index].usedInNoteID = noteID
        persist()
    }

    public func restore(_ id: String) {
        guard let index = clips.firstIndex(where: { $0.id == id }) else { return }
        clips[index].usedInNoteID = nil
        persist()
    }

    private func persist() {
        guard let data = try? JSONEncoder().encode(clips) else { return }
        defaults.set(data, forKey: Self.storageKey)
    }
}

/// Uses UTF-16 just like UITextView. The quote is a separate Markdown block even when
/// inserted in the middle of a sentence, and the caret lands in the following blank paragraph.
public enum QuoteInsertion {
    public static func insert(_ clip: QuoteClip, in text: inout String, selection: inout NSRange) {
        let source = text as NSString
        let start = min(max(0, selection.location), source.length)
        let length = min(max(0, selection.length), source.length - start)
        let before = source.substring(to: start)
        let after = source.substring(from: start + length)
        let leading = before.isEmpty || before.hasSuffix("\n\n") ? "" : before.hasSuffix("\n") ? "\n" : "\n\n"
        let replacement = leading + clip.markdown + "\n\n"
        text = before + replacement + after
        selection = NSRange(location: start + replacement.utf16.count, length: 0)
    }
}
