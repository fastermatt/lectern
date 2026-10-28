import AppKit
import SwiftUI
import XCTest
import StudyTableCore
@testable import StudyTable

/// R3 (0.10): BSB section headings, parallel references and paragraph starts.
///
/// Set STUDYTABLE_SNAPSHOT_DIR to write the review renders. Set LECTERN_R3_BASELINE_DIR to a folder
/// of renders captured from the pre-heading reader to run the pixel comparisons against the real
/// "before" (the 0.10 baseline lives in /private/tmp/st-R3-baseline).
@MainActor
final class HeadingTests: XCTestCase {
    // MARK: Offscreen rendering (same approach as SnapshotTests)

    static func bitmap<V: View>(_ view: V, dark: Bool, size: CGSize) throws -> NSBitmapImageRep {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = appearance
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))   // offscreen; never shown to the user
        window.orderBack(nil)
        defer { window.contentView = nil; window.orderOut(nil) }
        for _ in 0..<8 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.2)) }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    static func stateAt(_ code: String, _ chapter: Int, _ verse: Int, translation: String = "BSB",
                        size: Double = 20, spacing: Double = 8, headings: Bool = true) -> AppState {
        let state = makeOfflineState()
        state.translationID = translation
        state.selectedBookCode = code
        state.selectedChapter = chapter
        state.selectedVerse = verse
        state.fontSize = size
        state.lineSpacing = spacing
        state.preferenceStore.set(headings, forKey: "showSectionHeadings")
        return state
    }

    private var snapshotDirectory: URL? {
        ProcessInfo.processInfo.environment["STUDYTABLE_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }
    private var baselineDirectory: URL? {
        ProcessInfo.processInfo.environment["LECTERN_R3_BASELINE_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    static func write(_ rep: NSBitmapImageRep, to directory: URL, name: String) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("\(name).png"))
    }

    /// Bytes in a fixed RGBA8 sRGB layout, so a decoded PNG and a fresh render compare exactly.
    static func rgba(_ rep: NSBitmapImageRep) -> (width: Int, height: Int, bytes: [UInt8]) {
        let width = rep.pixelsWide, height = rep.pixelsHigh
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        bytes.withUnsafeMutableBytes { buffer in
            let context = CGContext(data: buffer.baseAddress, width: width, height: height, bitsPerComponent: 8,
                                    bytesPerRow: width * 4, space: space,
                                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            if let image = rep.cgImage { context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height)) }
        }
        return (width, height, bytes)
    }

    /// One hash per pixel row (FNV-1a over the row's bytes), skipping the pane's own edge bands, which
    /// carry a vertical light gradient that depends on absolute position.
    static func rowHashes(_ image: (width: Int, height: Int, bytes: [UInt8])) -> [UInt64] {
        let margin = 100
        return (0..<image.height).map { y in
            var hash: UInt64 = 0xcbf29ce484222325
            image.bytes.withUnsafeBufferPointer { buffer in
                for byte in buffer[(y * image.width * 4 + margin * 4)..<((y + 1) * image.width * 4 - margin * 4)] {
                    hash = (hash ^ UInt64(byte)) &* 0x100000001b3
                }
            }
            return hash
        }
    }

    // MARK: Source helpers

    private func sourceLines(_ folder: String) throws -> [String] {
        let directory = TestPaths.scriptureSource.appendingPathComponent(folder)
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "usfm" }.sorted { $0.lastPathComponent < $1.lastPathComponent }
            .flatMap { try String(contentsOf: $0, encoding: .utf8).components(separatedBy: .newlines) }
    }

    private func builtPack(_ folder: String) throws -> BuiltPack {
        try ScripturePackBuilder.build(sourceDirectory: TestPaths.scriptureSource.appendingPathComponent(folder))
    }

    private func parse(_ usfm: String) throws -> ParsedBook {
        try XCTUnwrap(USFMParser.parseBook("\\id JHN Test\n\\toc1 John\n" + usfm))
    }
}

// MARK: - Parser

extension HeadingTests {
    func testHeadingKeyedToTheVerseItPrecedesWithItsParallelReferences() throws {
        let book = try parse("""
        \\c 4
        \\s1 Jesus Calms the Storm
        \\r (Psalms 107:1–43; Matthew 8:23–27; Luke 8:22–25)
        \\b
        \\m
        \\v 35 On that day, when evening came, He said to them.
        \\v 36 Leaving the crowd.
        \\s2 A subsection
        \\v 37 A great storm.
        """)
        let headings = try XCTUnwrap(book.headings[4])
        XCTAssertEqual(headings.map(\.verse), [35, 37])
        XCTAssertEqual(headings.map(\.level), [1, 2])
        XCTAssertEqual(headings[0].title, "Jesus Calms the Storm")
        XCTAssertEqual(headings[0].parallels?.map(\.label), ["Psalms 107:1–43", "Matthew 8:23–27", "Luke 8:22–25"])
        XCTAssertEqual(book.chapters[4]?.map(\.text).first, "On that day, when evening came, He said to them.", "verse text is untouched")
    }

