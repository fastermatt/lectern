import AppKit
import SwiftUI
import XCTest
@testable import StudyTable

// Covers the Puritan Library feature (browse/download/read EEBO-TCP works, CC0). The TEI parser
// tests deliberately use real EEBO-TCP structure — `<div type="...">` (TEI P5, generic, arbitrary
// nesting), never the numbered `<div1>`/`<div2>` of the older P3/P4 DTD — confirmed by downloading
// and inspecting a real file (`A63066.xml`) while fixing the first version of this parser, which
// was built and tested only against a hand-written `<div1>`/`<div2>` fixture and so silently
// produced zero real sections for every actual download. `<gap><desc>...</desc></gap>` (damage/
// illegible-text annotations) and `<note>` (marginalia) both appear heavily in real files, often
// nested inside a `<p>`, and must never bleed into the reading text.
final class PuritanLibraryTests: XCTestCase {
    // MARK: - Catalogue Loading

    @MainActor
    private func waitForCatalogue(_ service: PuritanLibraryService) async -> PuritanLibraryCatalogue? {
        for _ in 0..<50 {
            if let catalogue = service.catalogue { return catalogue }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return service.catalogue
    }

    @MainActor
    func testCatalogueLoads() async {
        let service = PuritanLibraryService(storageDirectory: temporaryDirectory("puritan"))
        let catalogue = await waitForCatalogue(service)
        XCTAssertNotNil(catalogue)
        XCTAssertEqual(catalogue?.version, 1)
        XCTAssertGreaterThan(catalogue?.works.count ?? 0, 0)
    }

    @MainActor
    func testCatalogueHasExpectedFields() async {
        let service = PuritanLibraryService(storageDirectory: temporaryDirectory("puritan"))
        guard let catalogue = await waitForCatalogue(service), let first = catalogue.works.first else {
            return XCTFail("Catalogue did not load")
        }
        XCTAssertFalse(first.tcpId.isEmpty)
        XCTAssertFalse(first.author.isEmpty)
        XCTAssertFalse(first.title.isEmpty)
    }

    @MainActor
    func testCatalogueGroupingByAuthor() async {
        let service = PuritanLibraryService(storageDirectory: temporaryDirectory("puritan"))
        guard let catalogue = await waitForCatalogue(service) else { return XCTFail("Catalogue did not load") }
        let grouped = catalogue.groupedByAuthor
        XCTAssertGreaterThan(grouped.count, 0)
        for group in grouped { XCTAssertFalse(group.works.isEmpty) }
        let authors = grouped.map(\.author)
        XCTAssertEqual(authors, authors.sorted())
        XCTAssertEqual(authors.count, Set(authors).count)
    }

    @MainActor
    func testCatalogueByTcpId() async {
        let service = PuritanLibraryService(storageDirectory: temporaryDirectory("puritan"))
        guard let catalogue = await waitForCatalogue(service) else { return XCTFail("Catalogue did not load") }
        let byId = catalogue.byTcpId
        XCTAssertEqual(byId.count, catalogue.works.count)
        for work in catalogue.works { XCTAssertEqual(byId[work.tcpId]?.tcpId, work.tcpId) }
    }

    // MARK: - TEI XML Parsing (real EEBO-TCP structure — see file header)

    func testTEIParserExtractsTopLevelDivsAsSections() {
        let xml = """
        <?xml version="1.0"?>
        <TEI.2><text><body>
          <div type="dedication"><head>To the Reader</head><p>Some prefatory remarks.</p></div>
          <div type="commentary"><head>Upon the First Chapter</head><p>Paragraph one text here.</p><p>Paragraph two text here.</p></div>
        </body></text></TEI.2>
        """.data(using: .utf8)!

        guard let work = TEIParser.parse(xml) else { return XCTFail("Parser returned nil") }
        XCTAssertEqual(work.sections.count, 2)
        XCTAssertEqual(work.sections[0].heading, "To the Reader")
        XCTAssertEqual(work.sections[1].heading, "Upon the First Chapter")
        XCTAssertTrue(work.sections[1].body.contains("Paragraph one text here."))
        XCTAssertTrue(work.sections[1].body.contains("Paragraph two text here."))
    }

    func testTEIParserHandlesNestedDivsAsSeparateSectionsWithoutDuplication() {
        // Real files nest to depth 2: a <div type="commentary"> containing several chapter divs.
        let xml = """
        <?xml version="1.0"?>
        <TEI.2><text><body>
          <div type="commentary">
            <head>The Whole Book</head>
            <p>Introductory remarks for the whole book.</p>
            <div type="chapter"><head>Chapter 1</head><p>Chapter one content.</p></div>
            <div type="chapter"><head>Chapter 2</head><p>Chapter two content.</p></div>
          </div>
        </body></text></TEI.2>
        """.data(using: .utf8)!

        guard let work = TEIParser.parse(xml) else { return XCTFail("Parser returned nil") }
        // Three sections: the outer div (its own intro text only) plus both chapters — this is
        // the exact defect the rewrite fixes: the original implementation lost a second nested
        // sibling div's content entirely once the first sibling had been flushed.
        XCTAssertEqual(work.sections.count, 3)
        let headings = work.sections.map(\.heading)
        XCTAssertTrue(headings.contains("The Whole Book"))
        XCTAssertTrue(headings.contains("Chapter 1"))
        XCTAssertTrue(headings.contains("Chapter 2"))
        let outer = work.sections.first { $0.heading == "The Whole Book" }
        XCTAssertEqual(outer?.body, "Introductory remarks for the whole book.")
        XCTAssertFalse(outer?.body.contains("Chapter one") ?? true, "child content leaked into the parent section")
        let ch1 = work.sections.first { $0.heading == "Chapter 1" }
        XCTAssertEqual(ch1?.body, "Chapter one content.")
    }

    func testTEIParserFallsBackToDivTypeAttributeWhenHeadIsMissing() {
        let xml = """
        <?xml version="1.0"?>
        <TEI.2><text><body>
          <div type="table_of_contents"><p>Contents listing.</p></div>
        </body></text></TEI.2>
        """.data(using: .utf8)!

        guard let work = TEIParser.parse(xml) else { return XCTFail("Parser returned nil") }
        XCTAssertEqual(work.sections.first?.heading, "Table Of Contents")
    }

    func testTEIParserFallsBackToUntitledWhenNeitherHeadNorTypeIsPresent() {
        let xml = """
        <?xml version="1.0"?>
        <TEI.2><text><body>
          <div><p>Content with no heading and no type attribute.</p></div>
        </body></text></TEI.2>
        """.data(using: .utf8)!

        guard let work = TEIParser.parse(xml) else { return XCTFail("Parser returned nil") }
        XCTAssertEqual(work.sections.first?.heading, "Untitled section")
    }

    func testTEIParserKeepsHiTagTextInline() {
        let xml = """
        <?xml version="1.0"?>
        <TEI.2><text><body>
          <div type="commentary"><head>Emphasis</head><p>This is <hi>emphasized</hi> text.</p></div>
        </body></text></TEI.2>
        """.data(using: .utf8)!

        guard let work = TEIParser.parse(xml) else { return XCTFail("Parser returned nil") }
        XCTAssertTrue(work.sections.first?.body.contains("emphasized") ?? false)
    }

    func testTEIParserSuppressesGapDescriptionAndMarginalNotesInsideAParagraph() {
        // Both <gap><desc>...</desc></gap> (damage/illegibility annotation) and <note> (marginal
        // note) commonly sit *inside* a real <p> — their text must never leak into the sentence.
        let xml = """
        <?xml version="1.0"?>
        <TEI.2><text><body>
          <div type="commentary"><head>Damaged Leaf</head>
            <p>The word is <gap><desc>2 letters illegible</desc></gap>plain to see<note>a marginal cross-reference</note>.</p>
          </div>
        </body></text></TEI.2>
        """.data(using: .utf8)!

        guard let work = TEIParser.parse(xml) else { return XCTFail("Parser returned nil") }
        let body = work.sections.first?.body ?? ""
        XCTAssertFalse(body.contains("illegible"), "gap/desc text leaked into the reading text")
        XCTAssertFalse(body.contains("marginal cross-reference"), "note text leaked into the reading text")
        XCTAssertTrue(body.contains("plain to see"))
    }

    func testTEIParserFallsBackToWholeDocumentTextWhenNoDivStructureExists() {
        // Some very old/unusual TCP files use no <div> at all. The fallback must be lenient
        // (any non-suppressed character data anywhere), unlike the strict per-section extraction,
        // so a document that doesn't match the expected shape still shows *something*.
        let xml = """
        <?xml version="1.0"?>
        <root><text>Some plaintext content here, not wrapped in div or p at all.</text></root>
        """.data(using: .utf8)!

        guard let work = TEIParser.parse(xml) else { return XCTFail("Parser returned nil") }
        XCTAssertEqual(work.sections.count, 1)
        XCTAssertTrue(work.sections.first?.body.contains("Some plaintext content here") ?? false)
    }

    func testTEIParserReturnsNilOnCompleteFailure() {
        let work = TEIParser.parse("not xml at all".data(using: .utf8)!)
        XCTAssertNil(work)
    }

    // MARK: - Storage and Download

    @MainActor
    func testStorageDirectoryIsCreatedOnFirstDownload() async {
        let tempDir = temporaryDirectory("storage-test")
        let xmlData = "<TEI.2><text><body><div type=\"commentary\"><p>Mock content.</p></div></body></text></TEI.2>".data(using: .utf8)!
        let mock = MockNetwork { _ in (200, xmlData) }
        let service = PuritanLibraryService(storageDirectory: tempDir, transport: mock.transport)
        let entry = PuritanCatalogueEntry(tcpId: "A00000", author: "A", title: "T", partLabel: nil, bibleReference: nil, year: nil, note: nil)

        // `temporaryDirectory()` already creates its directory; what this test actually checks is
        // that a fresh, empty directory has no work file in it until a real download writes one.
        XCTAssertFalse(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("A00000.xml").path))
        await service.downloadAndStore(entry)
        XCTAssertTrue(FileManager.default.fileExists(atPath: tempDir.appendingPathComponent("A00000.xml").path))
    }

