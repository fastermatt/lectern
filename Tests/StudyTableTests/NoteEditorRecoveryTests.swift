import AppKit
import SwiftUI
import XCTest
@testable import StudyTable

@MainActor
final class NoteEditorRecoveryTests: XCTestCase {
    private func settle(_ host: NSView) {
        for _ in 0..<5 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        }
    }

    private func textViews(in view: NSView) -> [NSTextView] {
        (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap { textViews(in: $0) }
    }

    private func withEditor(_ state: AppState, action: (NSView) throws -> Void) rethrows {
        let host = NSHostingView(rootView: NoteEditor(startsExpanded: true).environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: 480, height: 700)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderBack(nil)
        defer { window.contentView = nil; window.orderOut(nil) }
        settle(host)
        try action(host)
    }

    func testOpenSpecificSermonNoteDoesNotShowFirstNoteAtSamePassage() throws {
        let state = makeOfflineState()
        state.navigate(bookCode: "ROM", chapter: 8, verse: 28)
        let anchor = Anchor(book: "ROM", chapter: 8, verse: 28)
        let first = try XCTUnwrap(state.study.addNote(anchors: [anchor], body: "First unrelated note"))
        let sermon = try XCTUnwrap(state.study.addNote(anchors: [anchor], title: "Sunday sermon", kind: .sermonIdea,
            sections: [NoteSection(key: "points", text: "My sermon outline must remain visible")]))
        withEditor(state) { host in
            XCTAssertTrue(textViews(in: host).contains { $0.string == first.body })
            NotificationCenter.default.post(name: .openStudyNote, object: sermon.id)
            settle(host)
            XCTAssertTrue(textViews(in: host).contains { $0.string == "My sermon outline must remain visible" })
            XCTAssertEqual(state.study.note(id: first.id), first)
            XCTAssertEqual(state.study.note(id: sermon.id), sermon)
        }
    }

    func testOpenRangeNoteWhileReaderIsAtItsFirstVerse() throws {
        let state = makeOfflineState()
        state.navigate(bookCode: "ROM", chapter: 8, verse: 28)
        let anchor = Anchor(book: "ROM", chapter: 8, verses: 28, to: 39)
        let note = try XCTUnwrap(state.study.addNote(anchors: [anchor], body: "Notes on the entire sermon passage"))
        withEditor(state) { host in
            NotificationCenter.default.post(name: .openStudyNote, object: note.id)
            settle(host)
            XCTAssertTrue(textViews(in: host).contains { $0.string == note.body })
            XCTAssertEqual(state.study.note(id: note.id)?.anchors, [anchor])
        }
    }

    func testOpenNoteWhileNotebookIsHiddenRetainsRequestUntilItMounts() throws {
        let state = makeOfflineState()
        state.focusMode = true
        state.showNotes = false
        state.showStudyDesk = false
        let note = try XCTUnwrap(state.study.addNote(anchors: [Anchor(book: "LUK", chapter: 15, verses: 11, to: 32)],
            title: "Sunday sermon", kind: .sermonIdea, sections: [NoteSection(key: "points", text: "The lost son returns")]))
        XCTAssertTrue(state.openStudyNote(note.id))
        XCTAssertFalse(state.focusMode)
        XCTAssertTrue(state.showNotes && state.showStudyDesk)
        withEditor(state) { host in
            XCTAssertTrue(textViews(in: host).contains { $0.string == "The lost son returns" })
            XCTAssertEqual(state.study.note(id: note.id), note)
        }
    }

    func testOpenFromAnotherPassageAndReopenSameSermonPreservesBothNotes() throws {
        let state = makeOfflineState()
        state.navigate(bookCode: "JHN", chapter: 3, verse: 16)
        let first = try XCTUnwrap(state.study.addNote(anchors: [Anchor(book: "JHN", chapter: 3, verse: 16)], body: "John notes"))
        let sermon = try XCTUnwrap(state.study.addNote(anchors: [Anchor(book: "ROM", chapter: 8, verse: 28)],
            kind: .sermonIdea, sections: [NoteSection(key: "points", text: "Romans sermon outline")]))
        withEditor(state) { host in
            XCTAssertTrue(state.openStudyNote(sermon.id))
            settle(host)
            XCTAssertTrue(textViews(in: host).contains { $0.string == "Romans sermon outline" })
            let request = state.requestedStudyNote
            XCTAssertTrue(state.openStudyNote(sermon.id))
            XCTAssertNotEqual(state.requestedStudyNote, request)
            settle(host)
            XCTAssertEqual(state.study.note(id: first.id), first)
            XCTAssertEqual(state.study.note(id: sermon.id), sermon)
        }
    }

    func testNativeTypingSavesBeforePassageChangesAndSurvivesReload() throws {
        let state = makeOfflineState()
        state.navigate(bookCode: "ROM", chapter: 8, verse: 28)
        let anchor = Anchor(book: "ROM", chapter: 8, verse: 28)
        try withEditor(state) { host in
            let editor = try XCTUnwrap(textViews(in: host).first { $0.isEditable })
            editor.insertText("Sermon preparation must persist", replacementRange: NSRange(location: 0, length: 0))
            XCTAssertEqual(state.study.notes(exactlyAt: anchor).first?.body, "Sermon preparation must persist")
            state.navigate(bookCode: "JHN", chapter: 3, verse: 16)
            settle(host)
            let reload = StudyStore(directory: state.study.directory)
            XCTAssertEqual(reload.notes(exactlyAt: anchor).first?.body, "Sermon preparation must persist")
            XCTAssertTrue(reload.notes(exactlyAt: Anchor(book: "JHN", chapter: 3, verse: 16)).isEmpty)
        }
    }

    func testInvalidOrDeletedNoteRequestDoesNotNavigate() throws {
        let state = makeOfflineState()
        let passage = state.passage
        XCTAssertFalse(state.openStudyNote(UUID()))
        XCTAssertEqual(state.passage, passage)
        let note = try XCTUnwrap(state.study.addNote(anchors: [Anchor(book: "ROM", chapter: 8, verse: 28)], body: "Deleted note"))
        state.study.deleteNote(note.id)
        XCTAssertFalse(state.openStudyNote(note.id))
        XCTAssertEqual(state.passage, passage)
        XCTAssertTrue(state.study.recentlyDeleted.contains { $0.id == note.id })
    }

    func testLibrarySearchRetainsExactNoteIdentityForOpening() throws {
        let state = makeOfflineState()
        let note = try XCTUnwrap(state.study.addNote(anchors: [Anchor(book: "ROM", chapter: 8, verses: 28, to: 39)],
            title: "Sermon search", kind: .sermonIdea, sections: [NoteSection(key: "points", text: "A distinctive sermon outline")]))
        let result = try LibraryTextSearch.search(query: "distinctive", scope: .notes, offset: 0,
            studyRoot: nil, books: [], notes: state.study.allNotes, historicRoot: nil, includeResearch: false)
        let hit = try XCTUnwrap(result.hits.first)
        XCTAssertEqual(hit.noteID, note.id)
        XCTAssertTrue(state.openStudyNote(try XCTUnwrap(hit.noteID)))
        withEditor(state) { host in
            XCTAssertTrue(textViews(in: host).contains { $0.string == "A distinctive sermon outline" })
            XCTAssertEqual(state.study.note(id: note.id), note)
        }
    }
}
