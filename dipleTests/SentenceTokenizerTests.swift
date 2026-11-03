import XCTest
import WebKit
@testable import diple

final class SentenceTokenizerTests: XCTestCase {

    func testMultiSentenceEnglishParagraph() {
        let text = "It was a bright cold day in April. The clocks were striking thirteen! Winston Smith hurried home."
        let all = SentenceTokenizer.sentences(in: text, language: "en")
        XCTAssertEqual(all.map(\.text), [
            "It was a bright cold day in April.",
            "The clocks were striking thirteen!",
            "Winston Smith hurried home."
        ])

        // Tap inside the second sentence.
        let offset = (text as NSString).range(of: "striking").location
        let tapped = SentenceTokenizer.sentence(in: text, atUTF16Offset: offset, language: "en")
        XCTAssertEqual(tapped?.text, "The clocks were striking thirteen!")
        if let tapped {
            let slice = (text as NSString).substring(with: NSRange(location: tapped.utf16Start, length: tapped.utf16End - tapped.utf16Start))
            XCTAssertEqual(slice, "The clocks were striking thirteen!")
        }
    }

    func testEnglishAbbreviationsAndInitialsStayInSentence() {
        let text = "In Jan. 1895, Dr. J. R. R. Tolkien visited St. Petersburg with Mr. and Mrs. Smith (see fig. 4, p. 12, e.g. the map). They returned on Friday."
        let all = SentenceTokenizer.sentences(in: text, language: "en")
        XCTAssertEqual(all.map(\.text), [
            "In Jan. 1895, Dr. J. R. R. Tolkien visited St. Petersburg with Mr. and Mrs. Smith (see fig. 4, p. 12, e.g. the map).",
            "They returned on Friday."
        ])

        let offset = (text as NSString).range(of: "Petersburg").location
        let match = SentenceTokenizer.sentence(in: text, atUTF16Offset: offset, language: "en")
        XCTAssertEqual(
            match?.text,
            "In Jan. 1895, Dr. J. R. R. Tolkien visited St. Petersburg with Mr. and Mrs. Smith (see fig. 4, p. 12, e.g. the map)."
        )
    }

    func testRussianAbbreviationsAndInitials() {
        let text = "В 1833 г. А. С. Пушкин приехал в с. Болдино (см. т. 4, стр. 18, т. е. черновики) и написал поэму. Осень выдалась тихой."
        let all = SentenceTokenizer.sentences(in: text, language: "ru")
        XCTAssertEqual(all.map(\.text), [
            "В 1833 г. А. С. Пушкин приехал в с. Болдино (см. т. 4, стр. 18, т. е. черновики) и написал поэму.",
            "Осень выдалась тихой."
        ])

        let offset = (text as NSString).range(of: "Пушкин").location
        let match = SentenceTokenizer.sentence(in: text, atUTF16Offset: offset, language: "ru")
        XCTAssertEqual(
            match?.text,
            "В 1833 г. А. С. Пушкин приехал в с. Болдино (см. т. 4, стр. 18, т. е. черновики) и написал поэму."
        )
    }

    func testRussianTemporalIntroBeforeCapitalizedProperNoun() {
        let text = "В 1917 г. Россия пережила переворот. В XIX в. Москва быстро росла."
        let all = SentenceTokenizer.sentences(in: text, language: "ru")
        XCTAssertEqual(all.map(\.text), [
            "В 1917 г. Россия пережила переворот.",
            "В XIX в. Москва быстро росла."
        ])
    }

    func testDialogueAttributionStaysAttachedWhileSeparateQuotesSplit() {
        let english = "“Where are you going?” she asked quietly. “Wait!” “Don’t leave yet!”"
        let enSentences = SentenceTokenizer.sentences(in: english, language: "en")
        XCTAssertEqual(enSentences.map(\.text), [
            "“Where are you going?” she asked quietly.",
            "“Wait!”",
            "“Don’t leave yet!”"
        ])

        let russianQuotes = "«Куда ты идёшь?» — спросил он тихо. «Подожди!» «Не уходи!»"
        let ruQuoteSentences = SentenceTokenizer.sentences(in: russianQuotes, language: "ru")
        XCTAssertEqual(ruQuoteSentences.map(\.text), [
            "«Куда ты идёшь?» — спросил он тихо.",
            "«Подожди!»",
            "«Не уходи!»"
        ])

        let russianDash = "— Куда ты идёшь? — спросил он. — В город."
        let ruDashSentences = SentenceTokenizer.sentences(in: russianDash, language: "ru")
        XCTAssertEqual(ruDashSentences.map(\.text), [
            "— Куда ты идёшь? — спросил он.",
            "— В город."
        ])
    }

    func testEllipsisMidSentenceVersusEndOfSentence() {
        let text = "She hesitated… and then spoke softly. The room fell silent… Nobody moved."
        let all = SentenceTokenizer.sentences(in: text, language: "en")
        XCTAssertEqual(all.map(\.text), [
            "She hesitated… and then spoke softly.",
            "The room fell silent…",
            "Nobody moved."
        ])
    }

