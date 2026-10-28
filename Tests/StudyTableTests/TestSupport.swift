import Foundation
import AppKit
import os
import XCTest
import StudyTableCore
@testable import StudyTable

enum TestPaths {
    /// Project root, derived from this file's location (Tests/StudyTableTests/TestSupport.swift).
    static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let isPublicSource = FileManager.default.fileExists(atPath: root.appendingPathComponent("Sources/StudyTable/Resources/public-resource-report.json").path)
    static let scriptureSource = root.appendingPathComponent("scripture-source")
    static let scripturePacks = root.appendingPathComponent("Sources/StudyTable/Resources/Scripture")
}

/// All 66 study indexes, decoded once per test run.
@MainActor
enum Corpus {
    static let store = StudyResourceStore()
    static let byBook: [String: [StudySource]] = {
        Dictionary(uniqueKeysWithValues: Canon.bookCodes.map { ($0, store.entries(bookCode: $0)) })
    }()
    static var all: [StudySource] { Canon.bookCodes.flatMap { byBook[$0] ?? [] } }
}

func temporaryDirectory(_ name: String = "st") -> URL {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("\(name)-\(UUID().uuidString)", isDirectory: true)
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Records requests and answers from a closure. Sendable so it can back an HTTPTransport.
final class MockNetwork: @unchecked Sendable {
    private let log = OSAllocatedUnfairLock<[URLRequest]>(initialState: [])
    let handler: @Sendable (URLRequest) throws -> (Int, Data)

    init(_ handler: @escaping @Sendable (URLRequest) throws -> (Int, Data)) { self.handler = handler }

    var requests: [URLRequest] { log.withLock { $0 } }

    var transport: HTTPTransport {
        { [self] request in
            log.withLock { $0.append(request) }
            let (status, data) = try handler(request)
            let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
            return (data, response)
        }
    }
}

final class TestClock: Sendable {
    private let current: OSAllocatedUnfairLock<Date>
    init(_ date: Date = Date()) { current = OSAllocatedUnfairLock(initialState: date) }
    var now: Date { current.withLock { $0 } }
    func advance(days: Double) { current.withLock { $0 = $0.addingTimeInterval(days * 86_400) } }
    func advance(seconds: Double) { current.withLock { $0 = $0.addingTimeInterval(seconds) } }
}

@MainActor
func makeOfflineState(keys: @escaping @Sendable (OnlineProvider) -> String? = { _ in nil }) -> AppState {
    let cache = OnlineChapterCache(directory: temporaryDirectory("cache"))
    let service = OnlineTranslationService(
        cache: cache, transport: { _ in throw URLError(.notConnectedToInternet) },
        idStore: BibleIDStore(defaultsKey: "test.ids.\(UUID().uuidString)"), keyReader: keys)
    let state = AppState(library: ScriptureLibrary(), studyResources: StudyResourceStore(), online: service, defaults: ephemeralDefaults(), notes: ephemeralNotes(), resourceBooks: ResourceBookLibrary(root: temporaryDirectory("resource-books")))
    // All layout preferences use the injected suite; never change the reader's workspace.
    state.hasSeenIntro = true
    state.applyPreset(.study)
    state.fontSize = 20
    state.lineSpacing = 8
    state.showResearchTier = false
    return state
}

/// A throwaway preferences store so tests never read or write the user's real defaults.
func ephemeralDefaults() -> UserDefaults {
    let suite = "studytable.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return defaults
}

/// A throwaway study store so tests never read or write the user's real
/// ~/Library/Application Support/StudyTable/ (study.json / notes.json).
@MainActor
func ephemeralStudy(clock: @escaping () -> Date = Date.init) -> StudyStore {
    StudyStore(directory: temporaryDirectory("study"), clock: clock)
}

/// Pre-0.10 name; existing tests call this.
@MainActor
func ephemeralNotes() -> StudyStore { ephemeralStudy() }

/// Fixed 2x backing pixels make snapshots independent of the host's physical display.
/// Keep the logical point size so AppKit draws at the intended scale.
@MainActor
func snapshotBitmap(of view: NSView) throws -> NSBitmapImageRep {
    let size = view.bounds.size
    let rep = try XCTUnwrap(NSBitmapImageRep(bitmapDataPlanes: nil,
        pixelsWide: Int(size.width * 2), pixelsHigh: Int(size.height * 2),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
    rep.size = size
    view.cacheDisplay(in: view.bounds, to: rep)
    return rep
}
