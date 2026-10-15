//
//  RootTabAccessibilityUITests.swift
//  dipleUITests
//

import XCTest

/// The shell keeps all four roots mounted and shows one of them (`RootTabView`). The three it
/// hides have to leave the accessibility tree, not only the screen. Until 2026-10-15 they did
/// not: VoiceOver could walk into four screens at once, and `buttons["Settings"]` matched the
/// shelf's gear under Home's — which is how the two Settings tests came to fail.
final class RootTabAccessibilityUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOnlyTheRootOnScreenIsInTheAccessibilityTree() throws {
        let app = XCUIApplication()
        app.launchArguments = ["-diple_has_completed_first_launch", "YES"]
        app.launch()

        // Landmarks that are there whatever the library holds: the wordmark only Home prints,
        // and the navigation bar only the search root shows. The gear needs a library to be
        // doubled — an empty shelf prints no masthead — but it is the query that broke.
        let wordmark = app.staticTexts["diple."]
        let searchBar = app.navigationBars["Search"]
        let settings = app.buttons.matching(NSPredicate(format: "label == 'Settings'"))

        XCTAssertTrue(wordmark.waitForExistence(timeout: 5))
        XCTAssertFalse(searchBar.exists)
        XCTAssertEqual(settings.count, 1)

        app.buttons["shell.search"].tap()
        XCTAssertTrue(searchBar.waitForExistence(timeout: 5))
        XCTAssertFalse(wordmark.exists)
        XCTAssertEqual(settings.count, 0)

        app.buttons["Home"].tap()
        XCTAssertTrue(wordmark.waitForExistence(timeout: 5))
        XCTAssertFalse(searchBar.exists)
        XCTAssertEqual(settings.count, 1)
    }
}
