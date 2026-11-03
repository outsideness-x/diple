import Foundation
import NaturalLanguage

/// A sentence extracted from a block of prose, paired with its exact UTF-16 code-unit bounds in
/// the source string so the page can highlight the same span it hands to the system translator.
public struct SentenceMatch: Equatable, Sendable {
    /// The sentence text with internal whitespace collapsed to single spaces.
    public let text: String
    /// Inclusive start index in UTF-16 code units within the input string.
    public let utf16Start: Int
    /// Exclusive end index in UTF-16 code units within the input string.
    public let utf16End: Int

    public nonisolated init(text: String, utf16Start: Int, utf16End: Int) {
        self.text = text
        self.utf16Start = utf16Start
        self.utf16End = utf16End
    }
}

/// Segments prose into literary sentences for language-learning tap-to-translate.
///
/// `NLTokenizer(unit: .sentence)` provides the ICU baseline across Latin, Cyrillic, Hangul and
/// CJK scripts, and a second pass repairs the places where standard ICU sentence break rules
/// misfire on books:
/// - Titles, scholarly references and pre-nominal abbreviations (`Mr.`, `Dr.`, `St.`, `Prof.`,
///   `fig.`, `e.g.`, `i.e.`, `ул.`, `проф.`, `см.`, `т. е.`) that precede a capitalised name.
/// - Single-letter initials (`A. S. Pushkin`, `J. R. R. Tolkien`, `А. С. Пушкин`).
/// - Introductory Russian date/century phrases (`В 1917 г. Россия…`, `В XIX в. Пушкин…`) and
///   context-dependent abbreviations (`etc.`, `т.д.`, `т.п.`, `г.`, `в.`) when followed by
///   continuation text rather than a new sentence.
/// - Mid-sentence ellipses (`…`, `...`) and direct-speech attributions (`"Where to?" she asked.`,
///   `«Куда?» — спросил он.`, `— Куда? — спросил он.`) where the segment after `?`/`!` starts
///   with a lowercase verb of speaking.
/// - Adjacent quoted or dash-introduced sentences (`“Wait!” “Don’t go!”`, `Он вошёл. — Привет!`)
///   that `NLTokenizer` occasionally leaves fused.
public enum SentenceTokenizer {

    /// Abbreviations that almost never end a declarative sentence on their own and therefore
    /// attach to the following word even when that word begins with an uppercase letter.
    private nonisolated static let nonFinalAbbreviations: Set<String> = [
        // English honorifics, titles & scholarly markers
        "mr.", "mrs.", "ms.", "mx.", "dr.", "prof.", "rev.", "fr.", "st.", "mt.", "ft.",
        "capt.", "col.", "gen.", "lt.", "sgt.", "maj.", "adm.", "cpl.", "pvt.", "gov.",
        "sen.", "rep.", "pres.", "hon.", "messrs.", "mmes.", "vs.", "v.", "cf.", "e.g.",
        "i.e.", "viz.", "fig.", "figs.", "vol.", "vols.", "no.", "nos.", "p.", "pp.",
        "ch.", "pt.", "sec.", "ed.", "eds.", "trans.", "tr.", "approx.", "ca.",
        // Russian pre-nominal & reference abbreviations
        "г-н.", "г-жа.", "тов.", "проф.", "акад.", "доц.", "д-р.", "канд.", "им.", "св.",
        "ул.", "пер.", "пл.", "наб.", "бул.", "ш.", "кв.", "корп.", "обл.", "р-н.", "дер.",
        "пос.", "ст.", "оз.", "см.", "ср.", "напр.", "т.е.", "т. е.", "т.к.", "т. к.",
        "т.н.", "т. н.", "гл.", "рис.", "табл.", "тыс.", "млн.", "млрд.",
        "с.", "стр.", "т.", "тт.", "ч.", "п.", "пп.", "д.", "р.", "о.",
        // French, German, Spanish & Italian literary abbreviations
        "m.", "mme.", "mlle.", "mgr.", "ste.", "vgl.", "hr.", "nr.", "bd.", "z.b.", "z. b.",
        "d.h.", "d. h.", "sra.", "srta.", "pág.", "págs.", "cap.", "sig.", "dott."
    ]

