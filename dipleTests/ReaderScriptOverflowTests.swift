import XCTest
@testable import diple

final class ReaderScriptOverflowTests: XCTestCase {
    /// A token the hyphenator has no dictionary for — a URL in a bibliography — has to wrap
    /// rather than widen the chapter. In scroll mode a document wider than the phone is a column
    /// that slides sideways and leaves blank paper on the right; in paginated mode the same line
    /// is cut off at the column. See `ReaderScript.cssOverrides`.
    func testEveryScriptLetsAnUnbreakableTokenWrap() {
        for script in [ReaderScript.latin, .cjk] {
            XCTAssertEqual(script.cssOverrides["overflow-wrap"] ?? nil, "break-word", "\(script)")
        }
    }
}
