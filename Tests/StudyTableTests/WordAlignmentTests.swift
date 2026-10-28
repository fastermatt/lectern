import XCTest
@testable import StudyTable

/// English word -> original word alignment. Pure-logic tests plus real-verse checks against the
/// bundled KJV Strong's tagging and STEPBible interlinear data.
@MainActor
final class WordAlignmentTests: XCTestCase {
    private let library = ScriptureLibrary()
    private let lexicon = LexiconStore()
    private let interlinear = InterlinearStore()

    // MARK: Helpers

    private func verseText(_ translation: String, _ book: String, _ chapter: Int, _ verse: Int) -> String? {
        library.chapter(translation: translation, bookCode: book, chapter: chapter)?.first { $0.number == verse }?.text
    }

    /// Aligns the `occurrence`-th (0-based) occurrence of `word` in the verse.
    private func align(_ translation: String, _ book: String, _ chapter: Int, _ verse: Int,
                       _ word: String, occurrence: Int = 0) throws -> (WordAlignmentResult, [InterlinearWord]) {
        let text = try XCTUnwrap(verseText(translation, book, chapter, verse), "\(translation) \(book) \(chapter):\(verse) missing")
        let tokens = WordTokenizer.tokens(in: text)
        let key = WordTokenizer.normalizedKey(word)
        let token = try XCTUnwrap(tokens.first { $0.key == key && $0.occurrence == occurrence },
                                  "\"\(word)\" #\(occurrence) not in: \(text)")
        let hit = WordHit(word: token.text, range: token.range, occurrence: token.occurrence, tokenIndex: token.index, key: token.key)
        let words = interlinear.words(bookCode: book, chapter: chapter, verse: verse)
        let result = WordAlignment.align(hit: hit, verseText: text,
                                         tags: lexicon.tags(bookCode: book, chapter: chapter, verse: verse), words: words)
        return (result, words)
    }

    private func lemma(_ result: WordAlignmentResult, _ words: [InterlinearWord]) -> String? {
        result.match.map { words[$0.wordIndex].lemma }
    }

    // MARK: Tokenizer

    func testTokenizerStripsPunctuationAndKeepsPossessives() {
        let tokens = WordTokenizer.tokens(in: "\u{201C}God\u{2019}s world,\u{201D} he said\u{2014}\u{201C}don't go.\u{201D}")
        XCTAssertEqual(tokens.map(\.text), ["God\u{2019}s", "world", "he", "said", "don't", "go"])
        XCTAssertEqual(tokens.map(\.key), ["god", "world", "he", "said", "don't", "go"])
    }

    func testTokenizerSplitsHyphenatedWordsAndNumbersOccurrences() {
        let tokens = WordTokenizer.tokens(in: "the God-fearing man and the woman and the child")
        XCTAssertEqual(tokens.map(\.text), ["the", "God", "fearing", "man", "and", "the", "woman", "and", "the", "child"])
        XCTAssertEqual(tokens.filter { $0.key == "the" }.map(\.occurrence), [0, 1, 2])
        XCTAssertEqual(tokens.filter { $0.key == "and" }.map(\.occurrence), [0, 1])
    }

    func testTokenRangesAreUTF16OffsetsIntoTheOriginalString() {
        let text = "Caf\u{00E9} \u{201C}Jesus\u{201D} wept"
        let ns = text as NSString
        for token in WordTokenizer.tokens(in: text) {
            XCTAssertEqual(ns.substring(with: token.range), token.text)
        }
    }

    func testApostropheWithoutLettersOnBothSidesEndsTheWord() {
        XCTAssertEqual(WordTokenizer.tokens(in: "the brothers\u{2019} houses").map(\.text), ["the", "brothers", "houses"])
        XCTAssertEqual(WordTokenizer.tokens(in: "'tis").map(\.text), ["tis"])
    }

    // MARK: Stemming

