import AppKit
import SwiftUI
import XCTest
import StudyTableCore
@testable import StudyTable

/// Covers the 0.8 Fathers-breadth pass (workstream I): every profile field is sourced, the
/// broadened admission rule is reflected in `FatherProfileStore`, Origen/Tertullian and the other
/// newly-broadened authors are default-visible and labelled, and a council-condemned author's
/// profile only ever surfaces behind the existing research-only toggle. Offscreen renders of
/// `FatherBentLabel`/`FatherProfileSheet` follow the same pattern `SnapshotTests.swift` uses.
@MainActor
final class FatherProfileTests: XCTestCase {
    private var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["STUDYTABLE_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    // MARK: - Store

    func testStoreLoadsTheBundledProfileFileWithoutDiagnostics() {
        let store = FatherProfileStore()
        XCTAssertTrue(store.diagnostics.isEmpty, "FatherProfileStore diagnostics: \(store.diagnostics)")
        XCTAssertGreaterThanOrEqual(store.count, 60, "expected at least the 60 profiles workstream I wrote")
    }

    func testLookupByExactAuthorNameMatchesTheDatabaseSAuthorString() {
        let store = FatherProfileStore()
        XCTAssertNotNil(store.profile(forAuthor: "Origen of Alexandria"))
        XCTAssertNotNil(store.profile(forAuthor: "John Chrysostom"))
        XCTAssertNil(store.profile(forAuthor: "Not A Real Father"))
    }

    // MARK: - Coverage and sourcing discipline

    /// "Never guess — omit an unsourced field": every profile must carry at least one source
    /// with both a title and a URL. Most profiled names also actually appear somewhere in the
    /// corpus, but not all are required to: `_father_admission` admits by author, not by "has
    /// surviving content in this app's 66-book canon" — Arius's only database row, for example,
    /// cites 2 Maccabees (outside the Protestant canon this app uses) and is correctly dropped by
    /// the "book not in canon" check, so he is architecturally admitted and profiled but produces
    /// zero visible cards. That is a real, checked finding (see workstream I's final report), not
    /// a bug, so this test only requires *most* profiled names to have surviving content, not all.
    func testEveryProfileIsSourcedAndMostCorrespondToVisibleContent() {
        let store = FatherProfileStore()
        let admittedAuthors = Set(Corpus.all.filter { $0.tradition == .fathers }.map(\.author))
        var namesWithNoSurvivingContent: [String] = []
        for name in allProfileNames(store) {
            guard let profile = store.profile(forAuthor: name) else { return XCTFail("profile \(name) failed to load back") }
            XCTAssertFalse(profile.sources.isEmpty, "\(name) has no source citation")
            for source in profile.sources {
                XCTAssertFalse(source.title.isEmpty, "\(name) has a source with an empty title")
                XCTAssertNotNil(source.url, "\(name) has a source with no URL")
            }
            if !admittedAuthors.contains(name) { namesWithNoSurvivingContent.append(name) }
            XCTAssertLessThanOrEqual(profile.emphases.count, 3, "\(name) has more than the spec's 1-3 emphases")
        }
        if TestPaths.isPublicSource { XCTAssertTrue(admittedAuthors.isEmpty); return }
        XCTAssertEqual(namesWithNoSurvivingContent, ["Arius"],
                       "only Arius is known to have zero surviving in-canon content (his one DB row cites 2 Maccabees); "
                       + "any other name here means a profile/name mismatch worth investigating")
    }

    /// Workstream L (0.8, second Fathers-breadth pass): every admitted Fathers author with a
    /// real, high-volume presence in the corpus (≥25 cards) should have a sourced profile — this
    /// is the "most-read first" prioritization the task was worked in, and it closed the gap for
    /// 14 of the 16 authors that met this bar at the start of the pass (Oecumenius down through
    /// Prudentius). Two remain open, named explicitly rather than silently: **Olympiodorus of
    /// Alexandria** (57 cards) and **Paterius** (37 cards) — a public-domain, per-author article
    /// in Wace & Piercy, Smith & Wace, Schaff's NPNF, or the Catholic Encyclopedia could not be
    /// located for either within this pass (only passing mentions in finding-aid lists, not
    /// enough to source dates/region/school/emphases honestly). This test pins that exact
    /// remainder so a future pass either shrinks the named list (and must update this test) or
    /// the list silently grows (which fails the test and demands attention) — never a fact
    /// invented to fill the gap.
    func testEveryFathersAuthorWithAtLeast25CardsHasASourcedProfile() {
        let store = FatherProfileStore()
        var cardCounts: [String: Int] = [:]
        for entry in Corpus.all where entry.tradition == .fathers {
            cardCounts[entry.author, default: 0] += 1
        }
        let missing = cardCounts
            .filter { $0.value >= 25 && store.profile(forAuthor: $0.key) == nil }
            .sorted { $0.value > $1.value }
        let missingNames = Set(missing.map(\.key))
        let documentedRemainingGap: Set<String> = TestPaths.isPublicSource ? [] : ["Olympiodorus of Alexandria", "Paterius"]
        XCTAssertEqual(missingNames, documentedRemainingGap,
                      "authors with \u{2265}25 Fathers cards but no profile changed from the documented remainder: "
                      + missing.map { "\($0.key) (\($0.value))" }.joined(separator: ", "))
    }

    /// Workstream L's misattribution finding, corrected by Claude: the Gospel comments the
    /// database files under "Remigius of Rheims" (d. c. 533) are Remigius of Auxerre's (d. 908),
    /// cited in Aquinas's Catena Aurea. Cards and profile must carry the corrected name and date,
    /// and the profile must explain the correction with a source.
    func testRemigiusCatenaMaterialIsAttributedToRemigiusOfAuxerre() throws {
        let store = FatherProfileStore()
        XCTAssertNil(store.profile(forAuthor: "Remigius of Rheims"), "the misattributed name must not carry a profile")
        let profile = try XCTUnwrap(store.profile(forAuthor: "Remigius of Auxerre"))
        XCTAssertTrue(profile.dates?.contains("908") == true)
        let controversies = try XCTUnwrap(profile.controversies)
        XCTAssertTrue(controversies.contains("Rheims"), "must explain the database's original attribution")
        XCTAssertTrue(controversies.contains("Catena Aurea"))
        XCTAssertFalse(profile.sources.isEmpty)
        let cards = Canon.bookCodes.flatMap { (Corpus.byBook[$0] ?? []) }.filter { $0.tradition == .fathers }
        XCTAssertFalse(cards.contains { $0.author == "Remigius of Rheims" }, "no card may still say Remigius of Rheims")
        let remigius = cards.filter { $0.author == "Remigius of Auxerre" }
        if TestPaths.isPublicSource { XCTAssertTrue(remigius.isEmpty); return }
        XCTAssertFalse(remigius.isEmpty)
        XCTAssertTrue(remigius.allSatisfy { $0.era == "d. 908" })
    }

    /// Oecumenius is this pass's largest single unresolved attribution case (1,285 cards): the
    /// database lumps together at least three distinct authorship problems under one name. The
    /// profile must name the composite/pseudonymous nature rather than presenting one clean bio.
    func testOecumeniusProfileFlagsTheCompositeCatenaAuthorship() throws {
        let store = FatherProfileStore()
        let profile = try XCTUnwrap(store.profile(forAuthor: "Oecumenius"))
        let controversies = try XCTUnwrap(profile.controversies)
        XCTAssertTrue(controversies.contains("riddle"), "should carry the Catholic Encyclopedia's own characterization")
        XCTAssertFalse(profile.sources.isEmpty)
    }

    /// The Desert Fathers entry is an anthology (the Apophthegmata Patrum), not a person; its
    /// profile must say so honestly rather than inventing a biography, per the task's brief.
    func testDesertFathersProfileIsHonestlyLabelledAsAnAnthologyNotAPerson() throws {
        let store = FatherProfileStore()
        let profile = try XCTUnwrap(store.profile(forAuthor: "Desert Fathers"))
        let school = try XCTUnwrap(profile.school)
        XCTAssertTrue(school.contains("anthology") || school.contains("Not a single author"),
                      "school/tradition field should say this is a collection, not an individual author")
    }

    /// Spec: "every default-bank author with ≥ school + region + one sourced field." Every
    /// profile workstream I wrote for the default bank meets this; this test would fail loudly
    /// if a future edit added a thin profile that didn't.
    func testEveryDefaultBankProfileHasAtLeastSchoolRegionAndOneFurtherSourcedField() {
        let store = FatherProfileStore()
        let condemned = conciliarCondemnedNames(store)
        for name in allProfileNames(store) where !condemned.contains(name) {
            guard let profile = store.profile(forAuthor: name) else { continue }
            XCTAssertNotNil(profile.school, "\(name) (default bank) has no school/tradition")
            XCTAssertNotNil(profile.region, "\(name) (default bank) has no region")
            let hasFurtherField = profile.dates != nil || profile.ecclesialRecognition != nil
                || !profile.emphases.isEmpty || profile.controversies != nil
            XCTAssertTrue(hasFurtherField, "\(name) (default bank) has only school+region, no further sourced field")
        }
    }

    /// Origen, Tertullian, Clement of Alexandria and Eusebius of Caesarea are the four the 0.8
    /// brief names explicitly as moving into the default bank ("clearly labelled").
    func testTheFourNamedBriefAuthorsAreProfiledAndLabelled() {
        let store = FatherProfileStore()
        for name in ["Origen of Alexandria", "Tertullian", "Clement of Alexandria", "Eusebius of Caesarea"] {
            guard let profile = store.profile(forAuthor: name) else { return XCTFail("\(name) has no profile") }
            XCTAssertNotNil(profile.school, "\(name) has no school/tradition label")
            XCTAssertNotNil(profile.bentLineForTesting, "\(name) has no compact bent-label text")
        }
    }

    /// Origen's specific case: the brief asks that he be labelled precisely rather than bucketed
    /// with heresiarchs unless the flag + a real source demand it. His profile documents the
    /// disputed 553 anathemas without claiming a settled council condemnation of him by name.
    func testOrigenIsPreciselyLabelledNotBucketedAsAHeresiarch() throws {
        let store = FatherProfileStore()
        let profile = try XCTUnwrap(store.profile(forAuthor: "Origen of Alexandria"))
        XCTAssertNil(profile.conciliarJudgment, "Origen has no settled, sourced conciliar condemnation by name")
        let controversies = try XCTUnwrap(profile.controversies)
        XCTAssertTrue(controversies.contains("553"), "Origen's profile should still name the traditionally cited 553 council for context")
        if TestPaths.isPublicSource { XCTAssertFalse(Corpus.all.contains { $0.source == "hcf" }); return }
        XCTAssertTrue(Corpus.all.contains { $0.author == "Origen of Alexandria" && $0.tier == .tier2HistoricWitness },
                      "Origen must actually appear as a default-visible (Tier 2) Father")
    }

    // MARK: - Condemned bucket: profile + conciliar judgment only behind the toggle

    func testCouncilCondemnedAuthorHasAConciliarJudgmentAndOnlySurfacesWithTheToggleOn() throws {
        let store = FatherProfileStore()
        let profile = try XCTUnwrap(store.profile(forAuthor: "Theodore of Mopsuestia"))
        let judgment = try XCTUnwrap(profile.conciliarJudgment, "Theodore of Mopsuestia should carry a sourced conciliar judgment")
        XCTAssertEqual(judgment.council, "Second Council of Constantinople")
        XCTAssertEqual(judgment.year, 553)

        // The database's own condemned_by_council flag is 0 for this author (verified directly,
        // 2026-09-23) -- this is the one place the build script overrides it against a real
        // source. Confirm the override actually took effect in the shipped data.
        if TestPaths.isPublicSource { XCTAssertFalse(Corpus.all.contains { $0.source == "hcf" }); return }
        guard let entry = Corpus.all.first(where: { $0.author == "Theodore of Mopsuestia" }) else {
            return XCTFail("Theodore of Mopsuestia should appear somewhere in the corpus")
        }
        XCTAssertEqual(entry.tier, .tier3ResearchOnly, "overridden despite the database's own flag; must be Tier 3")

        let resourceStore = StudyResourceStore()
        let defaultResults = resourceStore.sources(bookCode: bookCode(for: entry), bookName: "Test",
                                                     chapter: entry.chapter, verse: entry.startVerse)
        XCTAssertFalse(defaultResults.contains { $0.entry.author == "Theodore of Mopsuestia" },
                       "must not appear by default without the research-tier opt-in")
        let optedIn = resourceStore.sources(bookCode: bookCode(for: entry), bookName: "Test",
                                             chapter: entry.chapter, verse: entry.startVerse, includeResearchTier: true)
        XCTAssertTrue(optedIn.contains { $0.entry.author == "Theodore of Mopsuestia" },
                     "should appear once the reader opts into research-only sources")
    }

    /// Heracleon, Valentinus and Tatian are condemned per the database's flag, but no ecumenical
    /// council names any of the three -- all three predate the conciliar era. Their profiles must
    /// not invent a "council + year" that no source documents.
    func testPreConciliarHeresiarchsCarryNoInventedCouncilLabel() throws {
        let store = FatherProfileStore()
        for name in ["Heracleon", "Valentinus", "Tatian the Assyrian"] {
            let profile = try XCTUnwrap(store.profile(forAuthor: name))
            XCTAssertNil(profile.conciliarJudgment, "\(name) predates the conciliar era; no council/year should be invented")
            XCTAssertNotNil(profile.controversies, "\(name) should still explain why they're in the condemned bucket")
        }
    }

    private func bookCode(for entry: StudySource) -> String {
        // StudySource itself doesn't carry its book code (chapter files are already scoped to
        // one book); recover it the same way ContentIntegrityTests does, via Corpus.byBook.
        for (code, entries) in Corpus.byBook where entries.contains(where: { $0.id == entry.id }) { return code }
        return "ROM"
    }

    private func allProfileNames(_ store: FatherProfileStore) -> [String] {
        // FatherProfileStore doesn't expose a name list (callers only ever look up one author at
        // a time), so tests read the shipped file directly to enumerate every profile it ships.
        guard let url = AppResources.url("Study/fathers-profiles.json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(FatherProfileFile.self, from: data) else { return [] }
        return file.profiles.map(\.name)
    }

    private func conciliarCondemnedNames(_ store: FatherProfileStore) -> Set<String> {
        Set(allProfileNames(store).filter { store.profile(forAuthor: $0)?.conciliarJudgment != nil
            || ["Heracleon", "Valentinus", "Tatian the Assyrian"].contains($0) })
    }

    // MARK: - Offscreen renders (no computer-use, per standing decision)

    private func render<V: View>(_ view: V, dark: Bool, size: CGSize, name: String) throws -> NSBitmapImageRep {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = appearance
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderBack(nil)
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        }
        let rep = try snapshotBitmap(of: host)
        if let directory = outputDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("\(name).png"))
        }
        window.orderOut(nil)
        return rep
    }

    private func assertNotBlank(_ rep: NSBitmapImageRep, _ label: String) {
        var distinct = Set<UInt32>()
        for x in stride(from: 0, to: rep.pixelsWide, by: 11) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 11) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                    distinct.insert(UInt32(c.redComponent * 63) << 12 | UInt32(c.greenComponent * 63) << 6 | UInt32(c.blueComponent * 63))
                }
            }
        }
        XCTAssertGreaterThan(distinct.count, 8, "\(label) rendered blank")
    }

    func testFatherBentLabelRendersInLightAndDark() throws {
        for (dark, name) in [(false, "light"), (true, "dark")] {
            let view = FatherBentLabel(authorName: "Origen of Alexandria")
                .padding(20).background(STColor.tileTop)
            let rep = try render(view, dark: dark, size: CGSize(width: 260, height: 60), name: "father-bent-label-\(name)")
            assertNotBlank(rep, name)
        }
    }

    func testFatherBentLabelRendersNothingForAnUnprofiledAuthor() throws {
        XCTAssertNil(FatherProfileStore().profile(forAuthor: "Abba Poemen"), "fixture assumption: admitted but deliberately not profiled")
        let view = FatherBentLabel(authorName: "Abba Poemen")
            .padding(20).background(STColor.tileTop)
        // A solid single-color background legitimately samples down to one or two distinct
        // colors (antialiasing at the edges) — this render only needs to prove the nil-profile
        // path doesn't crash and produces *some* pixels, not visual diversity. The real assertion
        // that FatherBentLabel shows nothing (no button, no text, no placeholder) for a
        // profile-less author is `profile(forAuthor:)` returning nil, checked above.
        let rep = try render(view, dark: false, size: CGSize(width: 260, height: 60), name: "father-bent-label-empty")
        XCTAssertGreaterThan(rep.pixelsWide, 0)
    }

    /// Workstream L: Oecumenius has by far the longest controversies text of any profile written
    /// so far (the composite-authorship explanation runs several sentences) — the sheet most
    /// likely to reveal a real layout problem (clipping, overflow) is rendered and inspected here.
    func testFatherProfileSheetRendersOecumeniusInLightAndDark() throws {
        let store = FatherProfileStore()
        let profile = try XCTUnwrap(store.profile(forAuthor: "Oecumenius"))
        for (dark, finish) in [(false, "light"), (true, "dark")] {
            let rep = try render(FatherProfileSheet(profile: profile), dark: dark,
                                  size: CGSize(width: 420, height: 560), name: "father-profile-sheet-oecumenius-\(finish)")
            assertNotBlank(rep, "oecumenius \(finish)")
        }
    }

    func testFatherProfileSheetRendersInLightAndDarkForADefaultBankAuthorAndACondemnedAuthor() throws {
        let store = FatherProfileStore()
        let origen = try XCTUnwrap(store.profile(forAuthor: "Origen of Alexandria"))
        let condemned = try XCTUnwrap(store.profile(forAuthor: "Theodore of Mopsuestia"))
        for (profile, label) in [(origen, "origen"), (condemned, "condemned")] {
            for (dark, finish) in [(false, "light"), (true, "dark")] {
                let rep = try render(FatherProfileSheet(profile: profile), dark: dark,
                                      size: CGSize(width: 420, height: 480), name: "father-profile-sheet-\(label)-\(finish)")
                assertNotBlank(rep, "\(label) \(finish)")
            }
        }
    }
}

private extension FatherProfile {
    /// Mirrors the private `bentLine` computed property in FatherProfileViews.swift so tests can
    /// assert on the same logic without making that extension non-private for production code.
    var bentLineForTesting: String? {
        if let school { return school.replacingOccurrences(of: " — ", with: " · ") }
        return ecclesialRecognition ?? region
    }
}
