import XCTest
import Foundation
@testable import StudyTable

@MainActor
final class HistoricWorkTests: XCTestCase {
    private func epub(title: String, chapters: [String]) throws -> Data {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("OPS"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        var manifest = "", spine = ""
        var files = ["META-INF/container.xml": "<container><rootfiles><rootfile full-path='OPS/book.opf'/></rootfiles></container>"]
        for (index, chapter) in chapters.enumerated() {
            manifest += "<item id='c\(index)' href='c\(index).xhtml' media-type='application/xhtml+xml'/>"
            spine += "<itemref idref='c\(index)'/>"
            files["OPS/c\(index).xhtml"] = "<html><body><h2>Chapter \(index + 1)</h2><p>\(chapter)</p></body></html>"
        }
        files["OPS/book.opf"] = "<package xmlns:dc='http://purl.org/dc/elements/1.1/'><metadata><dc:title>\(title)</dc:title><dc:creator>Gutenberg Author</dc:creator></metadata><manifest>\(manifest)</manifest><spine>\(spine)</spine></package>"
        for (path, text) in files { try Data(text.utf8).write(to: root.appendingPathComponent(path)) }
        let archive = root.appendingPathComponent("book.epub")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = root; process.arguments = ["-qr", archive.path, "META-INF", "OPS"]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return try Data(contentsOf: archive)
    }
    private func temporaryEPUB() -> URL { FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub") }

    func testCatalogUsesOneTrustedHostAndKnownProfiles() {
        XCTAssertEqual(Set(HistoricWork.catalog.map(\.id)).count, HistoricWork.catalog.count)
        XCTAssertFalse(HistoricWork.catalog.contains { $0.id == "pg-77576" }, "The Apostolic Fathers volume is already included offline")
        for work in HistoricWork.catalog {
            XCTAssertEqual(work.url.scheme, "https"); XCTAssertEqual(work.url.host, "www.gutenberg.org")
            XCTAssertTrue(work.id.hasPrefix("pg-"))
            XCTAssertFalse(work.expectedTitle.isEmpty)
            if let name = work.profile {
                XCTAssertNotNil(FatherProfileStore.shared.profile(forAuthor: name), "Missing sourced profile for \(name)")
            }
        }
        for shelf in HistoricWork.Shelf.allCases { XCTAssertFalse(HistoricWork.works(on: shelf).isEmpty) }
        XCTAssertNotNil(ResourceCatalog.resources(in: .downloads).first { $0.id == "historic-works" })
        XCTAssertEqual(DiscoverableResource.catalog.filter { $0.id.hasPrefix("pg-") }.count, HistoricWork.catalog.count)
    }

    func testConvertedWorkKeepsCatalogueIdentityAndRecordsProvenance() throws {
        let work = try XCTUnwrap(HistoricWork.catalog.first { $0.ebook == 3296 })
        let tmp = temporaryEPUB(); defer { try? FileManager.default.removeItem(at: tmp) }
        let book = try HistoricWorkFiles.convert(work, data: epub(title: "The Confessions of St. Augustine", chapters: ["Great art Thou, O Lord", "Book two"]), temporary: tmp)
        XCTAssertEqual(book.id, "pg-3296")
        XCTAssertEqual(book.title, "The Confessions"); XCTAssertEqual(book.author, "Augustine of Hippo")
        XCTAssertEqual(book.source, "https://www.gutenberg.org/ebooks/3296")
        XCTAssertTrue(book.attribution.contains("Pusey")); XCTAssertTrue(book.attribution.contains("SHA-256"))
        XCTAssertTrue(book.attribution.contains("not doctrinal endorsement") || book.attribution.contains("does not mean doctrinal endorsement"))
        XCTAssertEqual(book.articles.count, 2)
    }

    func testMismatchedOrEmptyDownloadsInstallNothing() throws {
        let work = try XCTUnwrap(HistoricWork.catalog.first { $0.ebook == 45304 })
        let tmp = temporaryEPUB(); defer { try? FileManager.default.removeItem(at: tmp) }
        XCTAssertThrowsError(try HistoricWorkFiles.convert(work, data: epub(title: "Some Other Book", chapters: ["a", "b"]), temporary: tmp))
        XCTAssertThrowsError(try HistoricWorkFiles.convert(work, data: epub(title: "The City of God, Volume I", chapters: ["only one"]), temporary: tmp))
        XCTAssertThrowsError(try HistoricWorkFiles.convert(work, data: Data("not a zip".utf8), temporary: tmp))
        // Volume I must not accept Volume II's file and vice versa.
        let volumeTwo = try XCTUnwrap(HistoricWork.catalog.first { $0.ebook == 45305 })
        XCTAssertThrowsError(try HistoricWorkFiles.convert(volumeTwo, data: epub(title: "The City of God, Volume I", chapters: ["a", "b"]), temporary: tmp))
    }

    func testInstalledWorkIsStoredOnceAndListedInTheLibrary() async throws {
        let work = try XCTUnwrap(HistoricWork.catalog.first { $0.ebook == 1653 })
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let tmp = temporaryEPUB(); defer { try? FileManager.default.removeItem(at: tmp) }
        let book = try HistoricWorkFiles.convert(work, data: epub(title: "The Imitation of Christ", chapters: ["Of the imitation of Christ", "Of humility"]), temporary: tmp)
        try ResourceBookFiles.store(book, root: root)
        XCTAssertThrowsError(try ResourceBookFiles.store(book, root: root), "An installed work is never overwritten")
        let library = ResourceBookLibrary(root: root)
        await library.load()
        let titles = library.books.map(\.title)
        XCTAssertEqual(titles, ["The Imitation of Christ"])
    }

    func testUntrustedWorkIsRejectedBeforeAnyRequest() async {
        let forged = HistoricWork(ebook: 999_999, title: "Forged", author: "Nobody", edition: "None", shelf: .classics, detail: "", expectedTitle: "Forged")
        do { _ = try await HistoricWorkFiles.fetch(forged); XCTFail("Must reject a work outside the catalogue") } catch {}
    }

    /// Explicit network smoke test: STUDYTABLE_TEST_DOWNLOADS=1 swift test --filter HistoricWorkTests/testLiveCatalogue
    func testLiveCatalogue() async throws {
        guard ProcessInfo.processInfo.environment["STUDYTABLE_TEST_DOWNLOADS"] == "1" else {
            throw XCTSkip("Live network downloads require explicit opt-in")
        }
        for work in HistoricWork.catalog {
            do {
                let data = try await HistoricWorkFiles.fetch(work)
                let tmp = temporaryEPUB(); defer { try? FileManager.default.removeItem(at: tmp) }
                let book = try HistoricWorkFiles.convert(work, data: data, temporary: tmp)
                let characters = book.articles.reduce(0) { $0 + $1.body.count }
                XCTAssertGreaterThan(characters, 100_000 / 4, work.title)
                print("VERIFIED HISTORIC WORK: \(work.id) · \(book.articles.count) sections · \(characters) characters")
            } catch {
                XCTFail("\(work.id) \(work.title) failed: \(error.localizedDescription)")
            }
        }
    }

    func testGutenbergNotesBecomeNumberedParagraphsWithMarkers() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("OPS"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = [
            "META-INF/container.xml": "<container><rootfiles><rootfile full-path='OPS/book.opf'/></rootfiles></container>",
            "OPS/book.opf": "<package xmlns:dc='http://purl.org/dc/elements/1.1/'><metadata><dc:title>Institutes</dc:title></metadata><manifest><item id='a' href='a.xhtml' media-type='application/xhtml+xml'/><item id='n' href='n.xhtml' media-type='application/xhtml+xml'/></manifest><spine><itemref idref='a'/><itemref idref='n'/></spine></package>",
            "OPS/a.xhtml": "<html><body><h1>Chapter I</h1><p>Where there is no\n        vision, the people perish.<a href='n.xhtml#note_2' id='noteref_2'><span>2</span></a> See <a href='http://example.com/#top'>this</a>.</p></body></html>",
            "OPS/n.xhtml": "<html><body><h1>Footnotes</h1><dl><dt><a href='a.xhtml#noteref_2' id='note_2'>2.</a></dt><dd>Prov. xxix.\n 18.</dd></dl></body></html>"
        ]
        for (path, text) in files { try Data(text.utf8).write(to: root.appendingPathComponent(path)) }
        let archive = root.appendingPathComponent("book.epub")
        let zip = Process(); zip.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        zip.currentDirectoryURL = root; zip.arguments = ["-qr", archive.path, "META-INF", "OPS"]
        try zip.run(); zip.waitUntilExit()
        let book = try PersonalBookImporter.read(archive)
        XCTAssertEqual(book.articles[0].paragraphs, ["Chapter I", "Where there is no vision, the people perish.[2] See this."])
        XCTAssertEqual(book.articles[1].paragraphs, ["Footnotes", "[2] Prov. xxix. 18."])
        let hit = try XCTUnwrap(LibraryCitationIndex.build([book]).citing(Anchor(book: "PRO", chapter: 29, verse: 18)).first)
        XCTAssertEqual(hit.paragraph, 1); XCTAssertEqual(hit.footnote, "2")
    }
}

final class WorkLabelTests: XCTestCase {
    func testEveryWorkHasSourcedDescriptiveLabels() {
        for id in HistoricWork.catalog.map(\.id) + ["apostolic-fathers-1870"] {
            guard let labels = WorkLabels.of(id) else { XCTFail("Missing labels for \(id)"); continue }
            XCTAssertFalse(labels.badge.isEmpty); XCTAssertFalse(labels.sources.isEmpty, id)
            XCTAssertTrue(labels.sources.allSatisfy { $0.hasPrefix("https://") }, id)
            XCTAssertTrue(labels.topics.allSatisfy(WorkLabels.topicOrder.contains), "Unknown topic in \(id)")
            XCTAssertFalse(labels.badge.localizedCaseInsensitiveContains("heretic"), "Labels describe; they are not verdicts")
        }
        let lastThings = HistoricWork.catalog.filter { WorkLabels.of($0.id)?.topics.contains("Last things") == true }.map(\.id)
        XCTAssertTrue(lastThings.contains("pg-45305")); XCTAssertTrue(lastThings.contains("pg-24979"))
    }
    func testDispensationalComparisonIsLaterFrameworkNotCouncilVerdict() throws {
        let topic = try XCTUnwrap(ReceptionTopic.topics.first { $0.id == "dispensational-rapture" })
        XCTAssertEqual(topic.kind, .later)
        XCTAssertTrue(topic.limit.contains("no council has ruled"))
        XCTAssertTrue(topic.limit.contains("Pseudo-Ephraem"), "Counter-evidence pastors will meet is presented")
    }
}


@MainActor
final class CatalogSuggestionTests: XCTestCase {
    /// Regenerates the shipped reference index from the catalogue's editions (metadata only).
    func testWriteIndex() throws {
        guard let folder = ProcessInfo.processInfo.environment["STUDYTABLE_WRITE_CITATION_INDEX"] else { throw XCTSkip("Opt-in generator") }
        var books: [ResourceBook] = []
        for work in HistoricWork.catalog {
            let file = URL(fileURLWithPath: folder).appendingPathComponent("pg\(work.ebook).epub")
            books.append(try HistoricWorkFiles.convert(work, data: Data(contentsOf: file), temporary: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")))
        }
        let works = try CatalogCitationIndex.build(books)
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withFullDate]
        let json: [String: Any] = ["schema": 1, "generated": formatter.string(from: Date()),
            "note": "Bible references cited by each optional Project Gutenberg work, with section titles. No text from the works.", "works": works]
        let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Sources/StudyTable/Resources/Reference/historic-citations.json")
        try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys]).write(to: output)
        print("WROTE \(output.path)")
    }

    func testShippedIndexSuggestsUndownloadedWorksAcrossAuthors() throws {
        let index = try XCTUnwrap(CatalogCitationIndex.shared, "historic-citations.json ships with the app")
        XCTAssertEqual(Set(index.works.keys), Set(HistoricWork.catalog.map(\.id)))
        let rev20 = index.suggestions(for: Anchor(book: "REV", chapter: 20, verses: 1, to: 6), excluding: [])
        XCTAssertTrue(rev20.contains { $0.work.id == "pg-45305" }, "City of God II discusses Revelation 20")
        let authors = rev20.map(\.work.author)
        XCTAssertEqual(Array(authors.prefix(Set(authors).count)), Array(NSOrderedSet(array: authors).array as! [String]), "One work per author before repeats")
        XCTAssertFalse(index.suggestions(for: Anchor(book: "REV", chapter: 20, verses: 1, to: 6), excluding: ["pg-45305"]).contains { $0.work.id == "pg-45305" })
        let context = AIContextBuilder.suggestions(for: Anchor(book: "REV", chapter: 20, verses: 1, to: 6), installed: [], budget: 2000)
        XCTAssertTrue(context.contains("NOT downloaded")); XCTAssertLessThanOrEqual(context.utf8.count, 2000)
    }
}