    func testStemRelatesInflectionsButNotUnrelatedWords() {
        XCTAssertEqual(WordStem.stem("loved"), WordStem.stem("love"))
        XCTAssertEqual(WordStem.stem("loves"), WordStem.stem("loveth"))
        XCTAssertEqual(WordStem.stem("believes"), WordStem.stem("believeth"))
        XCTAssertEqual(WordStem.stem("worlds"), WordStem.stem("world"))
        XCTAssertEqual(WordStem.stem("gave"), WordStem.stem("giving"))
        XCTAssertEqual(WordStem.stem("sinned"), WordStem.stem("sin"))
        XCTAssertEqual(WordStem.stem("carried"), WordStem.stem("carry"))
        XCTAssertNotEqual(WordStem.stem("forest"), WordStem.stem("for"))
        XCTAssertNotEqual(WordStem.stem("bread"), WordStem.stem("brea"))
        XCTAssertEqual(WordStem.stem("red"), "red")
        XCTAssertEqual(WordStem.stem("was"), "was")
        XCTAssertNotEqual(WordStem.stem("God"), WordStem.stem("good"))
    }

    // MARK: Synthetic alignment (no bundled data)

    private func word(_ gloss: String, _ strongs: [String], lemma: String = "λ") -> InterlinearWord {
        InterlinearWord(surface: "s", transliteration: "t", gloss: gloss, lemma: lemma, strongs: strongs,
                        morphCode: "N", morphDescription: "Noun", language: .greek)
    }

    private func hit(_ text: String, _ key: String, occurrence: Int = 0) -> WordHit {
        let token = WordTokenizer.tokens(in: text).first { $0.key == key && $0.occurrence == occurrence }!
        return WordHit(word: token.text, range: token.range, occurrence: token.occurrence, tokenIndex: token.index, key: token.key)
    }

    func testNoOriginalDataIsReportedNotGuessed() {
        let text = "In the beginning"
        let result = WordAlignment.align(hit: hit(text, "beginning"), verseText: text, tags: [], words: [])
        XCTAssertNil(result.match)
        XCTAssertEqual(result.gap, .noOriginalData)
    }

    func testArticleNeverMatchesAndOffersCandidates() {
        let text = "the Lord spoke"
        let words = [word("the", ["G3588"]), word("Lord", ["G2962"]), word("spoke", ["G2980"])]
        let tags = [WordTag(word: "Lord", strongs: ["G2962"])]
        let result = WordAlignment.align(hit: hit(text, "the"), verseText: text, tags: tags, words: words)
        XCTAssertNil(result.match)
        XCTAssertEqual(result.gap, .article)
        XCTAssertEqual(result.candidates, [0])
        XCTAssertEqual(result.provenanceLine, "\u{201C}the\u{201D} has no single original word of its own.")
        XCTAssertNotNil(result.gapExplanation)
    }

    func testFunctionWordInsideAPhraseTagDoesNotMatchThePhrase() {
        // "he" sits inside the KJV phrase "he gave"; the phrase is the verb, not a pronoun.
        let text = "he gave"
        let words = [word("He gave", ["G1325"])]
        let tags = [WordTag(word: "he gave", strongs: ["G1325"])]
        let he = WordAlignment.align(hit: hit(text, "he"), verseText: text, tags: tags, words: words)
        XCTAssertNil(he.match)
        XCTAssertEqual(he.gap, .functionWord)
        XCTAssertEqual(he.candidates, [0])
        let gave = WordAlignment.align(hit: hit(text, "gave"), verseText: text, tags: tags, words: words)
        XCTAssertEqual(gave.match?.wordIndex, 0)
        XCTAssertEqual(gave.match?.method, .kjvTag)
        XCTAssertEqual(gave.match?.confidence, .high)
    }

    func testZeroPaddedAndSuffixedStrongsNumbersNormalize() {
        // KJV tag "H1254" must find the interlinear's "H1254A"; "G25" must find "G0025".
        let hebrewText = "God created"
        let hebrew = [word("God", ["H0430G"]), word("he created", ["H1254A"])]
        let tags = [WordTag(word: "God", strongs: ["H430"]), WordTag(word: "created", strongs: ["H1254"])]
        XCTAssertEqual(WordAlignment.align(hit: hit(hebrewText, "created"), verseText: hebrewText, tags: tags, words: hebrew).match?.wordIndex, 1)
        XCTAssertEqual(WordAlignment.align(hit: hit(hebrewText, "god"), verseText: hebrewText, tags: tags, words: hebrew).match?.wordIndex, 0)
        let greekText = "loved"
        XCTAssertEqual(WordAlignment.align(hit: hit(greekText, "loved"), verseText: greekText,
                                           tags: [WordTag(word: "loved", strongs: ["G25"])], words: [word("loved", ["G0025"])]).match?.wordIndex, 0)
    }

