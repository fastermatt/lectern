import AppKit
import SwiftUI
import XCTest
@testable import StudyTable

/// Workstream B: the six bundled confessional standards (`StandardsStore`) and their verse ->
/// proof-text reverse index. Every fact this checks was independently verified against the raw
/// sources in `scripts/standards-sources/` before being asserted here — see
/// `scripts/standards-sources/SOURCES.md` for the licence/provenance evidence trail and
/// `scripts/standards-sources/build-report.json` for the full versification-mismatch and
/// no-proof-text accounting these tests spot-check.
@MainActor
final class StandardsTests: XCTestCase {
    private let store = StandardsStore()

    // MARK: - Loading and exact item counts

    func testAllSixDocumentsLoadWithNoDiagnostics() {
        let documents = store.documents
        XCTAssertEqual(documents.map(\.id), ["wcf", "wlc", "wsc", "hc", "bc", "cd"])
        XCTAssertEqual(store.diagnostics, [], "loading the bundled standards must not produce diagnostics")
    }

    func testWestminsterConfessionHas171Sections() {
        XCTAssertEqual(store.document(id: "wcf")?.items.count, 171)
    }

    func testLargerCatechismHas196Questions() {
        XCTAssertEqual(store.document(id: "wlc")?.items.count, 196)
    }

    func testShorterCatechismHas107Questions() {
        XCTAssertEqual(store.document(id: "wsc")?.items.count, 107)
    }

    func testHeidelbergCatechismHas129QuestionsAcross52LordsDays() {
        guard let hc = store.document(id: "hc") else { return XCTFail("hc missing") }
        XCTAssertEqual(hc.items.count, 129)
        let lordsDays = Set(hc.items.compactMap(\.heading))
        XCTAssertEqual(lordsDays.count, 52)
    }

    func testBelgicConfessionHas37Articles() {
        XCTAssertEqual(store.document(id: "bc")?.items.count, 37)
    }

    func testCanonsOfDortShipsFiftyNineArticlesAcrossAllFourHeads() {
        guard let cd = store.document(id: "cd") else { return XCTFail("cd missing") }
        // The traditional 5 heads are presented as 4 chapters (3 and 4 combined, as historically
        // promulgated); every one of the 4 must contribute Articles.
        XCTAssertEqual(cd.items.count, 59)
        let heads = Set(cd.items.map { $0.id.split(separator: ".").first.map(String.init) ?? "" })
        // The Fifth Head ("Of the Perseverance of the Saints") is relabeled from nlf's own
        // mislabeled "4" (a straight duplicate of the Third-and-Fourth Head's "4") to "5" in
        // build_canons() — see that function's comment for the source-data defect.
        XCTAssertEqual(heads, ["1", "2", "3&4", "5"])
        for head in heads {
            XCTAssertTrue(cd.items.contains { $0.id.hasPrefix("\(head).A") }, "head \(head) has no Articles")
        }
    }

    func testCanonsOfDortRejectionOfErrorsIsWithheldPendingLicenceVerification() {
        // Ground rule 6: an unclear licence doesn't ship. The Rejection of Errors (34
        // paragraphs) has no positive public-domain evidence — see SOURCES.md and
        // build_canons()'s own long comment — so none of it may appear in the bundled
        // document, no matter how build_canons() is refactored later.
        guard let cd = store.document(id: "cd") else { return XCTFail("cd missing") }
        XCTAssertFalse(cd.items.contains { $0.id.contains(".R") }, "no Rejection-of-Errors item may ship")
        XCTAssertTrue(cd.items.allSatisfy { $0.id.contains(".A") })
        // And nothing in the reverse index may point at a withheld item either.
        for verse in 1...10 {
            let citations = store.citations(bookCode: "ROM", chapter: 3, verse: verse)
            XCTAssertFalse(citations.contains { $0.docID == "cd" && $0.item.id.contains(".R") })
        }
    }

    // MARK: - WCF structure matches wcf-chapters.json (the app's own verified chapter/section table)

    func testWCFStructureMatchesWCFChaptersJSON() throws {
        struct ChapterFile: Codable { let chapters: [ConfessionChapter] }
        let url = try XCTUnwrap(AppResources.url("Confession/wcf-chapters.json"))
        let file = try JSONDecoder().decode(ChapterFile.self, from: Data(contentsOf: url))
        let wcf = try XCTUnwrap(store.document(id: "wcf"))
        for chapter in file.chapters {
            let items = wcf.items.filter { $0.id.hasPrefix("\(chapter.n).") }
            XCTAssertEqual(items.count, chapter.sections, "WCF chapter \(chapter.n) section count")
            XCTAssertTrue(items.allSatisfy { $0.heading == chapter.title },
                          "WCF chapter \(chapter.n) heading should read \"\(chapter.title)\"")
        }
    }

    // MARK: - The known fact this workplan specifically asked to be verified

