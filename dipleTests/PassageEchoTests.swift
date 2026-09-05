import XCTest
@testable import diple

@MainActor
final class PassageEchoTests: XCTestCase {
    private func passage(_ id: String, book: String = "book-a", _ text: String, comment: String? = nil) -> Highlight {
        Highlight(
            id: id,
            bookId: book,
            locator: "",
            text: text,
            comment: comment,
            createdAt: Date(timeIntervalSince1970: 100),
            bookTitle: book
        )
    }

    /// Filler that gives the corpus a vocabulary to be common *against*. Without it every word
    /// in the library is rare and everything answers everything.
    private var filler: [Highlight] {
        (1...8).map { index in
            passage(
                "filler-\(index)",
                book: "book-filler",
                "Здесь читатель просто читает страницу номер \(index) и ничего особенного не происходит."
            )
        }
    }

    /// The claim the feature makes: passages built from the same *uncommon* words answer each
    /// other, and passages sharing only the library's everyday words do not.
    func testTwoPassagesSharingRareWordsAnswerEachOtherAndCommonWordsDoNot() {
        let subject = passage("subject", "Полифония романа держится на карнавальном смехе.")
        let answer = passage("answer", book: "book-b", "Карнавальное начало и полифония — одно и то же открытие.")
        let commonOnly = passage("common", book: "book-c", "Здесь читатель просто читает страницу и ничего особенного.")

        let corpus = PassageEchoCorpus(filler + [subject, answer, commonOnly])
        let echoes = corpus.echoes(for: subject)

        XCTAssertEqual(echoes.map(\.passage.id), ["answer"])
        let echo = try? XCTUnwrap(echoes.first)
        XCTAssertTrue(
            echo?.sharedTerms.contains("полифония") ?? false,
            "the words that made the connection are printed as the passage wrote them, not as stems"
        )
        XCTAssertTrue(
            corpus.echoes(for: commonOnly).isEmpty,
            "sharing the words everybody uses is not a connection"
        )
    }

    /// In a library of four passages every word is rare, so rarity measures nothing. Silence is
    /// the honest output, not a shrug of low-confidence guesses.
    func testASmallLibraryOffersNothingRatherThanNoise() {
        let few = [
            passage("a", "Полифония романа."),
            passage("b", "Полифония и карнавал."),
            passage("c", "Что-то ещё.")
        ]
        let corpus = PassageEchoCorpus(few)
        XCTAssertFalse(corpus.isUsable)
        XCTAssertTrue(corpus.echoes(for: few[0]).isEmpty)
    }

    /// One shared word is a coincidence; the rule asks for two.
    func testOneSharedWordIsNotAConnection() {
        let subject = passage("subject", "Карнавал занимает целую главу.")
        let neighbour = passage("neighbour", book: "book-b", "Карнавал в совершенно другом смысле.")
        // Both carry exactly one distinctive word in common — `карнавал` — because everything
        // else in them is filler vocabulary.
        let corpus = PassageEchoCorpus(filler + [subject, neighbour])
        XCTAssertTrue(corpus.echoes(for: subject).isEmpty)
    }

    /// Two passages from one book are usually two paragraphs of one argument. Where the promise
    /// is "somewhere else in your reading", the same source is not an answer.
    func testTheSameSourceCanBeExcluded() {
        let subject = passage("subject", "Полифония романа держится на карнавальном смехе.")
        let neighbour = passage("neighbour", "Полифония и карнавальный смех, страницей позже.")
        let corpus = PassageEchoCorpus(filler + [subject, neighbour])

        XCTAssertEqual(corpus.echoes(for: subject).map(\.passage.id), ["neighbour"])
        XCTAssertTrue(corpus.echoes(for: subject, excludingSameSource: true).isEmpty)
    }

    /// The reader's own words count. The most valuable connection in a reading library is
    /// between the two moments they wrote something down.
    func testACommentIsPartOfThePassage() {
        let subject = passage("subject", "Ничем не примечательная строка.", comment: "Полифония и карнавальный смех снова.")
        let answer = passage("answer", book: "book-b", "Полифония романа и карнавальный смех.")
        let corpus = PassageEchoCorpus(filler + [subject, answer])
        XCTAssertEqual(corpus.echoes(for: subject).map(\.passage.id), ["answer"])
    }

    /// The same library must produce the same page every time it is drawn.
    func testTheOrderIsStable() {
        let subject = passage("subject", "Полифония романа держится на карнавальном смехе.")
        let answers = (1...3).map {
            passage("answer-\($0)", book: "book-\($0)", "Полифония и карнавальный смех у автора \($0).")
        }
        let corpus = PassageEchoCorpus(filler + [subject] + answers)
        let first = corpus.echoes(for: subject, limit: 3).map(\.passage.id)
        let second = PassageEchoCorpus(filler + [subject] + answers.reversed())
            .echoes(for: subject, limit: 3)
            .map(\.passage.id)
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.count, 3)
    }

    /// Three scripts, one tokenizer. Korean does not put spaces where a splitter would want
    /// them, Russian inflects everything, and case and diacritics are not distinctions a reader
    /// means when they say "the same word".
    func testTokensCoverTheLibrarysThreeScriptsAndFoldWhatIsNotAWord() {
        let index = PassageEchoCorpus.index("Свобода, Ёлка and freedom — 책을 읽는 사람 42 a")
        XCTAssertEqual(index["свобод"], "свобода", "the key is a stem; the printed word is what was written")
        XCTAssertEqual(
            index["елка"],
            "елка",
            "ё folds onto е; four letters is too short to stem, so the key is the whole word"
        )
        XCTAssertTrue(index.keys.contains("freedom"))
        XCTAssertTrue(index.keys.contains(where: { $0.contains("책") }))
        XCTAssertFalse(index.keys.contains("42"), "a number is not a word this feature can use")
        XCTAssertFalse(index.keys.contains("a"), "a single letter connects nothing")
    }

    /// The stemmer earns its place on exactly this: two inflections of one word have to meet.
    /// It is deliberately light — four characters must survive, so short words keep their shape.
    func testTheStemmerJoinsInflectionsWithoutFilingShortWordsAway() {
        XCTAssertEqual(
            PassageEchoCorpus.stemmed("карнавальном"),
            PassageEchoCorpus.stemmed("карнавальное")
        )
        XCTAssertEqual(PassageEchoCorpus.stemmed("романа"), "роман")
        XCTAssertEqual(
            PassageEchoCorpus.stemmed("карнавал"),
            "карнавал",
            "a bare л is a noun's last letter far more often than it is a past tense"
        )
        XCTAssertEqual(PassageEchoCorpus.stemmed("дом"), "дом", "nothing left to spare")
        XCTAssertEqual(PassageEchoCorpus.stemmed("поле"), "поле", "four characters have to remain")
        XCTAssertEqual(
            PassageEchoCorpus.stemmed("freedom"),
            "freedom",
            "only Cyrillic is stemmed; English already has real lemmas"
        )
        XCTAssertEqual(PassageEchoCorpus.stemmed("사람들"), "사람들", "a script we do not claim to know is left alone")
    }
}
