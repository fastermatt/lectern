import XCTest
import StudyTableCore
@testable import StudyTable

/// 0.10 (workstream R2): Calvin on the Psalms.
///
/// The Pillar/CrossWire Calvin conversion carries, for 148 of the 150 psalms, ONE text repeated in
/// every verse slot (the psalm's introduction + the comment on its first verse group), which the
/// desk showed under every verse. HelloAO's independent digitization of the same Calvin
/// Translation Society text has the real per-verse commentary. `build_calvin_psalms()` in
/// `scripts/build-study-resources.py` documents and applies the precedence rule these tests pin:
///   * Ps 55 and 120 (Pillar has genuine per-verse text) keep Pillar, no HelloAO;
///   * Ps 53 and 70 (Calvin wrote no separate commentary — HelloAO has only the quoted psalm) keep
///     Pillar's single block;
///   * every other psalm ships HelloAO per-verse entries, plus at most ONE Pillar entry: the
///     psalm's own introduction, anchored at verse 1 (HelloAO's digitization lacks it).
@MainActor
final class CalvinPsalmsTests: XCTestCase {
    private static let introWork = "Commentary (introduction to the psalm)"
    private static let pillarPerVerse: Set<Int> = [55, 120]
    private static let onlyABlock: Set<Int> = [53, 70]

    private func calvin(_ chapter: Int, source: String? = nil) -> [StudySource] {
        (Corpus.byBook["PSA"] ?? []).filter {
            $0.chapter == chapter && $0.author == "John Calvin" && (source == nil || $0.source == source)
        }
    }

    // MARK: the pastor's example

    /// Ps 22:16 is the "pierced" crux. The old block never mentioned it; the per-verse card must
    /// open with Calvin's own verse-16 heading and discuss the reading.
    func testPsalm22Verse16HasCalvinsOwnDiscussionOfPierced() throws {
        let cards = Corpus.store.sources(bookCode: "PSA", bookName: "Psalms", chapter: 22, verse: 16)
            .filter { $0.entry.author == "John Calvin" }
        XCTAssertEqual(cards.count, 1, "exactly one Calvin card at Ps 22:16: \(cards.map(\.id))")
        let entry = try XCTUnwrap(cards.first).entry
        XCTAssertEqual(entry.source, "calvin-helloao")
        XCTAssertEqual(entry.startVerse, 16)
        XCTAssertEqual(entry.endVerse, 16, "a per-verse card, not a run of verses")
        XCTAssertEqual(entry.rangeBasis, .stated)
        XCTAssertTrue(entry.excerpt.hasPrefix("16. They have pierced my hands and my feet."), String(entry.excerpt.prefix(80)))
        XCTAssertTrue(entry.excerpt.contains("like a lion"), "Calvin's discussion of the Hebrew reading")
        XCTAssertLessThan(entry.excerpt.split(separator: " ").count, 1200)
    }

    /// The whole-psalm introduction must not follow the reader through the psalm: at Ps 22:14 the
    /// Calvin card is the v.14 comment only.
    func testPsalmIntroductionIsNotRepeatedUnderEveryVerse() throws {
        for verse in [2, 8, 14, 22, 31] {
            let cards = Corpus.store.sources(bookCode: "PSA", bookName: "Psalms", chapter: 22, verse: verse)
                .filter { $0.entry.author == "John Calvin" }
            XCTAssertFalse(cards.isEmpty, "Ps 22:\(verse) lost its Calvin card")
            for card in cards {
                XCTAssertFalse(card.entry.excerpt.hasPrefix("PSALM 22."), "the introduction is shown at Ps 22:\(verse)")
                XCTAssertNotEqual(card.entry.work, Self.introWork)
            }
        }
        // ...and it is available, once, at verse 1, listed ahead of the verse-1 comment it introduces.
        let atOne = Corpus.store.sources(bookCode: "PSA", bookName: "Psalms", chapter: 22, verse: 1)
            .filter { $0.entry.author == "John Calvin" }
        XCTAssertEqual(atOne.count, 2, "introduction + v.1 comment")
        let intro = try XCTUnwrap(atOne.first).entry
        XCTAssertEqual(intro.work, Self.introWork)
        XCTAssertEqual(intro.source, "calvin")
        XCTAssertEqual(intro.rangeBasis, .anchored)
        XCTAssertTrue(intro.excerpt.hasPrefix("PSALM 22. David complains in this psalm"))
        XCTAssertEqual(atOne.last?.entry.source, "calvin-helloao")
    }

