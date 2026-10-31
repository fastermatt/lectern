import XCTest
import Foundation
@testable import StudyTable

/// Opt-in, read-only usability walkthrough: a pastor researching whether dispensational
/// distinctives appear in early Christian writers. Uses the app's own search, citation index,
/// and (optionally) its built-in local model path with the exact context buttons the app offers.
///   PASTOR_WALKTHROUGH=1 STUDYTABLE_CITATION_SAMPLES=/folder/of/gutenberg/epubs
///   PASTOR_AI_MODEL_DIR=<folder holding a verified model> PASTOR_AI_RUNTIME=<Helpers/LocalAI>
@MainActor
final class PastorWalkthroughTests: XCTestCase {
    private func libraryBooks() throws -> [ResourceBook] {
        var books = [try PatristicReader.load()]
        if let folder = ProcessInfo.processInfo.environment["STUDYTABLE_CITATION_SAMPLES"] {
            let files = try FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: folder), includingPropertiesForKeys: nil).filter { $0.pathExtension == "epub" }
            for file in files.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                let ebook = Int(file.deletingPathExtension().lastPathComponent.dropFirst(2)) ?? 0
                guard let work = HistoricWork.catalog.first(where: { $0.ebook == ebook }) else { continue }
                books.append(try HistoricWorkFiles.convert(work, data: Data(contentsOf: file), temporary: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")))
            }
        }
        return books
    }

    func testResearchingDispensationalismInTheLibrary() throws {
        guard ProcessInfo.processInfo.environment["PASTOR_WALKTHROUGH"] == "1" else { throw XCTSkip("Opt-in walkthrough") }
        let books = try libraryBooks()
        let index = try LibraryCitationIndex.build(books)
        print("LIBRARY: \(books.count) books, \(index.count) linked citations")
        let passages: [(String, Anchor)] = [
            ("Revelation 20:1-6 (thousand years)", Anchor(book: "REV", chapter: 20, verses: 1, to: 6)),
            ("1 Thessalonians 4:16-17 (caught up)", Anchor(book: "1TH", chapter: 4, verses: 16, to: 17)),
            ("Daniel 9:24-27 (seventy weeks)", Anchor(book: "DAN", chapter: 9, verses: 24, to: 27)),
            ("2 Thessalonians 2:1-12 (man of sin)", Anchor(book: "2TH", chapter: 2, verses: 1, to: 12)),
            ("Matthew 24:21-31 (tribulation, gathering)", Anchor(book: "MAT", chapter: 24, verses: 21, to: 31)),
            ("Romans 11:25-27 (all Israel)", Anchor(book: "ROM", chapter: 11, verses: 25, to: 27)),
            ("Galatians 3:28-29 / 6:16 (Israel of God)", Anchor(book: "GAL", chapter: 6, verse: 16)),
            ("Ephesians 2:14-16 (one new man)", Anchor(book: "EPH", chapter: 2, verses: 14, to: 16))]
        for (label, anchor) in passages {
            let hits = index.citing(anchor)
            print("CITES \(label): \(hits.count)")
            for hit in hits.prefix(6) {
                let text = books.first { $0.id == hit.bookID }?.articles.first { $0.id == hit.articleID }?.paragraphs[safe: hit.paragraph] ?? ""
                let note = hit.footnote.map { " (note \($0))" } ?? ""
                print("   · \(hit.author) — \(hit.bookTitle) — \(hit.articleTitle.prefix(60)) — cites \(hit.reference.split(whereSeparator: \.isWhitespace).joined(separator: " "))\(note)")
                print("     \(ReaderText.snippet(text, terms: [hit.footnote.map { "[\($0)]" } ?? String(hit.reference.prefix(6))], length: 300))")
            }
        }
        for query in ["thousand years", "rapture", "caught up", "tribulation antichrist", "first resurrection", "kingdom Jerusalem rebuilt", "Israel church", "seventy weeks"] {
            let page = try LibraryTextSearch.search(query: query, scope: .books, offset: 0, studyRoot: nil, books: books, notes: [], historicRoot: nil, includeResearch: false)
            print("SEARCH \"\(query)\": \(page.total) paragraphs")
            for hit in page.hits.prefix(4) {
                print("   · \(hit.collection) — \(hit.title.prefix(60))")
                print("     \(ReaderText.snippet(hit.body, terms: ReaderText.terms(query), length: 300))")
            }
        }
    }

    func testAskingTheBuiltInModel() async throws {
        guard let modelDir = ProcessInfo.processInfo.environment["PASTOR_AI_MODEL_DIR"],
              let runtime = ProcessInfo.processInfo.environment["PASTOR_AI_RUNTIME"] else { throw XCTSkip("Opt-in local model walkthrough") }
        let manager = LocalAIManager(root: URL(fileURLWithPath: modelDir), runtime: URL(fileURLWithPath: runtime))
        defer { manager.stop() }
        guard let model = LocalAIModel.catalog.last(where: { manager.installed.contains($0.id) }) else { throw XCTSkip("No verified model in folder") }
        var start = Date()
        manager.start(model)
        while manager.busy { try await Task.sleep(for: .milliseconds(200)) }
        print("AI MODEL \(model.id) ready in \(String(format: "%.1f", Date().timeIntervalSince(start)))s; error: \(manager.error ?? "none")")
        let connection = try XCTUnwrap(manager.connection)
        // Exactly what the app's two Attach buttons produce.
        func context(_ reference: String, guide: Bool) async -> String {
            var text = String(data: await LecternCLI.run(["read", reference, "--translation", "BSB"]).data, encoding: .utf8) ?? ""
            if guide { text += "\nCited study guide (first three entries; totals and truncation flags included):\n" + (String(data: await LecternCLI.run(["guide", reference, "--limit", "3"]).data, encoding: .utf8) ?? "") }
            return text
        }
        // The same library the reader would have after adding the works.
        let root = temporaryDirectory("pastor-ai-library")
        for book in try libraryBooks() where book.id.hasPrefix("pg-") { try ResourceBookFiles.store(book, root: root) }
        let library = ResourceBookLibrary(root: root)
        await library.load(); await library.citationsReady()
        let questions: [(String, String?, String)] = [
            ("What did the early church fathers teach about the thousand years in this passage? Name the fathers and cite their works.", "Revelation 20:1-6", "guide"),
            ("What do these early writers say about the thousand years? Quote and cite only the attached sources, and say where they differ.", "Revelation 20:1-6", "library"),
            ("Do any of the attached writers say the church is caught up before a time of tribulation? Answer only from the attached quotations and cite them.", "1 Thessalonians 4:16-17", "library")]
        for (question, reference, kind) in questions {
            let session = AIChatSession()
            session.draft = question
            if let reference {
                if kind == "library" {
                    let anchor = try XCTUnwrap(LibraryTextSearch.referenceQuery(reference.replacingOccurrences(of: "Revelation", with: "Rev").replacingOccurrences(of: "1 Thessalonians", with: "1 Thess")))
                    session.context = AIContextBuilder.library(library.citations.citing(anchor), passage: reference, books: library, budget: AIContextBuilder.localBudget)
                } else {
                    session.context = AIContextBuilder.fit(await context(reference, guide: true), budget: AIContextBuilder.localBudget)
                }
                print("AI CONTEXT (\(kind)) for \(reference): \(session.context.utf8.count) bytes")
                print(session.context.prefix(1500))
            }
            start = Date()
            session.send(key: manager.key, using: connection, local: true)
            while session.isSending { try await Task.sleep(for: .milliseconds(250)) }
            print("AI Q: \(question) [\(reference ?? "no context")] — \(String(format: "%.1f", Date().timeIntervalSince(start)))s")
            print("AI ERROR: \(session.error ?? "none")")
            print("AI A: \(session.messages.last?.content ?? "")\n")
        }
    }
}
