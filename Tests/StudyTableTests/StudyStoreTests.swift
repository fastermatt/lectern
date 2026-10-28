import XCTest
import StudyTableCore
@testable import StudyTable

// MARK: - Fixtures (real v1 `notes.json` shapes)

/// The exact shape the pre-0.10 `NotesStore` wrote: a bare JSON array of
/// `{id, passage, title, body, modifiedAt}` with `modifiedAt` as seconds since 2001-01-01
/// (Foundation's default `Date` encoding).
enum V1Fixture {
    static let romans = "11111111-1111-1111-1111-111111111111"
    static let john = "22222222-2222-2222-2222-222222222222"
    static let ghost = "33333333-3333-3333-3333-333333333333"
    static let range = "44444444-4444-4444-4444-444444444444"

    static func note(id: String, passage: String, title: String, body: String, modifiedAt: Double? = 800_000_000.5) -> String {
        var fields = ["\"id\":\"\(id)\"", "\"passage\":\"\(passage)\"", "\"title\":\"\(title)\"", "\"body\":\"\(body)\""]
        if let modifiedAt { fields.append("\"modifiedAt\":\(modifiedAt)") }
        return "{" + fields.joined(separator: ",") + "}"
    }

    static var threeNotes: String {
        "[" + [
            note(id: romans, passage: "Romans 8:28", title: "Providence", body: "All things work together.", modifiedAt: 800_000_001.25),
            note(id: john, passage: "John 3:16", title: "The Word", body: "God so loved the world.", modifiedAt: 800_000_002.5),
            note(id: range, passage: "1 Corinthians 13:4", title: "Love", body: "Love is patient.", modifiedAt: 800_000_003.75)
        ].joined(separator: ",") + "]"
    }
}

/// Every regular file under `directory`, recursively.
func allFiles(under directory: URL) -> [URL] {
    guard let walker = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
    return walker.compactMap { $0 as? URL }.filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true }
}

// MARK: - Pastor QA data-loss reproductions (written first, failing against the old NotesStore)

@MainActor
final class StudyStoreDataLossReproTests: XCTestCase {
    /// PASTOR-QA defect 1a: a truncated notes.json used to load as 0 notes and the next new
    /// note overwrote the file, destroying every original with no backup.
    func testTruncatedNotesFileSurvivesTheNextSave() throws {
        let dir = temporaryDirectory("repro-truncated")
        let full = Data(V1Fixture.threeNotes.utf8)
        let truncated = full.prefix(full.count - 40)            // cut mid-way through the 3rd note
        try truncated.write(to: dir.appendingPathComponent("notes.json"))

        let store = NotesStore(directory: dir)
        store.update(passage: "Mark 1:1", title: "New", body: "A brand new note after launch.")

        let survivors = allFiles(under: dir).filter { (try? Data(contentsOf: $0)) == Data(truncated) }
        XCTAssertFalse(survivors.isEmpty, "the original truncated bytes must still exist somewhere after the next save")
        XCTAssertNotNil(store.note(for: "Romans 8:28"), "the complete notes before the truncation point must be recovered")
        XCTAssertNotNil(store.note(for: "John 3:16"))
    }

    /// PASTOR-QA defect 1b: one note missing a field (`modifiedAt`) failed the whole array, so
    /// every note silently vanished and the next save destroyed them all.
    func testNoteMissingModifiedAtDoesNotDestroyTheOthers() throws {
        let dir = temporaryDirectory("repro-missing-field")
        let json = "[" + [
            V1Fixture.note(id: V1Fixture.romans, passage: "Romans 8:28", title: "Providence", body: "Body one"),
            V1Fixture.note(id: V1Fixture.john, passage: "John 3:16", title: "The Word", body: "Body two", modifiedAt: nil)
        ].joined(separator: ",") + "]"
        try Data(json.utf8).write(to: dir.appendingPathComponent("notes.json"))

        let store = NotesStore(directory: dir)
        store.update(passage: "Mark 1:1", title: "New", body: "Fresh note.")

        XCTAssertEqual(store.note(for: "Romans 8:28")?.body, "Body one")
        XCTAssertEqual(store.note(for: "John 3:16")?.body, "Body two", "a note missing one field must load with a default, not be dropped")
        XCTAssertEqual(store.note(for: "Mark 1:1")?.body, "Fresh note.")
    }
}

// MARK: - Helpers

@MainActor
private func store(in dir: URL, clock: TestClock? = nil) -> StudyStore {
    if let clock { return StudyStore(directory: dir, clock: { clock.now }) }
    return StudyStore(directory: dir)
}

private func write(_ text: String, to name: String, in dir: URL) throws {
    try Data(text.utf8).write(to: dir.appendingPathComponent(name))
}

private func read(_ name: String, in dir: URL) -> Data? {
    try? Data(contentsOf: dir.appendingPathComponent(name))
}