    // MARK: the precedence rule, chapter by chapter

    func testPrecedenceRuleHoldsForEveryPsalm() {
        for chapter in 1...150 {
            let entries = calvin(chapter)
            XCTAssertFalse(entries.isEmpty, "Psalm \(chapter) has no Calvin at all (Reformed coverage regression)")
            let helloao = calvin(chapter, source: "calvin-helloao")
            let pillar = calvin(chapter, source: "calvin")
            if Self.pillarPerVerse.contains(chapter) {
                XCTAssertTrue(helloao.isEmpty, "Ps \(chapter) has real per-verse Pillar text and must not also ship HelloAO")
                XCTAssertGreaterThan(pillar.count, 1)
            } else if Self.onlyABlock.contains(chapter) {
                XCTAssertTrue(helloao.isEmpty, "Ps \(chapter): HelloAO has no commentary text, the Pillar block stays")
                XCTAssertEqual(pillar.count, 1)
                XCTAssertEqual(pillar.first?.rangeBasis, .block)
            } else {
                XCTAssertFalse(helloao.isEmpty, "Ps \(chapter) should ship HelloAO per-verse commentary")
                XCTAssertLessThanOrEqual(pillar.count, 1, "Ps \(chapter): Pillar may contribute only the introduction")
                for entry in pillar {
                    XCTAssertEqual(entry.work, Self.introWork, entry.id)
                    XCTAssertEqual(entry.startVerse, 1, entry.id)
                    XCTAssertEqual(entry.endVerse, 1, entry.id)
                    XCTAssertEqual(entry.rangeBasis, .anchored, entry.id)
                }
                // HelloAO entries never overlap one another (one card per verse, per source).
                let spans = helloao.map { ($0.startVerse, $0.endVerse) }.sorted { $0.0 < $1.0 }
                for (a, b) in zip(spans, spans.dropFirst()) {
                    XCTAssertLessThan(a.1, b.0, "Ps \(chapter): overlapping Calvin entries \(a) and \(b)")
                }
                // Nothing in the block-repeat style survives: no entry spans more than a few verses
                // (Ps 108 is one single 13-verse group in Calvin's own layout).
                for entry in helloao where chapter != 108 {
                    XCTAssertLessThanOrEqual(entry.spanCount, 7, "\(entry.id) spans \(entry.spanCount) verses")
                }
            }
        }
    }

    /// The honest list of what is still ONE card for the whole psalm, pinned so a regression (or a
    /// future improvement) is a deliberate change. Four short psalms: 53 and 70 (Calvin wrote no
    /// separate commentary — he refers the reader to Psalms 14 and 40; HelloAO has only the quoted
    /// psalm, so the Pillar block stays) and 108 and 117 (Calvin's own layout is one passage-level
    /// comment on the whole psalm; it ships from HelloAO as a single card, which IS his commentary).
    func testOnlyFourShortPsalmsRemainSingleWholePsalmCards() {
        let wholePsalm = (1...150).filter { chapter in
            let entries = calvin(chapter)
            return entries.count == 1 && entries[0].rangeBasis == .block
        }
        XCTAssertEqual(wholePsalm, [53, 70, 108, 117])
        XCTAssertEqual([53, 70].map { calvin($0).first?.source }, ["calvin", "calvin"])
        XCTAssertEqual([108, 117].map { calvin($0).first?.source }, ["calvin-helloao", "calvin-helloao"])
        // Psalms 53 / 70: Calvin's own text refers the reader to Psalms 14 / 40.
        XCTAssertTrue(calvin(53).first?.excerpt.contains("almost identical with the fourteenth") ?? false)
        XCTAssertTrue(calvin(70).first?.excerpt.contains("merely a part of the fortieth") ?? false)
    }

    // MARK: apparatus, verse anchoring, re-homed group

