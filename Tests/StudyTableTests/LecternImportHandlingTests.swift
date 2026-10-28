import XCTest
@testable import StudyTable

// LecternImportHandling.swift wires the pure, already-tested `LecternStudyImporter` (S2c) to the
// app's open/drop entry points. These tests exercise that seam only — parsing/dedup/apply
// correctness itself is covered exhaustively in ExportTests.swift — using a real file on disk
// (`.onOpenURL`'s actual input) rather than in-memory `Data`, and confirm a hostile/malformed
// file surfaces a reader-facing message instead of crashing.
@MainActor
final class LecternImportHandlingTests: XCTestCase {
    private let bsb = TranslationInfo(id: "BSB", name: "Berean Standard Bible", delivery: .bundled,
                                       licenseSummary: "Public domain", attribution: "Berean Standard Bible (public domain)")

    private func writeTempFile(_ data: Data) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".lecternstudy")
        try data.write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testValidFileProducesAPreviewFromDisk() throws {
        let store = ephemeralStudy()
        let anchor = Anchor(book: "ROM", chapter: 8, verse: 28)
        _ = store.save(anchor)
        // A second, unsaved anchor makes this a real, non-trivial file.
        let file = LecternStudyWriter.makeFile(kind: .collection, title: "Shared with a friend",
                                                saved: [store.savedPassage(matching: anchor)!,
                                                        SavedPassage(anchor: Anchor(book: "JHN", chapter: 3, verse: 16), createdAt: Date())],
                                                translation: bsb, verses: .empty)
        let url = try writeTempFile(try LecternStudyWriter.encode(file))

        // Import against a *different* fresh store, so nothing in it is a duplicate yet.
        let pending = PendingLecternImport(url: url, into: ephemeralStudy())
        guard case .preview(let preview) = pending.outcome else { return XCTFail("expected a preview, got \(pending.outcome)") }
        XCTAssertEqual(preview.title, "Shared with a friend")
        XCTAssertEqual(preview.newSavedCount, 2)
        XCTAssertEqual(preview.duplicateSavedCount, 0)
        XCTAssertEqual(pending.sourceDescription, url.lastPathComponent)
    }

    func testDuplicateAgainstTheSameStoreIsReportedNotSilentlyMerged() throws {
        let store = ephemeralStudy()
        let anchor = Anchor(book: "ROM", chapter: 8, verse: 28)
        _ = store.save(anchor)
        let file = LecternStudyWriter.makeFile(kind: .collection, title: "Round trip",
                                                saved: [store.savedPassage(matching: anchor)!],
                                                translation: bsb, verses: .empty)
        let url = try writeTempFile(try LecternStudyWriter.encode(file))

        // Import against the SAME store that already has this passage saved.
        let pending = PendingLecternImport(url: url, into: store)
        guard case .preview(let preview) = pending.outcome else { return XCTFail("expected a preview") }
        XCTAssertEqual(preview.newSavedCount, 0)
        XCTAssertEqual(preview.duplicateSavedCount, 1)
    }

    func testHostileFileFailsSafelyWithAReaderFacingMessageNotACrash() throws {
        let url = try writeTempFile(Data("not a lectern study file at all — just garbage bytes {{{".utf8))
        let pending = PendingLecternImport(url: url, into: ephemeralStudy())
        guard case .failed(let message) = pending.outcome else { return XCTFail("expected a failure outcome") }
        XCTAssertFalse(message.isEmpty)
        XCTAssertFalse(message.contains("Optional(")) // never leak a raw Swift error description
    }

    func testMissingFileFailsSafelyRatherThanCrashing() {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".lecternstudy")
        let pending = PendingLecternImport(url: missing, into: ephemeralStudy())
        guard case .failed = pending.outcome else { return XCTFail("expected a failure outcome for a missing file") }
    }

    func testEmptyFileIsPreviewedAsNothingToImportRatherThanBlockedFromImporting() throws {
        let file = LecternStudyWriter.makeFile(kind: .collection, title: "Empty", translation: bsb, verses: .empty)
        let url = try writeTempFile(try LecternStudyWriter.encode(file))
        let pending = PendingLecternImport(url: url, into: ephemeralStudy())
        guard case .preview(let preview) = pending.outcome else { return XCTFail("expected a preview") }
        XCTAssertEqual(preview.totalItems, 0)
    }
}