private func files(in dir: URL, prefix: String) -> [URL] {
    ((try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
        .filter { $0.lastPathComponent.hasPrefix(prefix) }
}

private func reference(_ book: String, _ c: Int, _ v: Int) -> Anchor { Anchor(book: book, chapter: c, verse: v) }

// MARK: - Anchor

final class AnchorTests: XCTestCase {
    func testBookTableMatchesBSBManifestAndAliasesDoNotCollide() throws {
        let manifestURL = TestPaths.scripturePacks.appendingPathComponent("BSB/manifest.json")
        let manifest = try JSONDecoder().decode(TranslationManifest.self, from: Data(contentsOf: manifestURL))
        XCTAssertEqual(BookTable.all.map(\.code), Canon.bookCodes, "book table order must be canonical")
        for book in manifest.books {
            let info = try XCTUnwrap(BookTable.info(code: book.code))
            XCTAssertEqual(info.chapters, book.chapterCount, "\(book.code) chapter count")
        }
        XCTAssertEqual(BookTable.aliasCollisions, [], "an alias claimed by two books would mis-parse")
        for info in BookTable.all {
            XCTAssertEqual(BookTable.splitReference("\(info.name) 1")?.book.code, info.code, info.name)
            XCTAssertEqual(BookTable.splitReference("\(info.osis) 1")?.book.code, info.code, info.osis)
            XCTAssertEqual(Anchor(osis: info.osis)?.book, info.code, "OSIS book id \(info.osis)")
        }
    }

    func testParsesEveryLegacyShape() {
        XCTAssertEqual(Anchor.parse("Romans 8:28"), Anchor(book: "ROM", chapter: 8, verse: 28))
        XCTAssertEqual(Anchor.parse("Romans 8:28-39"), Anchor(book: "ROM", chapter: 8, verses: 28, to: 39))
        XCTAssertEqual(Anchor.parse("Romans 8:28\u{2013}39"), Anchor(book: "ROM", chapter: 8, verses: 28, to: 39), "en dash")
        XCTAssertEqual(Anchor.parse("Romans 8:39\u{2013}9:5"),
                       Anchor(book: "ROM", chapterStart: 8, verseStart: 39, chapterEnd: 9, verseEnd: 5), "cross-chapter")
        XCTAssertEqual(Anchor.parse("Romans 8"), Anchor(book: "ROM", chapter: 8), "whole chapter")
        XCTAssertEqual(Anchor.parse("Romans 8-9"), Anchor(book: "ROM", chapter: 8, throughChapter: 9))
        XCTAssertEqual(Anchor.parse("1 Corinthians 13:4"), Anchor(book: "1CO", chapter: 13, verse: 4), "numbered book")
        XCTAssertEqual(Anchor.parse("1 Cor 13:4\u{2013}7"), Anchor(book: "1CO", chapter: 13, verses: 4, to: 7), "abbreviation")
        XCTAssertEqual(Anchor.parse("2 Timothy 3:16"), Anchor(book: "2TI", chapter: 3, verse: 16))
        XCTAssertEqual(Anchor.parse("3 John 4"), Anchor(book: "3JN", chapter: 1, verse: 4), "single-chapter book: bare number is a verse")
        XCTAssertEqual(Anchor.parse("Psalm 23"), Anchor(book: "PSA", chapter: 23))
        XCTAssertEqual(Anchor.parse("Psalms 23:1"), Anchor(book: "PSA", chapter: 23, verse: 1))
        XCTAssertEqual(Anchor.parse("Ps 119:176"), Anchor(book: "PSA", chapter: 119, verse: 176))
        XCTAssertEqual(Anchor.parse("Song of Solomon 2:1"), Anchor(book: "SNG", chapter: 2, verse: 1))
        XCTAssertEqual(Anchor.parse("Song 2:1"), Anchor(book: "SNG", chapter: 2, verse: 1), "the app's own book name")
        XCTAssertEqual(Anchor.parse("Jude 1:5"), Anchor(book: "JUD", chapter: 1, verse: 5))
        XCTAssertEqual(Anchor.parse("Romans"), Anchor.wholeBook("ROM"))
        XCTAssertEqual(Anchor.parse("  rom.  8 : 28  "), Anchor(book: "ROM", chapter: 8, verse: 28), "case, dots, spaces")
        XCTAssertEqual(Anchor.parse("Psalm 3:0"), Anchor(book: "PSA", chapter: 3, verse: 0), "superscription")
    }

    func testRejectsWhatIsNotOneContiguousPassage() {
        // "Romans 8:28-9" is verse 28 through verse 9 of chapter 8 — reversed, so rejected.
        for bad in ["", "Test 1:1", "Romans 17:1", "Romans 0", "Romans 8:39-28", "Romans 8:28,30", "Romans 8:", "8:28",
                    "Romans 8:28-9", "Romans 9-8", "Genesis 1:1000", "Romans 8:28; John 3:16", "Isaiah's 8"] {
            XCTAssertNil(Anchor.parse(bad), "\"\(bad)\" must not parse")
        }
    }

    func testDisplayAndOSISFormatting() {
        XCTAssertEqual(reference("ROM", 8, 28).displayString, "Romans 8:28")
        XCTAssertEqual(Anchor(book: "ROM", chapter: 8, verses: 28, to: 39).displayString, "Romans 8:28\u{2013}39")
        XCTAssertEqual(Anchor(book: "ROM", chapterStart: 8, verseStart: 39, chapterEnd: 9, verseEnd: 5).displayString, "Romans 8:39\u{2013}9:5")
        XCTAssertEqual(Anchor(book: "ROM", chapter: 8).displayString, "Romans 8")
        XCTAssertEqual(Anchor(book: "ROM", chapter: 8, throughChapter: 9).displayString, "Romans 8\u{2013}9")
        XCTAssertEqual(Anchor.wholeBook("ROM").displayString, "Romans")
        XCTAssertEqual(Anchor(book: "PSA", chapter: 23).displayString, "Psalm 23")
        XCTAssertEqual(Anchor(book: "PSA", chapter: 22, throughChapter: 24).displayString, "Psalms 22\u{2013}24")
        XCTAssertEqual(Anchor(book: "SNG", chapter: 2, verse: 1).displayString, "Song of Solomon 2:1")
        XCTAssertEqual(reference("1CO", 13, 4).displayString, "1 Corinthians 13:4")

        XCTAssertEqual(reference("ROM", 8, 28).osis, "Rom.8.28")
        XCTAssertEqual(Anchor(book: "ROM", chapter: 8, verses: 28, to: 39).osis, "Rom.8.28-Rom.8.39")
        XCTAssertEqual(Anchor(book: "ROM", chapter: 8).osis, "Rom.8")
        XCTAssertEqual(Anchor(book: "ROM", chapter: 8, throughChapter: 9).osis, "Rom.8-Rom.9")
        XCTAssertEqual(Anchor.wholeBook("JUD").osis, "Jude")
        XCTAssertEqual(reference("1CO", 13, 4).osis, "1Cor.13.4")
    }

    func testRoundTripsForEveryChapterOfTheCanon() {
        for info in BookTable.all {
            for chapter in 1...info.chapters {
                let whole = Anchor(book: info.code, chapter: chapter)
                XCTAssertEqual(Anchor(osis: whole.osis), whole, "\(info.code) \(chapter) osis")
                let verse = reference(info.code, chapter, 1)
                XCTAssertEqual(Anchor.parse(verse.displayString), verse, verse.displayString)
                XCTAssertEqual(Anchor(osis: verse.osis), verse, verse.osis)
                if !info.isSingleChapter { XCTAssertEqual(Anchor.parse(whole.displayString), whole, whole.displayString) }
            }
        }
        let range = Anchor(book: "ROM", chapterStart: 8, verseStart: 39, chapterEnd: 9, verseEnd: 5)
        XCTAssertEqual(Anchor.parse(range.displayString), range)
        XCTAssertEqual(Anchor(osis: range.osis), range)
        XCTAssertEqual(Anchor(osis: "Rom.8.28-39"), Anchor(book: "ROM", chapter: 8, verses: 28, to: 39), "OSIS shorthand end")
        XCTAssertNil(Anchor(osis: "Rom.8.28-John.3.16"), "cross-book is not one anchor")
    }

    func testOverlapAndContainment() {
        let chapter = Anchor(book: "ROM", chapter: 8)
        let range = Anchor(book: "ROM", chapter: 8, verses: 28, to: 39)
        let verse = reference("ROM", 8, 28)
        let cross = Anchor(book: "ROM", chapterStart: 8, verseStart: 39, chapterEnd: 9, verseEnd: 5)
        XCTAssertTrue(chapter.overlaps(verse)); XCTAssertTrue(verse.overlaps(chapter))
        XCTAssertTrue(chapter.contains(range)); XCTAssertFalse(range.contains(chapter))
        XCTAssertTrue(range.overlaps(cross), "8:39 is shared")
        XCTAssertFalse(Anchor(book: "ROM", chapter: 8, verses: 28, to: 30).overlaps(reference("ROM", 8, 31)), "adjacent, not overlapping")
        XCTAssertFalse(verse.overlaps(reference("JHN", 8, 28)), "different book")
        XCTAssertTrue(cross.contains(chapter: 9, verse: 1))
        XCTAssertFalse(cross.contains(chapter: 9, verse: 6))
        XCTAssertTrue(Anchor(book: "PSA", chapter: 3).overlaps(reference("PSA", 3, 0)), "whole chapter includes the superscription")
        XCTAssertFalse(Anchor(book: "PSA", chapter: 3, verses: 1, to: 8).overlaps(reference("PSA", 3, 0)))
        XCTAssertTrue(Anchor.wholeBook("ROM").contains(cross))
        XCTAssertEqual([reference("JHN", 3, 16), reference("GEN", 1, 1), reference("ROM", 8, 28), reference("ROM", 8, 1)].sorted().map(\.displayString),
                       ["Genesis 1:1", "John 3:16", "Romans 8:1", "Romans 8:28"], "canonical order")
    }

    func testCodableRoundTripAndTolerantDecoding() throws {
        let anchor = Anchor(book: "ROM", chapter: 8, verse: 28, word: WordRef(index: 3, strong: "G3956"))
        let data = try JSONEncoder().encode(anchor)
        XCTAssertEqual(try JSONDecoder().decode(Anchor.self, from: data), anchor)
        let sparse = try JSONDecoder().decode(Anchor.self, from: Data(#"{"book":"ROM","chapterStart":8,"verseStart":"oops","extra":true}"#.utf8))
        XCTAssertEqual(sparse.book, "ROM")
        XCTAssertEqual(sparse.chapterStart, 8)
        let unknown = try JSONDecoder().decode(Anchor.self, from: Data(#"{"chapterStart":8}"#.utf8))
        XCTAssertFalse(unknown.isValid, "a missing book decodes as an invalid anchor rather than throwing")
    }
}

// MARK: - Migration & safe load

@MainActor
final class StudyStoreMigrationTests: XCTestCase {
    private let romans = UUID(uuidString: V1Fixture.romans)!

    func testMigratesRealV1ShapesPreservingIdentityAndDates() throws {
        let dir = temporaryDirectory("mig")
        let json = "[" + [
            V1Fixture.note(id: V1Fixture.romans, passage: "Romans 8:28", title: "Providence", body: "All things.", modifiedAt: 800_000_001.25),
            V1Fixture.note(id: V1Fixture.range, passage: "Romans 8:39\u{2013}9:5", title: "Cross", body: "Nothing separates.", modifiedAt: 800_000_002.5),
            V1Fixture.note(id: V1Fixture.john, passage: "John 3", title: "Whole chapter", body: "Nicodemus", modifiedAt: 800_000_003.75),
            V1Fixture.note(id: UUID().uuidString, passage: "1 Corinthians 13:4", title: "Love", body: "Patient."),
            V1Fixture.note(id: UUID().uuidString, passage: "Psalms 23:1", title: "Shepherd", body: "Lord"),
            V1Fixture.note(id: UUID().uuidString, passage: "Song 2:1", title: "Rose", body: "Sharon"),
            V1Fixture.note(id: UUID().uuidString, passage: "Test 1:1", title: "Unparseable", body: "kept verbatim")
        ].joined(separator: ",") + "]"
        try write(json, to: "notes.json", in: dir)
        let original = try XCTUnwrap(read("notes.json", in: dir))

        let s = store(in: dir)

        XCTAssertEqual(s.allNotes.count, 7)
        let r = try XCTUnwrap(s.note(id: romans))
        XCTAssertEqual(r.title, "Providence"); XCTAssertEqual(r.body, "All things.")
        XCTAssertEqual(r.anchors, [reference("ROM", 8, 28)])
        XCTAssertEqual(r.modifiedAt, Date(timeIntervalSinceReferenceDate: 800_000_001.25), "modifiedAt preserved exactly")
        XCTAssertEqual(s.note(id: UUID(uuidString: V1Fixture.range)!)?.anchors,
                       [Anchor(book: "ROM", chapterStart: 8, verseStart: 39, chapterEnd: 9, verseEnd: 5)])
        XCTAssertEqual(s.note(id: UUID(uuidString: V1Fixture.john)!)?.anchors, [Anchor(book: "JHN", chapter: 3)])
        XCTAssertTrue(s.allNotes.contains { $0.anchors == [reference("1CO", 13, 4)] })
        XCTAssertTrue(s.allNotes.contains { $0.anchors == [reference("PSA", 23, 1)] })
        XCTAssertTrue(s.allNotes.contains { $0.anchors == [reference("SNG", 2, 1)] })
        let unparsed = try XCTUnwrap(s.allNotes.first { $0.title == "Unparseable" })
        XCTAssertEqual(unparsed.legacyPassage, "Test 1:1"); XCTAssertTrue(unparsed.anchors.isEmpty)
        XCTAssertEqual(s.loadReport.unparsedPassages, ["Test 1:1"])

        // Safety copy first, byte-identical; notes.json itself untouched; study.json is schema 2.
        guard case let .migratedFromV1(count, backup) = s.loadReport.outcome else { return XCTFail("outcome \(s.loadReport.outcome)") }
        XCTAssertEqual(count, 7)
        XCTAssertEqual(try Data(contentsOf: backup), original)
        XCTAssertEqual(backup.deletingLastPathComponent().lastPathComponent, "Backups")
        XCTAssertTrue(backup.lastPathComponent.hasPrefix("notes-v1-"))
        XCTAssertEqual(read("notes.json", in: dir), original)
        let onDisk = try XCTUnwrap(read("study.json", in: dir))
        XCTAssertEqual(try StudyEnvelope.decodeTolerant(onDisk, fallbackDate: Date()).envelope.schema, 2)
        XCTAssertNil(s.alert, "a clean migration is silent")
    }

    func testEmptyObservationGhostsAreDroppedFromLiveDataButKeptInTheBackup() throws {
        let dir = temporaryDirectory("ghost")
        let json = "[" + [
            V1Fixture.note(id: V1Fixture.ghost, passage: "Romans 8:31", title: "Observation", body: ""),
            V1Fixture.note(id: UUID().uuidString, passage: "Romans 8:32", title: "Observation", body: "  \\n "),
            V1Fixture.note(id: V1Fixture.romans, passage: "Romans 8:28", title: "Observation", body: "Real text"),
            V1Fixture.note(id: UUID().uuidString, passage: "Romans 8:33", title: "My custom title", body: "")
        ].joined(separator: ",") + "]"
        try write(json, to: "notes.json", in: dir)

        let s = store(in: dir)

        XCTAssertEqual(s.loadReport.droppedGhosts.map(\.passage).sorted(), ["Romans 8:31", "Romans 8:32"])
        XCTAssertEqual(s.allNotes.count, 2, "the real note and the custom-titled empty note survive")
        XCTAssertNil(s.allNotes.first { $0.referenceLabel == "Romans 8:31" })
        guard case let .migratedFromV1(_, backup) = s.loadReport.outcome else { return XCTFail() }
        XCTAssertTrue(try String(contentsOf: backup, encoding: .utf8).contains("Romans 8:31"), "ghosts stay in the backup")
    }

    func testMigrationIsIdempotent() throws {
        let dir = temporaryDirectory("idem")
        try write(V1Fixture.threeNotes, to: "notes.json", in: dir)
        let first = store(in: dir)
        XCTAssertEqual(first.allNotes.count, 3)
        first.update(passage: "Mark 1:1", title: "New", body: "Added after migration")
        let studyBytes = read("study.json", in: dir)

        // An old build (or Time Machine restore) rewrites notes.json later — it must never re-import.
        try write("[]", to: "notes.json", in: dir)
        let second = store(in: dir)
        XCTAssertEqual(second.allNotes.count, 4)
        XCTAssertEqual(files(in: dir.appendingPathComponent("Backups"), prefix: "notes-v1-").count, 1, "no second backup")
        XCTAssertEqual(second.loadReport.outcome, .loaded)
        XCTAssertEqual(read("study.json", in: dir), studyBytes, "reopening writes nothing")

        // Even if study.json is lost and a good backup is missing, the marker stops a stale re-import.
        try FileManager.default.removeItem(at: dir.appendingPathComponent("study.json"))
        try FileManager.default.removeItem(at: dir.appendingPathComponent("study.json.bak"))
        for url in files(in: dir.appendingPathComponent("Backups"), prefix: "study-") { try FileManager.default.removeItem(at: url) }
        try write(V1Fixture.threeNotes, to: "notes.json", in: dir)
        XCTAssertEqual(store(in: dir).allNotes.count, 0)
    }

    func testTruncatedV1FileIsSalvagedAndNothingIsLost() throws {
        let dir = temporaryDirectory("trunc")
        let full = Data(V1Fixture.threeNotes.utf8)
        let truncated = full.prefix(full.count - 40)
        try truncated.write(to: dir.appendingPathComponent("notes.json"))

        let s = store(in: dir)
        XCTAssertEqual(s.allNotes.count, 2, "the two complete notes are recovered")
        XCTAssertNotNil(s.note(for: "Romans 8:28")); XCTAssertNotNil(s.note(for: "John 3:16"))
        XCTAssertNotNil(s.alert, "the user is told")
        XCTAssertEqual(s.alert?.severity, .warning)
        guard case let .salvagedFromV1(recovered, backup) = s.loadReport.outcome else { return XCTFail("\(s.loadReport.outcome)") }
        XCTAssertEqual(recovered, 2)
        XCTAssertEqual(try Data(contentsOf: backup), Data(truncated), "the damaged original is preserved byte for byte")
        s.update(passage: "Mark 1:1", title: "New", body: "after")
        XCTAssertFalse(files(in: dir.appendingPathComponent("Backups"), prefix: "notes-v1-").isEmpty)
    }

    func testV1FileWithNothingRecoverableRunsReadOnlyAndKeepsTheFile() throws {
        let dir = temporaryDirectory("dead")
        let garbage = Data(#"[{"id":"11111111-1111-1111-1111-111111111111","passage":"Rom"#.utf8)   // cut inside the first note
        try garbage.write(to: dir.appendingPathComponent("notes.json"))

        let s = store(in: dir)
        XCTAssertTrue(s.isReadOnly)
        XCTAssertEqual(s.alert?.severity, .error)
        guard case let .corrupt(damaged) = s.loadReport.outcome, let damagedURL = damaged else { return XCTFail("\(s.loadReport.outcome)") }
        XCTAssertTrue(damagedURL.lastPathComponent.hasPrefix("notes.corrupt-"))
        XCTAssertEqual(try Data(contentsOf: damagedURL), garbage)
        XCTAssertNil(s.addNote(title: "x", body: "y"), "read-only rejects writes")
        s.update(passage: "Mark 1:1", title: "t", body: "b")
        XCTAssertTrue(s.allNotes.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("study.json").path), "nothing is written while read-only")

        XCTAssertTrue(s.resumeEditing())
        s.update(passage: "Mark 1:1", title: "t", body: "b")
        XCTAssertEqual(s.allNotes.count, 1)
        XCTAssertEqual(try Data(contentsOf: damagedURL), garbage, "the damaged file is still there")
    }

    func testNoteMissingFieldsAndExtraFieldsAndWrongTypesAllLoad() throws {
        let dir = temporaryDirectory("fields")
        let json = """
        [{"id":"\(V1Fixture.romans)","passage":"Romans 8:28","title":"No date","body":"one","future":{"nested":[1,2]}},
         {"id":"\(V1Fixture.john)","passage":"John 3:16","title":5,"body":"two","modifiedAt":"not a date"},
         {"passage":"Mark 1:1","title":"No id","body":"three","modifiedAt":800000000},
         {"id":"\(V1Fixture.range)","passage":"Luke 1:1","body":"no title"},
         7, "junk", null]
        """
        try write(json, to: "notes.json", in: dir)
        let fileDate = try XCTUnwrap(try FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent("notes.json").path)[.modificationDate] as? Date)

        let s = store(in: dir)

        XCTAssertEqual(s.allNotes.count, 4, "every object-shaped record survives; non-objects are skipped and counted")
        XCTAssertEqual(s.loadReport.skippedElements, 3)
        XCTAssertEqual(s.note(for: "Romans 8:28")?.body, "one")
        XCTAssertEqual(abs(try XCTUnwrap(s.note(for: "Romans 8:28")).modifiedAt.timeIntervalSince(fileDate)) < 2, true,
                       "a missing modifiedAt defaults to the file's date, not 'now' or the epoch")
        XCTAssertEqual(s.note(for: "John 3:16")?.title, "", "a wrong-typed title defaults")
        XCTAssertEqual(s.note(for: "John 3:16")?.body, "two")
        XCTAssertEqual(s.note(for: "Mark 1:1")?.modifiedAt, Date(timeIntervalSinceReferenceDate: 800_000_000))
        XCTAssertEqual(s.note(for: "Luke 1:1")?.body, "no title")
        XCTAssertNotNil(s.alert, "skipped junk elements are reported")
    }

    func testLegacyDateFormatsBothDecode() throws {
        let dir = temporaryDirectory("dates")
        let iso = "2026-09-24T12:00:00Z"
        try write("[" + V1Fixture.note(id: V1Fixture.romans, passage: "Romans 8:28", title: "a", body: "b", modifiedAt: 800_000_000) + "," +
                  "{\"id\":\"\(V1Fixture.john)\",\"passage\":\"John 3:16\",\"title\":\"c\",\"body\":\"d\",\"modifiedAt\":\"\(iso)\"}]", to: "notes.json", in: dir)
        let s = store(in: dir)
        XCTAssertEqual(s.note(for: "John 3:16")?.modifiedAt, ISO8601DateFormatter().date(from: iso))
        XCTAssertEqual(s.note(for: "Romans 8:28")?.modifiedAt, Date(timeIntervalSinceReferenceDate: 800_000_000))
    }

    func testMigrationRefusesToProceedWithoutABackup() throws {
        let dir = temporaryDirectory("nobackup")
        try write(V1Fixture.threeNotes, to: "notes.json", in: dir)
        // A regular FILE named Backups makes the backup directory impossible to create.
        try write("in the way", to: "Backups", in: dir)
        let s = store(in: dir)
        XCTAssertTrue(s.isReadOnly)
        XCTAssertEqual(s.alert?.severity, .error)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("study.json").path))
        XCTAssertEqual(read("notes.json", in: dir), Data(V1Fixture.threeNotes.utf8), "the original is untouched")
    }

    func testRealSupportFolderIsNeverTouched() throws {
        let real = AppResources.supportDirectory
        func snapshot() -> [String: Data?] {
            let names = (try? FileManager.default.contentsOfDirectory(atPath: real.path)) ?? []
            return Dictionary(uniqueKeysWithValues: names.map { ($0, try? Data(contentsOf: real.appendingPathComponent($0))) })
        }
        let before = snapshot()
        let dir = temporaryDirectory("isolated")
        try write(V1Fixture.threeNotes, to: "notes.json", in: dir)
        let s = store(in: dir)
        s.update(passage: "Mark 1:1", title: "t", body: "b")
        s.save(reference("ROM", 8, 28))
        XCTAssertEqual(snapshot(), before)
    }
}

// MARK: - study.json (v2) safety

@MainActor
final class StudyStoreSafetyTests: XCTestCase {
    func testRoundTripThroughDisk() throws {
        let dir = temporaryDirectory("rt")
        let a = store(in: dir)
        let note = try XCTUnwrap(a.addNote(anchors: [Anchor(book: "ROM", chapter: 8, verses: 28, to: 39)], title: "T", kind: .oia,
                                           body: "b", sections: [NoteSection(key: "observation", text: "obs")], tags: ["Faith", "#hope", "faith"]))
        let saved = try XCTUnwrap(a.save(reference("JHN", 3, 16), highlight: .green, isMemory: true, tags: ["gospel"]))
        let collection = try XCTUnwrap(a.createCollection(name: "Security"))
        a.addToCollection(savedID: saved.id, collectionID: collection.id)
        a.addClip(Clip(kind: .commentary, excerpt: "Calvin on 8:28", citation: ClipCitation(author: "John Calvin", work: "Romans", licence: "PD"),
                       anchor: reference("ROM", 8, 28), capturedAt: Date(timeIntervalSinceReferenceDate: 5)))
        a.upsertProject(StudyProject(title: "Romans 8 sermon", kind: .sermon, primaryAnchor: Anchor(book: "ROM", chapter: 8),
                                     outline: [OutlineNode(title: "Point 1", children: [OutlineNode(title: "Sub")])], createdAt: Date()))

        let b = store(in: dir)
        XCTAssertEqual(b.data, a.data, "everything round-trips exactly")
        XCTAssertEqual(b.note(id: note.id)?.tags, ["Faith", "hope"], "tags are normalised and de-duplicated")
        XCTAssertEqual(b.savedPassages.first?.highlight, .green)
        XCTAssertEqual(b.savedPassages(in: collection.id).count, 1)
    }

    func testCorruptStudyFileIsMovedAsideAndRecoveredFromTheBackup() throws {
        let dir = temporaryDirectory("corrupt-bak")
        let first = store(in: dir)
        first.addNote(anchors: [reference("ROM", 8, 28)], title: "One", body: "first")
        first.addNote(anchors: [reference("ROM", 8, 29)], title: "Two", body: "second")   // 2nd save → .bak holds state after "One"
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent("study.json.bak").path))
        let good = try XCTUnwrap(read("study.json", in: dir))
        let truncated = good.prefix(good.count / 2)
        try truncated.write(to: dir.appendingPathComponent("study.json"))

        let second = store(in: dir)
        XCTAssertFalse(second.isReadOnly, "a valid backup exists, so editing is safe")
        XCTAssertEqual(second.allNotes.count, 1, "restored from .bak (one save older)")
        guard case let .recoveredFromBackup(source, damaged) = second.loadReport.outcome, let damagedURL = damaged else { return XCTFail("\(second.loadReport.outcome)") }
        XCTAssertEqual(source.lastPathComponent, "study.json.bak")
        XCTAssertEqual(try Data(contentsOf: damagedURL), Data(truncated), "the truncated bytes are kept")
        XCTAssertTrue(damagedURL.lastPathComponent.hasPrefix("study.corrupt-"))
        XCTAssertNotNil(second.alert)
        XCTAssertEqual(store(in: dir).allNotes.count, 1, "and the restore was written back")
    }

    func testCorruptStudyFileWithNoBackupRunsReadOnly() throws {
        let dir = temporaryDirectory("corrupt-nobak")
        let garbage = Data("{ this is not json".utf8)
        try garbage.write(to: dir.appendingPathComponent("study.json"))
        let s = store(in: dir)
        XCTAssertTrue(s.isReadOnly)
        XCTAssertEqual(s.alert?.severity, .error)
        XCTAssertNil(s.addNote(title: "x", body: "y"))
        XCTAssertNil(s.save(reference("ROM", 8, 28)))
        XCTAssertEqual(files(in: dir, prefix: "study.corrupt-").count, 1)
        XCTAssertEqual(try Data(contentsOf: files(in: dir, prefix: "study.corrupt-")[0]), garbage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("study.json").path))
    }

    func testNewerSchemaIsOpenedReadOnlyAndNeverOverwritten() throws {
        let dir = temporaryDirectory("newer")
        let future = #"{"schema":9,"notes":[{"id":"11111111-1111-1111-1111-111111111111","title":"From the future","body":"x","hologram":true}],"telepathy":[1,2]}"#
        try write(future, to: "study.json", in: dir)
        let s = store(in: dir)
        XCTAssertTrue(s.isReadOnly)
        XCTAssertEqual(s.loadReport.outcome, .newerSchema(9))
        XCTAssertEqual(s.allNotes.count, 1, "still readable")
        XCTAssertNil(s.addNote(title: "no", body: "no"))
        XCTAssertFalse(s.resumeEditing(), "not overridable — an older build must not rewrite newer data")
        XCTAssertEqual(read("study.json", in: dir), Data(future.utf8), "the file is byte-identical")
    }

    func testUnusableElementsAreSkippedCountedAndThePartialFileIsPreserved() throws {
        let dir = temporaryDirectory("partial")
        let json = #"{"schema":2,"notes":[{"id":"11111111-1111-1111-1111-111111111111","title":"ok","body":"b"}, 42],"saved":[],"collections":[],"projects":[],"clips":[]}"#
        try write(json, to: "study.json", in: dir)
        let s = store(in: dir)
        XCTAssertEqual(s.allNotes.count, 1)
        XCTAssertEqual(s.loadReport.skippedElements, 1)
        XCTAssertEqual(s.alert?.severity, .warning)
        let kept = files(in: dir.appendingPathComponent("Backups"), prefix: "study-partial-")
        XCTAssertEqual(kept.count, 1)
        XCTAssertEqual(try Data(contentsOf: kept[0]), Data(json.utf8), "the original with the odd element stays on disk")
    }

    func testMissingStudyFileRestoresFromBackup() throws {
        let dir = temporaryDirectory("missing")
        let a = store(in: dir)
        a.addNote(title: "Keep", body: "me")
        a.addNote(title: "Keep2", body: "me too")
        try FileManager.default.removeItem(at: dir.appendingPathComponent("study.json"))
        let b = store(in: dir)
        XCTAssertGreaterThanOrEqual(b.allNotes.count, 1)
        guard case .recoveredFromBackup = b.loadReport.outcome else { return XCTFail("\(b.loadReport.outcome)") }
    }

    func testBackupRotationAndDailySnapshots() throws {
        let dir = temporaryDirectory("rotate")
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let s = store(in: dir, clock: clock)
        s.addNote(title: "1", body: "a")                       // creates study.json; nothing to rotate yet
        XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent("study.json.bak").path))
        let afterFirst = try XCTUnwrap(read("study.json", in: dir))
        s.addNote(title: "2", body: "b")                       // first rotation of the session
        XCTAssertEqual(read("study.json.bak", in: dir), afterFirst, ".bak is the previous good file")
        let bakAfterSecond = read("study.json.bak", in: dir)
        s.addNote(title: "3", body: "c")                       // within 5 minutes: bak unchanged
        XCTAssertEqual(read("study.json.bak", in: dir), bakAfterSecond)
        clock.advance(seconds: 301)
        let beforeFourth = try XCTUnwrap(read("study.json", in: dir))
        s.addNote(title: "4", body: "d")
        XCTAssertEqual(read("study.json.bak", in: dir), beforeFourth, "bak refreshes after five minutes")
        XCTAssertEqual(files(in: dir.appendingPathComponent("Backups"), prefix: "study-2").count, 1, "one dated snapshot per day")

        // Pruning keeps the newest 14 dated snapshots.
        let backups = dir.appendingPathComponent("Backups")
        for day in 1...20 { try Data("{}".utf8).write(to: backups.appendingPathComponent(String(format: "study-201001%02d.json", day))) }
        clock.advance(days: 1)
        s.addNote(title: "5", body: "e")
        XCTAssertLessThanOrEqual(files(in: backups, prefix: "study-2").count, 14)
    }

    func testAGoodBackupIsNeverReplacedByAnUndecodableFile() throws {
        let dir = temporaryDirectory("guard-bak")
        let clock = TestClock()
        let a = store(in: dir, clock: clock)
        a.addNote(title: "1", body: "a"); a.addNote(title: "2", body: "b")
        let goodBak = try XCTUnwrap(read("study.json.bak", in: dir))
        // Something damages study.json while the app keeps running…
        try Data("garbage".utf8).write(to: dir.appendingPathComponent("study.json"))
        clock.advance(seconds: 3600)
        a.addNote(title: "3", body: "c")
        XCTAssertEqual(read("study.json.bak", in: dir), goodBak, "garbage must not overwrite the last good backup")
    }

    func testSaveFailureKeepsWorkInMemoryAlertsAndRetries() throws {
        let dir = temporaryDirectory("readonly-dir")
        let s = store(in: dir)
        s.addNote(title: "safe", body: "on disk")
        chmod(dir.path, 0o555)
        defer { chmod(dir.path, 0o755) }
        s.addNote(title: "blocked", body: "in memory only")
        XCTAssertEqual(s.allNotes.count, 2, "the note is still on screen")
        XCTAssertTrue(s.hasUnsavedChanges)
        XCTAssertEqual(s.alert?.severity, .error)
        chmod(dir.path, 0o755)
        s.addNote(title: "recovered", body: "next change retries everything")
        XCTAssertFalse(s.hasUnsavedChanges)
        XCTAssertEqual(store(in: dir).allNotes.count, 3)
    }

    func testJSONSalvageHandlesEscapesNestingAndTruncation() {
        let text = #"[{"a":"quote \" brace } bracket ]","n":{"x":[1,2,{"y":3}]}},{"b":"two"},{"c":"cut o"#
        let objects = JSONSalvage.completeObjects(inArray: Data(text.utf8)).map { String(decoding: $0, as: UTF8.self) }
        XCTAssertEqual(objects.count, 2)
        XCTAssertTrue(objects[0].contains("quote \\\" brace }"))
        XCTAssertEqual(objects[1], #"{"b":"two"}"#)
        XCTAssertTrue(JSONSalvage.completeObjects(inArray: Data("not an array".utf8)).isEmpty)
        XCTAssertEqual(JSONSalvage.completeObjects(inArray: Data("[]".utf8)).count, 0)
    }
}