    func testAHeadingBeforeAChapterMarkerBelongsToTheNewChapterAndPsalmTitlesStayVerseZero() throws {
        let book = try parse("""
        \\c 1
        \\v 1 First.
        \\ms1 BOOK II
        \\mr Psalms 42—72
        \\c 2
        \\s1 A Title
        \\d For the choirmaster.
        \\v 1 Text.
        """)
        XCTAssertNil(book.headings[1])
        let second = try XCTUnwrap(book.headings[2])
        XCTAssertEqual(second.map(\.title), ["BOOK II", "A Title"])
        XCTAssertEqual(second.map(\.verse), [0, 0], "both sit above the unnumbered superscription")
        XCTAssertEqual(second[0].subtitle, "Psalms 42—72")
        XCTAssertEqual(book.chapters[2]?.map(\.number), [0, 1])
    }

    func testHeadingsThatPointNowhereAreDroppedAndCounted() throws {
        let book = try parse("""
        \\c 1
        \\v 1 First line
        \\s2 The Friends
        \\b
        \\q1 second half of the same verse
        \\v 2 Second.
        \\s1 Written to Titus from Nicopolis
        """)
        XCTAssertNil(book.headings[1], "a heading in the middle of a verse, or with no verse after it, is not kept")
        XCTAssertEqual(book.stats.droppedHeadings.count, 2)
        XCTAssertEqual(book.chapters[1]?.first?.text, "First line second half of the same verse")
    }

    func testAcrosticLettersAreHeadingsAndNoLongerLeakIntoTheVerseAboveThem() throws {
        let book = try parse("""
        \\c 119
        \\v 8 I will keep Your statutes.
        \\b
        \\qa BETH
        \\b
        \\q1
        \\v 9 How can a young man keep his way pure?
        """)
        XCTAssertEqual(book.chapters[119]?.first?.text, "I will keep Your statutes.")
        XCTAssertEqual(book.headings[119]?.map(\.title), ["BETH"])
        XCTAssertEqual(book.headings[119]?.first?.verse, 9)
        XCTAssertEqual(book.headings[119]?.first?.level, 3)
    }

    func testParagraphStartsFollowBreakMarkersAndIgnoreBreaksInsideAVerse() throws {
        let book = try parse("""
        \\c 1
        \\p
        \\v 1 One.
        \\v 2 Two.
        \\p
        \\v 3 Three
        \\b
        \\q1 still verse three
        \\v 4 Four.
        \\b
        \\m
        \\v 5 Five.
        """)
        XCTAssertEqual(book.paragraphStarts[1], [1, 3, 5])
    }

    func testParallelReferenceParsingCoversEveryFormTheSourceUses() {
        func one(_ text: String) -> ParallelReference { ParallelReferenceParser.parseOne(text) }
        let simple = one("Matthew 8:23–27")
        XCTAssertEqual([simple.book, "\(simple.chapter):\(simple.verse)–\(simple.endChapter):\(simple.endVerse)"], ["MAT", "8:23–8:27"])
        let single = one("Isaiah 6:1")
        XCTAssertEqual([single.chapter, single.verse, single.endChapter, single.endVerse], [6, 1, 6, 1])
        let cross = one("1 Chronicles 15:29—16:3")
        XCTAssertEqual(cross.book, "1CH")
        XCTAssertEqual([cross.chapter, cross.verse, cross.endChapter, cross.endVerse], [15, 29, 16, 3])
        let chapters = one("Genesis 15—22")
        XCTAssertEqual([chapters.chapter, chapters.verse, chapters.endChapter, chapters.endVerse], [15, 0, 22, 0])
        let whole = one("Psalm 23")
        XCTAssertEqual([whole.book, "\(whole.chapter)"], ["PSA", "23"])
        let oneChapterBook = one("Jude 5–7")
        XCTAssertEqual([oneChapterBook.chapter, oneChapterBook.verse, oneChapterBook.endVerse], [1, 5, 7])
        XCTAssertEqual(one("Song of Solomon 2:1").book, "SNG")
        XCTAssertEqual(one("Nowhere 3:4").book, nil, "an unknown book keeps its label and is not navigable")
        XCTAssertFalse(one("Nowhere 3:4").isNavigable)
        XCTAssertEqual(ParallelReferenceParser.parse("(Isaiah 40:1–5; Matthew 3:1–17; Luke 3:1–22; John 1:19–34)").count, 4)
        XCTAssertEqual(ParallelReferenceParser.parse("").count, 0)
    }
}

// MARK: - The shipped packs