    /// Abbreviations that can appear either mid-sentence or at the end of a sentence. They stay
    /// attached when followed by lowercase text, digits, or mid-sentence punctuation.
    private nonisolated static let contextAbbreviations: Set<String> = [
        "etc.", "al.", "et al.", "inc.", "ltd.", "corp.", "co.", "bros.", "jr.", "sr.",
        "a.m.", "p.m.", "u.s.", "u.k.", "e.u.", "b.c.", "a.d.", "ph.d.", "m.d.",
        "г.", "гг.", "в.", "вв.", "т.д.", "т. д.", "т.п.", "т. п.", "н.э.", "н. э.",
        "др.", "пр.", "руб.", "коп.", "чел.", "экз.", "u.a.", "u. a.", "usw.", "bzw.", "jh."
    ]

    private nonisolated static let closingPunctuation: Set<Character> = [
        "\"", "”", "’", "'", "»", "›", ")", "]", "}", "」", "』", "】", "）"
    ]

    private nonisolated static let openingPunctuation: Set<Character> = [
        "\"", "“", "‘", "'", "«", "‹", "(", "[", "{", "「", "『", "【", "（"
    ]

    private nonisolated static let dialogueDashes: Set<Character> = [
        "—", "–", "-", "―", "‒"
    ]

    private nonisolated static let hardTermCharacters: Set<Character> = [
        ".", "!", "?", "…", "。", "！", "？", "⁈", "⁇", "⁉"
    ]

    /// Returns the sentence containing `offset` (in UTF-16 code units), or `nil` if the offset
    /// does not fall on a prose sentence containing at least one letter.
    public nonisolated static func sentence(
        in text: String,
        atUTF16Offset offset: Int,
        language: String? = nil
    ) -> SentenceMatch? {
        let totalUTF16 = text.utf16.count
        guard totalUTF16 > 0 else { return nil }
        let clampedOffset = min(max(offset, 0), totalUTF16)

        let paragraphRanges = splitHardLines(in: text)
        guard let paragraphRange = paragraphRanges.first(where: { range in
            let start = range.lowerBound.utf16Offset(in: text)
            let end = range.upperBound.utf16Offset(in: text)
            return clampedOffset >= start && clampedOffset <= end
        }) else {
            return nil
        }

        let matches = sentences(inParagraph: paragraphRange, of: text, language: language)
        guard !matches.isEmpty else { return nil }

        // Direct hit inside a sentence's span.
        if let direct = matches.first(where: { clampedOffset >= $0.utf16Start && clampedOffset <= $0.utf16End }) {
            return direct
        }

        // If the tap landed on the whitespace between two sentences, pick the nearest one.
        var bestMatch: SentenceMatch?
        var bestDistance = Int.max
        for match in matches {
            let distance: Int
            if clampedOffset < match.utf16Start {
                distance = match.utf16Start - clampedOffset
            } else {
                distance = clampedOffset - match.utf16End
            }
            if distance <= bestDistance {
                bestDistance = distance
                bestMatch = match
            }
        }
        return bestMatch
    }

    /// Returns all sentences in `text`.
    public nonisolated static func sentences(
        in text: String,
        language: String? = nil
    ) -> [SentenceMatch] {
        splitHardLines(in: text).flatMap { paragraphRange in
            sentences(inParagraph: paragraphRange, of: text, language: language)
        }
    }

    // MARK: - Paragraph Pipeline

    private nonisolated static func splitHardLines(in text: String) -> [Range<String.Index>] {
        var ranges: [Range<String.Index>] = []
        var lineStart = text.startIndex
        var idx = text.startIndex

        while idx < text.endIndex {
            let ch = text[idx]
            if ch == "\n" || ch == "\r" || ch == "\u{2028}" || ch == "\u{2029}" {
                if lineStart < idx {
                    ranges.append(lineStart ..< idx)
                }
                idx = text.index(after: idx)
                lineStart = idx
            } else {
                idx = text.index(after: idx)
            }
        }
        if lineStart < text.endIndex {
            ranges.append(lineStart ..< text.endIndex)
        }
        return ranges
    }