// MARK: - Behaviour fixes (legacy adapter) and the new note API

@MainActor
final class StudyStoreBehaviourTests: XCTestCase {
    func testUnchangedUpdateDoesNotTouchModifiedAtOrTheFile() throws {
        let dir = temporaryDirectory("stable")
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let s = store(in: dir, clock: clock)
        s.update(passage: "Romans 8:28", title: "Providence", body: "Body")
        let created = try XCTUnwrap(s.note(for: "Romans 8:28")).modifiedAt
        let bytes = read("study.json", in: dir)

        clock.advance(days: 3)
        // What NoteEditor does on every visit: load → onChange → update with identical values.
        s.update(passage: "Romans 8:28", title: "Providence", body: "Body")
        s.update(passage: "Romans 8:28", title: "Providence", body: "Body")
        XCTAssertEqual(s.note(for: "Romans 8:28")?.modifiedAt, created, "visiting a verse must not reorder 'recent first'")
        XCTAssertEqual(read("study.json", in: dir), bytes, "no write at all")

        s.update(passage: "Romans 8:28", title: "Providence", body: "Body, edited")
        XCTAssertEqual(s.note(for: "Romans 8:28")?.modifiedAt, clock.now, "a real edit moves modifiedAt")
    }

    func testEmptyBodyOnAMissingNoteCreatesNothing() {
        let s = ephemeralStudy()
        s.update(passage: "Romans 8:31", title: "Observation", body: "")
        s.update(passage: "Romans 8:31", title: "Renamed but empty", body: "   \n ")
        XCTAssertTrue(s.allNotes.isEmpty)
        XCTAssertNil(s.note(for: "Romans 8:31"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: s.studyURL.path), "not even a file")
    }

