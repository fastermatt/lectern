import XCTest
import Foundation
@testable import StudyTable
@testable import StudyTableCore

final class DownloadTests: XCTestCase, @unchecked Sendable {
    func testCatalogIsTrustedAndDoesNotOfferRestrictedOrBundledEditions() {
        XCTAssertEqual(Set(BibleDownload.catalog.map(\.id)).count, BibleDownload.catalog.count)
        for entry in BibleDownload.catalog {
            XCTAssertEqual(entry.archiveURL.host, "ebible.org")
            XCTAssertEqual(entry.archiveURL.scheme, "https")
            XCTAssertFalse(["ESV", "NKJV", "NASB", "KJV", "BSB", "WEB"].contains(entry.id))
        }
    }

    func testCorruptArchiveRejected() {
        XCTAssertThrowsError(try BibleArchive.members(Data()))
        XCTAssertThrowsError(try BibleArchive.members(Data(repeating: 0, count: 200)))
    }

    private func zipDirectory(firstName: String = "0.usfm", size: Int = 100, flags: Int = 0, attributes: Int = 0, duplicate: Bool = false) -> Data {
        var result = Data()
        func put(_ value: Int, bytes: Int, at: Int, in data: inout Data) {
            for n in 0..<bytes { data[at + n] = UInt8((value >> (8 * n)) & 255) }
        }
        for index in 0..<66 {
            let name = Data((index == 0 || duplicate ? firstName : "\(index).usfm").utf8)
            var entry = Data(repeating: 0, count: 46)
            put(0x02014b50, bytes: 4, at: 0, in: &entry)
            put(index == 0 ? flags : 0, bytes: 2, at: 8, in: &entry)
            put(index == 0 ? size : 100, bytes: 4, at: 24, in: &entry)
            put(name.count, bytes: 2, at: 28, in: &entry)
            put(index == 0 ? attributes : 0, bytes: 4, at: 38, in: &entry)
            result.append(entry); result.append(name)
        }
        var end = Data(repeating: 0, count: 22)
        put(0x06054b50, bytes: 4, at: 0, in: &end)
        put(66, bytes: 2, at: 8, in: &end); put(66, bytes: 2, at: 10, in: &end)
        put(result.count, bytes: 4, at: 12, in: &end)
        result.append(end)
        return result
    }

    func testZIPDirectorySafetyGates() throws {
        XCTAssertEqual(try BibleArchive.members(zipDirectory()).count, 66)
        for name in ["../escape.usfm", "/absolute.usfm", "folder/../../escape.usfm", "-option.usfm", "wild*.usfm", "back\\slash.usfm"] {
            XCTAssertThrowsError(try BibleArchive.members(zipDirectory(firstName: name)), name)
        }
        XCTAssertThrowsError(try BibleArchive.members(zipDirectory(size: BibleArchive.maximumMember + 1)))
        XCTAssertThrowsError(try BibleArchive.members(zipDirectory(flags: 1)))
        XCTAssertThrowsError(try BibleArchive.members(zipDirectory(attributes: 0xa1ff << 16)))
        XCTAssertThrowsError(try BibleArchive.members(zipDirectory(duplicate: true)))
    }

    func testCancelledDownloadLeavesNoPartialPack() async throws {
        let root = try directory()
        let installer = BibleInstaller(root: root) { _, _ in throw CancellationError() }
        do { try await installer.install(BibleDownload.catalog[0]) { _ in }; XCTFail("must cancel") }
        catch is CancellationError { } catch { XCTFail("Wrong error: \(error)") }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testNoncatalogEditionRejectedBeforeFetch() async throws {
        let root = try directory()
        let installer = BibleInstaller(root: root) { _, _ in XCTFail("must not fetch"); return Data() }
        let edition = BibleDownload(id: "BSB", name: "Untrusted", language: "English", sourceID: "unknown")
        do { try await installer.install(edition) { _ in }; XCTFail("must reject") } catch { }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("study-download-test-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testFailureLeavesNoPartialPack() async throws {
        let root = try directory()
        let installer = BibleInstaller(root: root) { _, _ in Data("not a zip".utf8) }
        do { try await installer.install(BibleDownload.catalog[0]) { _ in }; XCTFail("must reject") } catch { }
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testExistingPackNeverOverwritten() async throws {
        let root = try directory(), edition = BibleDownload.catalog[0]
        let existing = root.appendingPathComponent(edition.id)
        try FileManager.default.createDirectory(at: existing, withIntermediateDirectories: false)
        let sentinel = existing.appendingPathComponent("keep.txt")
        try Data("original".utf8).write(to: sentinel)
        let installer = BibleInstaller(root: root) { _, _ in XCTFail("must not fetch"); return Data() }
        do { try await installer.install(edition) { _ in }; XCTFail("must reject") } catch { }
        XCTAssertEqual(try String(contentsOf: sentinel, encoding: .utf8), "original")
    }

    func testRemovalRejectsUnmanagedAndSymlinkPacks() async throws {
        let root = try directory(), edition = BibleDownload.catalog[0]
        let installer = BibleInstaller(root: root)
        do { try await installer.remove(edition); XCTFail("must reject") } catch { }
        let outside = try directory()
        try Data(edition.id.utf8).write(to: outside.appendingPathComponent(".study-table-download"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent(edition.id), withDestinationURL: outside)
        XCTAssertFalse(BibleInstaller.isManaged(edition, root: root))
        do { try await installer.remove(edition); XCTFail("must reject symlink") } catch { }
        XCTAssertTrue(FileManager.default.fileExists(atPath: outside.path))
    }

    func testRemovalOnlyDeletesManagedEdition() async throws {
        let root = try directory(), edition = BibleDownload.catalog[0]
        let target = root.appendingPathComponent(edition.id)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: false)
        try Data(edition.id.utf8).write(to: target.appendingPathComponent(".study-table-download"))
        try Data("notes".utf8).write(to: root.appendingPathComponent("notes.json"))
        try await BibleInstaller(root: root).remove(edition)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), ["notes.json"])
    }

    /// Explicit network smoke test: real installer, temp-only destination, every catalog entry.
    /// STUDYTABLE_TEST_DOWNLOADS=1 swift test --filter DownloadTests/testLiveCatalog
    func testLiveCatalog() async throws {
        guard ProcessInfo.processInfo.environment["STUDYTABLE_TEST_DOWNLOADS"] == "1" else {
            throw XCTSkip("Live network downloads require explicit opt-in")
        }
        let root = try directory()
        // Optional comma-separated subset, e.g. STUDYTABLE_TEST_DOWNLOAD_IDS=GNV,LSG
        let only = ProcessInfo.processInfo.environment["STUDYTABLE_TEST_DOWNLOAD_IDS"].map { Set($0.split(separator: ",").map(String.init)) }
        for edition in BibleDownload.catalog where only?.contains(edition.id) ?? true {
            do {
                try await BibleInstaller(root: root).install(edition) { _ in }
                let data = try Data(contentsOf: root.appendingPathComponent(edition.id).appendingPathComponent("manifest.json"))
                let manifest = try JSONDecoder().decode(TranslationManifest.self, from: data)
                XCTAssertEqual(manifest.books.count, 66, edition.id)
                XCTAssertEqual(manifest.books.reduce(0) { $0 + $1.chapterCount }, 1189, edition.id)
                XCTAssertTrue(BibleInstaller.isManaged(edition, root: root), edition.id)
                print("VERIFIED OFFLINE DOWNLOAD: \(edition.id)")
            } catch {
                XCTFail("\(edition.id) (\(edition.sourceID)) failed: \(error.localizedDescription)")
            }
        }
    }
}