    private nonisolated static func sentences(
        inParagraph paragraphRange: Range<String.Index>,
        of text: String,
        language: String?
    ) -> [SentenceMatch] {
        let paragraphSubstring = text[paragraphRange]
        guard paragraphSubstring.contains(where: { $0.isLetter }) else { return [] }

        // 1. Initial ICU segmentation via NLTokenizer.
        let initialSpans = initialTokenRanges(in: paragraphRange, of: text, language: language)
        guard !initialSpans.isEmpty else { return [] }

        // 2. Split any sentences that NLTokenizer left fused (e.g. adjacent quotes or dash dialogue).
        var refinedSpans: [Range<String.Index>] = []
        for (index, span) in initialSpans.enumerated() {
            let subSpans = splitMissedBoundaries(
                in: span,
                of: text,
                isFirstInParagraph: index == 0 && refinedSpans.isEmpty
            )
            refinedSpans.append(contentsOf: subSpans)
        }

        // 3. Heal false splits after abbreviations, initials, ellipses, and dialogue attributions.
        var mergedSpans: [Range<String.Index>] = []
        for span in refinedSpans {
            guard let previous = mergedSpans.last else {
                mergedSpans.append(span)
                continue
            }
            let leftText = String(text[previous])
            let rightText = String(text[span])
            if shouldMerge(
                left: leftText,
                right: rightText,
                isAtParagraphStart: mergedSpans.count == 1
            ) {
                mergedSpans[mergedSpans.count - 1] = previous.lowerBound ..< span.upperBound
            } else {
                mergedSpans.append(span)
            }
        }

        // 4. Trim whitespace and build SentenceMatch values.
        return mergedSpans.compactMap { rawSpan in
            finalizeMatch(for: rawSpan, in: text)
        }
    }

    private nonisolated static func initialTokenRanges(
        in paragraphRange: Range<String.Index>,
        of text: String,
        language: String?
    ) -> [Range<String.Index>] {
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        if let resolvedLanguage = resolveLanguage(for: String(text[paragraphRange]), hint: language) {
            tokenizer.setLanguage(resolvedLanguage)
        }

        var rawTokens = tokenizer.tokens(for: paragraphRange)
        if rawTokens.isEmpty {
            rawTokens = [paragraphRange]
        }

        // Absorb any immediately trailing closing quotes/brackets that NLTokenizer left outside
        // a sentence token so `"Hello."` keeps its closing quote.
        var adjusted: [Range<String.Index>] = []
        for i in rawTokens.indices {
            var lower = rawTokens[i].lowerBound
            if let prevUpper = adjusted.last?.upperBound, lower < prevUpper {
                lower = prevUpper
            }
            var upper = rawTokens[i].upperBound
            let limit = (i + 1 < rawTokens.count) ? paragraphRange.upperBound : paragraphRange.upperBound
            while upper < limit, closingPunctuation.contains(text[upper]) {
                upper = text.index(after: upper)
            }
            if lower < upper {
                adjusted.append(lower ..< upper)
            }
        }
        return adjusted
    }