    func testClearedNoteStopsAppearingInTheLegacyList() {
        let s = ephemeralStudy()
        s.update(passage: "Romans 8:28", title: "T", body: "text")
        XCTAssertEqual(s.notes.count, 1)
        s.update(passage: "Romans 8:28", title: "T", body: "")
        XCTAssertTrue(s.notes.isEmpty, "no ghost row in the notes browser")
        XCTAssertNotNil(s.note(for: "Romans 8:28"), "but the note (and its title) remain for the editor")
    }

    func testLegacyDeleteAndRangeStrings() throws {
        let s = ephemeralStudy()
        s.update(passage: "Romans 8:28\u{2013}39", title: "Range", body: "Whole pericope")
        XCTAssertEqual(s.note(for: "Romans 8:28-39")?.body, "Whole pericope", "hyphen and en dash are the same passage")
        XCTAssertEqual(s.notes.first?.passage, "Romans 8:28\u{2013}39")
        XCTAssertTrue(s.delete(passage: "Romans 8:28\u{2013}39"))
        XCTAssertNil(s.note(for: "Romans 8:28-39"))
        XCTAssertTrue(s.notes.isEmpty)
        XCTAssertEqual(s.recentlyDeleted.count, 1)
        XCTAssertFalse(s.delete(passage: "Romans 8:28-39"), "already gone")
    }