    func testRepeatedNumberPicksTheOccurrenceOrdinal() {
        // "his" then "him" share G846; the second must pick the second original word.
        let text = "his Son in him"
        let words = [word("of him", ["G0846"]), word("Son", ["G5207"]), word("in", ["G1722"]), word("Him", ["G0846"])]
        let tags = [WordTag(word: "his", strongs: ["G846"]), WordTag(word: "Son", strongs: ["G5207"]),
                    WordTag(word: "in", strongs: ["G1722"]), WordTag(word: "him", strongs: ["G846"])]
        XCTAssertEqual(WordAlignment.align(hit: hit(text, "his"), verseText: text, tags: tags, words: words).match?.wordIndex, 0)
        XCTAssertEqual(WordAlignment.align(hit: hit(text, "him"), verseText: text, tags: tags, words: words).match?.wordIndex, 3)
    }

    func testGlossPathIsLabelledAndLessConfidentThanKJVPath() {
        let text = "a certain man"
        let words = [word("a man", ["G0444"]), word("certain", ["G5100"])]
        let result = WordAlignment.align(hit: hit(text, "man"), verseText: text, tags: [], words: words)
        XCTAssertEqual(result.match?.wordIndex, 0)
        XCTAssertEqual(result.match?.method, .glossExact)
        XCTAssertLessThan(result.match!.confidence, .high)
        XCTAssertTrue(result.isHeuristic)
        XCTAssertEqual(result.provenanceLine, "Best guess from the English gloss.")
    }

    func testStemMatchIsWeakerThanExactMatch() {
        let text = "he believes"
        let words = [word("is believing", ["G4100"])]
        let result = WordAlignment.align(hit: hit(text, "believes"), verseText: text, tags: [], words: words)
        XCTAssertEqual(result.match?.method, .glossStem)
        XCTAssertEqual(result.match?.confidence, .low)
    }

    func testNoCounterpartOffersNearestContentWords() {
        let text = "one and only Son"
        let words = [word("the", ["G3588"]), word("only begotten", ["G3439"]), word("Son", ["G5207"])]
        let result = WordAlignment.align(hit: hit(text, "one"), verseText: text, tags: [], words: words)
        XCTAssertNil(result.match)
        XCTAssertEqual(result.gap, .noCounterpart)
        XCTAssertFalse(result.candidates.isEmpty)
        XCTAssertFalse(result.candidates.contains(0), "an article is not a candidate for a content word")
        XCTAssertEqual(result.provenanceLine, "No single original word matches \u{201C}one\u{201D}.")
        XCTAssertTrue(result.gapExplanation?.contains("Translations combine") == true)
    }

    func testPossessiveClicksMatchTheBaseWord() {
        let text = "God\u{2019}s word"
        let words = [word("God", ["G2316"]), word("word", ["G3056"])]
        let tags = [WordTag(word: "God", strongs: ["G2316"]), WordTag(word: "word", strongs: ["G3056"])]
        XCTAssertEqual(WordAlignment.align(hit: hit(text, "god"), verseText: text, tags: tags, words: words).match?.wordIndex, 0)
    }

    // MARK: Real verses

    func testJohn316KnownWordsInBSBKJVAndWEB() throws {
        for translation in ["BSB", "KJV", "WEB"] {
            let (loved, words) = try align(translation, "JHN", 3, 16, "loved")
            XCTAssertEqual(lemma(loved, words), "ἀγαπάω", "\(translation) loved")
            XCTAssertEqual(words[loved.match!.wordIndex].strongs, ["G0025"])
            XCTAssertEqual(loved.match?.confidence, .high, "\(translation) loved")

            let (world, w2) = try align(translation, "JHN", 3, 16, "world")
            XCTAssertEqual(lemma(world, w2), "κόσμος", translation)
            let (god, w3) = try align(translation, "JHN", 3, 16, "God")
            XCTAssertEqual(lemma(god, w3), "θεός", translation)
            let (son, w4) = try align(translation, "JHN", 3, 16, "Son")
            XCTAssertEqual(lemma(son, w4), "υἱός", translation)
            let (perish, w5) = try align(translation, "JHN", 3, 16, "perish")
            XCTAssertEqual(lemma(perish, w5), "ἀπόλλυμι", translation)
            let (life, w6) = try align(translation, "JHN", 3, 16, "life")
            XCTAssertEqual(lemma(life, w6), "ζωή", translation)
        }
    }

