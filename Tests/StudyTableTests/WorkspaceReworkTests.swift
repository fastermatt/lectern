import XCTest
import AppKit
@testable import StudyTable

@MainActor
final class WorkspaceReworkTests: XCTestCase {
    func testNamedLayoutRestoresPassageToolsAndDividersAndSurvivesRelaunch() throws {
        let state = makeOfflineState()
        let suite = "LayoutTest-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let library = LayoutLibrary(defaults: defaults)
        state.navigate(bookCode: "ROM", chapter: 8, verse: 28)
        state.rangeEndVerse = 30; state.sourcesOnLeft = true; state.readingRatio = 0.43; state.notesRatio = 0.57
        state.deskMode = .sources; state.guideScope.pin(Anchor(book: "JHN", chapter: 3, verse: 16))
        let id = try XCTUnwrap(library.save("Romans study", recipe: state.workspaceRecipe()))
        library.favorite(id); library.setStartup(id); library.rename(id, to: "Sunday")
        let reopened = LayoutLibrary(defaults: defaults)
        XCTAssertEqual(reopened.startup, id); XCTAssertTrue(reopened.layouts[0].favorite)
        XCTAssertEqual(reopened.layouts[0].name, "Sunday")
        state.applyPreset(.reading); state.navigate(bookCode: "GEN", chapter: 1, verse: 1)
        state.openLayout(reopened.layouts[0])
        XCTAssertEqual(state.selectedBookCode, "ROM"); XCTAssertEqual(state.selectedChapter, 8)
        XCTAssertEqual(state.selectedVerse, 28); XCTAssertEqual(state.rangeEndVerse, 30)
        XCTAssertEqual(state.deskMode, .sources); XCTAssertTrue(state.sourcesOnLeft)
        XCTAssertEqual(state.readingRatio, 0.43); XCTAssertEqual(state.notesRatio, 0.57)
        XCTAssertEqual(state.guideScope.explicitAnchor?.book, "JHN")
        reopened.remove(id); XCTAssertNil(reopened.startup)
        XCTAssertTrue(LayoutLibrary(defaults: defaults).layouts.isEmpty)
    }
    func testLibraryRoutesOpenTheCorrectResourceBank() {
        let state = makeOfflineState()
        state.selectedTraditions = []; state.focusMode = true; state.showStudyDesk = false
        state.revealIncludedResource("cross-references")
        XCTAssertEqual(state.deskMode, .sources); XCTAssertTrue(state.selectedTraditions.contains(.crossReferences))
        XCTAssertFalse(state.focusMode); XCTAssertTrue(state.showStudyDesk)
        state.revealIncludedResource("word-study")
        XCTAssertEqual(state.deskMode, .tools); XCTAssertEqual(state.requestedStudyTool, .originalLanguage)
    }
    
    func testCorruptLayoutsAreNotOverwritten() {
        let suite = "LayoutTest-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let data = Data("future-or-damaged-data".utf8)
        defaults.set(data, forKey: "workspace.savedLayouts.v1")
        let library = LayoutLibrary(defaults: defaults)
        XCTAssertNotNil(library.message)
        XCTAssertNil(library.save("New", recipe: makeOfflineState().workspaceRecipe()))
        XCTAssertEqual(defaults.data(forKey: "workspace.savedLayouts.v1"), data)
        defaults.removeObject(forKey: "workspace.savedLayouts.v1")
    }
}

