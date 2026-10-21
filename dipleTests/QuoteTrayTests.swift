import XCTest
import SwiftUI
@testable import diple

final class QuoteTrayTests: XCTestCase {
    // This toolchain crashes in the main-actor back-deployment deinit shim when XCTest
    // releases a hosted editor (also documented in NoteCompletionTests). Keep only the
    // selection box for the test process lifetime; its reference to the text view is weak.
    @MainActor private static let undoSelection = NoteSelectionBox()
    private func passage(_ id: String = "one", text: String = "Слова автора\n두 번째 줄") -> PassageItem {
        PassageItem(highlight: Highlight(id: id, bookId: "book", locator: "{}", text: text, bookTitle: "Источник"), tags: [], book: nil)
    }

    func testQuoteKeepsEveryLineAndSourceAndLeavesWritingSpace() {
        var body = ""
        var selection = NSRange(location: 0, length: 0)
        QuoteInsertion.insert(QuoteClip(passage: passage()), in: &body, selection: &selection)
        XCTAssertEqual(body, "> Слова автора\n> 두 번째 줄\n> — Источник\n\n")
        XCTAssertEqual(selection, NSRange(location: body.utf16.count, length: 0))
    }

    func testInsertionInMiddleOfUnicodeTextKeepsBothSides() {
        var body = "До 🧑🏽‍💻 после"
        let prefix = "До 🧑🏽‍💻"
        var selection = NSRange(location: prefix.utf16.count, length: 0)
        let clip = QuoteClip(passage: passage(text: "цитата"))
        QuoteInsertion.insert(clip, in: &body, selection: &selection)
        XCTAssertEqual(body, prefix + "\n\n> цитата\n> — Источник\n\n после")
        XCTAssertEqual((body as NSString).substring(from: selection.location), " после")
    }

    func testSelectionIsReplacedAndExistingParagraphBreaksAreKept() {
        var body = "Before\n\nreplace me\n\nAfter"
        var selection = (body as NSString).range(of: "replace me")
        QuoteInsertion.insert(QuoteClip(passage: passage(text: "quote")), in: &body, selection: &selection)
        XCTAssertTrue(body.hasPrefix("Before\n\n> quote"))
        XCTAssertFalse(body.contains("replace me"))
        XCTAssertTrue(body.hasSuffix("\n\nAfter"))
    }

    func testStaleSelectionClampsToEnd() {
        var body = "Existing"
        var selection = NSRange(location: NSNotFound, length: 100)
        QuoteInsertion.insert(QuoteClip(passage: passage(text: "quote")), in: &body, selection: &selection)
        XCTAssertEqual(body, "Existing\n\n> quote\n> — Источник\n\n")
        XCTAssertEqual(selection.location, body.utf16.count)
    }

    func testMultilineSourceCannotEscapeTheBlockquote() {
        let source = PassageItem(highlight: Highlight(bookId: "b", locator: "{}", text: "Quote", bookTitle: "First\nSecond"), tags: [], book: nil)
        XCTAssertEqual(QuoteClip(passage: source).markdown, "> Quote\n> — First Second")
    }

    @MainActor
    func testCollectionDeduplicatesAndPersistsUsedStateAndRestoration() async throws {
        let suite = "QuoteTrayTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tray = QuoteTray(defaults: defaults)
        tray.collect([passage(), passage("two"), passage()])
        XCTAssertEqual(tray.pending.map(\.id), ["one", "two"])
        tray.markUsed("one", in: "note")
        let reopened = QuoteTray(defaults: defaults)
        XCTAssertEqual(reopened.pending.map(\.id), ["two"])
        XCTAssertEqual(reopened.clips.first?.usedInNoteID, "note")
        reopened.restore("one")
        XCTAssertEqual(reopened.pending.map(\.id), ["one", "two"])
        reopened.collect([passage(text: "Updated quote")])
        XCTAssertEqual(reopened.clips.first?.text, "Updated quote")
        XCTAssertEqual(reopened.clips.count, 2)
        reopened.remove("one")
        XCTAssertEqual(QuoteTray(defaults: defaults).pending.map(\.id), ["two"])
    }

    @MainActor
    func testNativeInsertionKeepsUndoHistory() async throws {
        let selection = Self.undoSelection
        var text = "Before"
        let editor = NoteEditorView(
            text: Binding(get: { text }, set: { text = $0 }),
            selection: selection,
            isFocused: .constant(false)
        )
        let host = UIHostingController(rootView: editor)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 400, height: 600))
        window.rootViewController = host
        window.makeKeyAndVisible()
        defer { window.isHidden = true }
        try await Task.sleep(for: .milliseconds(100))
        host.view.layoutIfNeeded()
        func findTextView(_ view: UIView) -> UITextView? {
            if let textView = view as? UITextView { return textView }
            return view.subviews.lazy.compactMap(findTextView).first
        }
        let native = try XCTUnwrap(findTextView(host.view))
        selection.move(to: NSRange(location: 6, length: 0))
        text = selection.insertingQuote(QuoteClip(passage: passage(text: "Quote")), into: text)
        XCTAssertEqual(native.text, "Before\n\n> Quote\n> — Источник\n\n")
        let undo = try XCTUnwrap(native.undoManager)
        XCTAssertTrue(undo.canUndo)
        undo.undo()
        XCTAssertEqual(native.text, "Before")
    }

    @MainActor
    func testEmptyPassagesAreNotCollected() async throws {
        let suite = "QuoteTrayTests." + UUID().uuidString
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let tray = QuoteTray(defaults: defaults)
        tray.collect([passage(text: " \n ")])
        XCTAssertTrue(tray.clips.isEmpty)
    }
}