    func testNumberedListPrefixStaysAttached() {
        let text = "1. First principle of reading. Second sentence follows."
        let all = SentenceTokenizer.sentences(in: text, language: "en")
        XCTAssertEqual(all.map(\.text), [
            "1. First principle of reading.",
            "Second sentence follows."
        ])
    }

    func testKoreanAndJapaneseSentences() {
        let korean = "오늘 날씨가 정말 좋습니다. 내일도 맑을까요?"
        let koAll = SentenceTokenizer.sentences(in: korean, language: "ko")
        XCTAssertEqual(koAll.map(\.text), [
            "오늘 날씨가 정말 좋습니다.",
            "내일도 맑을까요?"
        ])

        let japanese = "吾輩は猫である。名前はまだ無い。"
        let jaAll = SentenceTokenizer.sentences(in: japanese, language: "ja")
        XCTAssertEqual(jaAll.map(\.text), [
            "吾輩は猫である。",
            "名前はまだ無い。"
        ])
    }

    func testNonLetterOrnamentReturnsNil() {
        let ornament = "   * * *   "
        XCTAssertNil(SentenceTokenizer.sentence(in: ornament, atUTF16Offset: 4))
    }

    func testReaderSettingsLanguageLearningModePersistence() throws {
        var settings = ReaderSettings()
        XCTAssertFalse(settings.isLanguageLearningMode)
        settings.isLanguageLearningMode = true

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(ReaderSettings.self, from: data)
        XCTAssertTrue(decoded.isLanguageLearningMode)
    }

    @MainActor
    func testWebViewEndToEndSentenceHitTestAndHighlight() async throws {
        let config = WKWebViewConfiguration()
        config.userContentController.addUserScript(
            WKUserScript(
                source: ReaderSentenceScript.source,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            )
        )
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 390, height: 844), configuration: config)

        let html = """
        <!doctype html>
        <html lang="en">
        <head>
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
            :root[style*="--USER__backgroundColor"] * { background-color: transparent !important; }
            body { margin: 48px 32px; font-size: 20px; line-height: 1.6; }
            p { margin: 0 0 24px 0; }
        </style>
        </head>
        <body style="--USER__backgroundColor: #141413;">
            <p id="p1"><span class="drop">F</span>irst sentence here. <span id="target">Dr. <em>Jekyll</em> met
            Mr. Hyde<sup id="fn">14</sup> in the fog.</span> Third sentence ends the paragraph.</p>
        </body>
        </html>
        """
        webView.loadHTMLString(html, baseURL: nil)

        // Wait until layout completes and `#target` has a non-empty rect.
        var targetCenter: (x: Double, y: Double)?
        for _ in 0 ..< 40 {
            if let rectDict = try? await webView.evaluateJavaScript("""
                (function() {
                    var el = document.getElementById('target');
                    if (!el) return null;
                    var r = el.getBoundingClientRect();
                    if (r.width <= 0 || r.height <= 0) return null;
                    return { x: r.left + 12, y: r.top + r.height / 2 };
                })();
            """) as? [String: Double],
               let x = rectDict["x"],
               let y = rectDict["y"] {
                targetCenter = (x, y)
                break
            }
            try await Task.sleep(for: .milliseconds(50))
        }

        let center = try XCTUnwrap(targetCenter)

        // 1. Hit-test on the second sentence (spanning `<span>`, `<em>`, source newline, and `<sup>14</sup>`).
        let hitRaw = try await webView.evaluateJavaScript("window.__dipleSentenceHitTest(\(center.x), \(center.y));")
        let hit = try XCTUnwrap(hitRaw as? [String: Any])
        let blockText = try XCTUnwrap(hit["text"] as? String)
        let offset = try XCTUnwrap(hit["offset"] as? Int)
        let lang = hit["lang"] as? String

        let match = try XCTUnwrap(SentenceTokenizer.sentence(in: blockText, atUTF16Offset: offset, language: lang))
        XCTAssertEqual(match.text, "Dr. Jekyll met Mr. Hyde in the fog.")

        // 2. Highlight the matched sentence range and verify DOM boxes are painted with inline !important fill.
        let highlighted = try await webView.evaluateJavaScript(
            "window.__dipleHighlightSentenceRange(\(match.utf16Start), \(match.utf16End), true);"
        ) as? Bool
        XCTAssertEqual(highlighted, true)

        let boxCount = try await webView.evaluateJavaScript("""
            (function() {
                var layer = document.getElementById('diple-sentence-highlight-layer');
                return layer ? layer.children.length : 0;
            })();
        """) as? Int
        XCTAssertGreaterThan(boxCount ?? 0, 0)

        // 3. Tapping in the empty bottom margin returns null and clears the highlight.
        let marginHit = try await webView.evaluateJavaScript("window.__dipleSentenceHitTest(195, 800);")
        XCTAssertTrue(marginHit == nil || marginHit is NSNull)

        let boxCountAfterClear = try await webView.evaluateJavaScript("""
            (function() {
                var layer = document.getElementById('diple-sentence-highlight-layer');
                return layer ? layer.children.length : 0;
            })();
        """) as? Int
        XCTAssertEqual(boxCountAfterClear, 0)
    }
}
