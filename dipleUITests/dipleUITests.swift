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
        app.launchArguments = ["-diple_has_completed_first_launch", "YES"]
        app.launch()

        // Use XCTAssert and related functions to verify your tests produce the correct results.
    }

    @MainActor
    func testFirstLaunchIntro() throws {
        let app = XCUIApplication()
        // A dedicated QA argument reproduces a new installation without deleting the
        // developer's library or overriding the UserDefaults value that the intro itself must
        // be able to commit when it leaves.
        app.launchArguments = ["-diple-test-first-launch"]
        app.launch()

        let intro = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label BEGINSWITH 'Welcome to diple'"))
            .firstMatch
        XCTAssertTrue(intro.waitForExistence(timeout: 5))

        // Capture the central beat — opened pages, the icon mark and its reading line — rather
        // than racing the self-dismiss transition at the very end of the sequence.
        Thread.sleep(forTimeInterval: 2.0)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "First launch colophon"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        XCTAssertTrue(intro.exists)

        // The finished colophon now keeps its promise: TAP TO BEGIN remains on screen until
        // the reader taps, rather than appearing a fraction of a second before an automatic
        // dismissal.
        Thread.sleep(forTimeInterval: 3.0)
        XCTAssertTrue(intro.exists)
        intro.tap()
        let introGone = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: intro
        )
        wait(for: [introGone], timeout: 2)
        XCTAssertTrue(app.staticTexts["diple."].waitForExistence(timeout: 2))
    }

    @MainActor
    func testSettingsColophon() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-diple_has_completed_first_launch", "YES"]
        app.launch()

        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        let colophon = app.descendants(matching: .any)
            .matching(identifier: "settings.colophon")
            .firstMatch
        XCTAssertTrue(colophon.waitForExistence(timeout: 5))

        let comfortableBottomEdge = app.frame.maxY - 80
        for _ in 0..<8 where !colophon.isHittable || colophon.frame.maxY > comfortableBottomEdge {
            app.swipeUp()
        }

        XCTAssertTrue(colophon.isHittable)
        XCTAssertLessThanOrEqual(colophon.frame.maxY, comfortableBottomEdge)
        XCTAssertEqual(
            colophon.label,
            "designed and created by chemical pink. diple. version 1.0"
        )

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Settings colophon"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testSettingsShowsRestoreAndTruthfulSyncControls() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-diple_has_completed_first_launch", "YES"]
        app.launch()

        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()

        let export = app.buttons["settings.data.export"]
        let restore = app.buttons["settings.data.restore"]
        XCTAssertTrue(export.waitForExistence(timeout: 5))
        XCTAssertTrue(restore.exists)

        for _ in 0..<7 where !export.isHittable || !restore.isHittable {
            app.swipeUp()
        }

        XCTAssertTrue(export.isHittable)
        XCTAssertTrue(restore.isHittable)
        XCTAssertTrue(app.staticTexts["iCloud Sync"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Data restore controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    @MainActor
    func testNotesWorkspaceAndCaptureFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-diple_has_completed_first_launch", "YES"]
        app.launch()

        // diple owns a floating tab bar rather than using UITabBar, so the destinations are
        // regular accessible buttons in XCUI's hierarchy.
        let notesTab = app.buttons["Notes"]
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
    func testLivingMarginsTapSwipeEditAndCloseFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-diple_has_completed_first_launch", "YES",
            "-diple-test-living-margins"
        ]
        app.launch()

        let marker = app.buttons.matching(identifier: "livingMargins.marker.fixture").firstMatch
        XCTAssertTrue(marker.waitForExistence(timeout: 5))
        XCTAssertEqual(marker.label, "Note attached")

        marker.tap()
        var note = app.buttons.matching(identifier: "livingMargins.note").firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 3))
        XCTAssertEqual(note.label, "This thought stayed beside the first passage.")

        let openMarginShot = XCTAttachment(screenshot: app.screenshot())
        openMarginShot.name = "Living Margins open field"
        openMarginShot.lifetime = .keepAlways
        add(openMarginShot)

        note.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        note = app.buttons.matching(identifier: "livingMargins.note").firstMatch
        XCTAssertEqual(note.label, "This thought stayed beside the first passage. Revised.")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5))
            .press(
                forDuration: 0.08,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
            )
        note = app.buttons.matching(identifier: "livingMargins.note").firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 2))
        XCTAssertEqual(note.label, "A second thought, further into the book.")

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
            .press(
                forDuration: 0.08,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.88, dy: 0.5))
            )
        XCTAssertFalse(note.waitForExistence(timeout: 1))

        // The production reader installs a UIScreenEdgePanGestureRecognizer on Readium. This
        // deterministic host mirrors the same threshold so XCUI can exercise the entry route.
        let edge = app.coordinate(withNormalizedOffset: CGVector(dx: 0.99, dy: 0.52))
        let inward = app.coordinate(withNormalizedOffset: CGVector(dx: 0.52, dy: 0.52))
        edge.press(forDuration: 0.08, thenDragTo: inward)
        note = app.buttons.matching(identifier: "livingMargins.note").firstMatch
        XCTAssertTrue(note.waitForExistence(timeout: 2))

        let close = app.buttons.matching(identifier: "livingMargins.close").firstMatch
        XCTAssertTrue(close.exists)
        close.tap()
        XCTAssertFalse(note.waitForExistence(timeout: 1))
    }

    @MainActor
    func testEquationComposerAndRenderedFormulaFlow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-diple_has_completed_first_launch", "YES"]
        app.launch()

        XCTAssertTrue(app.buttons["Notes"].waitForExistence(timeout: 5))
        app.buttons["Notes"].tap()
        let newNote = app.buttons.matching(identifier: "notes.new").firstMatch
        XCTAssertTrue(newNote.waitForExistence(timeout: 5))
        newNote.tap()

        let noteTitle = "Equation QA · \(Int(Date().timeIntervalSince1970))"
        let title = app.textFields["note.title"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        title.tap()
        title.typeText(noteTitle)

        let equationButton = app.buttons["Equation"]
        XCTAssertTrue(equationButton.waitForExistence(timeout: 5))
        equationButton.tap()

        let source = app.textViews["formula.source"]
        XCTAssertTrue(source.waitForExistence(timeout: 5))
        source.tap()
        source.typeText(#"\frac{x + 1}{y}"#)

        let blockMode = app.buttons["Block"]
        XCTAssertTrue(blockMode.waitForExistence(timeout: 5))
        blockMode.tap()
        XCTAssertTrue(app.staticTexts["EQUATION"].waitForExistence(timeout: 5))

        let composerShot = XCTAttachment(screenshot: app.screenshot())
        composerShot.name = "Live equation composer"
        composerShot.lifetime = .keepAlways
        add(composerShot)

        let insert = app.buttons["formula.insert"]
        XCTAssertTrue(insert.isEnabled)
        insert.tap()

        let body = app.textViews["note.body"]
        XCTAssertTrue(body.waitForExistence(timeout: 5))
        XCTAssertTrue((body.value as? String)?.contains("$$") == true)

        app.buttons["Done"].tap()
        let savedNote = app.staticTexts[noteTitle].firstMatch
        XCTAssertTrue(savedNote.waitForExistence(timeout: 5))
        savedNote.tap()
        XCTAssertTrue(app.staticTexts["EQUATION"].waitForExistence(timeout: 5))

        let readerShot = XCTAttachment(screenshot: app.screenshot())
        readerShot.name = "Rendered block equation"
        readerShot.lifetime = .keepAlways
        add(readerShot)
    }

    @MainActor
    func testLaunchPerformance() throws {
        // This measures how long it takes to launch your application.
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            let app = XCUIApplication()
            app.launchArguments = ["-diple_has_completed_first_launch", "YES"]
            app.launch()
        }
    }

    @MainActor
    func testTemporaryReaderColophonQA() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-diple_has_completed_first_launch", "YES"]
        app.launch()

        let book = app.staticTexts["The Picture of Dorian Gray"].firstMatch
        XCTAssertTrue(book.waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.32)).tap()
        XCTAssertTrue(app.webViews.firstMatch.waitForExistence(timeout: 15))

        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)).tap()
        let start = app.coordinate(withNormalizedOffset: CGVector(dx: 0.08, dy: 0.89))
        let nearEnd = app.coordinate(withNormalizedOffset: CGVector(dx: 0.91, dy: 0.89))
        start.press(forDuration: 0.1, thenDragTo: nearEnd)

        let nextPage = app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.5))
        let close = app.buttons["Close"]
        for _ in 0..<50 where !close.exists {
            nextPage.tap()
        }
        for _ in 0..<10 where !close.exists {
            app.swipeLeft()
        }
        XCTAssertTrue(close.waitForExistence(timeout: 3))

        let webView = app.webViews.firstMatch
        let textBeforeTaps = webView.descendants(matching: .staticText)
            .allElementsBoundByIndex.map(\.label)
        XCTAssertFalse(textBeforeTaps.isEmpty)
        for _ in 0..<3 {
            nextPage.tap()
        }
        let textAfterTaps = webView.descendants(matching: .staticText)
            .allElementsBoundByIndex.map(\.label)
        XCTAssertEqual(textAfterTaps, textBeforeTaps)
        XCTAssertTrue(app.buttons["Keep reading"].exists)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Finished colophon blocking the reader"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }
}