final class ResourceBookTests: XCTestCase {
    func testTyndalePreservesTextAndCrossChapterScope() throws {
        let data = Data("""
        <items><item name="Gen.1.1-2.3" typename="StudyNote"><refs>Gen.1.1-2.3</refs><body><p>A <span>quoted</span> word.</p><p>Next paragraph.</p></body></item></items>
        """.utf8)
        let records = try TyndaleParser.parse(data)
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records[0].body, "A quoted word.\n\nNext paragraph.")
        XCTAssertEqual(records[0].anchor, Anchor(book: "GEN", chapterStart: 1, verseStart: 1, chapterEnd: 2, verseEnd: 3))
        XCTAssertEqual(TyndaleParser.reference("1Jn.3.1")?.book, "1JN")
        XCTAssertEqual(TyndaleParser.reference("Pr.3.5-6")?.book, "PRO")
    }
    func testXMLRejectsEntitiesAndMalformedDocuments() throws {
        XCTAssertThrowsError(try TyndaleParser.parse(Data("<!DOCTYPE items [<!ENTITY secret SYSTEM 'file:///etc/passwd'>]><items>&secret;</items>".utf8)))
        XCTAssertThrowsError(try TyndaleParser.parse(Data("<items><item>".utf8)))
    }
    func testArchivePathResolutionRejectsExternalAndEscapingPaths() {
        XCTAssertNil(PersonalBookImporter.resolve("../../secret.xhtml", relativeTo: "OPS/book.opf"))
        XCTAssertNil(PersonalBookImporter.resolve("https://evil.example/chapter", relativeTo: "OPS/book.opf"))
        XCTAssertNil(PersonalBookImporter.resolve("%2Fetc/passwd", relativeTo: "OPS/book.opf"))
        XCTAssertEqual(PersonalBookImporter.resolve("../Text/one.xhtml#verse", relativeTo: "OPS/book.opf"), "Text/one.xhtml")
    }
    func testPersonalTextRoundTripAndDuplicateProtection() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("My Book.txt")
        try Data("A personal theological study.".utf8).write(to: file)
        let book = try PersonalBookImporter.read(file)
        XCTAssertEqual(book.title, "My Book"); XCTAssertEqual(book.articles.first?.body, "A personal theological study.")
        let target = root.appendingPathComponent("library")
        try ResourceBookFiles.store(book, root: target)
        XCTAssertEqual(try ResourceBookFiles.load(root: target).first?.articles.first?.body, book.articles.first?.body)
        XCTAssertThrowsError(try ResourceBookFiles.store(book, root: target))
        try Data("broken".utf8).write(to: target.appendingPathComponent("damaged.json"))
        let scanned = try ResourceBookFiles.scan(root: target)
        XCTAssertEqual(scanned.books.count, 1); XCTAssertEqual(scanned.unreadable, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.appendingPathComponent("damaged.json").path))
    }
    func testRealPublisherArchives() throws {
        guard let directory = ProcessInfo.processInfo.environment["LECTERN_TYNDALE_FIXTURES"] else { throw XCTSkip("Optional real publisher archives") }
        for resource in OpenResource.catalog {
            let file = URL(fileURLWithPath: directory).appendingPathComponent(resource.id == "tyndale-notes" ? "tyndale-notes.zip" : "tyndale-dictionary.zip")
            let temporary = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
            defer { try? FileManager.default.removeItem(at: temporary) }
            let data = try Data(contentsOf: file)
            let book = try ResourceBookFiles.convert(resource, data: data, temporary: temporary)
            if resource.id == "tyndale-notes" {
                XCTAssertEqual(book.articles.count, 17478)
                let notes = book.articles.filter { $0.id.hasPrefix("StudyNote:") }
                XCTAssertEqual(notes.count, 16923)
                XCTAssertEqual(notes.filter { $0.anchor != nil }.count, notes.count, "Every study note must have a usable passage")
                XCTAssertTrue(book.articles.contains { $0.anchor?.contains(Anchor(book: "ROM", chapter: 8, verse: 28)) == true })
            } else { XCTAssertEqual(book.articles.count, 6120); XCTAssertTrue(book.attribution.contains("2023")) }
            var changed = data; changed[0] ^= 1
            XCTAssertThrowsError(try ResourceBookFiles.convert(resource, data: changed, temporary: temporary))
        }
    }
}

final class LibraryDiscoveryTests: XCTestCase {
    func testLibrarySearchPaginationFullNoteSectionsAndAllWords() throws {
        let book = ResourceBook(id: "fixture", title: "Reference", author: "Test", attribution: "Fixture", source: nil,
            articles: (0..<51).map { .init(id: String($0), title: "Chapter \($0)", body: "Grace and hope together", anchor: nil) })
        let note = Note(title: "My work", body: "Grace with hope", createdAt: Date())
        let first = try LibraryTextSearch.search(query: "hope grace", scope: .all, offset: 0, studyRoot: nil, books: [book], notes: [note], historicRoot: nil, includeResearch: false)
        let next = try LibraryTextSearch.search(query: "hope grace", scope: .all, offset: 40, studyRoot: nil, books: [book], notes: [note], historicRoot: nil, includeResearch: false)
        XCTAssertEqual(first.total, 52); XCTAssertEqual(first.hits.count, 40); XCTAssertEqual(next.hits.count, 12)
        XCTAssertTrue(Set(first.hits.map(\.id)).isDisjoint(with: Set(next.hits.map(\.id))))
        let onlyNotes = try LibraryTextSearch.search(query: "grace", scope: .notes, offset: 0, studyRoot: nil, books: [book], notes: [note], historicRoot: nil, includeResearch: false)
        XCTAssertEqual(onlyNotes.total, 1)
        let noMatch = try LibraryTextSearch.search(query: "grace justice", scope: .all, offset: 0, studyRoot: nil, books: [book], notes: [note], historicRoot: nil, includeResearch: false)
        XCTAssertEqual(noMatch.total, 0)
    }
    func testMorphologyIntersectsLemmaGrammarAndLanguage() throws {
        let word = InterlinearWord(surface: "test", transliteration: "test", gloss: "test", lemma: "ἀγάπη", strongs: ["G26"], morphCode: "N-NSF", morphDescription: "Noun Nominative Singular Feminine", language: .greek)
        XCTAssertTrue(MorphologyQuery(lemma: "g26", morphology: "singular noun", language: "G").matches(word))
        XCTAssertFalse(MorphologyQuery(lemma: "G26", morphology: "verb", language: "G").matches(word))
        XCTAssertFalse(MorphologyQuery(lemma: "G26", morphology: "", language: "H").matches(word))
        XCTAssertTrue(MorphologyQuery(lemma: "ἀγάπη", morphology: "N-NS", language: "").matches(word))
        XCTAssertFalse(MorphologyQuery().hasFilter)
    }
    func testRealMorphologyAndCommentarySearch() throws {
        let morph = try MorphologySearch.search(MorphologyQuery(lemma: "G26", morphology: "noun", language: "G"), root: TestPaths.root.appendingPathComponent("Sources/StudyTable/Resources/Interlinear"), offset: 0)
        XCTAssertGreaterThan(morph.total, 100); XCTAssertEqual(morph.unreadable, 0)
        XCTAssertTrue(morph.hits.allSatisfy { $0.word.strongs.contains { InterlinearStore.baseStrong($0) == "G26" } })
        let search = try LibraryTextSearch.search(query: "justification", scope: .commentary, offset: 0, studyRoot: TestPaths.root.appendingPathComponent("Sources/StudyTable/Resources/Study"), books: [], notes: [], historicRoot: nil, includeResearch: false)
        XCTAssertGreaterThan(search.total, 0); XCTAssertEqual(search.unreadable, 0)
        XCTAssertTrue(search.hits.allSatisfy { $0.anchor != nil })
    }
    