    func testUnparseablePassageStringsStillRoundTrip() {
        let s = ephemeralStudy()
        s.update(passage: "Test 1:1", title: "t", body: "b")
        XCTAssertEqual(s.note(for: "Test 1:1")?.body, "b")
        s.update(passage: "Test 1:1", title: "t", body: "b2")
        XCTAssertEqual(s.allNotes.count, 1)
        XCTAssertEqual(s.notes.first?.passage, "Test 1:1")
    }

    func testEditNoteBumpsModifiedAtOnlyOnContentChange() throws {
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let s = ephemeralStudy(clock: { clock.now })
        let note = try XCTUnwrap(s.addNote(anchors: [reference("ROM", 8, 28)], title: "T", body: "b"))
        clock.advance(days: 1)
        s.editNote(note.id) { $0.body = "b" }
        XCTAssertEqual(s.note(id: note.id)?.modifiedAt, note.modifiedAt)
        s.editNote(note.id) { $0.tags = ["#Faith", "faith"] }
        XCTAssertEqual(s.note(id: note.id)?.tags, ["Faith"])
        XCTAssertEqual(s.note(id: note.id)?.modifiedAt, clock.now)
        XCTAssertFalse(s.editNote(UUID()) { $0.body = "x" }, "unknown id")
    }

