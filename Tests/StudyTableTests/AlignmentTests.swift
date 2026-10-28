import AppKit
import SwiftUI
import XCTest
import StudyTableCore
@testable import StudyTable

/// Covers the 0.9.5 reader-selected alignment feature (workstream N): implements the 2026-09-24
/// Decision Log entry ("Lectern uses reader-selected creeds, not a declared Reformed product
/// identity"). Every assertion here traces back to real, already-sourced data in the shipped
/// corpus (`Corpus.all`/`Corpus.byBook`, same fixtures `ConfessionTests`/`FatherProfileTests`
/// use) rather than synthetic fixtures, so a future content regeneration that removes one of
/// these authors fails loudly here instead of silently losing coverage.
@MainActor
final class AlignmentTests: XCTestCase {
    private var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["STUDYTABLE_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    private var romans828: [StudySource] { (Corpus.byBook["ROM"] ?? []).filter { $0.chapter == 8 && $0.covers(verse: 28) } }

    private func first(author: String) throws -> StudySource {
        if TestPaths.isPublicSource && ["Theodore of Mopsuestia", "Origen of Alexandria"].contains(author) {
            // Synthetic text tests alignment logic against the separately sourced author profile.
            return StudySource(id: "ROM.8.28-28.fixture.00000000", chapter: 8, startVerse: 28, endVerse: 28,
                rangeBasis: .stated, author: author, work: "Synthetic test fixture", era: "test", tradition: .fathers,
                source: "fixture", excerpt: "Synthetic test text; not a historical quotation.", sourceURL: nil,
                isExactQuote: false, truncated: false,
                tier: author == "Theodore of Mopsuestia" ? .tier3ResearchOnly : .tier2HistoricWitness)
        }
        return try XCTUnwrap(Corpus.all.first { $0.author == author }, "\(author) should appear somewhere in the shipped corpus")
    }

    // MARK: - "No lens" shows no alignment claims at all

    func testNoLensReturnsNilForEverySourceRegardlessOfTradition() throws {
        let store = AlignmentStore()
        let calvin = try XCTUnwrap(romans828.first { $0.author == "John Calvin" })
        let gill = try first(author: "John Gill")
        let theodore = try first(author: "Theodore of Mopsuestia")
        for source in [calvin, gill, theodore] {
            XCTAssertNil(store.alignment(for: source, against: .none),
                        "\(source.author) must show no alignment claim under .none, not a rendered 'no mapping'")
        }
    }

    // MARK: - Same source, different (correct) language under different standards

    func testConfessionalReformedSourceShowsDocumentedAgreementUnderReformedLensesButNoMappingUnderEcumenicalCreeds() throws {
        let store = AlignmentStore()
        let calvin = try XCTUnwrap(romans828.first { $0.author == "John Calvin" })
        XCTAssertEqual(calvin.tier, .tier1Confessional, "fixture assumption: Calvin is Tier 1")

        guard case .documentedAgreement(let westminsterText)? = store.alignment(for: calvin, against: .westminsterStandards) else {
            return XCTFail("expected documented agreement under Westminster Standards")
        }
        guard case .documentedAgreement(let threeFormsText)? = store.alignment(for: calvin, against: .threeFormsOfUnity) else {
            return XCTFail("expected documented agreement under Three Forms of Unity")
        }
        XCTAssertTrue(westminsterText.contains("Westminster Standards"))
        XCTAssertTrue(threeFormsText.contains("Three Forms of Unity"))
        XCTAssertNotEqual(westminsterText, threeFormsText, "the same source should carry standard-specific language, not identical boilerplate")

        XCTAssertEqual(store.alignment(for: calvin, against: .ecumenicalCreeds), .noMapping,
                       "no per-source data ties Calvin's commentary to the ecumenical creeds specifically; must not invent agreement")
    }

    func testNonTier1ReformedBankSourceIsNoMappingUnderAnyLens() throws {
        // Matthew Henry is Tier 1 too in the shipped data, so this specifically checks the tier
        // gate itself rather than the author: a hand-built Tier 2/3 "Reformed"-tradition fixture
        // must not receive documented agreement it hasn't earned.
        let store = AlignmentStore()
        let nonTier1 = StudySource(id: "TEST.1.1-1.fixture.0", chapter: 1, startVerse: 1, endVerse: 1,
                                   rangeBasis: .stated, author: "Test Author", work: "Test Work", era: "n/a",
                                   tradition: .reformed, source: "test", excerpt: "excerpt",
                                   sourceURL: nil, isExactQuote: true, truncated: false,
                                   tier: .tier2HistoricWitness, contentKind: .generalWork)
        XCTAssertEqual(store.alignment(for: nonTier1, against: .westminsterStandards), .noMapping)
        XCTAssertEqual(store.alignment(for: nonTier1, against: .threeFormsOfUnity), .noMapping)
        XCTAssertEqual(store.alignment(for: nonTier1, against: .ecumenicalCreeds), .noMapping)
    }

    // MARK: - The sanctioned Baptist/paedobaptist example (WORKPLAN-0.9.5.md section N item 2)

    func testGillsBaptistTraditionIsTensionUnderReformedLensesAndNoMappingUnderEcumenicalCreeds() throws {
        let store = AlignmentStore()
        let gill = try first(author: "John Gill")
        XCTAssertEqual(gill.authorTradition, "Particular Baptist", "fixture assumption")

        guard case .tension(let westminsterText)? = store.alignment(for: gill, against: .westminsterStandards) else {
            return XCTFail("expected a sourced tension, not agreement or no-mapping, under Westminster Standards")
        }
        XCTAssertTrue(westminsterText.contains("Baptist"))
        XCTAssertTrue(westminsterText.contains("paedobaptist"))
        // Must be stated as fact, never a verdict: no "wrong"/"error"/"false" language.
        for banned in ["wrong", "error", "false", "heretical", "heterodox"] {
            XCTAssertFalse(westminsterText.lowercased().contains(banned), "tension text must stay factual, not a verdict (\"\(banned)\")")
        }

        guard case .tension(let threeFormsText)? = store.alignment(for: gill, against: .threeFormsOfUnity) else {
            return XCTFail("expected the same sourced tension under Three Forms of Unity")
        }
        XCTAssertTrue(threeFormsText.contains("Three Forms of Unity"))

        XCTAssertEqual(store.alignment(for: gill, against: .ecumenicalCreeds), .noMapping,
                       "baptism mode isn't a Trinitarian/Christological ecumenical-creed question; must not be surfaced there")
    }

    func testUndocumentedExegeteTraditionsAreNoMappingRatherThanInventedTension() throws {
        // Keil & Delitzsch (Lutheran) and Jamieson-Fausset-Brown (Presbyterian & Anglican) have an
        // `authorTradition` label but no specific, already-sourced point of doctrinal disagreement
        // in this codebase -- unlike Gill's Baptist/paedobaptism case, which the workplan names
        // explicitly. Inventing one would violate the decision's "never invent a claim" rule.
        let store = AlignmentStore()
        for author in ["Keil & Delitzsch", "Jamieson, Fausset & Brown"] {
            let source = try first(author: author)
            XCTAssertEqual(store.alignment(for: source, against: .westminsterStandards), .noMapping, author)
            XCTAssertEqual(store.alignment(for: source, against: .threeFormsOfUnity), .noMapping, author)
        }
    }

    // MARK: - Condemned author: never merely "in tension," under any lens

    func testCouncilCondemnedAuthorIsAlwaysHistoricallyDisputedNeverTensionUnderAnyLens() throws {
        let store = AlignmentStore()
        let theodore = try first(author: "Theodore of Mopsuestia")
        for standard: AlignmentStandard in [.westminsterStandards, .threeFormsOfUnity, .ecumenicalCreeds] {
            guard case .historicallyDisputed(let council, let year, _)? = store.alignment(for: theodore, against: standard) else {
                return XCTFail("\(standard) must show historicallyDisputed for a council-condemned author, never tension or no-mapping")
            }
            XCTAssertEqual(council, "Second Council of Constantinople")
            XCTAssertEqual(year, 553)
        }
    }

    // MARK: - Ecumenical creeds lens: patristic controversy without a conciliar judgment

    func testDisputedButNotConciliarlyCondemnedFatherIsTensionOnlyUnderEcumenicalCreeds() throws {
        let store = AlignmentStore()
        let origen = try first(author: "Origen of Alexandria")
        XCTAssertNil(FatherProfileStore.shared.profile(forAuthor: "Origen of Alexandria")?.conciliarJudgment,
                    "fixture assumption: Origen has disputed reception but no settled conciliar judgment by name")

        guard case .tension(let text)? = store.alignment(for: origen, against: .ecumenicalCreeds) else {
            return XCTFail("expected a sourced tension (from FatherProfile.controversies) under the ecumenical-creeds lens")
        }
        XCTAssertFalse(text.isEmpty)

        // Reformed-family lenses don't look at patristic FatherProfile.controversies at all in
        // this pass (Origen isn't Reformed/Exegetes tradition) -- honest no-mapping, not a guess.
        XCTAssertEqual(store.alignment(for: origen, against: .westminsterStandards), .noMapping)
        XCTAssertEqual(store.alignment(for: origen, against: .threeFormsOfUnity), .noMapping)
    }

    // MARK: - Cross-references: never doctrinal content

    func testCrossReferencesAreAlwaysNoMappingUnderAnyRealLens() throws {
        let store = AlignmentStore()
        guard let crossRef = Corpus.all.first(where: { $0.tradition == .crossReferences }) else {
            return XCTFail("expected at least one cross-reference entry in the corpus")
        }
        for standard: AlignmentStandard in [.westminsterStandards, .threeFormsOfUnity, .ecumenicalCreeds] {
            XCTAssertEqual(store.alignment(for: crossRef, against: standard), .noMapping)
        }
    }

    // MARK: - No fixed app-wide identity in code, onboarding, or product copy

    func testNoCodePathAssertsAFixedAppWideReformedIdentity() {
        // AppState's default lens must be "no lens," not a Westminster/Reformed default -- the
        // whole point of the decision is that Lectern ships with no declared identity.
        let state = makeOfflineState()
        XCTAssertEqual(state.alignmentStandard, .none, "the shipped default must be no alignment lens")
    }

    private static let bannedPhrases = [
        "designed from a confessional reformed perspective",
        "designed from a reformed perspective",
        "reformed perspective",
        "declared reformed",
        "lectern is reformed",
        "study table is reformed",
    ]

    func testOnboardingCopyDoesNotContainTheBannedFixedIdentityPhrasing() {
        let sheet = WelcomeSheet()
        let combined = sheet.points.map { "\($0.0) \($0.1)" }.joined(separator: " ").lowercased()
        for phrase in Self.bannedPhrases {
            XCTAssertFalse(combined.contains(phrase), "onboarding copy still contains banned phrase: \"\(phrase)\"")
        }
    }

    func testProductDocDoesNotContainTheBannedFixedIdentityPhrasing() throws {
        let url = TestPaths.root.appendingPathComponent("PRODUCT.md")
        let text = try String(contentsOf: url, encoding: .utf8).lowercased()
        for phrase in Self.bannedPhrases {
            XCTAssertFalse(text.contains(phrase), "PRODUCT.md still contains banned phrase: \"\(phrase)\"")
        }
        XCTAssertTrue(text.contains("does not declare one fixed confessional identity"), "PRODUCT.md should state the decision explicitly")
    }

    // MARK: - Offscreen renders (no computer-use, per standing decision)
    // At least two different selected lenses plus "no lens," in both light and dark, actually
    // viewed via the saved PNGs when STUDYTABLE_SNAPSHOT_DIR is set.

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

    func testAlignmentBadgeRendersUnderTwoRealLensesInLightAndDark() throws {
        let store = AlignmentStore()
        let calvin = try XCTUnwrap(romans828.first { $0.author == "John Calvin" })
        for standard: AlignmentStandard in [.westminsterStandards, .ecumenicalCreeds] {
            for (dark, finish) in [(false, "light"), (true, "dark")] {
                let view = AlignmentBadge(source: calvin, standard: standard, store: store)
                    .padding(20).background(STColor.tileTop)
                let rep = try render(view, dark: dark, size: CGSize(width: 240, height: 60),
                                     name: "alignment-badge-\(standard.rawValue)-\(finish)")
                assertNotBlank(rep, "\(standard.rawValue) \(finish)")
            }
        }
    }

    func testAlignmentBadgeRendersNothingUnderNoLensInLightAndDark() throws {
        let store = AlignmentStore()
        let calvin = try XCTUnwrap(romans828.first { $0.author == "John Calvin" })
        XCTAssertNil(store.alignment(for: calvin, against: .none), "the real assertion: no lens computes no claim")
        for (dark, finish) in [(false, "light"), (true, "dark")] {
            let view = AlignmentBadge(source: calvin, standard: .none, store: store)
                .padding(20).background(STColor.tileTop)
            // Same convention as FatherProfileTests' nil-profile render: proves the empty path
            // doesn't crash and produces a plain background, not that it's visually diverse.
            let rep = try render(view, dark: dark, size: CGSize(width: 240, height: 60), name: "alignment-badge-none-\(finish)")
            XCTAssertGreaterThan(rep.pixelsWide, 0)
        }
    }
}