extension HeadingTests {
    /// The counts in the brief: 3,017 section headings and 1,324 parallel lines in the BSB source.
    func testBSBHeadingAndParallelCountsMatchTheSource() throws {
        let lines = try sourceLines("bsb")
        let sourceHeadings = lines.filter { $0 == "\\s1" || $0.hasPrefix("\\s1 ") }.count
        let sourceParallels = lines.filter { $0.hasPrefix("\\r ") }.count
        XCTAssertEqual(sourceHeadings, 3017)
        XCTAssertEqual(sourceParallels, 1324)

        let stats = try builtPack("bsb").stats
        XCTAssertEqual(stats.headingsByLevel[1], 3017, "every \\s1 in the source is a level-1 heading in the pack")
        XCTAssertEqual(stats.parallelLines, 1324)
        XCTAssertEqual(stats.unresolvedReferences, [], "every parallel reference resolves to a real book")
        XCTAssertEqual(stats.headingsByLevel[0], 5, "BOOK I...V of the Psalter")
        XCTAssertEqual(stats.headingsByLevel[3], 22, "Psalm 119's acrostic letters")
        XCTAssertEqual(stats.droppedHeadings.count, 6, "six Song of Solomon speaker labels sit in the middle of a verse")
        XCTAssertTrue(stats.droppedHeadings.allSatisfy { $0.hasPrefix("SNG") && $0.contains("mid-verse") })
        print("BSB STRUCTURE: headings \(stats.headings) \(stats.headingsByLevel.sorted { $0.key < $1.key }), parallel lines \(stats.parallelLines), references \(stats.parallelReferences), paragraph starts \(stats.paragraphStarts)")
    }

    func testCommittedPacksCarryExactlyWhatAFreshBuildProduces() throws {
        // Byte identity is asserted by the drift test in ScriptureTests; this checks it through the reader's decode path.
        let library = ScriptureLibrary()
        let fresh = try builtPack("bsb")
        let mark = try XCTUnwrap(fresh.books.first { $0.code == "MRK" })
        let chapter = try XCTUnwrap(mark.chapters.first { $0.n == 4 })
        let structure = try XCTUnwrap(library.structure(translation: "BSB", bookCode: "MRK", chapter: 4))
        XCTAssertEqual(structure.headings, chapter.s)
        XCTAssertEqual(structure.paragraphStarts, Set(chapter.p ?? []))
    }

    func testMarkFourThirtyFiveHasItsHeadingAndThreeParallels() throws {
        let library = ScriptureLibrary()
        let structure = try XCTUnwrap(library.structure(translation: "BSB", bookCode: "MRK", chapter: 4))
        let heading = try XCTUnwrap(structure.headings(before: 35).first)
        XCTAssertEqual(heading.title, "Jesus Calms the Storm")
        XCTAssertEqual(heading.level, 1)
        XCTAssertEqual(heading.parallels?.map(\.label), ["Psalms 107:1–43", "Matthew 8:23–27", "Luke 8:22–25"])
        XCTAssertEqual(heading.parallels?.map(\.book), ["PSA", "MAT", "LUK"])
        XCTAssertEqual(heading.parallels?.map(\.chapter), [107, 8, 8])
        XCTAssertEqual(heading.parallels?.map(\.verse), [1, 23, 22])
        XCTAssertEqual(heading.parallels?.map(\.endVerse), [43, 27, 25])
        XCTAssertTrue(heading.parallels?.allSatisfy(\.isNavigable) ?? false)
        // The verse text under it is what it always was.
        XCTAssertTrue(try XCTUnwrap(library.chapter(translation: "BSB", bookCode: "MRK", chapter: 4)?.first { $0.number == 35 }?.text)
            .hasPrefix("When that evening came, He said to His disciples"))
    }

    func testEveryHeadingPointsAtARealVerseInEveryBundledPack() throws {
        let library = ScriptureLibrary()
        for id in ["BSB", "KJV", "WEB"] {
            for book in library.books {
                for chapter in book.chapterNumbers {
                    guard let structure = library.structure(translation: id, bookCode: book.code, chapter: chapter) else { continue }
                    for heading in structure.headings {
                        XCTAssertTrue(structure.verseNumbers.contains(heading.verse), "\(id) \(book.code) \(chapter): heading “\(heading.title)” → verse \(heading.verse)")
                        XCTAssertFalse(heading.title.isEmpty)
                    }
                    XCTAssertTrue(structure.paragraphStarts.isSubset(of: Set(structure.verseNumbers)), "\(id) \(book.code) \(chapter)")
                }
            }
        }
    }