    func testMultipleNotesPerAnchorAndKinds() throws {
        let s = ephemeralStudy()
        let anchor = Anchor(book: "ROM", chapter: 8, verses: 28, to: 39)
        s.addNote(anchors: [anchor], title: "A", body: "one")
        s.addNote(anchors: [anchor], title: "B", kind: .oia,
                  sections: [NoteSection(key: "observation", text: "God works"), NoteSection(key: "application", text: "Trust")])
        XCTAssertEqual(s.notes(exactlyAt: anchor).count, 2)
        XCTAssertEqual(s.notes(overlapping: reference("ROM", 8, 30)).count, 2)
        XCTAssertEqual(s.notes.count, 2, "legacy list shows the OIA note via its section text")
        XCTAssertEqual(s.search("trust").first?.title, "B", "sections are searchable")
    }
}

// MARK: - Soft delete

@MainActor
final class StudyStoreSoftDeleteTests: XCTestCase {
    func testSoftDeleteHidesRestoresAndExpiresAfterThirtyDays() throws {
        let dir = temporaryDirectory("soft")
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let s = store(in: dir, clock: clock)
        let note = try XCTUnwrap(s.addNote(anchors: [reference("ROM", 8, 28)], title: "Bye", body: "text"))
        let saved = try XCTUnwrap(s.save(reference("JHN", 3, 16)))

        XCTAssertTrue(s.deleteNote(note.id)); XCTAssertTrue(s.unsave(saved.id))
        XCTAssertTrue(s.allNotes.isEmpty); XCTAssertTrue(s.savedPassages.isEmpty)
        XCTAssertTrue(s.search("bye").isEmpty, "deleted items never surface in search")
        XCTAssertTrue(s.items(overlapping: Anchor(book: "ROM", chapter: 8)).isEmpty)
        let deleted = s.recentlyDeleted
        XCTAssertEqual(Set(deleted.map(\.kind.hashValue)).count, 2)
        XCTAssertEqual(deleted.first?.expiresAt, clock.now.addingTimeInterval(30 * 86_400))

        XCTAssertTrue(s.restore(try XCTUnwrap(deleted.first { $0.id == note.id })))
        XCTAssertEqual(s.note(id: note.id)?.body, "text")

        clock.advance(days: 29)
        XCTAssertEqual(s.purgeExpired(), 0, "29 days is still inside retention")
        clock.advance(days: 2)
        XCTAssertEqual(s.purgeExpired(), 1, "the un-restored saved passage expires at 30 days")
        XCTAssertTrue(s.recentlyDeleted.isEmpty)
        XCTAssertNotNil(s.note(id: note.id), "restored items are unaffected")
    }

