import XCTest
@testable import diple

/// The rule that decides whether a passage is a term, which is the whole of the lookup slot's
/// behaviour: a term goes to the dictionary, prose goes to the translator. Nothing here asks
/// the system whether the word is *in* a dictionary — `DictionaryLookup.term` records why that
/// question is deliberately not part of the rule.
final class DictionaryLookupTests: XCTestCase {
    func testAWordIsATerm() {
        XCTAssertEqual(DictionaryLookup.term(in: "carnival"), "carnival")
    }

    func testSentencePunctuationIsTrimmedFromBothEnds() {
        XCTAssertEqual(DictionaryLookup.term(in: "carnival."), "carnival")
        XCTAssertEqual(DictionaryLookup.term(in: "“carnival,”"), "carnival")
        XCTAssertEqual(DictionaryLookup.term(in: "(carnival)"), "carnival")
        XCTAssertEqual(DictionaryLookup.term(in: "  carnival \n"), "carnival")
    }

    func testPunctuationInsideTheWordIsTheWord() {
        XCTAssertEqual(DictionaryLookup.term(in: "well-being"), "well-being")
        XCTAssertEqual(DictionaryLookup.term(in: "don’t"), "don’t")
    }

    func testShortPhrasesAreEntriesToo() {
        XCTAssertEqual(DictionaryLookup.term(in: "ad hoc"), "ad hoc")
        XCTAssertEqual(DictionaryLookup.term(in: "carry on with"), "carry on with")
    }

    func testProseIsNotATerm() {
        XCTAssertNil(DictionaryLookup.term(in: "You cannot buy the revolution."))
        XCTAssertNil(
            DictionaryLookup.term(in: "antidisestablishmentarianism antidisestablishmentarianism")
        )
    }

    func testSomethingWithNoLetterInItIsNotATerm() {
        XCTAssertNil(DictionaryLookup.term(in: "1938"))
        XCTAssertNil(DictionaryLookup.term(in: "…"))
        XCTAssertNil(DictionaryLookup.term(in: "   "))
        XCTAssertNil(DictionaryLookup.term(in: ""))
    }

    /// The two scripts this library is actually in besides English. Both are single words with
    /// nothing ASCII in them, and the rule must not quietly be a rule about Latin.
    func testCyrillicAndHangulAreTerms() {
        XCTAssertEqual(DictionaryLookup.term(in: "свобода."), "свобода")
        XCTAssertEqual(DictionaryLookup.term(in: "자유"), "자유")
    }
}
