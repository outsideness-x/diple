import XCTest

/// Uses the simulator's existing library; no generated books or passages are installed.
final class HighlightsScrollPerformanceTests: XCTestCase {
    @MainActor
    func testScrollingPassages() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "-diple_has_completed_first_launch", "YES",
            "-diple_notes_layout", "list"
        ]
        app.launch()
        app.buttons["Highlights"].tap()

        let catalogue = app.scrollViews["highlights.catalogue"]
        XCTAssertTrue(catalogue.waitForExistence(timeout: 5))
        let passage = app.buttons.matching(NSPredicate(format: "label CONTAINS 'Marked '")).firstMatch
        try XCTSkipUnless(passage.waitForExistence(timeout: 5), "Requires saved passages in the simulator library")

        let options = XCTMeasureOptions()
        options.iterationCount = 3
        var metrics: [XCTMetric] = [XCTOSSignpostMetric.scrollingAndDecelerationMetric]
        if #available(iOS 26.0, *) {
            metrics.append(XCTHitchMetric(application: app))
        }
        measure(metrics: metrics, options: options) {
            catalogue.swipeUp(velocity: .fast)
            catalogue.swipeUp(velocity: .fast)
            catalogue.swipeDown(velocity: .fast)
            catalogue.swipeDown(velocity: .fast)
        }
        // A fast reverse flick need not finish at exactly the same content offset. Check
        // that the persistent shell still responds instead of assuming the masthead is visible.
        app.buttons["shell.search"].tap()
        XCTAssertTrue(app.navigationBars["Search"].waitForExistence(timeout: 5))
    }
}