    func testExpiredItemsArePurgedAtLaunchAndEmptyTrashWorks() throws {
        let dir = temporaryDirectory("soft-launch")
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let a = store(in: dir, clock: clock)
        let n = try XCTUnwrap(a.addNote(title: "old", body: "x")); a.deleteNote(n.id)
        clock.advance(days: 31)
        let b = store(in: dir, clock: clock)
        XCTAssertEqual(b.loadReport.purgedExpired, 1)
        XCTAssertTrue(b.data.notes.isEmpty)

        let m = try XCTUnwrap(b.addNote(title: "new", body: "y")); b.deleteNote(m.id)
        XCTAssertEqual(b.emptyRecentlyDeleted(), 1)
        XCTAssertTrue(b.data.notes.isEmpty)
    }
}

// MARK: - Saved, collections, tags

@MainActor
final class StudyStoreSavedTests: XCTestCase {
    func testSaveIsIdempotentTogglesAndRestoresTheSameRecord() throws {
        let s = ephemeralStudy()
        let anchor = Anchor(book: "ROM", chapter: 8, verses: 28, to: 39)
        let first = try XCTUnwrap(s.save(anchor))
        XCTAssertEqual(s.save(anchor)?.id, first.id, "saving twice yields one record")
        XCTAssertEqual(s.savedPassages.count, 1)
        XCTAssertTrue(s.isSaved(anchor))
        XCTAssertEqual(s.toggleSaved(anchor), false)
        XCTAssertFalse(s.isSaved(anchor))
        XCTAssertEqual(s.toggleSaved(anchor), true)
        XCTAssertEqual(s.savedPassages.first?.id, first.id, "toggling back on restores the original record")
        XCTAssertEqual(s.data.saved.count, 1)
    }

    func testHighlightMemoryTagsAndCanonicalOrder() throws {
        let s = ephemeralStudy()
        let john = try XCTUnwrap(s.save(reference("JHN", 3, 16)))
        let gen = try XCTUnwrap(s.save(reference("GEN", 1, 1)))
        s.setHighlight(john.id, .pink); s.setMemory(john.id, true); s.setTags(savedID: john.id, tags: ["gospel", "Gospel", " love "])
        XCTAssertEqual(s.savedPassages.map(\.id), [gen.id, john.id], "canonical Bible order")
        let stored = try XCTUnwrap(s.savedPassage(id: john.id))
        XCTAssertEqual(stored.highlight, .pink); XCTAssertTrue(stored.isMemory); XCTAssertEqual(stored.tags, ["gospel", "love"])
        s.setHighlight(john.id, nil)
        XCTAssertNil(s.savedPassage(id: john.id)?.highlight)
        XCTAssertEqual(s.savedPassages(taggedWith: "#GOSPEL").count, 1)
    }

    func testCollectionsDedupeOrderAndDeleteKeepsPassages() throws {
        let s = ephemeralStudy()
        let a = try XCTUnwrap(s.save(reference("ROM", 8, 28))), b = try XCTUnwrap(s.save(reference("ROM", 8, 29)))
        let c = try XCTUnwrap(s.createCollection(name: "  Security in Christ "))
        XCTAssertEqual(s.createCollection(name: "security IN christ")?.id, c.id, "case-insensitive dedupe")
        XCTAssertNil(s.createCollection(name: "   "))
        XCTAssertFalse(s.addToCollection(savedID: a.id, collectionID: UUID()), "unknown collection")
        s.addToCollection(savedID: a.id, collectionID: c.id); s.addToCollection(savedID: b.id, collectionID: c.id)
        s.addToCollection(savedID: a.id, collectionID: c.id)
        XCTAssertEqual(s.savedPassages(in: c.id).map(\.id), [a.id, b.id])
        s.setOrder(collectionID: c.id, order: [b.id, a.id])
        XCTAssertEqual(s.savedPassages(in: c.id).map(\.id), [b.id, a.id])
        XCTAssertTrue(s.renameCollection(c.id, to: "Renamed"))
        XCTAssertEqual(s.collections.first?.name, "Renamed")
        s.removeFromCollection(savedID: a.id, collectionID: c.id)
        XCTAssertEqual(s.savedPassages(in: c.id).map(\.id), [b.id])
        s.deleteCollection(c.id)
        XCTAssertEqual(s.savedPassages.count, 2, "deleting a collection never deletes passages")
        XCTAssertTrue(s.savedPassages.allSatisfy { $0.collectionIDs.isEmpty })
    }

    func testTagCountsAcrossNotesAndSaved() throws {
        let s = ephemeralStudy()
        s.addNote(title: "n", body: "b", tags: ["Faith", "hope"])
        let p = try XCTUnwrap(s.save(reference("ROM", 8, 28), tags: ["faith"]))
        _ = p
        XCTAssertEqual(s.tagCounts().map(\.tag), ["Faith", "hope"])
        XCTAssertEqual(s.tagCounts().map(\.count), [2, 1])
        XCTAssertEqual(s.notes(taggedWith: "FAITH").count, 1)
    }
}

// MARK: - Overlap queries and search

