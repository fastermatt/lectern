import XCTest
import StudyTableCore
@testable import StudyTable

/// Guards the generated study indexes: deterministic IDs, verse-range accuracy, duplicate
/// handling, source provenance and honest review status.
@MainActor
final class ContentIntegrityTests: XCTestCase {
    func testAllSixtySixIndexesLoadAsSchemaTwoWithoutDefects() {
        XCTAssertEqual(Corpus.byBook.count, 66)
        for code in Canon.bookCodes {
            XCTAssertFalse(Corpus.byBook[code]?.isEmpty ?? true, "\(code) has no entries")
        }
        XCTAssertTrue(Corpus.store.diagnostics.isEmpty, "loader diagnostics: \(Corpus.store.diagnostics)")
    }

    func testEntryIDsAreUniqueStableAndConsistentWithTheirRange() throws {
        let pattern = try NSRegularExpression(pattern: #"^([0-9A-Z]{3})\.(\d+)\.(\d+)-(\d+)\.(matthew-henry|calvin|calvin-helloao|hcf|tsk|john-gill|keil-delitzsch|jamieson-fausset-brown|mhcc)\.[0-9a-f]{8}$"#)
        var seen = Set<String>()
        for (code, entries) in Corpus.byBook {
            for entry in entries {
                XCTAssertTrue(seen.insert(entry.id).inserted, "duplicate ID \(entry.id)")
                let range = NSRange(entry.id.startIndex..., in: entry.id)
                guard let match = pattern.firstMatch(in: entry.id, range: range) else {
                    XCTFail("malformed ID \(entry.id)"); continue
                }
                func part(_ i: Int) -> String { String(entry.id[Range(match.range(at: i), in: entry.id)!]) }
                XCTAssertEqual(part(1), code)
                XCTAssertEqual(Int(part(2)), entry.chapter)
                XCTAssertEqual(Int(part(3)), entry.startVerse)
                XCTAssertEqual(Int(part(4)), entry.endVerse)
                XCTAssertEqual(part(5), entry.source)
            }
        }
    }

    func testVerseRangesAreAccurateForEverySource() {
        for entry in Corpus.all {
            XCTAssertGreaterThanOrEqual(entry.startVerse, 1, entry.id)
            XCTAssertGreaterThanOrEqual(entry.endVerse, entry.startVerse, entry.id)
            switch entry.tradition {
            case .crossReferences: XCTAssertEqual(entry.spanCount, 1, "cross-reference lists are per verse: \(entry.id)")
            case .fathers: XCTAssertLessThanOrEqual(entry.spanCount, 30, entry.id)
            case .reformed, .exegetes: break
            }
            if entry.rangeBasis == .block { XCTAssertGreaterThan(entry.spanCount, 1, "a block spans a run of verses: \(entry.id)") }
            if entry.rangeBasis == .anchored { XCTAssertEqual(entry.spanCount, 1, "anchored entries claim only their slot: \(entry.id)") }
        }
    }

    func testEveryEntryIsWithinItsBooksRealVersesWhereCommentaryIsVerseBound() {
        let library = ScriptureLibrary()
        for code in ["ROM", "JHN", "PSA", "GEN", "REV"] {
            guard let book = library.summary(code: code) else { return XCTFail("missing \(code)") }
            for entry in Corpus.byBook[code] ?? [] where entry.tradition == .fathers || entry.tradition == .crossReferences {
                let count = book.verseCount(chapter: entry.chapter)
                XCTAssertGreaterThan(count, 0, "\(entry.id) points at a chapter that does not exist")
                XCTAssertLessThanOrEqual(entry.startVerse, count + 1, "\(entry.id) starts past the chapter end (\(count))")
            }
        }
    }

    func testResolvedSourcesCoverExactlyTheirStatedRange() {
        // Matthew Henry Complete's Romans 8:29-30 section ("the order of the causes of our
        // salvation, a golden chain") must appear for 29...30 and nowhere else.
        let section = (Corpus.byBook["ROM"] ?? []).first { $0.source == "matthew-henry" && $0.chapter == 8 && $0.startVerse == 29 }
        guard let section else { return XCTFail("expected a Matthew Henry section starting at Romans 8:29") }
        XCTAssertEqual(section.endVerse, 30)
        for verse in 26...33 {
            let ids = Corpus.store.sources(bookCode: "ROM", bookName: "Romans", chapter: 8, verse: verse).map(\.id)
            XCTAssertEqual(ids.contains(section.id), (29...30).contains(verse), "verse \(verse)")
        }
    }

    func testEveryEntryHasCompleteProvenance() throws {
        let registry = Corpus.store.registry
        var expected: Set<String> = ["matthew-henry", "calvin", "calvin-helloao", "tsk", "john-gill", "keil-delitzsch", "jamieson-fausset-brown", "mhcc"]
        if !TestPaths.isPublicSource { expected.insert("hcf") }
        XCTAssertEqual(Set(registry.keys), expected)
        for record in registry.values {
            XCTAssertEqual(record.url.scheme, "https")
            XCTAssertFalse(record.title.isEmpty); XCTAssertFalse(record.license.isEmpty)
            XCTAssertFalse(record.publisher.isEmpty); XCTAssertFalse(record.review.note.isEmpty)
        }
        for entry in Corpus.all {
            XCTAssertNotNil(registry[entry.source], "\(entry.id) names an unregistered source")
            if let url = entry.sourceURL { XCTAssertTrue(["http", "https"].contains(url.scheme ?? ""), entry.id) }
            XCTAssertFalse(entry.author.isEmpty); XCTAssertFalse(entry.work.isEmpty)
            XCTAssertGreaterThanOrEqual(entry.excerpt.count, 5, entry.id)   // a lone reference such as "Matt 15:39" is legitimate
        }
        // The 9,000+ Fathers rows with no per-record URL (workstream M's 0.9.5 audit corrected an
        // earlier "23" figure, which was a QA spot-check sample size, not the true population —
        // see CONTENT-ROADMAP.md) still resolve to the dataset URL, but must say so honestly
        // rather than read the same as a verified work-specific citation (`ProvenanceScope`,
        // `Models.swift`).
        if TestPaths.isPublicSource {
            XCTAssertFalse(Corpus.all.contains { $0.source == "hcf" })
            return
        }
        let uncited = Corpus.all.first { $0.tradition == .fathers && $0.sourceURL == nil }
        XCTAssertNotNil(uncited)
        let resolved = Corpus.store.sources(bookCode: uncited!.id.prefix(3).description, bookName: "x",
                                            chapter: uncited!.chapter, verse: uncited!.startVerse)
            .first { $0.id == uncited!.id }
        XCTAssertNotNil(resolved?.provenanceURL)
        XCTAssertEqual(resolved?.provenanceScope, .sourceDatabaseOnly)

        // A per-row citation (e.g. Theodoret of Cyrus's Romans commentary, M's fix) must read as
        // the more precise scope, not be flattened to the same "database only" label.
        let cited = try XCTUnwrap(Corpus.all.first { $0.author == "Theodoret of Cyrus" && $0.sourceURL != nil })
        let citedResolved = Corpus.store.sources(bookCode: cited.id.prefix(3).description, bookName: "x",
                                                 chapter: cited.chapter, verse: cited.startVerse)
            .first { $0.id == cited.id }
        XCTAssertEqual(citedResolved?.provenanceScope, .specificWork)
    }

    func testReviewStatusIsHonest() {
        let registry = Corpus.store.registry
        if TestPaths.isPublicSource { XCTAssertNil(registry["hcf"]) }
        else { XCTAssertEqual(registry["hcf"]?.review.state, .automatedFilter) }
        XCTAssertEqual(registry["matthew-henry"]?.review.state, .sourceAttributed)
        XCTAssertEqual(registry["john-gill"]?.review.state, .sourceAttributed)
        XCTAssertEqual(registry["calvin"]?.review.state, .sourceAttributed)
        XCTAssertEqual(registry["calvin-helloao"]?.review.state, .sourceAttributed)
        XCTAssertEqual(registry["tsk"]?.review.state, .datasetSupplied)
        XCTAssertEqual(registry["keil-delitzsch"]?.review.state, .sourceAttributed)
        XCTAssertEqual(registry["jamieson-fausset-brown"]?.review.state, .sourceAttributed)
        XCTAssertEqual(registry["mhcc"]?.review.state, .sourceAttributed)
        for record in registry.values {
            let note = record.review.note.lowercased()
            XCTAssertFalse(note.contains("approved") || note.contains("theologically reviewed by"), "review note overclaims")
        }
        // The old model labeled every Reformed and canonical entry "aligned". No class may imply WCF agreement.
        let labels = [SourceClass.receivedFather, .reformedSource, .canonicalIndex, .contrastView].map(\.label)
        XCTAssertFalse(labels.contains { $0.localizedCaseInsensitiveContains("aligned") || $0.contains("WCF") })
    }

    func testCalvinBlocksAreFreeOfNeighbouringBookAndChapterMatter() throws {
        let contamination = try NSRegularExpression(pattern:
            #"END OF (THE )?[A-Z]{4}|COMMENTAR(Y|IES) ON THE [A-Z]|THE ARGUMENT\b|PRELECTIONS OF JOHN CALVIN|CHRISTIAN CLASSICS ETHEREAL|TRANSLATOR’S PREFACE|CHAPTER \d+\s+([1-3]\s+)?[A-Z][A-Za-z ]+ \d+:\d+"#)
        for entry in Corpus.all where entry.author == "John Calvin" {
            let range = NSRange(entry.excerpt.startIndex..., in: entry.excerpt)
            XCTAssertNil(contamination.firstMatch(in: entry.excerpt, range: range), "front/back matter in \(entry.id)")
        }
    }

    func testCalvinWholeChapterBlocksAreNotRepeatedIntoEveryVerse() {
        for (code, entries) in Corpus.byBook {
            var seen: [String: String] = [:]
            for entry in entries where entry.author == "John Calvin" {
                let key = "\(entry.chapter)|\(entry.excerpt)"
                if let previous = seen[key] { XCTFail("\(code): identical Calvin text in \(previous) and \(entry.id)") }
                seen[key] = entry.id
            }
        }
        // 1 Timothy 3 used to repeat one whole-chapter block in every verse slot. Scoped to
        // Calvin specifically (not just rangeBasis == .block): Matthew Henry Complete's own
        // discourse groupings legitimately also produce multi-verse block entries now (3 of
        // them in this same chapter, verified directly), which is correct, not a regression of
        // the bug this test guards against.
        let blocks = (Corpus.byBook["1TI"] ?? []).filter { $0.rangeBasis == .block && $0.chapter == 3 && $0.source == "calvin" }
        XCTAssertEqual(blocks.count, 1)
        XCTAssertGreaterThan(blocks.first?.spanCount ?? 0, 10)
    }

    /// 0.8 (workstream I): the Fathers bank moved from a small curated name list to a rule-based
    /// admission (every patristic-era author in the source database's four patristic categories,
    /// through c. AD 800, except council-condemned figures) — see `_father_admission` in
    /// `build-study-resources.py`. This test no longer pins an exact name-for-name allowlist
    /// (that would just re-hardcode the old whitelist one layer up), but it does pin the
    /// non-negotiables: the always-excluded categories never appear, the explicit
    /// council-condemned bucket is exactly right (this list *is* worth hardcoding — a silent
    /// change here is exactly the failure mode a confessional app cannot afford), Origen and
    /// Tertullian and the other newly-broadened names the 0.8 brief specifically called out are
    /// genuinely default-visible now, and every tier still carries the right class/disclaimer.
    func testFathersExtractRespectsThePatristicEraAdmissionRule() throws {
        try XCTSkipIf(TestPaths.isPublicSource, "HCF excerpt audit requires the withheld developer corpus; public reader/profile tests still run.")
        // Never allowed at any tier: medieval scholastics and modern authors the source database
        // also carries under one of the four patristic categories, correctly excluded by the
        // through-c.-AD-800 cutoff, not by a hand-maintained exclusion list.
        let neverAllowed: Set<String> = ["Thomas Aquinas", "Bonaventure", "Bernard of Clairvaux", "CS Lewis", "GK Chesterton"]
        // The council-condemned bucket, hardcoded deliberately (unlike the default bank): exactly
        // these nine names, each backed by a real conciliar/synodal citation in
        // fathers-profiles.json (see FatherProfileTests for the citation checks). A change here
        // must be a deliberate, reviewed edit to `_father_admission`/`CONDEMNED_OVERRIDE_ADD`,
        // never a silent database-driven drift.
        let tier3Expected: Set<String> = [
            "Heracleon", "Valentinus", "Novatian", "Arius", "Apollinaris of Laodicea",
            "Tatian the Assyrian", "Pelagius", "Theodore of Mopsuestia", "Julian of Eclanum",
        ]
        // Explicitly named in WORKPLAN-0.8.md as moving into the default bank, plus two judgment
        // calls workstream I made and documented in fathers-profiles.source.json (Theodoret of
        // Cyrus and Gregory the Dialogist/Gregory the Great: only specific writings, not the
        // person, were ever subject to conciliar action, so both stay Tier 2 by the same
        // reasoning Origen does) — a regression here would silently re-narrow the bank.
        let mustBeTier2Fathers: Set<String> = [
            "Origen of Alexandria", "Tertullian", "Clement of Alexandria", "Eusebius of Caesarea",
            "Theodoret of Cyrus", "Gregory the Dialogist",
        ]
        var seenTier2: Set<String> = []
        var seenTier3: Set<String> = []
        for entry in Corpus.all where entry.tradition == .fathers {
            XCTAssertFalse(neverAllowed.contains(entry.author), "\(entry.author) is medieval/modern and must not reappear in the patristic bank")
            switch entry.tier {
            case .tier2HistoricWitness:
                seenTier2.insert(entry.author)
                XCTAssertFalse(tier3Expected.contains(entry.author), "\(entry.author) is council-condemned and must never appear as a Tier 2 received Father")
                XCTAssertEqual(entry.sourceClass, .receivedFather)
                XCTAssertEqual(entry.tier.disclaimer, "Historic Christian witness — not uniformly confessional Reformed.")
            case .tier3ResearchOnly:
                seenTier3.insert(entry.author)
                XCTAssertTrue(tier3Expected.contains(entry.author), "\(entry.author) appears Tier 3 but is not in the expected council-condemned bucket")
                XCTAssertEqual(entry.sourceClass, .researchOnly, "a Tier 3 card must never claim to be a received Father")
            case .tier1Confessional:
                XCTFail("\(entry.author) is filed under Fathers but tagged Tier 1 — patristic authors are never Tier 1")
            }
        }
        // Arius is architecturally admitted to the condemned bucket and profiled (see
        // FatherProfileTests), but produces zero surviving cards in this app's 66-book canon:
        // his only database row cites 2 Maccabees, dropped by the existing "book not in canon"
        // check. That is a real, checked finding, not a bug — see workstream I's final report.
        XCTAssertEqual(seenTier3, tier3Expected.subtracting(["Arius"]),
                       "every council-condemned author except Arius (no in-canon row) should appear at least once, and no unexpected one should")
        for name in mustBeTier2Fathers {
            XCTAssertTrue(seenTier2.contains(name), "\(name) should be default-visible (Tier 2) per the 0.8 broadened admission rule")
        }
        // The bank genuinely broadened, not just re-shuffled: 0.7 shipped 21 curated names.
        XCTAssertGreaterThan(seenTier2.count, 100, "the rule-based admission should yield well over 100 distinct default-bank Fathers authors")
    }

    func testLoaderDropsDuplicateIDsAndRejectsUnsupportedSchemas() throws {
        // Resources/Study/<CODE>/<CHAPTER>.json, per-chapter, since 0.7 (see StudyResourceStore).
        let directory = temporaryDirectory("study")
        let romDir = directory.appendingPathComponent("ROM")
        let jhnDir = directory.appendingPathComponent("JHN")
        try FileManager.default.createDirectory(at: romDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: jhnDir, withIntermediateDirectories: true)
        let entry = #"{"id":"ROM.1.1-1.matthew-henry.aaaaaaaa","chapter":1,"startVerse":1,"endVerse":1,"rangeBasis":"stated","author":"A","work":"W","era":"e","tradition":"Reformed","source":"matthew-henry","excerpt":"Some source text here.","isExactQuote":true,"crossRefs":[],"tier":"tier1","contentKind":"verse-commentary"}"#
        try #"{"schema":3,"code":"ROM","book":"Romans","chapter":1,"entries":[\#(entry),\#(entry)]}"#.write(to: romDir.appendingPathComponent("1.json"), atomically: true, encoding: .utf8)
        try #"{"schema":1,"code":"JHN","book":"John","chapter":1,"entries":[]}"#.write(to: jhnDir.appendingPathComponent("1.json"), atomically: true, encoding: .utf8)
        let store = StudyResourceStore(studyDirectory: directory)
        XCTAssertEqual(store.sources(bookCode: "ROM", bookName: "Romans", chapter: 1, verse: 1).count, 1)
        XCTAssertNil(store.load(bookCode: "JHN"))
        XCTAssertTrue(store.diagnostics.contains { $0.contains("duplicate") })
        XCTAssertTrue(store.diagnostics.contains { $0.contains("unsupported schema") })
    }

    func testRangeLabelsStateWhatIsKnown() {
        func make(_ start: Int, _ end: Int, _ basis: RangeBasis) -> StudySource {
            StudySource(id: "x", chapter: 1, startVerse: start, endVerse: end, rangeBasis: basis, author: "a", work: "w",
                        era: "e", tradition: .reformed, source: "mhcc", excerpt: "e", sourceURL: nil, isExactQuote: true, truncated: nil)
        }
        XCTAssertEqual(make(3, 3, .stated).rangeLabel(bookName: "John"), "John 1:3")
        XCTAssertEqual(make(1, 5, .stated).rangeLabel(bookName: "John"), "John 1:1–5")
        XCTAssertEqual(make(2, 2, .anchored).rangeBasis.caption, "Attached to this verse; extent not stated")
    }

    /// Every entry's excerpt must be clean prose: no leaked source markup. A full-corpus scan
    /// while adding Gill/Henry (2026-09-22) found several pre-existing defects this guards
    /// against regressing (a literal `{see Hebrews 5:4}` aside in Calvin normalized to
    /// parentheses, 21 Fathers rows with stray literal backslash escapes unescaped/stripped, one
    /// John Gill entry with a literal `\@@...\@@` emphasis-marker leak stripped).
    func testNoEntryLeaksSourceMarkupCharacters() {
        for entry in Corpus.all {
            for character in ["<", "{", "\\"] as [Character] {
                XCTAssertFalse(entry.excerpt.contains(character), "\(entry.id) leaks '\(character)' into its excerpt")
            }
        }
    }
}

/// Cross-reference chips: every entry must resolve to a real place in the canon, since a bad
/// chip would silently mis-navigate the reader.
extension ContentIntegrityTests {
    func testCrossReferenceLinksPointAtRealBooksAndAreLabeled() {
        let library = ScriptureLibrary()
        var checked = 0
        for entry in Corpus.all where entry.tradition == .crossReferences {
            for ref in entry.crossRefs {
                checked += 1
                XCTAssertNotNil(Canon.order[ref.code], "\(entry.id): unknown book code \(ref.code)")
                XCTAssertGreaterThanOrEqual(ref.start, 1, ref.label)
                XCTAssertGreaterThanOrEqual(ref.end, ref.start, ref.label)
                XCTAssertFalse(ref.label.isEmpty)
                if let book = library.summary(code: ref.code) {
                    XCTAssertLessThanOrEqual(ref.chapter, book.chapterCount, "\(ref.label) chapter out of range for \(ref.code)")
                }
            }
        }
        XCTAssertGreaterThan(checked, 25_000, "structured cross-references should cover almost every TSK entry")
    }

    func testCrossReferenceParsingHandlesCommaAndRangeTokensDifferently() {
        // Genesis 1:1's TSK links include "Ps 33:6,9" (two non-contiguous verses in one token,
        // so two separate links) and "Ps 89:11-12" (one contiguous range, so one link).
        guard let entry = (Corpus.byBook["GEN"] ?? []).first(where: { $0.tradition == .crossReferences && $0.chapter == 1 && $0.startVerse == 1 }) else {
            return XCTFail("expected Genesis 1:1 cross-references")
        }
        let psalm33 = entry.crossRefs.filter { $0.code == "PSA" && $0.chapter == 33 }
        XCTAssertEqual(Set(psalm33.map { "\($0.start)-\($0.end)" }), ["6-6", "9-9"], "a comma token is two exact-verse links, not a range")
        let psalm89 = entry.crossRefs.filter { $0.code == "PSA" && $0.chapter == 89 }
        XCTAssertEqual(psalm89.map { "\($0.start)-\($0.end)" }, ["11-12"], "a hyphen token stays one range link")
        XCTAssertTrue(entry.crossRefs.allSatisfy { !$0.label.isEmpty })
    }

    func testSemicolonJoinedCrossChapterTokensProduceOneLinkPerChapter() throws {
        // Revelation 13's TSK data has "Rev 12:17; Rev 13:1,3"-style tokens spanning two
        // chapters, which required a build-script fix (see data/study-build-report.json history).
        let candidates = (Corpus.byBook["REV"] ?? []).filter { $0.tradition == .crossReferences && $0.crossRefs.contains { $0.chapter == 12 } && $0.crossRefs.contains { $0.chapter == 13 } }
        XCTAssertFalse(candidates.isEmpty, "expected at least one Revelation entry spanning chapters 12 and 13")
    }

    func testOnlyCrossReferencesCarryCrossRefLinks() {
        for entry in Corpus.all where entry.tradition != .crossReferences {
            XCTAssertTrue(entry.crossRefs.isEmpty, "\(entry.id) is not a cross-reference but carries crossRefs")
        }
    }
}

/// Matthew Henry's Concise Commentary used to need two different heading-layout branches parsed
/// from raw text; that parser was retired with the Concise itself (see build-study-resources.py's
/// "Matthew Henry (retired 2026-09-22)" section) in favor of the unabridged Complete Commentary
/// via HelloAO, which has no such heading-layout ambiguity to guard against. The regression it
/// guarded against no longer applies to the current pipeline; the tests below guard the new one.
extension ContentIntegrityTests {
    func testEcclesiastesAndSongOfSolomonHaveReformedCommentaryOnChapterOne() {
        for code in ["ECC", "SNG"] {
            XCTAssertFalse((Corpus.byBook[code] ?? []).filter { $0.tradition == .reformed && $0.chapter == 1 }.isEmpty, code)
        }
    }

    func testOverallReformedChapterCoverageMeetsAFloor() throws {
        // Guards against silent regression: fewer than 90% of the canon's chapters having at
        // least one Reformed entry would mean a parser or data regression, not a source gap.
        // Adding Gill and Matthew Henry Complete (2026-09-22) first brought measured coverage
        // from 94.7% (63 zero-coverage chapters) to 100%. E1 (2026-09-23) then moved Gill out of
        // the Reformed bank into the new Tier-2 Exegetes bank ("REFORMED" now means Tier 1
        // only), which would have reopened every chapter only Gill covered -- E3's mhcc gap-fill
        // (Matthew Henry's Concise Commentary, restored *only* for the exact chapters the
        // unabridged Complete leaves empty) closes those back to 100% via Calvin and/or Henry
        // alone. See testExegetesBankIsAlwaysTierTwoAndEveryCardNamesItsAuthorsTradition and
        // testMHCCGapFillNeverOverlapsTheCompleteCommentary for the mechanics. The floor stays
        // below the measured value rather than pinned to it, so a future source change that
        // removes a few chapters' worth of coverage fails loudly without requiring every single
        // chapter to stay covered forever.
        let library = ScriptureLibrary()
        var totalChapters = 0, coveredChapters = 0
        for book in library.books {
            for chapter in 1...book.chapterCount {
                totalChapters += 1
                if (Corpus.byBook[book.code] ?? []).contains(where: { $0.tradition == .reformed && $0.chapter == chapter }) {
                    coveredChapters += 1
                }
            }
        }
        let coverage = Double(coveredChapters) / Double(totalChapters)
        XCTAssertGreaterThan(coverage, 0.98, "Reformed chapter coverage dropped to \(Int(coverage * 100))%")
    }

    /// Gill (66 books) and Matthew Henry Complete (65 -- no Song of Solomon, see SOURCES) must
    /// each cover at least 95% of the chapters within the books they actually claim to cover, not
    /// the whole 1,189-chapter canon (Henry's absence from Song of Solomon is a documented,
    /// verified source limitation, not a coverage failure of the books he does cover).
    func testGillAndHenryCompleteCoverAtLeastNinetyFivePercentOfTheChaptersTheyClaim() {
        let library = ScriptureLibrary()
        func coverage(of source: String, excluding: Set<String> = []) -> (covered: Int, total: Int) {
            var covered = 0, total = 0
            for book in library.books where !excluding.contains(book.code) {
                for chapter in 1...book.chapterCount {
                    total += 1
                    if (Corpus.byBook[book.code] ?? []).contains(where: { $0.source == source && $0.chapter == chapter }) {
                        covered += 1
                    }
                }
            }
            return (covered, total)
        }
        let gill = coverage(of: "john-gill")
        XCTAssertGreaterThan(Double(gill.covered) / Double(gill.total), 0.95,
                             "John Gill covers only \(gill.covered)/\(gill.total) chapters")
        let henry = coverage(of: "matthew-henry", excluding: ["SNG"])
        XCTAssertGreaterThan(Double(henry.covered) / Double(henry.total), 0.95,
                             "Matthew Henry Complete covers only \(henry.covered)/\(henry.total) claimed chapters")
    }

    /// John 3:16 must carry all three of Calvin, Matthew Henry Complete and John Gill -- the
    /// most-quoted verse in the Bible is a natural, high-visibility check that the Reformed bank
    /// is actually deep, not just wide.
    func testJohn316HasCalvinHenryAndGill() {
        let sources = Set((Corpus.byBook["JHN"] ?? [])
            .filter { $0.chapter == 3 && $0.covers(verse: 16) }
            .map(\.source))
        XCTAssertTrue(sources.isSuperset(of: ["calvin", "matthew-henry", "john-gill"]),
                      "John 3:16 sources: \(sources)")
    }

    /// New 2026-09-24 (workstream M, 0.9.5): Isaiah 49-66 -- the whole Book of Consolation,
    /// including the Servant Songs and Isaiah 53 -- used to have zero Calvin commentary because
    /// the cached Pillar conversion is genuinely empty for these 18 chapters upstream. A gap-fill
    /// from HelloAO's independent digitization of the same commentary (source id
    /// "calvin-helloao") now covers every one of them. This is a direct regression guard: if the
    /// gap-fill source ever goes missing or is emitted for the wrong chapters, this fails loudly
    /// instead of silently reopening the gap the pastor-QA and Matt both specifically asked about.
    func testIsaiah49Through66HaveCalvinCommentaryViaTheGapFillSource() {
        let isaiah = Corpus.byBook["ISA"] ?? []
        for chapter in 49...66 {
            let hasCalvin = isaiah.contains {
                $0.chapter == chapter && $0.author == "John Calvin" && $0.source == "calvin-helloao"
            }
            XCTAssertTrue(hasCalvin, "Isaiah \(chapter) has no Calvin commentary (gap-fill regression)")
        }
        // Isaiah 53 specifically, the passage Matt and the pastor-QA both named directly.
        let isaiah53 = isaiah.filter { $0.chapter == 53 && $0.author == "John Calvin" }
        XCTAssertFalse(isaiah53.isEmpty, "Isaiah 53 has no Calvin commentary")
        for entry in isaiah53 {
            XCTAssertEqual(entry.source, "calvin-helloao")
            XCTAssertGreaterThanOrEqual(entry.excerpt.count, 20)
        }
        // The gap-fill must never duplicate the primary source: no chapter should carry both
        // "calvin" and "calvin-helloao" (1-48 keep the primary source; 49-66 use the gap-fill;
        // never both for the same chapter).
        for chapter in 1...66 {
            let sourcesInChapter = Set(isaiah.filter { $0.chapter == chapter && $0.author == "John Calvin" }.map(\.source))
            XCTAssertLessThanOrEqual(sourcesInChapter.count, 1,
                                      "Isaiah \(chapter) has Calvin from more than one source: \(sourcesInChapter)")
        }
    }

    /// New 2026-09-24 (workstream M, 0.9.5): FATHERS_SOURCE_URL_OVERRIDES in
    /// build-study-resources.py gives Theodoret of Cyrus's Romans commentary rows a real,
    /// hand-verified, work-specific URL instead of falling back to the generic whole-repository
    /// link (Models.swift's `entry.sourceURL ?? record?.url`). This is a small, honest fix for
    /// one of the thousands of no-URL Fathers rows found in this pass -- see
    /// CONTENT-ROADMAP.md for why the rest are not hand-curated.
    func testTheodoretOfCyrusRomansHasAWorkSpecificSourceURL() throws {
        try XCTSkipIf(TestPaths.isPublicSource, "HCF excerpt audit requires the withheld developer corpus; public reader/profile tests still run.")
        let entries = (Corpus.byBook["ROM"] ?? []).filter { $0.author == "Theodoret of Cyrus" }
        XCTAssertFalse(entries.isEmpty, "expected at least one Theodoret of Cyrus entry in Romans")
        for entry in entries {
            XCTAssertEqual(entry.sourceURL?.host, "www.tertullian.org", "\(entry.id) should link to the specific work, not the generic HCF repository")
        }
    }

    /// The workstream's own performance budget: worst-case cold book switch (decode + index,
    /// including the LCD's coverage() call, not just sources()) must stay <=150ms even for the
    /// single largest chapter file the corpus now has (Psalm 119, ~975KB after adding Gill and
    /// Matthew Henry Complete -- verified the largest with `find Resources/Study -name '*.json'
    /// | xargs ls -la | sort -k5 -n -r`). Each book gets a *fresh* StudyResourceStore so its
    /// per-chapter cache is genuinely empty, simulating a real cold switch, not a cache hit.
    /// Before this pass, the whole book was one file (Psalms alone was already 9.46MB with only
    /// Calvin/MHCC/Fathers/cross-refs, and 0.5.0's measured worst cold whole-book switch was
    /// 31ms against a much smaller corpus) -- per-chapter files keep the decoded unit small
    /// regardless of how much a book's total commentary grows.
    func testColdBookSwitchStaysUnderTheOneHundredFiftyMillisecondBudget() {
        let targets: [(code: String, chapter: Int)] = [
            ("PSA", 119), ("JER", 1), ("ISA", 1), ("MAT", 1), ("GEN", 1), ("ROM", 8), ("EZK", 16),
        ]
        var worst = 0.0
        for (code, chapter) in targets {
            let store = StudyResourceStore()  // fresh instance: empty chapterCache/coverageCache
            let start = DispatchTime.now().uptimeNanoseconds
            _ = store.sources(bookCode: code, bookName: code, chapter: chapter, verse: 1)
            _ = store.coverage(bookCode: code, chapter: chapter)
            let ms = Double(DispatchTime.now().uptimeNanoseconds - start) / 1_000_000
            worst = max(worst, ms)
            FileHandle.standardError.write(Data("PERF cold_chapter_switch \(code) \(chapter) ms=\(String(format: "%.2f", ms))\n".utf8))
        }
        XCTAssertLessThan(worst, 150, "worst-case cold book switch was \(worst) ms, over the 150ms budget")
    }
}

/// The confessional tier and content-kind taxonomy: every entry must carry an honest tier
/// (patristic material is never Tier 1) and a content kind that matches its genre.
extension ContentIntegrityTests {
    func testReformedContentIsTierOneAndFathersContentIsNeverTierOne() {
        for entry in Corpus.all where entry.tradition == .reformed {
            XCTAssertEqual(entry.tier, .tier1Confessional, "\(entry.id) is Reformed but not Tier 1")
        }
        for entry in Corpus.all where entry.tradition == .fathers {
            XCTAssertNotEqual(entry.tier, .tier1Confessional, "\(entry.id) is patristic but tagged Tier 1")
        }
        for entry in Corpus.all where entry.tradition == .crossReferences {
            XCTAssertEqual(entry.tier, .tier1Confessional, "cross-references should not be tier-gated")
        }
    }

    /// E1/E2 (0.7 wave 2): the new Exegetes bank is Tier 2 across the board -- Gill (Particular
    /// Baptist), Keil & Delitzsch (Lutheran) and Jamieson-Fausset-Brown (Presbyterian &
    /// Anglican) are none of them confessionally Reformed, so none of them may ever be Tier 1,
    /// and (unlike patristic material, which can also be Tier 3) none of them is Tier 3 either
    /// -- they are settled, named, received exegetes, not disputed-reception material.
    func testExegetesBankIsAlwaysTierTwoAndEveryCardNamesItsAuthorsTradition() {
        let expectedTraditionLabel: [String: String] = [
            "john-gill": "Particular Baptist",
            "keil-delitzsch": "Lutheran",
            "jamieson-fausset-brown": "Presbyterian & Anglican",
        ]
        var seenSources = Set<String>()
        for entry in Corpus.all where entry.tradition == .exegetes {
            XCTAssertEqual(entry.tier, .tier2HistoricWitness, "\(entry.id) is in the Exegetes bank but not Tier 2")
            XCTAssertEqual(entry.sourceClass, .exegete)
            XCTAssertEqual(entry.authorTradition, expectedTraditionLabel[entry.source], "\(entry.id) has the wrong tradition label")
            seenSources.insert(entry.source)
        }
        XCTAssertEqual(seenSources, Set(expectedTraditionLabel.keys), "every Exegetes source should actually appear at least once")
        // "REFORMED" now means Tier 1 only: no Exegetes-bank source should ever also appear
        // filed under the Reformed tradition (that would be the exact bug E1 fixes).
        for source in expectedTraditionLabel.keys {
            XCTAssertTrue(Corpus.all.filter { $0.source == source }.allSatisfy { $0.tradition == .exegetes },
                          "\(source) has an entry outside the Exegetes bank")
        }
        XCTAssertTrue(Corpus.all.filter { $0.tradition == .reformed }.allSatisfy { $0.source != "john-gill" },
                      "Gill must no longer appear in the Reformed bank")
    }

    /// E3: Matthew Henry's Concise Commentary is restored strictly gap-only -- every "mhcc"
    /// entry must land on a chapter where the unabridged Complete has zero entries, and must
    /// never coexist in the same chapter as a "matthew-henry" entry (two Henry cards on one
    /// chapter is exactly what the 2026-09-22 retirement removed).
    func testMHCCGapFillNeverOverlapsTheCompleteCommentary() {
        var mhccByChapter: [String: Set<Int>] = [:]
        var completeByChapter: [String: Set<Int>] = [:]
        for entry in Corpus.all where entry.source == "mhcc" {
            mhccByChapter[entry.id.prefix(3).description, default: []].insert(entry.chapter)
        }
        for entry in Corpus.all where entry.source == "matthew-henry" {
            completeByChapter[entry.id.prefix(3).description, default: []].insert(entry.chapter)
        }
        XCTAssertFalse(mhccByChapter.isEmpty, "expected at least one gap-fill entry")
        for (code, chapters) in mhccByChapter {
            let overlap = chapters.intersection(completeByChapter[code] ?? [])
            XCTAssertTrue(overlap.isEmpty, "\(code) has both mhcc and matthew-henry entries on chapters \(overlap)")
        }
        // The documented gap list (CONTENT-SOURCES.md / data/study-build-report.json): Matthew
        // 19-28, Song of Solomon (all), 2 Samuel 23-24, Jonah 2-4, Numbers 31-35, Joshua 22-23,
        // Psalm 72 -- 31 chapters, all of them backfilled.
        XCTAssertEqual(mhccByChapter["MAT"], Set(19...28))
        XCTAssertEqual(mhccByChapter["SNG"], Set(1...8))
        XCTAssertEqual(mhccByChapter["2SA"], [23, 24])
        XCTAssertEqual(mhccByChapter["JON"], [2, 3, 4])
        XCTAssertEqual(mhccByChapter["NUM"], Set(31...35))
        XCTAssertEqual(mhccByChapter["JOS"], [22, 23])
        XCTAssertEqual(mhccByChapter["PSA"], [72])
        for entries in mhccByChapter.values { XCTAssertFalse(entries.isEmpty) }
    }

    func testTierTwoDisclaimerTextIsExactlyTheRequiredSentence() {
        XCTAssertEqual(ConfessionalTier.tier2HistoricWitness.disclaimer,
                       "Historic Christian witness — not uniformly confessional Reformed.")
        XCTAssertNil(ConfessionalTier.tier1Confessional.disclaimer)
        XCTAssertNotNil(ConfessionalTier.tier3ResearchOnly.disclaimer)
    }

    func testContentKindMatchesGenreNotJustTradition() {
        // Calvin's single-verse entries should read as verse commentary; his whole-chapter
        // "block" entries as passage commentary. Cross-references are their own distinct kind.
        let calvinSingle = Corpus.all.first { $0.author == "John Calvin" && $0.rangeBasis == .stated && $0.spanCount == 1 }
        XCTAssertEqual(calvinSingle?.contentKind, .verseCommentary)
        let calvinBlock = Corpus.all.first { $0.author == "John Calvin" && $0.rangeBasis == .block }
        XCTAssertEqual(calvinBlock?.contentKind, .passageCommentary)
        for entry in Corpus.all where entry.tradition == .crossReferences {
            XCTAssertEqual(entry.contentKind, .canonicalIndex)
        }
        // A homily-attributed father entry should classify as a sermon, not generic commentary.
        if TestPaths.isPublicSource { return } // HCF homilies are deliberately not distributed.
        let homily = Corpus.all.first { $0.tradition == .fathers && $0.work.localizedCaseInsensitiveContains("homil") }
        XCTAssertEqual(homily?.contentKind, .sermon, "a homily should classify as a sermon, not commentary")
    }

    func testNoEntryOverclaimsGeneralWorkAsCommentary() {
        // The conservative default: unclassifiable Fathers material is general-work, never
        // silently presented as commentary. Confirm the fallback is actually reachable and that
        // every content kind used is one of the eight defined cases (a typo would decode as
        // nothing, since ContentKind is Decodable with no unknown-case fallback).
        let kinds = Set(Corpus.all.map(\.contentKind))
        if !TestPaths.isPublicSource { XCTAssertTrue(kinds.contains(.generalWork), "expected at least one conservatively-classified entry") }
        XCTAssertTrue(kinds.isSubset(of: Set(ContentKind.allCases)))
    }
}

extension ContentIntegrityTests {
    /// A subagent QA pass (2026-09-21) found 131 Fathers entries whose "work" field was a raw
    /// import filename ("Song of Solomon 1_1.toml") rather than a title, because the database
    /// has no source_title for those rows and the old fallback used file_name verbatim.
    func testNoFatherEntryLeaksARawImportFilenameAsItsWork() {
        for entry in Corpus.all where entry.tradition == .fathers {
            XCTAssertFalse(entry.work.hasSuffix(".toml"), "\(entry.id) leaks a raw filename as its work title: \(entry.work)")
        }
    }

    /// Item 8, 0.7 fix batch: because Sources/ lives inside an iCloud-synced Documents folder,
    /// macOS/iCloud conflict-copy duplicates ("<name> N.ext") kept reappearing under Resources
    /// and shipping as dead weight in the bundle (1,186 found and removed by
    /// `scripts/clean-sync-duplicates.sh` in this pass alone). This reads the actual resources
    /// directory on disk (via `TestPaths.root`, the same anchor `ScriptureTests` uses for
    /// `scripture-source`), not a generated index, so it catches a *fresh* sync conflict written
    /// after the last cleaner run, not just a regression in the cleaner itself.
    func testNoICloudSyncConflictDuplicatesInResources() throws {
        let resources = TestPaths.root.appendingPathComponent("Sources/StudyTable/Resources")
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: resources.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            XCTFail("Resources directory not found at \(resources.path)"); return
        }
        let pattern = try NSRegularExpression(pattern: #" [0-9]+\.[^./]+$"#)
        var offenders: [String] = []
        let enumerator = FileManager.default.enumerator(at: resources, includingPropertiesForKeys: [.isRegularFileKey])
        while let url = enumerator?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let name = url.lastPathComponent
            let range = NSRange(name.startIndex..., in: name)
            if pattern.firstMatch(in: name, range: range) != nil {
                offenders.append(url.path(percentEncoded: false).replacingOccurrences(of: resources.path, with: ""))
            }
        }
        XCTAssertTrue(offenders.isEmpty,
            "\(offenders.count) iCloud sync-conflict duplicate(s) in Resources -- run scripts/clean-sync-duplicates.sh: \(offenders.prefix(10))")
    }
}
