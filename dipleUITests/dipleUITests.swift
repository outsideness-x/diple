//
//  dipleUITests.swift
//  dipleUITests
//
//  Created by chemical_pink on 01.08.2026.
//

import XCTest

final class dipleUITests: XCTestCase {

    override func setUpWithError() throws {
        // Put setup code here. This method is called before the invocation of each test method in the class.

        // In UI tests it is usually best to stop immediately when a failure occurs.
        continueAfterFailure = false

        // In UI tests it’s important to set the initial state - such as interface orientation - required for your tests before they run. The setUp method is a good place to do this.
    }

    override func tearDownWithError() throws {
        // Put teardown code here. This method is called after the invocation of each test method in the class.
    }

    @MainActor
    func testExample() throws {
        // UI tests must launch the application that they test.
        let app = XCUIApplication()
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testNotesWorkspaceAndCaptureFlow() throws {
        let app = XCUIApplication()
        app.launch()

        let notesTab = app.tabBars.buttons["Notes"]
        XCTAssertTrue(notesTab.waitForExistence(timeout: 5))
        notesTab.tap()

        let newNote = app.buttons.matching(identifier: "notes.new").firstMatch
        XCTAssertTrue(newNote.waitForExistence(timeout: 5))

        let workspaceShot = XCTAttachment(screenshot: app.screenshot())
        workspaceShot.name = "Notes workspace"
        workspaceShot.lifetime = .keepAlways
        add(workspaceShot)

        newNote.tap()

        let noteTitle = "A thought worth keeping · \(Int(Date().timeIntervalSince1970))"
        let title = app.textFields["note.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText(noteTitle)

        let body = app.textViews["note.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        body.tap()
        body.typeText("## The idea\n\nReading becomes knowledge when a note is easy to return to.\n\n## Next step\n\n- [ ] Follow the thread")

        XCTAssertTrue(app.buttons["Bold"].exists)
        XCTAssertTrue(app.staticTexts["Saving…"].waitForExistence(timeout: 2) || app.staticTexts["Saved"].exists)

        let editorShot = XCTAttachment(screenshot: app.screenshot())
        editorShot.name = "Selection-aware note editor"
        editorShot.lifetime = .keepAlways
        add(editorShot)

        app.buttons["Done"].tap()
        let savedNote = app.staticTexts[noteTitle].firstMatch
        XCTAssertTrue(savedNote.waitForExistence(timeout: 5))
        savedNote.tap()

        XCTAssertTrue(app.staticTexts["On this page"].waitForExistence(timeout: 5))

        let readerShot = XCTAttachment(screenshot: app.screenshot())
        readerShot.name = "Rendered note with automatic outline"
        readerShot.lifetime = .keepAlways
        add(readerShot)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            XCUIApplication().launch()
        }
    }
}