    func testJohn316OnlyBegottenAndBelievesAcrossTranslations() throws {
        let (kjvOnly, kjvWords) = try align("KJV", "JHN", 3, 16, "only")
        XCTAssertEqual(lemma(kjvOnly, kjvWords), "μονογενής")
        let (kjvBegotten, w) = try align("KJV", "JHN", 3, 16, "begotten")
        XCTAssertEqual(lemma(kjvBegotten, w), "μονογενής")
        // BSB says "one and only": "only" is in the KJV tag phrase, "one" has no counterpart.
        let (bsbOnly, w2) = try align("BSB", "JHN", 3, 16, "only")
        XCTAssertEqual(lemma(bsbOnly, w2), "μονογενής")
        let (bsbOne, _) = try align("BSB", "JHN", 3, 16, "one")
        XCTAssertNil(bsbOne.match, "\"one\" in \"one and only\" has no single original word")
        XCTAssertEqual(bsbOne.gap, .noCounterpart)
        // BSB "believes" vs KJV "believeth": same stem, weaker label.
        let (believes, w3) = try align("BSB", "JHN", 3, 16, "believes")
        XCTAssertEqual(lemma(believes, w3), "πιστεύω")
        XCTAssertNotEqual(believes.match?.confidence, .high)
    }

    func testJohn316RepeatedWordsUseOrdinals() throws {
        // "that" twice: first is ὥστε (G5620), second ἵνα (G2443), in every translation that repeats it.
        for translation in ["KJV", "BSB"] {
            let (first, words) = try align(translation, "JHN", 3, 16, "that", occurrence: 0)
            let (second, _) = try align(translation, "JHN", 3, 16, "that", occurrence: 1)
            XCTAssertEqual(first.match.map { words[$0.wordIndex].strongs }, ["G5620"], translation)
            XCTAssertEqual(second.match.map { words[$0.wordIndex].strongs }, ["G2443"], translation)
        }
        // his / him share G846 but are two different original words.
        let (his, words) = try align("KJV", "JHN", 3, 16, "his")
        let (him, _) = try align("KJV", "JHN", 3, 16, "him")
        XCTAssertNotEqual(his.match?.wordIndex, him.match?.wordIndex)
        XCTAssertEqual(words[his.match!.wordIndex].transliteration, "autou")
        XCTAssertEqual(words[him.match!.wordIndex].transliteration, "auton")
    }

    func testArticlesInJohn316NeverMatchButOfferCandidates() throws {
        for translation in ["KJV", "BSB", "WEB"] {
            let (the, words) = try align(translation, "JHN", 3, 16, "the")
            XCTAssertNil(the.match, translation)
            XCTAssertEqual(the.gap, .article)
            XCTAssertFalse(the.candidates.isEmpty)
            XCTAssertTrue(the.candidates.allSatisfy { words[$0].gloss.lowercased().contains("the") })
        }
    }

    func testRomans828() throws {
        let (loveKJV, words) = try align("KJV", "ROM", 8, 28, "love")
        XCTAssertEqual(lemma(loveKJV, words), "ἀγαπάω")
        let (loveBSB, w2) = try align("BSB", "ROM", 8, 28, "love")
        XCTAssertEqual(lemma(loveBSB, w2), "ἀγαπάω")
        let (goodKJV, w3) = try align("KJV", "ROM", 8, 28, "good")
        XCTAssertEqual(lemma(goodKJV, w3), "ἀγαθός")
        let (godKJV, w4) = try align("KJV", "ROM", 8, 28, "God")
        XCTAssertEqual(lemma(godKJV, w4), "θεός")
        let (calledBSB, w5) = try align("BSB", "ROM", 8, 28, "called")
        XCTAssertEqual(lemma(calledBSB, w5), "κλητός")
    }

    func testGenesis11InHebrew() throws {
        for translation in ["KJV", "BSB", "WEB"] {
            let (created, words) = try align(translation, "GEN", 1, 1, "created")
            XCTAssertEqual(words[created.match!.wordIndex].lemma, "בָּרָא", translation)
            XCTAssertEqual(words[created.match!.wordIndex].language, .hebrew)
            let (god, w2) = try align(translation, "GEN", 1, 1, "God")
            XCTAssertEqual(w2[god.match!.wordIndex].lemma, "אֱלֹהִים", translation)
            let (earth, w3) = try align(translation, "GEN", 1, 1, "earth")
            XCTAssertEqual(w3[earth.match!.wordIndex].lemma, "אֶרֶץ", translation)
        }
        let (heavenKJV, words) = try align("KJV", "GEN", 1, 1, "heaven")
        XCTAssertEqual(words[heavenKJV.match!.wordIndex].lemma, "שָׁמַיִם")
        let (heavens, w2) = try align("BSB", "GEN", 1, 1, "heavens")
        XCTAssertEqual(w2[heavens.match!.wordIndex].lemma, "שָׁמַיִם")
        XCTAssertEqual(heavens.match?.method, .kjvTagStem, "\"heavens\" reaches the KJV's \"heaven\" by stem")
        let (beginning, w3) = try align("BSB", "GEN", 1, 1, "beginning")
        XCTAssertEqual(w3[beginning.match!.wordIndex].lemma, "רֵאשִׁית")
    }

