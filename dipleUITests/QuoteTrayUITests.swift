import XCTest

/// Exercises the simulator's real library, without generated books or highlights.
final class QuoteTrayUITests: XCTestCase {
    @MainActor
    func testCollectWriteInsertAndRestore() throws {
        continueAfterFailure = false
        let app = XCUIApplication()
        app.launchArguments = ["-diple_has_completed_first_launch", "YES", "-diple-test-notes"]
        app.launch()
        app.buttons["Highlights"].tap()

        // A passage goes into the tray from its long-press menu: the board carries no button
        // of its own on every row.
        let row = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH 'passage.row.'")).firstMatch
        try XCTSkipUnless(row.waitForExistence(timeout: 5), "Requires a saved passage in the simulator library")
        let clipID = String(row.identifier.dropFirst("passage.row.".count))
        row.press(forDuration: 1.0)
        let collect = app.buttons["quoteTray.collect.\(clipID)"]
        XCTAssertTrue(collect.waitForExistence(timeout: 3))
        if collect.label == "In quote tray" {
            // Already gathered by an earlier run: take it out and put it back, so the test
            // always starts from a passage that has just arrived.
            collect.tap()
            row.press(forDuration: 1.0)
            XCTAssertTrue(collect.waitForExistence(timeout: 3))
        }
        collect.tap()
        let write = app.buttons["quoteTray.write"]
        XCTAssertTrue(write.waitForExistence(timeout: 3))
        write.tap()

        let title = app.textFields["note.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText("Quote tray check")
        let body = app.textViews["note.body"]
        body.tap()
        body.typeText("My opening thought.")

        let card = app.buttons["quoteTray.insert.\(clipID)"]
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        // The collected card is appended. Scroll to the end before asking XCTest for an
        // offscreen button's activation point (iOS 26 throws instead of reporting false).
        scrollTrayToEnd(app)
        XCTAssertTrue(card.isHittable)
        let before = XCTAttachment(screenshot: app.screenshot())
        before.name = "Quote tray above the keyboard"
        before.lifetime = .keepAlways
        add(before)
        card.tap()
        XCTAssertTrue((body.value as? String ?? "").hasPrefix("My opening thought.\n\n> "))
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        body.typeText("My connecting thought.")
        XCTAssertTrue((body.value as? String ?? "").hasSuffix("My connecting thought."))
        let writing = XCTAttachment(screenshot: app.screenshot())
        writing.name = "Caret after the quotation"
        writing.lifetime = .keepAlways
        add(writing)

        app.buttons["Used"].tap()
        XCTAssertTrue(card.waitForExistence(timeout: 3))
        let written = body.value as? String
        card.tap()
        XCTAssertEqual(body.value as? String, written, "Restoring a card must not remove the quote from the note")
        XCTAssertTrue(card.exists)

        app.buttons["Collapse quote tray"].tap()
        XCTAssertTrue(app.buttons["Expand quote tray"].exists)
        app.buttons["Expand quote tray"].tap()
        // The collected card is appended. Scroll to the end before asking XCTest for an
        // offscreen button's activation point (iOS 26 throws instead of reporting false).
        scrollTrayToEnd(app)
        XCTAssertTrue(card.isHittable)
        let after = XCTAttachment(screenshot: app.screenshot())
        after.name = "Quote woven into a note"
        after.lifetime = .keepAlways
        add(after)

        app.buttons["Done"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }
        let wide = expectation(for: NSPredicate { _, _ in app.frame.width > app.frame.height }, evaluatedWith: app)
        wait(for: [wide], timeout: 5)
        XCTAssertGreaterThan(card.frame.minX, body.frame.minX)
        let landscape = XCTAttachment(screenshot: app.screenshot())
        landscape.name = "Quote tray beside the page at wide width"
        landscape.lifetime = .keepAlways
        add(landscape)
    }

    /// Drags along the row of cards itself, not at the centre of the strip: the strip reports a
    /// frame that runs on under the keyboard, and a swipe aimed at its middle lands on the keys.
    private func scrollTrayToEnd(_ app: XCUIApplication) {
        let strip = app.scrollViews["quoteTray.cards"]
        XCTAssertTrue(strip.waitForExistence(timeout: 3))
        for _ in 0..<4 {
            let start = strip.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0))
                .withOffset(CGVector(dx: 0, dy: 50))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: -300, dy: 0)))
        }
    }
}
