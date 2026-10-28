import AppKit
import SwiftUI
import XCTest
@testable import StudyTable

@MainActor
final class DeskIntegrationTests: XCTestCase {
    func testFocusedWordIsBoundToPassageNotJustIndex() {
        let selection = InterlinearSelection()
        selection.focus(wordIndex: 2, passage: "JHN.3.16")
        XCTAssertEqual(selection.focusedIndex(for: "JHN.3.16"), 2)
        XCTAssertNil(selection.focusedIndex(for: "ROM.8.28"))
        XCTAssertNotEqual(InterlinearSelection.rowID(passage: "JHN.3.16", index: 2),
                          InterlinearSelection.rowID(passage: "ROM.8.28", index: 2))
    }

    func testLCDRevealRestoresHiddenToolAndDeskWithoutChangingOtherSections() {
        let state = makeOfflineState()
        state.navigate(bookCode: "ROM", chapter: 8, verse: 28)
        state.showStudyDesk = false
        state.focusMode = true
        state.setDeskSectionVisible(.originalLanguage, false)
        state.setDeskSectionVisible(.topics, false)
        let selection = InterlinearSelection()
        selection.reveal(wordIndex: 3, state: state)
        XCTAssertTrue(state.showStudyDesk)
        XCTAssertFalse(state.focusMode)
        XCTAssertTrue(state.visibleDeskSections.contains(.originalLanguage))
        XCTAssertFalse(state.visibleDeskSections.contains(.topics))
        XCTAssertEqual(selection.focusedIndex(for: "ROM.8.28"), 3)
    }

    func testIntegratedDeskRendersFocusedGreekAndHebrewInBothFinishes() throws {
        defer { InterlinearSelection.shared.focus(wordIndex: 0) }
        for dark in [false, true] {
            for (book, chapter, verse) in [("ROM", 8, 28), ("GEN", 1, 1)] {
                let state = makeOfflineState()
                state.navigate(bookCode: book, chapter: chapter, verse: verse)
                InterlinearSelection.shared.reveal(wordIndex: 2, state: state)
                let defaults = ephemeralDefaults()
                let view = SourcesPane().tileFace().environmentObject(state).defaultAppStorage(defaults)
                    .environment(\.colorScheme, dark ? .dark : .light)
                    .frame(width: 340, height: 700)
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(x: 0, y: 0, width: 340, height: 700)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                window.contentView = host
                window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
                window.orderBack(nil)
                for _ in 0..<6 {
                    host.layoutSubtreeIfNeeded()
                    RunLoop.main.run(until: Date().addingTimeInterval(0.1))
                }
                let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                XCTAssertGreaterThan(rep.pixelsWide, 0)
                if let directory = ProcessInfo.processInfo.environment["STUDYTABLE_SNAPSHOT_DIR"] {
                    let url = URL(fileURLWithPath: directory, isDirectory: true)
                    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
                    try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                        .write(to: url.appendingPathComponent("desk-focus-\(book)-\(dark ? "dark" : "light").png"))
                }
                window.orderOut(nil)
            }
        }
    }
}