    @MainActor
    func testDownloadAndStoreSucceedsAndStateIsDownloadedImmediatelyAfterAwaiting() async {
        // Regression for the original implementation's `DispatchQueue.main.async`-wrapped state
        // mutation inside an already-@MainActor method: that deferred the mutation to a later
        // run-loop turn, so a caller reading `downloadStates` right after `await
        // downloadAndStore(...)` returned could still see the *old* state. This must not race.
        let tempDir = temporaryDirectory("download-test")
        let xmlData = "<TEI.2><text><body><div type=\"commentary\"><head>Test</head><p>Mock content.</p></div></body></text></TEI.2>".data(using: .utf8)!
        let mock = MockNetwork { request in
            request.url?.path.contains("A12345") == true ? (200, xmlData) : (404, Data())
        }
        let service = PuritanLibraryService(storageDirectory: tempDir, transport: mock.transport)
        let entry = PuritanCatalogueEntry(tcpId: "A12345", author: "Test Author", title: "Test Title", partLabel: nil, bibleReference: nil, year: 2000, note: nil)

        await service.downloadAndStore(entry)
        XCTAssertEqual(service.downloadStates["A12345"], .downloaded)
    }

    @MainActor
    func testDownloadFailureIsReportedNotSilentlyDropped() async {
        let tempDir = temporaryDirectory("download-fail-test")
        let mock = MockNetwork { _ in (404, Data()) }
        let service = PuritanLibraryService(storageDirectory: tempDir, transport: mock.transport)
        let entry = PuritanCatalogueEntry(tcpId: "A99999", author: "A", title: "T", partLabel: nil, bibleReference: nil, year: nil, note: nil)

        await service.downloadAndStore(entry)
        guard case .failed(let message) = service.downloadStates["A99999"] else {
            return XCTFail("expected .failed, got \(String(describing: service.downloadStates["A99999"]))")
        }
        XCTAssertFalse(message.isEmpty)
    }