    func testPsalm231() throws {
        let (shepherd, words) = try align("KJV", "PSA", 23, 1, "shepherd")
        XCTAssertEqual(words[shepherd.match!.wordIndex].lemma, "רָעָה")
        let (lord, w2) = try align("BSB", "PSA", 23, 1, "LORD")
        XCTAssertEqual(w2[lord.match!.wordIndex].lemma, "יְהֹוָה")
        let (want, w3) = try align("KJV", "PSA", 23, 1, "want")
        XCTAssertEqual(w3[want.match!.wordIndex].lemma, "חָסֵר")
    }

    func testEveryClickedWordAlwaysGetsAnHonestResult() throws {
        // Any word of any of these verses must yield a match OR an explicit gap with a provenance line.
        for (book, chapter, verse) in [("JHN", 1, 1), ("ROM", 8, 28), ("GEN", 1, 1), ("PSA", 23, 1), ("HEB", 11, 1)] {
            for translation in ["BSB", "KJV", "WEB"] {
                guard let text = verseText(translation, book, chapter, verse) else { continue }
                let words = interlinear.words(bookCode: book, chapter: chapter, verse: verse)
                for token in WordTokenizer.tokens(in: text) {
                    let hit = WordHit(word: token.text, range: token.range, occurrence: token.occurrence, tokenIndex: token.index, key: token.key)
                    let result = WordAlignment.align(hit: hit, verseText: text,
                                                     tags: lexicon.tags(bookCode: book, chapter: chapter, verse: verse), words: words)
                    XCTAssertTrue(result.match != nil || result.gap != nil, "\(translation) \(book) \(chapter):\(verse) \(token.text)")
                    XCTAssertFalse(result.provenanceLine.isEmpty)
                    if let match = result.match { XCTAssertTrue(words.indices.contains(match.wordIndex)) }
                    for index in result.candidates { XCTAssertTrue(words.indices.contains(index)) }
                }
            }
        }
    }

    // MARK: Measured hit rates