    func testOnlyBSBHasRealHeadingsAndTheOtherTwoDoNotInventAny() throws {
        let kjv = try builtPack("kjv").stats, web = try builtPack("web").stats
        XCTAssertEqual(kjv.headings, 22, "KJV: only Psalm 119's letters; the epistle subscriptions are not headings")
        XCTAssertEqual(kjv.droppedHeadings.count, 14)
        XCTAssertTrue(kjv.droppedHeadings.allSatisfy { $0.contains("no verse follows") })
        XCTAssertEqual(web.headings, 5, "WEB: the five Psalter divisions (its \\sp lines are speaker labels, not sections)")
        XCTAssertEqual(kjv.parallelLines + web.parallelLines, 0)
    }

    func testPackSizeGrowthIsReportedAndSmall() throws {
        var report: [String] = []
        for id in ["BSB", "KJV", "WEB"] {
            let directory = TestPaths.scripturePacks.appendingPathComponent(id)
            let total = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.fileSizeKey])
                .filter { $0.pathExtension == "json" }
                .reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
            report.append("\(id) \(total)")
            XCTAssertLessThan(total, 4_500_000, "\(id) pack is unexpectedly large")
        }
        print("PACK BYTES (after): \(report.joined(separator: ", ")); before: BSB 4039031, KJV 4330944, WEB 4219729")
    }
}

// MARK: - Pericopes (the API wave B builds range selection on)

extension HeadingTests {
    func testPericopeSpansFollowTheHeadings() throws {
        let library = ScriptureLibrary()
        let romans8 = library.pericopes(bookCode: "ROM", chapter: 8)
        XCTAssertEqual(romans8.map(\.title), ["Walking by the Spirit", "Heirs with Christ", "Future Glory", "God Works in All Things", "More than Conquerors"])
        let works = try XCTUnwrap(romans8.first { $0.title == "God Works in All Things" })
        XCTAssertEqual([works.startChapter, works.startVerse, works.endChapter, works.endVerse], [8, 28, 8, 34])
        let conquerors = try XCTUnwrap(romans8.last)
        XCTAssertEqual([conquerors.startVerse, conquerors.endChapter, conquerors.endVerse], [35, 8, 39], "runs to the end of the chapter that a new section then follows")
        // Mark 4:35–41, the storm.
        let storm = try XCTUnwrap(library.pericope(containing: 4, verse: 38, bookCode: "MRK"))
        XCTAssertEqual([storm.title, "\(storm.startVerse)-\(storm.endVerse)"], ["Jesus Calms the Storm", "35-41"])
        XCTAssertNil(library.pericope(containing: 4, verse: 38, bookCode: "MRK", translation: "KJV"), "KJV has no section headings")
    }

    func testSubsectionsNestInsideTheirSectionAndLevelChoosesWhichOneYouGet() throws {
        let library = ScriptureLibrary()
        // Genesis 1's six days are level-2 subsections of "The Creation" (level 1).
        let section = try XCTUnwrap(library.pericope(containing: 1, verse: 4, bookCode: "GEN", level: 1))
        XCTAssertEqual(section.title, "The Creation")
        let day = try XCTUnwrap(library.pericope(containing: 1, verse: 4, bookCode: "GEN"))
        XCTAssertEqual(day.title, "The First Day")
        XCTAssertEqual(day.level, 2)
        XCTAssertTrue(section.contains(chapter: 1, verse: 4) && day.contains(chapter: 1, verse: 4))
        XCTAssertLessThanOrEqual(section.startVerse, day.startVerse)
        XCTAssertGreaterThanOrEqual(section.endVerse, day.endVerse)
        XCTAssertTrue(library.pericopes(bookCode: "GEN", chapter: 1, maxLevel: 1).allSatisfy { $0.level == 1 })
    }

    func testAPsalmTitleIsPartOfItsSectionAndClampsToVerseOne() throws {
        let library = ScriptureLibrary()
        let psalm3 = try XCTUnwrap(library.pericopes(bookCode: "PSA", chapter: 3).first)
        XCTAssertEqual(psalm3.title, "Deliver Me, O LORD!")
        XCTAssertTrue(psalm3.includesSuperscription)
        XCTAssertEqual([psalm3.startVerse, psalm3.endChapter, psalm3.endVerse], [1, 3, 8])
        XCTAssertEqual(psalm3.parallels.map(\.label), ["2 Samuel 15:13–29"])
        // "BOOK I" is a division (level 0): reachable on request, not in the default list.
        XCTAssertFalse(library.pericopes(bookCode: "PSA", chapter: 1).contains { $0.level == 0 })
        let division = try XCTUnwrap(library.allPericopes(bookCode: "PSA").first { $0.level == 0 })
        XCTAssertEqual([division.title, division.subtitle ?? ""], ["BOOK I", "Psalms 1—41"])
        XCTAssertEqual([division.startChapter, division.endChapter, division.endVerse], [1, 41, 13])
    }