@MainActor
final class StudyStoreSearchTests: XCTestCase {
    private func seeded() throws -> (StudyStore, [String: UUID]) {
        let clock = TestClock(Date(timeIntervalSince1970: 1_800_000_000))
        let s = ephemeralStudy(clock: { clock.now })
        var ids: [String: UUID] = [:]
        func add(_ key: String, _ anchor: Anchor?, _ title: String, _ body: String, tags: [String] = []) {
            clock.advance(seconds: 10)
            ids[key] = s.addNote(anchors: anchor.map { [$0] } ?? [], title: title, body: body, tags: tags)?.id
        }
        add("r28", reference("ROM", 8, 28), "Providence", "All things work together for good", tags: ["providence"])
        add("r31", Anchor(book: "ROM", chapter: 8, verses: 31, to: 39), "No separation", "Nothing can separate us", tags: ["security"])
        add("j316", reference("JHN", 3, 16), "The Word", "God so loved the world")
        add("r9", reference("ROM", 9, 1), "Israel", "Great sorrow and unceasing anguish")
        add("cafe", nil, "Café notes", "Résumé of a sermon")
        clock.advance(seconds: 10)
        ids["saved"] = s.save(reference("ROM", 8, 30), tags: ["calling"], collectionIDs: [])?.id
        let coll = try XCTUnwrap(s.createCollection(name: "Golden chain"))
        s.addToCollection(savedID: try XCTUnwrap(ids["saved"]), collectionID: coll.id)
        return (s, ids)
    }

    func testOverlapQueryFindsRangesAndVerses() throws {
        let (s, ids) = try seeded()
        let chapter8 = s.items(overlapping: Anchor(book: "ROM", chapter: 8))
        XCTAssertEqual(Set(chapter8.notes.map(\.id)), [try XCTUnwrap(ids["r28"]), try XCTUnwrap(ids["r31"])])
        XCTAssertEqual(chapter8.saved.count, 1)
        XCTAssertEqual(s.items(overlapping: reference("ROM", 8, 33)).notes.map(\.id), [try XCTUnwrap(ids["r31"])], "range note covers 8:33")
        XCTAssertTrue(s.items(overlapping: reference("ROM", 8, 30)).notes.isEmpty, "8:30 falls between the two notes")
        XCTAssertEqual(s.items(overlapping: Anchor(book: "ROM", chapter: 8, throughChapter: 9)).notes.count, 3)
        XCTAssertTrue(s.items(overlapping: Anchor(book: "GEN", chapter: 1)).isEmpty)
    }

    func testReferenceQueriesFindOverlappingItems() throws {
        let (s, ids) = try seeded()
        let romans8 = s.search("Rom 8")
        XCTAssertEqual(Set(romans8.map(\.id)), [try XCTUnwrap(ids["r28"]), try XCTUnwrap(ids["r31"]), try XCTUnwrap(ids["saved"])])
        XCTAssertEqual(s.search("Romans 8:35").map(\.id), [try XCTUnwrap(ids["r31"])])
        XCTAssertEqual(Set(s.search("Romans 8:28\u{2013}39").map(\.id)), Set(romans8.map(\.id)))
        XCTAssertEqual(s.search("Romans").count, 4, "a bare book name matches every Romans item")
    }

    func testTextTagAndCollectionSearch() throws {
        let (s, ids) = try seeded()
        XCTAssertEqual(s.search("separate").map(\.id), [try XCTUnwrap(ids["r31"])])
        XCTAssertEqual(s.search("loved world").map(\.id), [try XCTUnwrap(ids["j316"])], "all words must match")
        XCTAssertTrue(s.search("loved banana").isEmpty)
        XCTAssertEqual(s.search("#security").map(\.id), [try XCTUnwrap(ids["r31"])], "#tag matches tags only")
        XCTAssertTrue(s.search("#separate").isEmpty)
        XCTAssertEqual(s.search("golden").map(\.id), [try XCTUnwrap(ids["saved"])], "collection names find their passages")
        XCTAssertEqual(s.search("calling").map(\.kind), [.saved], "saved tags")
        XCTAssertEqual(s.search("CAFE").map(\.id), [try XCTUnwrap(ids["cafe"])], "case and diacritic insensitive")
        XCTAssertEqual(s.search("resume").count, 1)
    }

    func testScopeFilterOrderAndEmptyQuery() throws {
        let (s, ids) = try seeded()
        XCTAssertEqual(s.search("", scope: .all).count, 6)
        XCTAssertEqual(s.search("", scope: .notes).count, 5)
        XCTAssertEqual(s.search("", scope: .saved).map(\.id), [try XCTUnwrap(ids["saved"])])
        XCTAssertTrue(s.search("Rom 8", scope: .clips).isEmpty)
        let hits = s.search("Romans")
        XCTAssertEqual(hits.map(\.date), hits.map(\.date).sorted(by: >), "newest first")
    }

    func testClipsAndProjectsAreSearchable() throws {
        let s = ephemeralStudy()
        s.addClip(Clip(kind: .commentary, excerpt: "Providence is the hand of God", citation: ClipCitation(author: "Calvin", work: "Institutes"),
                       anchor: reference("ROM", 8, 28), capturedAt: Date()))
        s.upsertProject(StudyProject(title: "Sunday sermon", primaryAnchor: Anchor(book: "ROM", chapter: 8),
                                     outline: [OutlineNode(title: "Golden chain", text: "foreknew predestined")], createdAt: Date()))
        XCTAssertEqual(s.search("hand of god").map(\.kind), [.clip])
        XCTAssertEqual(s.search("predestined").map(\.kind), [.project])
        XCTAssertEqual(Set(s.search("Rom 8").map(\.kind)), [.clip, .project])
        XCTAssertEqual(s.items(overlapping: reference("ROM", 8, 28)).clips.count, 1)
        s.removeClip(try XCTUnwrap(s.clips.first).id)
        XCTAssertTrue(s.clips.isEmpty)
    }
}

// MARK: - App wiring

@MainActor
final class StudyStoreWiringTests: XCTestCase {
    func testNavigateToStoredRangeLandsOnItsFirstVerse() {
        let state = makeOfflineState()
        state.navigate(toStoredPassage: "Romans 8:28\u{2013}39")
        XCTAssertEqual(state.selectedBookCode, "ROM"); XCTAssertEqual(state.selectedChapter, 8); XCTAssertEqual(state.selectedVerse, 28)
        state.navigate(toStoredPassage: "Romans 8:39\u{2013}9:5")
        XCTAssertEqual(state.selectedChapter, 8); XCTAssertEqual(state.selectedVerse, 39)
        state.navigate(toStoredPassage: "Psalms 23:1")
        XCTAssertEqual(state.selectedBookCode, "PSA"); XCTAssertEqual(state.selectedChapter, 23)
        state.navigate(toStoredPassage: "Psalm 23:4")
        XCTAssertEqual(state.selectedVerse, 4)
        state.navigate(toStoredPassage: "1 Corinthians 13:4")
        XCTAssertEqual(state.selectedBookCode, "1CO"); XCTAssertEqual(state.selectedVerse, 4)
    }

    func testAppStateExposesTheStudyStoreUnderBothNames() {
        let state = makeOfflineState()
        XCTAssertTrue(state.study === state.notes)
        state.notes.update(passage: state.passage, title: "T", body: "B")
        XCTAssertEqual(state.study.allNotes.first?.anchors.first?.displayString, state.passage.replacingOccurrences(of: "Psalms", with: "Psalm"))
    }
}