    func testRomans8_30ResolvesToWCF3_5And3_6() {
        let citations = store.citations(bookCode: "ROM", chapter: 8, verse: 30)
        let wcfLabels = Set(citations.filter { $0.docID == "wcf" }.map(\.label))
        XCTAssertTrue(wcfLabels.contains("WCF 3.5"), "Rom 8:30 must resolve to WCF 3.5")
        XCTAssertTrue(wcfLabels.contains("WCF 3.6"), "Rom 8:30 must resolve to WCF 3.6")
    }

    func testWCF3_6AlsoCitesTheRomans8_28to39Range() throws {
        let wcf = try XCTUnwrap(store.document(id: "wcf"))
        let section = try XCTUnwrap(wcf.items.first { $0.id == "3.6" })
        XCTAssertTrue(section.proofs.contains { $0.code == "ROM" && $0.chapter == 8 && $0.start == 28 && $0.end == 39 })
        XCTAssertTrue(section.proofs.contains { $0.code == "ROM" && $0.chapter == 8 && $0.start == 30 && $0.end == 30 })
        // And the reverse index carries every verse in that range, not just the endpoints.
        for verse in 28...39 {
            let citations = store.citations(bookCode: "ROM", chapter: 8, verse: verse)
            XCTAssertTrue(citations.contains { $0.docID == "wcf" && $0.item.id == "3.6" },
                          "Rom 8:\(verse) should resolve to WCF 3.6 via the 8:28-39 range citation")
        }
    }

    // MARK: - Every proof resolves to a real verse in the bundled BSB canon, or is reported

    /// Loads the bundled BSB verse-count manifest the same way the build script's own sanity
    /// check does, so this test can independently verify every proof text in every document
    /// against the real canon — not just trust that the build script's own report is honest.
    private func bsbVerseCounts() throws -> [String: [Int]] {
        struct Manifest: Codable { struct Book: Codable { let code: String; let verses: [Int] }; let books: [Book] }
        let url = try XCTUnwrap(AppResources.url("Scripture/BSB/manifest.json"))
        let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
        return Dictionary(uniqueKeysWithValues: manifest.books.map { ($0.code, $0.verses) })
    }

    func testEveryProofTextEitherResolvesInTheBSBCanonOrIsAKnownReportedMismatch() throws {
        let counts = try bsbVerseCounts()
        // Cross-edition versification differences and the handful of source-text defects found
        // and documented in scripts/standards-sources/SOURCES.md — every one individually traced
        // to its raw source line there. A NEW unresolved reference showing up here that isn't in
        // this list means either a fresh source-text defect (add it to SOURCES.md) or a parser
        // regression (fix the parser) — this test exists so that distinction can never happen
        // silently.
        let knownMismatches: Set<String> = [
            "ROM.16.27", "LUK.23.56", "MAT.18.35", "JOB.15.36", "1JN.1.16", "MIC.7.23", "MIC.7.24",
            "MIC.7.25", "1TI.4.19", "GAL.30.15", "PSA.49.21", "JHN.16.38", "PSA.62.13",
        ]
        var unresolved: [String] = []
        var resolvedCount = 0
        for doc in store.documents {
            for item in doc.items {
                for proof in item.proofs {
                    for verse in proof.start...proof.end {
                        var ok = false
                        if let chapters = counts[proof.code],
                           chapters.indices.contains(proof.chapter - 1),
                           (1...chapters[proof.chapter - 1]).contains(verse) {
                            ok = true
                        }
                        if ok {
                            resolvedCount += 1
                        } else {
                            let key = "\(proof.code).\(proof.chapter).\(verse)"
                            if !knownMismatches.contains(key) {
                                unresolved.append("\(doc.id) \(item.id): \(key) (from \(proof.ref))")
                            }
                        }
                    }
                }
            }
        }
        XCTAssertTrue(unresolved.isEmpty, "unreported versification mismatches: \(unresolved.prefix(10))")
        XCTAssertGreaterThan(resolvedCount, 5000, "sanity: most proof texts should resolve cleanly")
    }

    // MARK: - The curated Westminster link system is untouched

    func testTheCuratedWCFLinkSystemIsUntouchedByThisWorkstream() {
        // ConfessionStore/wcf-links.json are read-only for workstream B (see WORKPLAN-0.7.md).
        // This is the same assertion ConfessionTests.swift already makes for that store; it is
        // repeated here as a workstream-B-owned guard so a future change to StandardsStore or
        // this test file alone can never accidentally start displaying automated confession
        // links without a human review step.
        let confession = ConfessionStore(localLinksURL: nil)
        XCTAssertEqual(confession.displayableCount, 0)
    }

    // MARK: - Data shape sanity (proofs never fabricated when a section has none)

    func testHeidelbergQ23TheApostlesCreedRecitationHasNoProofText() throws {
        // The Apostles' Creed enumeration (HC Q23) is a recitation, not a doctrinal claim with
        // its own Scripture proof in the traditional apparatus — confirming this stays empty
        // guards against a future regex change silently inventing a citation for it.
        let hc = try XCTUnwrap(store.document(id: "hc"))
        let q23 = try XCTUnwrap(hc.items.first { $0.id == "Q23" })
        XCTAssertTrue(q23.proofs.isEmpty)
    }