    /// The property range selection needs: level-1 sections of a book tile it end to end, with no gap and no overlap.
    func testLevelOneSectionsTileEveryBookWithNoGapsOrOverlaps() throws {
        let library = ScriptureLibrary()
        var checked = 0
        for book in library.books {
            let sections = library.allPericopes(bookCode: book.code).filter { $0.level == 1 }
            XCTAssertFalse(sections.isEmpty, book.code)
            // Two headings over the same verse (Hebrews 11:30) share one span.
            var distinct: [Pericope] = []
            for section in sections where distinct.last.map({ ($0.startChapter, $0.startVerse) != (section.startChapter, section.startVerse) }) ?? true {
                distinct.append(section)
            }
            XCTAssertEqual([distinct[0].startChapter, distinct[0].startVerse], [1, 1], "\(book.code) starts at 1:1")
            for (previous, next) in zip(distinct, distinct.dropFirst()) {
                // BSB omits a few verses (Mark 9:44, 46; Acts 28:29), so the last verse is the highest number, not the count.
                let last = library.chapter(translation: "BSB", bookCode: book.code, chapter: previous.endChapter)?.map(\.number).max() ?? 0
                let expected = previous.endVerse >= last ? (previous.endChapter + 1, 1) : (previous.endChapter, previous.endVerse + 1)
                XCTAssertEqual([next.startChapter, next.startVerse], [expected.0, expected.1],
                               "\(book.code): “\(previous.title)” ends \(previous.endChapter):\(previous.endVerse) but “\(next.title)” starts \(next.startChapter):\(next.startVerse)")
                checked += 1
            }
            let tail = try XCTUnwrap(distinct.last)
            let lastVerse = library.chapter(translation: "BSB", bookCode: book.code, chapter: book.chapterCount)?.map(\.number).max() ?? 0
            XCTAssertEqual([tail.endChapter, tail.endVerse], [book.chapterCount, lastVerse], "\(book.code) ends at its last verse")
        }
        print("PERICOPE TILING: \(checked) adjacent BSB section pairs verified gap- and overlap-free across 66 books")
    }

    /// BSB opens nearly every chapter with a heading, so its own sections rarely cross a chapter line; the
    /// computation must still carry a section on when the next chapter has no heading of its own.
    func testASectionCarriesOnThroughAChapterThatHasNoHeading() {
        func chapter(_ n: Int, verses: Int, headings: [SectionHeading]) -> ChapterPack {
            ChapterPack(n: n, v: Array(1...verses), t: (1...verses).map { "v\($0)" }, s: headings.isEmpty ? nil : headings)
        }
        let book = BookPack(code: "TST", name: "Test", chapters: [
            chapter(1, verses: 10, headings: [SectionHeading(verse: 1, level: 1, title: "A"), SectionHeading(verse: 6, level: 1, title: "B")]),
            chapter(2, verses: 8, headings: []),
            chapter(3, verses: 5, headings: [SectionHeading(verse: 1, level: 1, title: "C"), SectionHeading(verse: 4, level: 2, title: "C-sub")]),
            chapter(4, verses: 3, headings: [SectionHeading(verse: 0, level: 1, title: "D")]),
        ])
        let spans = PericopeIndex.pericopes(in: book).map { "\($0.title) \($0.startChapter):\($0.startVerse)-\($0.endChapter):\($0.endVerse)" }
        XCTAssertEqual(spans, ["A 1:1-1:5", "B 1:6-2:8", "C 3:1-3:5", "C-sub 3:4-3:5", "D 4:1-4:3"])
        XCTAssertTrue(PericopeIndex.pericopes(in: book)[1].contains(chapter: 2, verse: 4))
    }
}

// MARK: - Downloaded, online and older packs

extension HeadingTests {
    func testAnInstalledPackFromTheDownloadManagerCarriesNoHeadings() async throws {
        // A real archive: every BSB USFM book (headings and all) zipped, then installed as the "ASV" download.
        let workspace = temporaryDirectory("r3-download")
        let source = TestPaths.scriptureSource.appendingPathComponent("bsb")
        let archive = workspace.appendingPathComponent("eng-asv_usfm.zip")
        let zip = Process()
        zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = source
        zip.arguments = ["-q", archive.path] + (try FileManager.default.contentsOfDirectory(atPath: source.path).filter { $0.hasSuffix(".usfm") })
        try zip.run(); zip.waitUntilExit()
        XCTAssertEqual(zip.terminationStatus, 0)
        let data = try Data(contentsOf: archive)
        let root = workspace.appendingPathComponent("Translations", isDirectory: true)
        let edition = try XCTUnwrap(BibleDownload.catalog.first { $0.id == "ASV" })
        try await BibleInstaller(root: root) { _, _ in data }.install(edition) { _ in }

        let mark = try String(contentsOf: root.appendingPathComponent("ASV/MRK.json"), encoding: .utf8)
        XCTAssertFalse(mark.contains("\"s\":["), "no section headings in a downloaded pack")
        XCTAssertFalse(mark.contains("\"p\":["), "no paragraph marks in a downloaded pack")
        XCTAssertFalse(mark.contains("Calms the Storm"))
        let library = ScriptureLibrary(userRoot: root)
        XCTAssertEqual(library.translation(id: "ASV")?.delivery, .installedPack)
        XCTAssertNil(library.structure(translation: "ASV", bookCode: "MRK", chapter: 4))
        XCTAssertNotNil(library.chapter(translation: "ASV", bookCode: "MRK", chapter: 4), "the text itself reads normally")
        XCTAssertTrue(library.pericopes(bookCode: "MRK", chapter: 4, translation: "ASV").isEmpty)
    }