    /// The translator's editorial footnotes (partly French) and their inline "[n]" markers are not
    /// shipped — neither for the Psalms nor, since this pass, for the Isaiah 49-66 gap-fill.
    func testNoFootnoteApparatusLeaksIntoCalvinHelloAOEntries() throws {
        let marker = try NSRegularExpression(pattern: #"\[\d{1,4}\]"#)
        var checked = 0
        for entry in Corpus.all where entry.source == "calvin-helloao" {
            checked += 1
            XCTAssertFalse(entry.excerpt.contains("Footnotes:"), entry.id)
            XCTAssertEqual(marker.numberOfMatches(in: entry.excerpt, range: NSRange(entry.excerpt.startIndex..., in: entry.excerpt)), 0,
                           "dangling footnote marker in \(entry.id)")
            XCTAssertFalse(entry.excerpt.contains("-- Fr."), "French translator's note leaked into \(entry.id)")
        }
        XCTAssertGreaterThan(checked, 1500, "expected the Psalms and Isaiah 49-66 entries")
        // The Isaiah 49-66 gap-fill itself is unchanged in scope (still every chapter, still one source).
        for chapter in 49...66 {
            XCTAssertTrue((Corpus.byBook["ISA"] ?? []).contains { $0.chapter == chapter && $0.source == "calvin-helloao" })
        }
    }

    /// Every per-verse card opens with the verse number Calvin's own text opened it with, and that
    /// number is the card's start verse (no card is filed under the wrong verse).
    func testNumberedPsalmCardsStartAtTheirOwnVerse() throws {
        let lead = try NSRegularExpression(pattern: #"^(\d{1,3})\.?\s"#)
        var numbered = 0
        for entry in Corpus.byBook["PSA"] ?? [] where entry.source == "calvin-helloao" {
            let range = NSRange(entry.excerpt.startIndex..., in: entry.excerpt)
            guard let match = lead.firstMatch(in: entry.excerpt, range: range),
                  let numberRange = Range(match.range(at: 1), in: entry.excerpt),
                  let number = Int(entry.excerpt[numberRange]) else { continue }  // an unnumbered group comment
            numbered += 1
            XCTAssertEqual(number, entry.startVerse, "\(entry.id) starts \"\(entry.excerpt.prefix(30))\"")
        }
        XCTAssertGreaterThan(numbered, 1400)
    }

    /// HelloAO files the group for Ps 104:19-22 inside Psalm 102's own item (header mislabelled);
    /// the build re-homes it (text untouched) so Ps 104 does not lose its commentary on the moon
    /// that marks the seasons and the lions that roar after their prey.
    func testPsalm104MoonAndLionsGroupIsRehomedFromPsalm102() throws {
        let entry = try XCTUnwrap(calvin(104, source: "calvin-helloao").first { $0.startVerse == 19 })
        XCTAssertTrue(entry.excerpt.hasPrefix("19. He hath appointed the moon to distinguish seasons"))
        XCTAssertTrue(calvin(104, source: "calvin-helloao").contains { $0.startVerse == 21 && $0.excerpt.contains("lions") })
        XCTAssertFalse(calvin(102).contains { $0.excerpt.contains("He hath appointed the moon") },
                       "the group must live under Psalm 104 only, never duplicated in Psalm 102")
    }

    // MARK: the build report backs the numbers

    func testBuildReportRecordsTheVerifiedPrecedenceOutcome() throws {
        let url = TestPaths.root.appendingPathComponent("data/study-build-report.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let report = try XCTUnwrap(object?["calvinPsalms"] as? [String: Any])
        XCTAssertEqual(report["chaptersImprovedCount"] as? Int, 146)
        XCTAssertEqual(report["chaptersKeptPillarPerVerse"] as? [Int], [55, 120])
        XCTAssertEqual((report["chaptersFallbackToPillarBlock"] as? [String: String])?.keys.sorted(), ["53", "70"])
        // The same-translation gate: every improved chapter shares >= 90% of its Pillar text (as
        // 6-word shingles) with the HelloAO chapter; measured minimum and median are recorded.
        let minimum = try XCTUnwrap(report["sameTranslationCoverageMin"] as? Double)
        XCTAssertGreaterThanOrEqual(minimum, 0.90)
        XCTAssertEqual(report["sameTranslationCoverageMedian"] as? Double, 1.0)
        XCTAssertLessThan(try XCTUnwrap(report["introDuplicateShareMax"] as? Double), 0.5,
                          "an introduction that HelloAO also carries must be dropped, not shipped twice")
        XCTAssertEqual(report["helloaoEntries"] as? Int, (Corpus.byBook["PSA"] ?? []).filter { $0.source == "calvin-helloao" }.count)
    }
}