    private struct SplitMix {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }
        mutating func below(_ n: Int) -> Int { Int(next() % UInt64(n)) }
    }

    private struct Tally {
        var total = 0
        var kjvHigh = 0, kjvOther = 0, glossMatch = 0, none = 0, noData = 0
        var agree = 0, compared = 0
        var kjvHighAgreeWithGloss = 0, kjvHighCompared = 0
    }

    /// 200 random *content* words per translation, deterministic seed. Reports how each was resolved.
    private func tally(translation: String, seed: UInt64, target: Int = 200) -> Tally {
        var rng = SplitMix(state: seed)
        var t = Tally()
        let books = library.books
        var guardCounter = 0
        while t.total < target, guardCounter < 5000 {
            guardCounter += 1
            let book = books[rng.below(books.count)]
            let chapter = 1 + rng.below(max(book.chapterCount, 1))
            guard let verses = library.chapter(translation: translation, bookCode: book.code, chapter: chapter), !verses.isEmpty else { continue }
            let verse = verses[rng.below(verses.count)]
            guard verse.number > 0 else { continue }
            let content = WordTokenizer.tokens(in: verse.text).filter { WordClass.weight(of: $0.key) == .content }
            guard !content.isEmpty else { continue }
            let token = content[rng.below(content.count)]
            let words = interlinear.words(bookCode: book.code, chapter: chapter, verse: verse.number)
            let tags = lexicon.tags(bookCode: book.code, chapter: chapter, verse: verse.number)
            let hit = WordHit(word: token.text, range: token.range, occurrence: token.occurrence, tokenIndex: token.index, key: token.key)
            let result = WordAlignment.align(hit: hit, verseText: verse.text, tags: tags, words: words)
            t.total += 1
            switch (result.match?.method, result.match?.confidence, result.gap) {
            case (_, _, .noOriginalData): t.noData += 1
            case (.some(.kjvTag), .some(.high), _): t.kjvHigh += 1
            case (.some(.kjvTag), _, _), (.some(.kjvTagStem), _, _): t.kjvOther += 1
            case (.some, _, _): t.glossMatch += 1
            default: t.none += 1
            }
            // Cross-check: does the gloss-only route pick the same original word as the KJV route?
            if let m = result.match, m.method == .kjvTag || m.method == .kjvTagStem {
                let gloss = WordAlignment.align(hit: hit, verseText: verse.text, tags: [], words: words)
                if let g = gloss.match {
                    t.compared += 1
                    if g.wordIndex == m.wordIndex { t.agree += 1 }
                    if m.method == .kjvTag && m.confidence == .high {
                        t.kjvHighCompared += 1
                        if g.wordIndex == m.wordIndex { t.kjvHighAgreeWithGloss += 1 }
                    }
                }
            }
        }
        return t
    }

    func testMeasuredHitRatesOnRandomContentWords() {
        var lines: [String] = []
        for (translation, seed) in [("KJV", 11 as UInt64), ("BSB", 22), ("WEB", 33)] {
            let t = tally(translation: translation, seed: seed,
                          target: Int(ProcessInfo.processInfo.environment["STUDYTABLE_ALIGNMENT_SAMPLE"] ?? "") ?? 200)
            let pct = { (n: Int) in String(format: "%.1f%%", Double(n) * 100 / Double(max(t.total - t.noData, 1))) }
            // Guard rails (measured 2026-09-24: KJV ~80% high / ~9% none; BSB ~39% / ~30%; WEB ~49% / ~20%).
            let answered = Double(t.total - t.noData)
            XCTAssertGreaterThan(Double(t.kjvHigh + t.kjvOther + t.glossMatch) / answered, translation == "KJV" ? 0.85 : 0.6, "\(translation) match rate fell")
            XCTAssertGreaterThan(Double(t.kjvHighAgreeWithGloss) / Double(max(t.kjvHighCompared, 1)), 0.9, "\(translation): KJV-tag and gloss routes disagree too often")
            lines.append("\(translation): n=\(t.total) (no original data \(t.noData)) | KJV-tag high \(t.kjvHigh) (\(pct(t.kjvHigh))) | KJV-tag medium/low/stem \(t.kjvOther) (\(pct(t.kjvOther))) | gloss \(t.glossMatch) (\(pct(t.glossMatch))) | none \(t.none) (\(pct(t.none))) | KJV-vs-gloss agreement \(t.agree)/\(t.compared) | high-confidence agreement \(t.kjvHighAgreeWithGloss)/\(t.kjvHighCompared)")
        }
        print("ALIGNMENT HIT RATES\n" + lines.joined(separator: "\n"))
    }

    /// Worked examples, printed for the record (and asserted, so they cannot silently rot).
    func testWorkedExamples() throws {
        let cases: [(String, String, Int, Int, String, Int)] = [
            ("BSB", "JHN", 3, 16, "loved", 0), ("KJV", "JHN", 3, 16, "only", 0), ("BSB", "JHN", 3, 16, "believes", 0),
            ("BSB", "JHN", 3, 16, "one", 0), ("BSB", "JHN", 3, 16, "the", 0), ("WEB", "GEN", 1, 1, "heavens", 0),
            ("BSB", "ROM", 8, 28, "called", 0), ("KJV", "PSA", 23, 1, "shepherd", 0)
        ]
        var lines: [String] = []
        for (translation, book, chapter, verse, word, occurrence) in cases {
            let (result, words) = try align(translation, book, chapter, verse, word, occurrence: occurrence)
            let target = result.match.map { "\(words[$0.wordIndex].surface) (\(words[$0.wordIndex].lemma), \(words[$0.wordIndex].gloss)) [\($0.method) / \($0.confidence)]" }
                ?? "NO MATCH (\(String(describing: result.gap!))), candidates: \(result.candidates.map { words[$0].transliteration })"
            lines.append("\(translation) \(book) \(chapter):\(verse) \"\(word)\" -> \(target)")
            XCTAssertFalse(result.provenanceLine.isEmpty)
        }
        print("ALIGNMENT EXAMPLES\n" + lines.joined(separator: "\n"))
    }
}