    private nonisolated static func resolveLanguage(for sample: String, hint: String?) -> NLLanguage? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(sample)
        if let dominant = recognizer.dominantLanguage, dominant != .undetermined {
            return dominant
        }
        guard let hint = hint?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased(),
              !hint.isEmpty
        else {
            return nil
        }
        let prefix = String(hint.prefix(2))
        return NLLanguage(rawValue: prefix)
    }

    // MARK: - Splitting Missed Boundaries

    private nonisolated static func splitMissedBoundaries(
        in span: Range<String.Index>,
        of text: String,
        isFirstInParagraph: Bool
    ) -> [Range<String.Index>] {
        var results: [Range<String.Index>] = []
        var segmentStart = span.lowerBound
        var cursor = span.lowerBound

        while cursor < span.upperBound {
            let ch = text[cursor]
            guard hardTermCharacters.contains(ch) else {
                cursor = text.index(after: cursor)
                continue
            }

            // Consume repeated terminators (`...`, `?!`, `!!`) and any immediately attached
            // closing quotes or brackets (`.”`, `!»`, `.)`).
            var punctEnd = text.index(after: cursor)
            while punctEnd < span.upperBound, hardTermCharacters.contains(text[punctEnd]) {
                punctEnd = text.index(after: punctEnd)
            }
            while punctEnd < span.upperBound, closingPunctuation.contains(text[punctEnd]) {
                punctEnd = text.index(after: punctEnd)
            }

            // Look for whitespace (or CJK fullwidth punctuation followed immediately by text).
            let isCJKPunct = (ch == "。" || ch == "！" || ch == "？")
            var nextStart = punctEnd
            while nextStart < span.upperBound, text[nextStart].isWhitespace {
                nextStart = text.index(after: nextStart)
            }

            let hasGap = (nextStart > punctEnd) || isCJKPunct
            guard hasGap, nextStart < span.upperBound else {
                cursor = punctEnd
                continue
            }

            let leftCandidate = String(text[segmentStart ..< punctEnd])
            let rightCandidate = String(text[nextStart ..< span.upperBound])

            if looksLikeNewSentenceStart(rightCandidate, afterPunctuation: ch, fullLeft: leftCandidate)
                && !shouldMerge(
                    left: leftCandidate,
                    right: rightCandidate,
                    isAtParagraphStart: isFirstInParagraph && results.isEmpty
                ) {
                results.append(segmentStart ..< punctEnd)
                segmentStart = nextStart
                cursor = nextStart
            } else {
                cursor = punctEnd
            }
        }

        if segmentStart < span.upperBound {
            results.append(segmentStart ..< span.upperBound)
        }
        return results
    }

    private nonisolated static func looksLikeNewSentenceStart(
        _ right: String,
        afterPunctuation punct: Character,
        fullLeft: String
    ) -> Bool {
        let trimmed = right.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first else { return false }

        // Dialogue dash (`— Привет!`) starting a new sentence when followed by an uppercase letter.
        if dialogueDashes.contains(first) {
            let afterDash = trimmed.drop(while: { dialogueDashes.contains($0) || $0.isWhitespace })
            guard let firstAfterDash = afterDash.first else { return false }
            if openingPunctuation.contains(firstAfterDash) {
                let afterOpen = afterDash.drop(while: { openingPunctuation.contains($0) || $0.isWhitespace })
                return afterOpen.first.map { $0.isUppercase || isCaselessScriptLetter($0) } ?? false
            }
            return firstAfterDash.isUppercase || isCaselessScriptLetter(firstAfterDash)
        }

        // Opening quote (`“Hello`, `«Привет`) followed by an uppercase letter or caseless script.
        if openingPunctuation.contains(first) {
            let afterQuote = trimmed.drop(while: { openingPunctuation.contains($0) || $0.isWhitespace })
            guard let firstInside = afterQuote.first else { return false }
            return firstInside.isUppercase || isCaselessScriptLetter(firstInside)
        }

        if first.isUppercase || isCaselessScriptLetter(first) {
            return true
        }

        // CJK fullwidth sentence punctuation always ends a sentence before digits/letters.
        if (punct == "。" || punct == "！" || punct == "？") && (first.isLetter || first.isNumber) {
            return true
        }

        return false
    }

    private nonisolated static func isCaselessScriptLetter(_ ch: Character) -> Bool {
        ch.isLetter && !ch.isUppercase && !ch.isLowercase
    }

    // MARK: - Healing False Splits

    private nonisolated static func shouldMerge(
        left: String,
        right: String,
        isAtParagraphStart: Bool
    ) -> Bool {
        let leftTrimmed = left.trimmingCharacters(in: .whitespacesAndNewlines)
        let rightTrimmed = right.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !leftTrimmed.isEmpty, !rightTrimmed.isEmpty else { return true }

        // 1. Unbalanced parentheses or brackets across the split.
        if hasUnclosedBracket(in: leftTrimmed, closedIn: rightTrimmed) {
            return true
        }

        // 2. Leading list marker at the start of a paragraph (`1.`, `IV.`, `a)`).
        if isAtParagraphStart, isListMarker(leftTrimmed) {
            return true
        }

        // 3. Mid-sentence ellipsis (`…` or `...`) followed by lowercase or dialogue continuation.
        if endsWithEllipsis(leftTrimmed), startsWithContinuationOrLowercase(rightTrimmed) {
            return true
        }

        // 4. Direct speech / question / exclamation followed by lowercase dialogue attribution
        //    (`"Where are you going?" she asked.`, `«Куда?» — спросил он.`, `— Куда? — спросил он.`).
        if endsWithSentenceOrQuote(leftTrimmed), startsWithContinuationOrLowercase(rightTrimmed) {
            return true
        }

        // 5. Abbreviations and initials ending with a period.
        if leftTrimmed.hasSuffix(".") {
            if endsWithNonFinalAbbreviation(leftTrimmed) {
                return true
            }
            if endsWithInitial(leftTrimmed), rightStartsWithNameOrInitial(rightTrimmed) {
                return true
            }
            if endsWithContextAbbreviation(leftTrimmed) {
                if startsWithContinuationOrLowercase(rightTrimmed) || rightStartsWithDigit(rightTrimmed) {
                    return true
                }
                if isShortRussianTemporalIntro(leftTrimmed) || isRussianCityPrefix(leftTrimmed) {
                    return true
                }
            }
            if endsWithDigitDot(leftTrimmed), rightStartsWithDigit(rightTrimmed) {
                return true
            }
        }

        return false
    }

    private nonisolated static func hasUnclosedBracket(in left: String, closedIn right: String) -> Bool {
        let openParen = left.filter { $0 == "(" }.count - left.filter { $0 == ")" }.count
        if openParen > 0, right.contains(")") {
            return true
        }
        let openBracket = left.filter { $0 == "[" }.count - left.filter { $0 == "]" }.count
        if openBracket > 0, right.contains("]") {
            return true
        }
        return false
    }

    private nonisolated static func isListMarker(_ token: String) -> Bool {
        let stripped = token.drop(while: { openingPunctuation.contains($0) })
        guard stripped.hasSuffix(".") || stripped.hasSuffix(")") else { return false }
        let core = String(stripped.dropLast())
        guard !core.isEmpty, core.count <= 6 else { return false }
        if core.allSatisfy({ $0.isNumber }) { return true }
        let romanChars: Set<Character> = ["I", "V", "X", "L", "C", "D", "M", "i", "v", "x", "l", "c", "d", "m"]
        if core.allSatisfy({ romanChars.contains($0) }) { return true }
        if core.count == 1, let only = core.first, only.isLetter { return true }
        return false
    }

    private nonisolated static func endsWithEllipsis(_ left: String) -> Bool {
        var core = Substring(left)
        while let last = core.last, closingPunctuation.contains(last) {
            core = core.dropLast()
        }
        return core.hasSuffix("…") || core.hasSuffix("...") || core.hasSuffix(". . .")
    }

    private nonisolated static func endsWithSentenceOrQuote(_ left: String) -> Bool {
        var core = Substring(left)
        while let last = core.last, closingPunctuation.contains(last) {
            core = core.dropLast()
        }
        guard let last = core.last else { return false }
        return hardTermCharacters.contains(last)
    }

    private nonisolated static func startsWithContinuationOrLowercase(_ right: String) -> Bool {
        var rest = Substring(right)
        // A comma, semicolon, colon, or closing paren immediately continues the sentence.
        if let first = rest.first, [",", ";", ":", ")", "]"].contains(first) {
            return true
        }
        // Skip leading dialogue dashes and whitespace (`— спросил он`).
        if let first = rest.first, dialogueDashes.contains(first) {
            rest = rest.drop(while: { dialogueDashes.contains($0) || $0.isWhitespace })
        }
        guard let ch = rest.first else { return false }
        return ch.isLowercase
    }

    private nonisolated static func rightStartsWithDigit(_ right: String) -> Bool {
        guard let first = right.first else { return false }
        return first.isNumber
    }

    private nonisolated static func endsWithDigitDot(_ left: String) -> Bool {
        guard left.hasSuffix(".") else { return false }
        let beforeDot = left.dropLast()
        guard let last = beforeDot.last else { return false }
        return last.isNumber
    }

    private nonisolated static func endsWithNonFinalAbbreviation(_ left: String) -> Bool {
        let lower = left.lowercased()
        for abbr in nonFinalAbbreviations where abbr.contains(" ") {
            if lower.hasSuffix(abbr), isWordBoundary(in: lower, beforeSuffixCount: abbr.count) {
                return true
            }
        }
        let tail = extractTrailingToken(from: lower)
        return nonFinalAbbreviations.contains(tail)
    }

    private nonisolated static func endsWithContextAbbreviation(_ left: String) -> Bool {
        let lower = left.lowercased()
        for abbr in contextAbbreviations where abbr.contains(" ") {
            if lower.hasSuffix(abbr), isWordBoundary(in: lower, beforeSuffixCount: abbr.count) {
                return true
            }
        }
        let tail = extractTrailingToken(from: lower)
        return contextAbbreviations.contains(tail)
    }

    /// Detects short Russian introductory time expressions like `"В 1917 г."` or `"В XIX в."`
    /// so they stay attached even when the next word is a capitalised proper noun (`"Россия"`).
    private nonisolated static func isShortRussianTemporalIntro(_ left: String) -> Bool {
        let lower = left.lowercased()
        let temporalSuffixes = [" г.", " гг.", " в.", " вв.", " н.э.", " н. э."]
        guard temporalSuffixes.contains(where: { lower.hasSuffix($0) }) else { return false }
        let words = lower.split(whereSeparator: { $0.isWhitespace })
        guard words.count >= 2 && words.count <= 5 else { return false }
        let penultimate = words[words.count - 2]
        let romanChars: Set<Character> = ["i", "v", "x", "l", "c", "d", "m"]
        return penultimate.contains(where: { $0.isNumber })
            || penultimate.allSatisfy({ romanChars.contains($0) })
    }

    /// Detects `"г."` used as `"город"` (`"в г. Москве"`, `"г. Санкт-Петербург"`), where the
    /// preceding token is not a year/number.
    private nonisolated static func isRussianCityPrefix(_ left: String) -> Bool {
        let lower = left.lowercased()
        guard lower == "г." || lower.hasSuffix(" г.") else { return false }
        let words = lower.split(whereSeparator: { $0.isWhitespace })
        guard words.count >= 2 else { return true }
        let penultimate = words[words.count - 2]
        return !penultimate.contains(where: { $0.isNumber })
    }

    /// Checks whether `left` ends with a single-letter uppercase initial (`A.`, `J. R. R.`, `А. С.`).
    private nonisolated static func endsWithInitial(_ left: String) -> Bool {
        guard left.hasSuffix(".") else { return false }
        let withoutDot = left.dropLast()
        guard let lastChar = withoutDot.last, lastChar.isUppercase else { return false }
        let beforeChar = withoutDot.dropLast()
        guard let prev = beforeChar.last else {
            // Single-letter initial at the very start of the segment (`"A."`).
            return true
        }
        return prev.isWhitespace || openingPunctuation.contains(prev) || prev == "."
    }

    private nonisolated static func rightStartsWithNameOrInitial(_ right: String) -> Bool {
        let stripped = right.drop(while: { $0.isWhitespace || openingPunctuation.contains($0) })
        guard let first = stripped.first else { return false }
        return first.isUppercase || first.isLowercase
    }

    private nonisolated static func extractTrailingToken(from lower: String) -> String {
        var idx = lower.endIndex
        while idx > lower.startIndex {
            let prev = lower.index(before: idx)
            let ch = lower[prev]
            if ch.isWhitespace || openingPunctuation.contains(ch) || closingPunctuation.contains(ch) {
                break
            }
            idx = prev
        }
        return String(lower[idx ..< lower.endIndex])
    }

    private nonisolated static func isWordBoundary(in text: String, beforeSuffixCount count: Int) -> Bool {
        guard text.count > count else { return true }
        let idx = text.index(text.endIndex, offsetBy: -count)
        let prev = text[text.index(before: idx)]
        return prev.isWhitespace || openingPunctuation.contains(prev)
    }

    // MARK: - Finalizing Sentence Match

    private nonisolated static func finalizeMatch(
        for rawRange: Range<String.Index>,
        in text: String
    ) -> SentenceMatch? {
        var start = rawRange.lowerBound
        var end = rawRange.upperBound

        while start < end, text[start].isWhitespace {
            start = text.index(after: start)
        }
        while end > start, text[text.index(before: end)].isWhitespace {
            end = text.index(before: end)
        }
        guard start < end else { return nil }

        let rawSlice = text[start ..< end]
        guard rawSlice.contains(where: { $0.isLetter }) else { return nil }

        let normalized = rawSlice
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
        guard !normalized.isEmpty else { return nil }

        let utf16Start = start.utf16Offset(in: text)
        let utf16End = end.utf16Offset(in: text)
        guard utf16End > utf16Start else { return nil }

        return SentenceMatch(
            text: normalized,
            utf16Start: utf16Start,
            utf16End: utf16End
        )
    }
}
