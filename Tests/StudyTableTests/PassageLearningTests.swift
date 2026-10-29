import XCTest
@testable import StudyTable

final class GrammarLessonsTests: XCTestCase {
    private func word(_ code: String, _ description: String, language: InterlinearLanguage = .greek) -> InterlinearWord {
        InterlinearWord(surface: "word", transliteration: "word", gloss: "word", lemma: "lemma", strongs: ["G5463"],
                        morphCode: code, morphDescription: description, language: language)
    }

    func testGreekImperfectDoesNotMatchPerfectOrPresent() {
        let lessons = GrammarLessons.lessons(for: word("V-IAI-3S", "Verb Imperfect Active Indicative 3rd Singular"))
        XCTAssertEqual(lessons.map(\.id), ["imperfect"])
    }

    func testGreekParticipleIncludesAspectAndMoodWithoutInventingTranslation() {
        let lessons = GrammarLessons.lessons(for: word("V-PAP-NSM", "Verb Present Active Participle Nominative Singular Masculine"))
        XCTAssertEqual(Set(lessons.map(\.id)), ["present", "participle"])
        XCTAssertTrue(lessons.allSatisfy { $0.source.scheme == "https" && !$0.question.isEmpty })
    }

    func testHebrewFusedMorphemeAndSequentialFormStayDistinct() {
        let perfect = word("HR/Vqp3ms", "Preposition + Verb Qal Perfect", language: .hebrew)
        let sequential = word("HVqw3ms", "Verb Qal Imperfect Sequential", language: .hebrew)
        XCTAssertEqual(GrammarLessons.lessons(for: perfect).map(\.id), ["hebrew-perfect"])
        XCTAssertEqual(GrammarLessons.lessons(for: sequential).map(\.id), ["hebrew-sequential-imperfect"])
        XCTAssertEqual(GrammarLessons.lessons(for: word("HVqi3ms", "Verb Qal Imperfect", language: .hebrew)).map(\.id), ["hebrew-imperfect"])
    }

    func testUnsupportedLanguageOrFormDoesNotAcquireALesson() {
        XCTAssertTrue(GrammarLessons.lessons(for: word("AVqp3ms", "Verb Perfect", language: .aramaic)).isEmpty)
        XCTAssertTrue(GrammarLessons.lessons(for: word("N-NSM", "Noun Perfect", language: .greek)).isEmpty)
        XCTAssertTrue(GrammarLessons.lessons(for: word("HVq?3ms", "unknown", language: .hebrew)).isEmpty)
    }
}

@MainActor
final class PassageLearningTests: XCTestCase {
    func testEditorialHighlightsMatchBundledTextAndFailClosedForOtherEditions() throws {
        let library = ScriptureLibrary()
        for note in PassageEmphasis.examples {
            let verses = try XCTUnwrap(library.chapter(translation: "BSB", bookCode: note.book, chapter: note.chapter))
            let text = try XCTUnwrap(verses.first { $0.number == note.verse }).text
            XCTAssertNotNil(PassageEmphasis.note(book: note.book, chapter: note.chapter, verse: note.verse, translation: "BSB", text: text))
            XCTAssertNil(PassageEmphasis.note(book: note.book, chapter: note.chapter, verse: note.verse, translation: "KJV", text: text))
            XCTAssertNil(PassageEmphasis.note(book: note.book, chapter: note.chapter, verse: note.verse, translation: "BSB", text: "different text"))
        }
        XCTAssertNil(PassageEmphasis.note(book: "ROM", chapter: 8, verse: 28, translation: "BSB", text: "anything"))
    }

    func testRepetitionFindsActualOccurrencesAndExcludesVariantAndFunctionRows() throws {
        let words = InterlinearStore().words(bookCode: "PHP", chapter: 4, verse: 4)
        let groups = PassageLearning.repetitions(in: words)
        let rejoice = try XCTUnwrap(groups.first { words[$0.indexes[0]].strongs.contains("G5463") })
        XCTAssertEqual(rejoice.indexes.count, 2)
        for group in groups {
            XCTAssertTrue(group.indexes.allSatisfy { words[$0].variant == nil })
        }
        let conjunction = InterlinearWord(surface: "and", transliteration: "kai", gloss: "and", lemma: "kai",
            strongs: ["G2532"], morphCode: "CONJ", morphDescription: "Conjunction", language: .greek)
        XCTAssertTrue(PassageLearning.repetitions(in: [conjunction, conjunction]).isEmpty)
    }

    func testReflectionCreatesNoGhostAndSurvivesReloadWithoutOverwritingOtherNotes() throws {
        let directory = temporaryDirectory("guided-reflection")
        let study = StudyStore(directory: directory)
        let anchor = Anchor(book: "PHP", chapter: 4, verse: 4)
        let other = try XCTUnwrap(study.addNote(anchors: [anchor], title: "Existing work", body: "Keep me"))
        XCTAssertTrue(GuidedReflection.update("  ", at: anchor, in: study))
        XCTAssertEqual(study.allNotes.count, 1)
        XCTAssertTrue(GuidedReflection.update("Read the surrounding paragraph.", at: anchor, in: study))
        let id = try XCTUnwrap(GuidedReflection.note(in: study, at: anchor)).id
        XCTAssertTrue(GuidedReflection.update("An updated reflection", at: anchor, in: study))
        XCTAssertEqual(GuidedReflection.note(in: study, at: anchor)?.id, id)
        XCTAssertEqual(study.note(id: other.id)?.body, "Keep me")
        let reload = StudyStore(directory: directory)
        XCTAssertEqual(GuidedReflection.note(in: reload, at: anchor)?.body, "An updated reflection")
        XCTAssertNil(GuidedReflection.note(in: reload, at: Anchor(book: "PHP", chapter: 4, verse: 5)))
    }

    func testLessonsMatchRealTaggedWordsInBothTestaments() {
        let store = InterlinearStore()
        let greek = store.words(bookCode: "PHP", chapter: 4, verse: 4)
        XCTAssertTrue(greek.contains { GrammarLessons.lessons(for: $0).contains { $0.id == "imperative" } })
        let hebrew = store.words(bookCode: "GEN", chapter: 1, verse: 3)
        XCTAssertTrue(hebrew.contains { GrammarLessons.lessons(for: $0).contains { $0.id == "hebrew-sequential-imperfect" } })
    }

    func testReadOnlyReflectionDoesNotWriteOrReplaceDamagedData() throws {
        let directory = temporaryDirectory("guided-read-only")
        let file = directory.appendingPathComponent("study.json")
        let original = Data("{\"schema\":9,\"notes\":[]}".utf8)
        try original.write(to: file)
        let study = StudyStore(directory: directory)
        XCTAssertTrue(study.isReadOnly)
        XCTAssertFalse(GuidedReflection.update("Do not overwrite", at: Anchor(book: "PHP", chapter: 4, verse: 4), in: study))
        XCTAssertEqual(try Data(contentsOf: file), original)
    }
}