    @MainActor
    func testDeleteDownload() {
        let tempDir = temporaryDirectory("delete-test")
        let service = PuritanLibraryService(storageDirectory: tempDir)
        let tcpId = "A99999"
        let xmlPath = tempDir.appendingPathComponent("\(tcpId).xml")
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try? "fake content".write(to: xmlPath, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: xmlPath.path))

        service.delete(tcpId)

        XCTAssertFalse(FileManager.default.fileExists(atPath: xmlPath.path))
        XCTAssertEqual(service.downloadStates[tcpId], .notDownloaded)
    }

    // MARK: - Work Loading

    @MainActor
    func testLoadWorkFromStorageParsesRealStructureAndFillsInCatalogueMetadata() async {
        let tempDir = temporaryDirectory("load-test")
        let xmlData = """
        <TEI.2><text><body><div type="commentary"><head>Section 1</head><p>Content for section 1.</p></div></body></text></TEI.2>
        """.data(using: .utf8)!
        try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        try? xmlData.write(to: tempDir.appendingPathComponent("A11111.xml"))
        let service = PuritanLibraryService(storageDirectory: tempDir)
        let entry = PuritanCatalogueEntry(tcpId: "A11111", author: "Test", title: "Test Work", partLabel: nil, bibleReference: nil, year: 1999, note: nil)

        let work = await service.loadWork(entry)

        XCTAssertEqual(work?.title, "Test Work")
        XCTAssertEqual(work?.author, "Test")
        XCTAssertEqual(work?.sections.count, 1)
        XCTAssertEqual(work?.sections.first?.heading, "Section 1")
    }

    @MainActor
    func testLoadNonexistentWorkReturnsNilRatherThanCrashing() async {
        let service = PuritanLibraryService(storageDirectory: temporaryDirectory("load-nil-test"))
        let entry = PuritanCatalogueEntry(tcpId: "NONEXISTENT", author: "Test", title: "Test", partLabel: nil, bibleReference: nil, year: nil, note: nil)
        let work = await service.loadWork(entry)
        XCTAssertNil(work)
    }

    // MARK: - Renders (offscreen; light + dark)

    private var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["STUDYTABLE_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    @MainActor
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
        for x in stride(from: 0, to: rep.pixelsWide, by: 7) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 7) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                    distinct.insert(UInt32(c.redComponent * 63) << 12 | UInt32(c.greenComponent * 63) << 6 | UInt32(c.blueComponent * 63))
                }
            }
        }
        XCTAssertGreaterThan(distinct.count, 8, "\(label) rendered blank")
    }

    @MainActor
    func testPuritanListRowRendersInLightAndDark() throws {
        let work = PuritanCatalogueEntry(tcpId: "A94797", author: "John Trapp", title: "A Clavis to the Bible",
                                          partLabel: nil, bibleReference: "Genesis–Deuteronomy", year: 1649, note: nil)
        for (dark, finish) in [(false, "light"), (true, "dark")] {
            let view = PuritanListRow(work: work, downloadState: .notDownloaded, onOpen: {}, onDownload: {}, onDelete: {})
                .padding(8).background(STColor.tileTop)
            let rep = try render(view, dark: dark, size: CGSize(width: 300, height: 50), name: "puritan-row-notdownloaded-\(finish)")
            assertNotBlank(rep, finish)
        }
    }

    @MainActor
    func testPuritanListRowDownloadedStateRenders() throws {
        let work = PuritanCatalogueEntry(tcpId: "A94797", author: "John Trapp", title: "A Clavis to the Bible",
                                          partLabel: nil, bibleReference: "Genesis–Deuteronomy", year: 1649, note: nil)
        let view = PuritanListRow(work: work, downloadState: .downloaded, onOpen: {}, onDownload: {}, onDelete: {})
            .padding(8).background(STColor.tileTop)
        let rep = try render(view, dark: false, size: CGSize(width: 300, height: 50), name: "puritan-row-downloaded")
        assertNotBlank(rep, "downloaded row")
    }

    @MainActor
    func testPuritanReaderViewRendersInLightAndDarkAndAt980pt() throws {
        let work = ParsedPuritanWork(tcpId: "A12345", title: "Test Work", author: "Test Author", sections: [
            PuritanWorkSection(heading: "Section 1", body: "This is the body text for section one."),
            PuritanWorkSection(heading: "Section 2", body: "This is the body text for section two.")
        ])
        let entry = PuritanCatalogueEntry(tcpId: "A12345", author: "Test Author", title: "Test Work", partLabel: nil, bibleReference: nil, year: nil, note: nil)
        for (dark, finish, width) in [(false, "light", 400.0), (true, "dark", 400.0), (false, "980", 980.0)] {
            let view = PuritanReaderView(work: work, entry: entry, selectedSectionId: .constant(nil), onBack: {})
                .environmentObject(makeOfflineState())
            let rep = try render(view, dark: dark, size: CGSize(width: width, height: 300), name: "puritan-reader-\(finish)")
            assertNotBlank(rep, finish)
        }
    }
}