    func testAPackFromBeforeSchemaTwoStillLoadsAndHasNoStructure() throws {
        let userRoot = temporaryDirectory("translations")
        let installed = userRoot.appendingPathComponent("OLD")
        try FileManager.default.copyItem(at: TestPaths.scripturePacks.appendingPathComponent("KJV"), to: installed)
        let manifestURL = installed.appendingPathComponent("manifest.json")
        let edited = try String(contentsOf: manifestURL, encoding: .utf8)
            .replacingOccurrences(of: "\"schema\":2", with: "\"schema\":1")
            .replacingOccurrences(of: "\"id\":\"KJV\"", with: "\"id\":\"OLD\"")
            .replacingOccurrences(of: "\"abbreviation\":\"KJV\"", with: "\"abbreviation\":\"OLD\"")
        XCTAssertTrue(edited.contains("\"schema\":1"))
        try edited.write(to: manifestURL, atomically: true, encoding: .utf8)
        // Strip the new fields from one book, as a schema-1 file would be.
        let johnURL = installed.appendingPathComponent("JHN.json")
        let stripped = try String(contentsOf: johnURL, encoding: .utf8)
            .replacingOccurrences(of: #",\"p\":\[[0-9,]*\]"#, with: "", options: .regularExpression)
            .replacingOccurrences(of: #"\"p\":\[[0-9,]*\],"#, with: "", options: .regularExpression)
        try stripped.write(to: johnURL, atomically: true, encoding: .utf8)
        let library = ScriptureLibrary(userRoot: userRoot)
        XCTAssertEqual(library.translation(id: "OLD")?.delivery, .installedPack)
        XCTAssertNotNil(library.chapter(translation: "OLD", bookCode: "JHN", chapter: 3))
        XCTAssertNil(library.structure(translation: "OLD", bookCode: "JHN", chapter: 3))
    }

    func testOnlineAndLockedTranslationsNeverHaveStructure() {
        let library = ScriptureLibrary()
        for id in ["ESV", "NKJV", "NASB"] {
            XCTAssertNil(library.structure(translation: id, bookCode: "MRK", chapter: 4), id)
            XCTAssertTrue(library.pericopes(bookCode: "MRK", chapter: 4, translation: id).isEmpty, id)
        }
    }

    func testABuildWithoutStructureAddsNothingToTheJSON() throws {
        let pack = try ScripturePackBuilder.build(sourceDirectory: TestPaths.scriptureSource.appendingPathComponent("bsb"), includeStructure: false)
        XCTAssertTrue(pack.books.allSatisfy { $0.chapters.allSatisfy { $0.s == nil && $0.p == nil } })
        XCTAssertEqual(pack.stats, StructureStats())
    }
}

// MARK: - Reader behaviour

extension HeadingTests {
    func testTappingAParallelChipNavigatesAndBackReturnsToTheStorm() throws {
        let state = Self.stateAt("MRK", 4, 35)
        let heading = try XCTUnwrap(state.library.structure(translation: "BSB", bookCode: "MRK", chapter: 4)?.headings(before: 35).first)
        let matthew = try XCTUnwrap(heading.parallels?.first { $0.book == "MAT" })
        ParallelNavigation.open(matthew, in: state)
        XCTAssertEqual([state.selectedBookCode, "\(state.selectedChapter)", "\(state.selectedVerse ?? 0)"], ["MAT", "8", "23"])
        XCTAssertEqual(state.passageHistory.last, "Mark 4:35", "the passage we left is on the Back stack")
        state.returnToPreviousPassage()
        XCTAssertEqual([state.selectedBookCode, "\(state.selectedChapter)"], ["MRK", "4"])
        // A whole-chapter reference opens verse 1.
        ParallelNavigation.open(ParallelReferenceParser.parseOne("Psalm 23"), in: state)
        XCTAssertEqual(state.selectedBookCode, "PSA")
        XCTAssertEqual(state.selectedChapter, 23)
        XCTAssertEqual(state.selectedVerse, 1)
        // An unresolved reference does nothing.
        let before = state.selectedChapter
        ParallelNavigation.open(ParallelReferenceParser.parseOne("Nowhere 9:9"), in: state)
        XCTAssertEqual(state.selectedChapter, before)
    }

    func testSectionHeadingRowsAreAccessibleHeadingsInBothFinishes() throws {
        for dark in [false, true] {
            let state = Self.stateAt("MRK", 4, 35)
            let heading = try XCTUnwrap(state.library.structure(translation: "BSB", bookCode: "MRK", chapter: 4)?.headings(before: 35))
            let rep = try Self.bitmap(SectionHeadingRow(headings: heading).environmentObject(state).background(STColor.paper),
                                      dark: dark, size: CGSize(width: 560, height: 110))
            let image = Self.rgba(rep)
            XCTAssertGreaterThan(Set(Self.rowHashes(image)).count, 8, "the heading row drew something")
        }
    }
}

// MARK: - Pixel proofs: verse typography is unchanged

extension HeadingTests {
    /// Verse rows and whole chapters rendered now must match the pre-heading baseline exactly.
    func testVerseRowsAndHeadinglessChaptersArePixelIdenticalToTheBaselineBeforeThisChange() throws {
        guard let baseline = baselineDirectory, FileManager.default.fileExists(atPath: baseline.path) else {
            throw XCTSkip("LECTERN_R3_BASELINE_DIR not set: baseline renders of the old reader are a one-off artefact")
        }
        var compared = 0, worst = 0
        func compare(_ rep: NSBitmapImageRep, _ name: String) throws {
            let data = try Data(contentsOf: baseline.appendingPathComponent("\(name).png"))
            let old = Self.rgba(try XCTUnwrap(NSBitmapImageRep(data: data))), new = Self.rgba(rep)
            XCTAssertEqual([old.width, old.height], [new.width, new.height], name)
            var different = 0
            for offset in stride(from: 0, to: min(old.bytes.count, new.bytes.count), by: 4)
            where old.bytes[offset..<(offset + 4)] != new.bytes[offset..<(offset + 4)] { different += 1 }
            worst = max(worst, different)
            XCTAssertEqual(different, 0, "\(name): \(different) pixels differ from the pre-heading baseline")
            compared += 1
        }
        let library = ScriptureLibrary()
        let samples: [(String, String, Int, Int)] = [
            ("BSB", "JHN", 3, 16), ("BSB", "ROM", 8, 28), ("BSB", "MRK", 4, 39), ("KJV", "JHN", 3, 16),
            ("WEB", "PSA", 119, 1), ("BSB", "PSA", 3, 0), ("BSB", "PSA", 3, 1), ("KJV", "GEN", 1, 1),
        ]
        for (index, (translation, code, chapter, verse)) in samples.enumerated() {
            let row = try XCTUnwrap(library.chapter(translation: translation, bookCode: code, chapter: chapter)?.first { $0.number == verse })
            for (size, spacing) in [(20.0, 8.0), (15.0, 2.0), (28.0, 16.0)] {
                for dark in [false, true] {
                    let state = Self.stateAt(code, chapter, verse, translation: translation, size: size, spacing: spacing)
                    try compare(try Self.bitmap(VerseRow(verse: row).environmentObject(state).background(STColor.paper),
                                                dark: dark, size: CGSize(width: 520, height: 260)),
                                "row-\(index)-\(Int(size))-\(Int(spacing))-\(dark ? "d" : "l")")
                }
            }
        }
        // Whole panes with the editorial layer (headings + paragraph spacing) turned off must equal the old reader exactly.
        let panes: [(String, String, Int, Bool)] = [("BSB", "MRK", 4, false), ("BSB", "PSA", 1, false), ("KJV", "JHN", 3, false), ("WEB", "JHN", 3, false), ("BSB", "ROM", 8, false)]
        for (index, (translation, code, chapter, headings)) in panes.enumerated() {
            let state = Self.stateAt(code, chapter, 1, translation: translation, headings: headings)
            try compare(try Self.bitmap(ScripturePane().environmentObject(state).background(STColor.paper), dark: false,
                                        size: CGSize(width: 640, height: 5200)), "pane-\(index)-\(translation)-\(code)\(chapter)")
        }
        print("PIXEL PROOF vs pre-change baseline: \(compared) renders (24 isolated verse rows x2, plus 5 whole chapters), worst \(worst) differing pixels")
    }

    /// With headings shown, every pixel row of the verse text is still there, in order, unchanged:
    /// the headings are extra rows between verses and nothing else moves inside a row.
    func testVerseTextRowsAreUnchangedWhenHeadingsAreShown() throws {
        for (translation, code, chapter) in [("BSB", "MRK", 4), ("BSB", "ROM", 8), ("BSB", "PSA", 3), ("BSB", "GEN", 1), ("KJV", "JHN", 3), ("WEB", "GEN", 1)] {
            let size = CGSize(width: 640, height: 5200)
            // No verse selected: the selection wash is drawn with anti-aliased edges that legitimately move with the row.
            let offState = Self.stateAt(code, chapter, 1, translation: translation, headings: false)
            let onState = Self.stateAt(code, chapter, 1, translation: translation, headings: true)
            offState.selectedVerse = nil; onState.selectedVerse = nil
            let offRep = try Self.bitmap(ScripturePane().environmentObject(offState).background(STColor.paper), dark: false, size: size)
            let off = Self.rgba(offRep)
            let onRep = try Self.bitmap(ScripturePane().environmentObject(onState).background(STColor.paper), dark: false, size: size)
            let on = Self.rgba(onRep)
            let offRows = Self.rowHashes(off), onRows = Self.rowHashes(on)
            // The pane's own bottom border is not content: look for the last ink row above it.
            let contentLimit = offRows.count - 60
            let background = try XCTUnwrap(Dictionary(grouping: offRows[200..<contentLimit], by: { $0 }).max { $0.value.count < $1.value.count }?.key)
            let lastInk = try XCTUnwrap(offRows[..<contentLimit].lastIndex { $0 != background })
            var cursor = 0, matched = 0
            for row in offRows[0...lastInk] {
                while cursor < onRows.count, onRows[cursor] != row { cursor += 1 }
                guard cursor < onRows.count else { break }
                cursor += 1; matched += 1
            }
            XCTAssertEqual(matched, lastInk + 1, "\(translation) \(code) \(chapter): every pixel row of the headingless reader appears, in order, with headings on")
            XCTAssertNotEqual(onRows, offRows, "\(translation) \(code) \(chapter): the editorial layer is visibly present")
            print("VERSE-TEXT ROW PROOF \(translation) \(code) \(chapter): \(matched)/\(lastInk + 1) rows preserved in order")
        }
    }
}

// MARK: - Review renders (light, dark, 980pt)

extension HeadingTests {
    func testRenderReviewImages() throws {
        guard let directory = snapshotDirectory else { return }
        for dark in [false, true] {
            let tag = dark ? "dark" : "light"
            let mark = Self.stateAt("MRK", 4, 35)
            try Self.write(try Self.bitmap(ScripturePane().environmentObject(mark).background(STColor.paper), dark: dark,
                                           size: CGSize(width: 640, height: 880)), to: directory, name: "r3-mark4-\(tag)")
            let psalm = Self.stateAt("PSA", 3, 1)
            try Self.write(try Self.bitmap(ScripturePane().environmentObject(psalm).background(STColor.paper), dark: dark,
                                           size: CGSize(width: 640, height: 640)), to: directory, name: "r3-psalm3-\(tag)")
            let console = Self.stateAt("ROM", 8, 28)
            try Self.write(try Self.bitmap(MainView().environmentObject(console), dark: dark,
                                           size: CGSize(width: 980, height: 650)), to: directory, name: "r3-console-980-\(tag)")
            let genesis = Self.stateAt("GEN", 1, 1)
            try Self.write(try Self.bitmap(ScripturePane().environmentObject(genesis).background(STColor.paper), dark: dark,
                                           size: CGSize(width: 640, height: 880)), to: directory, name: "r3-genesis1-\(tag)")
        }
        // Type at its ends: 15pt/2pt and 28pt/16pt, plus KJV without headings.
        for (size, spacing) in [(15.0, 2.0), (28.0, 16.0)] {
            let state = Self.stateAt("MRK", 4, 35, size: size, spacing: spacing)
            try Self.write(try Self.bitmap(ScripturePane().environmentObject(state).background(STColor.paper), dark: false,
                                           size: CGSize(width: 640, height: 880)), to: directory, name: "r3-mark4-type\(Int(size))")
        }
        let off = Self.stateAt("MRK", 4, 35, headings: false)
        try Self.write(try Self.bitmap(ScripturePane().environmentObject(off).background(STColor.paper), dark: false,
                                       size: CGSize(width: 640, height: 880)), to: directory, name: "r3-mark4-headings-off")
        for (translation, code, chapter, name) in [("KJV", "ROM", 8, "kjv-romans8"), ("WEB", "GEN", 1, "web-genesis1"), ("BSB", "PSA", 1, "bsb-psalm1"), ("BSB", "ROM", 8, "bsb-romans8")] {
            let state = Self.stateAt(code, chapter, 1, translation: translation)
            try Self.write(try Self.bitmap(ScripturePane().environmentObject(state).background(STColor.paper), dark: false,
                                           size: CGSize(width: 640, height: 880)), to: directory, name: "r3-\(name)")
        }
        let kjv = Self.stateAt("JHN", 3, 16, translation: "KJV")
        try Self.write(try Self.bitmap(ScripturePane().environmentObject(kjv).background(STColor.paper), dark: false,
                                       size: CGSize(width: 640, height: 700)), to: directory, name: "r3-kjv-john3")
    }
}