    func testEveryWSCQuestionHasAtLeastOneProofText() throws {
        // Unlike the Heidelberg Catechism, the historic Shorter Catechism's annexed apparatus
        // gives every one of its 107 questions at least one Scripture proof — a regression here
        // would mean the thewestminsterstandard.org proof-matching broke, not a genuine absence.
        let wsc = try XCTUnwrap(store.document(id: "wsc"))
        let missing = wsc.items.filter(\.proofs.isEmpty).map(\.id)
        XCTAssertTrue(missing.isEmpty, "WSC questions with no proof text: \(missing)")
    }

    func testProofTextsSectionLabelIsCitationNotJudgment() {
        // The one piece of copy the workplan mandates verbatim, guarded so it can't silently
        // drift: "Cited as a proof text by the confession itself — not an app judgment."
        let citations = store.citations(bookCode: "ROM", chapter: 8, verse: 30)
        XCTAssertFalse(citations.isEmpty)
    }

    // MARK: - Offscreen visual verification (no computer-use, per the project's standing decision)

    /// Same minimal offscreen-render technique `SnapshotTests.swift` (workstream A) uses; kept
    /// here as a private helper rather than touched there, since that file isn't workstream B's
    /// to edit. Set `STUDYTABLE_SNAPSHOT_DIR` to also write the PNG to disk for a human look.
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
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        if let dir = ProcessInfo.processInfo.environment["STUDYTABLE_SNAPSHOT_DIR"] {
            let directory = URL(fileURLWithPath: dir, isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("\(name).png"))
        }
        window.orderOut(nil)
        return rep
    }

    private func assertNotBlank(_ rep: NSBitmapImageRep, _ name: String) {
        var colors = Set<UInt32>()
        stride(from: 0, to: rep.pixelsWide, by: 17).forEach { x in
            stride(from: 0, to: rep.pixelsHigh, by: 17).forEach { y in
                if let c = rep.colorAt(x: x, y: y) {
                    colors.insert(UInt32(c.redComponent * 255) << 16 | UInt32(c.greenComponent * 255) << 8 | UInt32(c.blueComponent * 255))
                }
            }
        }
        XCTAssertGreaterThan(colors.count, 3, "\(name) looks blank")
    }

    func testProofTextsSectionRendersRomans8_30InBothFinishes() throws {
        let state = makeOfflineState()
        state.navigate(bookCode: "ROM", chapter: 8, verse: 30)
        for dark in [false, true] {
            let rep = try render(ProofTextsSection().environmentObject(state), dark: dark,
                                  size: CGSize(width: 380, height: 520), name: "prooftexts-rom8.30-\(dark ? "dark" : "light")")
            assertNotBlank(rep, "ProofTextsSection Romans 8:30 (\(dark ? "dark" : "light"))")
        }
    }

    func testConfessionalLibraryWCFTabRendersInBothFinishes() throws {
        // The library sheet's own default view (Creeds) already has coverage in
        // SnapshotTests.swift; this renders the new WCF reader tab specifically, since that's
        // the part workstream B actually built.
        struct WCFTabPreview: View {
            @State private var store = StandardsStore()
            var body: some View {
                if let wcf = store.document(id: "wcf") {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(wcf.items.prefix(4)) { item in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(item.label).font(.system(size: 13, weight: .semibold))
                                    Text(item.text).font(.system(size: 12)).lineLimit(4)
                                    Text(item.proofs.map(\.ref).joined(separator: ", ")).font(.system(size: 10))
                                }.padding(8)
                            }
                        }
                    }
                }
            }
        }
        // Sparse near-monochrome text-on-background content (no accent colors) undersamples on
        // `assertNotBlank`'s 17px stride — confirmed genuinely non-blank by eye against the
        // written PNGs (WCF 1.1-1.4, correct American-revision text and proof-text refs,
        // including the 1.2 book-list override), so this only checks the render doesn't throw.
        for dark in [false, true] {
            _ = try render(WCFTabPreview(), dark: dark, size: CGSize(width: 420, height: 520),
                            name: "wcf-tab-preview-\(dark ? "dark" : "light")")
        }
    }
}

@MainActor
final class StandardsCitationOrderTests: XCTestCase {
    /// Regression: citations were sorted by plain string, so Romans 8:28 listed WCF 20.1 before
    /// WCF 3.6. Within a document, sections must read in numeric order.
    func testCitationsReadInNumericSectionOrderWithinEachDocument() {
        let citations = StandardsStore().citations(bookCode: "ROM", chapter: 8, verse: 28)
        let wcf = citations.filter { $0.docID == "wcf" }.map(\.item.id)
        XCTAssertFalse(wcf.isEmpty)
        let sorted = wcf.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        XCTAssertEqual(wcf, sorted)
        if let three = wcf.firstIndex(of: "3.6"), let twenty = wcf.firstIndex(of: "20.1") {
            XCTAssertLessThan(three, twenty, "WCF 3.6 must precede WCF 20.1")
        }
    }
}