    func testNativeDividerRestoresFraction() async throws {
        await MainActor.run {
            let split = NSSplitView(frame: NSRect(x: 0, y: 0, width: 1000, height: 600))
            split.isVertical = true
            split.addSubview(NSView()); split.addSubview(NSView()); split.adjustSubviews()
            let coordinator = WorkspaceDivider.Coordinator()
            coordinator.connect(split, fraction: 0.67, revision: UUID())
            XCTAssertEqual(split.subviews[0].frame.width, 670, accuracy: 2)
            coordinator.connect(split, fraction: 0.32, revision: UUID())
            XCTAssertEqual(split.subviews[0].frame.width, 320, accuracy: 2)
            coordinator.disconnect()
        }
    }
    func testEPUBReadingOrderMetadataAndNoScriptContent() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("META-INF"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("OPS"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let files = [
            "META-INF/container.xml": "<container><rootfiles><rootfile full-path='OPS/book.opf'/></rootfiles></container>",
            "OPS/book.opf": "<package xmlns:dc='http://purl.org/dc/elements/1.1/'><metadata><dc:title>Owned Book</dc:title><dc:creator>A. Writer</dc:creator></metadata><manifest><item id='one' href='one.xhtml' media-type='application/xhtml+xml'/><item id='two' href='two.xhtml' media-type='application/xhtml+xml'/></manifest><spine><itemref idref='two'/><itemref idref='one'/></spine></package>",
            "OPS/one.xhtml": "<!DOCTYPE html><html><body><h1>First</h1><p>One</p><script>NEVER EXECUTE</script></body></html>",
            "OPS/two.xhtml": "<html><body><h1>Second</h1><p>Two</p></body></html>"
        ]
        for (path, text) in files { try Data(text.utf8).write(to: root.appendingPathComponent(path)) }
        let archive = root.appendingPathComponent("test.epub")
        let process = Process(); process.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        process.currentDirectoryURL = root; process.arguments = ["-qr", archive.path, "META-INF", "OPS"]
        process.standardOutput = FileHandle.nullDevice; process.standardError = FileHandle.nullDevice
        try process.run(); process.waitUntilExit(); XCTAssertEqual(process.terminationStatus, 0)
        let book = try PersonalBookImporter.read(archive)
        XCTAssertEqual(book.title, "Owned Book"); XCTAssertEqual(book.author, "A. Writer")
        XCTAssertEqual(book.articles.map(\.title), ["Second", "First"])
        XCTAssertFalse(book.articles.map(\.body).joined().contains("NEVER EXECUTE"))
        try Data("<encryption/>".utf8).write(to: root.appendingPathComponent("META-INF/encryption.xml"))
        let encrypt = Process(); encrypt.executableURL = URL(fileURLWithPath: "/usr/bin/zip")
        encrypt.currentDirectoryURL = root; encrypt.arguments = ["-q", archive.path, "META-INF/encryption.xml"]
        try encrypt.run(); encrypt.waitUntilExit()
        XCTAssertThrowsError(try PersonalBookImporter.read(archive))
    }
}
