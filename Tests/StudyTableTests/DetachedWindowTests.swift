import AppKit
import SwiftUI
import XCTest
@testable import StudyTable

private struct TestNotebookDock: View {
    @EnvironmentObject var state: AppState
    var body: some View {
        if !state.detachedPanels.contains(.notes) { NoteEditor(startsExpanded: true) }
        else { Text("Notebook detached") }
    }
}

@MainActor
final class DetachedWindowTests: XCTestCase {
    private func settle(_ view: NSView) {
        for _ in 0..<5 {
            view.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.06))
        }
    }
    private func textViews(_ view: NSView) -> [NSTextView] {
        (view as? NSTextView).map { [$0] } ?? view.subviews.flatMap(textViews)
    }
    private func state() -> AppState {
        let state = makeOfflineState()
        state.navigate(bookCode: "ROM", chapter: 8, verse: 28)
        state.detachedWindows.presentsWindows = false
        return state
    }
    private func withDock(_ state: AppState, _ action: (NSView) throws -> Void) rethrows {
        let host = NSHostingView(rootView: TestNotebookDock().environmentObject(state))
        host.frame = NSRect(x: 0, y: 0, width: 500, height: 700)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderBack(nil)
        defer { state.detachedWindows.redockAll(); window.contentView = nil; window.orderOut(nil) }
        settle(host)
        try action(host)
    }

    func testDetachAndReturnPreserveUnsavedTitleAndTemplateWithoutGhostNotes() throws {
        let state = state()
        try withDock(state) { dock in
            state.notebook.title = "Unsaved sermon title"
            state.notebook.kind = .sermonIdea
            state.detachedWindows.detach(.notes)
            let window = try XCTUnwrap(state.detachedWindows.window(for: .notes))
            settle(try XCTUnwrap(window.contentView))
            XCTAssertEqual(state.notebook.title, "Unsaved sermon title")
            XCTAssertEqual(state.notebook.kind, .sermonIdea)
            XCTAssertTrue(state.study.allNotes.isEmpty)
            state.navigate(bookCode: "JHN", chapter: 3, verse: 16)
            settle(try XCTUnwrap(window.contentView))
            XCTAssertEqual(state.notebook.title, "Unsaved sermon title")
            window.close()
            settle(dock)
            XCTAssertEqual(state.selectedBookCode, "ROM")
            XCTAssertEqual(state.notebook.title, "Unsaved sermon title")
            XCTAssertEqual(state.notebook.kind, .sermonIdea)
            XCTAssertTrue(state.study.allNotes.isEmpty)
        }
    }

    func testPinnedSermonEditsSaveThroughOneStoreAndReturnToSameNote() throws {
        let state = state()
        let anchor = Anchor(book: "ROM", chapter: 8, verses: 28, to: 39)
        let note = try XCTUnwrap(state.study.addNote(anchors: [anchor], kind: .sermonIdea,
            sections: [NoteSection(key: "points", text: "Sermon outline")]))
        state.openStudyNote(note.id)
        try withDock(state) { dock in
            state.detachedWindows.detach(.notes)
            let view = try XCTUnwrap(state.detachedWindows.window(for: .notes)?.contentView)
            settle(view)
            state.navigate(bookCode: "JHN", chapter: 3, verse: 16)
            settle(view)
            let editor = try XCTUnwrap(textViews(view).first { $0.string == "Sermon outline" })
            editor.insertText(" expanded", replacementRange: NSRange(location: editor.string.utf16.count, length: 0))
            XCTAssertEqual(state.study.note(id: note.id)?.sections.first { $0.key == "points" }?.text, "Sermon outline expanded")
            state.detachedWindows.redock(.notes)
            settle(dock)
            XCTAssertTrue(textViews(dock).contains { $0.string == "Sermon outline expanded" })
            XCTAssertEqual(state.study.allNotes.count, 1)
            XCTAssertEqual(StudyStore(directory: state.study.directory).note(id: note.id)?.sections.first { $0.key == "points" }?.text, "Sermon outline expanded")
        }
    }

    func testUnpinFollowsBibleWithoutChangingSavedSermon() throws {
        let state = state()
        let note = try XCTUnwrap(state.study.addNote(anchors: [Anchor(book: "ROM", chapter: 8, verse: 28)], body: "Pinned sermon"))
        try withDock(state) { _ in
            state.detachedWindows.detach(.notes)
            let view = try XCTUnwrap(state.detachedWindows.window(for: .notes)?.contentView)
            settle(view)
            state.navigate(bookCode: "JHN", chapter: 3, verse: 16)
            settle(view)
            XCTAssertEqual(state.notebook.currentNoteID, note.id)
            state.notebook.isPinned = false
            settle(view)
            XCTAssertNil(state.notebook.currentNoteID)
            XCTAssertEqual(state.notebook.loadedAnchor, state.selectedAnchor)
            XCTAssertEqual(state.study.note(id: note.id), note)
        }
    }

    func testExplicitOpenSelectsNewSermonInExistingDetachedWindow() throws {
        let state = state()
        let note = try XCTUnwrap(state.study.addNote(anchors: [Anchor(book: "JHN", chapter: 3, verse: 16)], body: "Requested sermon"))
        try withDock(state) { _ in
            state.detachedWindows.detach(.notes)
            let window = try XCTUnwrap(state.detachedWindows.window(for: .notes))
            settle(try XCTUnwrap(window.contentView))
            XCTAssertTrue(state.openStudyNote(note.id))
            settle(try XCTUnwrap(window.contentView))
            XCTAssertTrue(state.detachedWindows.window(for: .notes) === window)
            XCTAssertEqual(state.notebook.currentNoteID, note.id)
            XCTAssertTrue(textViews(try XCTUnwrap(window.contentView)).contains { $0.string == note.body })
            XCTAssertEqual(state.study.note(id: note.id), note)
        }
    }

    func testAllPanelsDetachOnceAndCloseBackIntoWorkspace() throws {
        let state = state()
        defer { state.detachedWindows.redockAll() }
        for panel in DetachedPanel.allCases {
            state.detachedWindows.detach(panel)
            let window = try XCTUnwrap(state.detachedWindows.window(for: panel))
            state.detachedWindows.detach(panel)
            XCTAssertTrue(state.detachedWindows.window(for: panel) === window)
            XCTAssertTrue(window.styleMask.contains(.resizable))
            XCTAssertTrue(state.detachedPanels.contains(panel))
        }
        XCTAssertFalse(state.hasDockedStudyDesk)
        state.detachedWindows.redockAll()
        XCTAssertTrue(state.detachedPanels.isEmpty)
        XCTAssertTrue(state.hasDockedStudyDesk)
        for panel in DetachedPanel.allCases { XCTAssertNil(state.detachedWindows.window(for: panel)) }
    }

    func testEditsFromAnotherStudySurfaceRefreshSharedNotebookBeforeReturning() throws {
        let state = state()
        let note = try XCTUnwrap(state.study.addNote(anchors: [Anchor(book: "ROM", chapter: 8, verse: 28)], body: "Original reflection"))
        try withDock(state) { dock in
            state.detachedWindows.detach(.notes)
            let view = try XCTUnwrap(state.detachedWindows.window(for: .notes)?.contentView)
            settle(view)
            state.study.editNote(note.id) { $0.body = "Updated on another study surface" }
            settle(view)
            XCTAssertEqual(state.notebook.body, "Updated on another study surface")
            state.detachedWindows.redock(.notes)
            settle(dock)
            XCTAssertTrue(textViews(dock).contains { $0.string == "Updated on another study surface" })
        }
    }

    func testFloatingWindowAppearanceTracksWorkspaceChoice() throws {
        let state = state()
        defer { state.detachedWindows.redockAll() }
        state.theme = .dark
        state.detachedWindows.detach(.notes)
        let window = try XCTUnwrap(state.detachedWindows.window(for: .notes))
        XCTAssertEqual(window.appearance?.bestMatch(from: [.aqua, .darkAqua]), .darkAqua)
        state.theme = .light
        settle(try XCTUnwrap(window.contentView))
        XCTAssertEqual(window.appearance?.bestMatch(from: [.aqua, .darkAqua]), .aqua)
    }

    func testReturnToWorkspaceRequestsTheMainScene() throws {
        let state = state()
        var opened: [String] = []
        state.openSceneWindow = { opened.append($0) }
        state.detachedWindows.detach(.notes)
        XCTAssertNotNil(state.detachedWindows.window(for: .notes))
        // The window was created offscreen; only the injected scene callback runs here.
        state.detachedWindows.presentsWindows = true
        state.detachedWindows.redock(.notes)
        XCTAssertEqual(opened, ["workspace"])
        XCTAssertTrue(state.detachedPanels.isEmpty)
    }

    // MARK: 0.22 — windows in layouts and across launches

    private func relaunch(_ defaults: UserDefaults) -> AppState {
        let cache = OnlineChapterCache(directory: temporaryDirectory("cache"))
        let service = OnlineTranslationService(cache: cache, transport: { _ in throw URLError(.notConnectedToInternet) },
            idStore: BibleIDStore(defaultsKey: "test.ids.\(UUID().uuidString)"), keyReader: { _ in nil })
        let state = AppState(library: ScriptureLibrary(), studyResources: StudyResourceStore(), online: service, defaults: defaults,
            notes: ephemeralNotes(), resourceBooks: ResourceBookLibrary(root: temporaryDirectory("resource-books")))
        state.detachedWindows.presentsWindows = false
        return state
    }

    func testLayoutRecordsAndReopensSeparateWindowsWithPinChoice() throws {
        let state = state()
        state.windowsReady = true
        defer { state.detachedWindows.redockAll() }
        state.detachedWindows.detach(.sources)
        state.detachedWindows.detach(.notes)
        state.notebook.isPinned = false
        let recipe = state.workspaceRecipe()
        XCTAssertEqual(recipe.windows?.map(\.panel), ["sources", "notes"])
        XCTAssertEqual(recipe.windows?.last?.pinned, false)
        XCTAssertNil(recipe.windows?.first?.frame, "Offscreen test windows must not record a frame")
        let layout = SavedWorkspace(name: "Two windows", recipe: recipe)
        state.detachedWindows.redockAll()
        state.navigate(bookCode: "GEN", chapter: 1, verse: 1)
        state.openLayout(layout)
        XCTAssertEqual(state.detachedPanels, [.sources, .notes])
        XCTAssertNotNil(state.detachedWindows.window(for: .notes))
        XCTAssertFalse(state.notebook.isPinned)
        XCTAssertEqual(state.selectedBookCode, "ROM"); XCTAssertEqual(state.selectedChapter, 8)
        XCTAssertEqual(state.showStudyDesk, recipe.sources); XCTAssertEqual(state.showNotes, recipe.notes)
    }

    func testLayoutWithoutWindowsReturnsPanesWithoutJumpingToPinnedPassage() throws {
        let state = state()
        state.windowsReady = true
        defer { state.detachedWindows.redockAll() }
        var recipe = state.workspaceRecipe()
        XCTAssertEqual(recipe.windows, [])
        recipe.windows = nil // a layout saved before 0.22
        state.navigate(bookCode: "JHN", chapter: 3, verse: 16)
        state.detachedWindows.detach(.notes)  // pinned to John 3:16
        state.detachedWindows.detach(.bible)
        state.openLayout(SavedWorkspace(name: "Docked", recipe: recipe))
        XCTAssertTrue(state.detachedPanels.isEmpty)
        XCTAssertNil(state.detachedWindows.window(for: .bible))
        XCTAssertEqual(state.selectedBookCode, "ROM", "The layout passage wins over the Notes pin")
        XCTAssertFalse(state.notebook.isPinned)
    }

    func testLayoutsSavedBeforeWindowsStillDecode() throws {
        var recipe = makeOfflineState().workspaceRecipe()
        recipe.windows = nil
        let json = try XCTUnwrap(String(data: JSONEncoder().encode(recipe), encoding: .utf8))
        XCTAssertFalse(json.contains("windows"))
        XCTAssertNil(try JSONDecoder().decode(WorkspaceRecipe.self, from: Data(json.utf8)).windows)
        let withWindows = WorkspaceRecipe(book: "ROM", chapter: 8, verse: 28, rangeEnd: nil, translation: "BSB", library: true,
            sources: true, notes: true, focus: false, sourcesOnLeft: false, mode: "sources", pinnedGuide: nil, order: [],
            hidden: [], banks: [], type: 20, leading: 8, readingRatio: 0.6, notesRatio: 0.65,
            windows: [DetachedWindowRecipe(panel: "bible", frame: [10, 20, 600, 700], pinned: nil)])
        XCTAssertEqual(try JSONDecoder().decode(WorkspaceRecipe.self, from: JSONEncoder().encode(withWindows)), withWindows)
    }

    func testSeparateWindowsReopenAfterRelaunchUnlessTurnedOff() throws {
        let defaults = ephemeralDefaults()
        let first = relaunch(defaults)
        first.windowsReady = true
        first.detachedWindows.detach(.bible)
        first.detachedWindows.detach(.notes)
        XCTAssertEqual(DetachedWindowManager.savedSession(in: defaults).map(\.panel), ["bible", "notes"])

        let second = relaunch(defaults)
        defer { second.detachedWindows.redockAll() }
        XCTAssertTrue(second.detachedPanels.isEmpty, "Windows wait for the workspace scene")
        second.restoreWindowsAtLaunch()
        XCTAssertEqual(second.detachedPanels, [.bible, .notes])
        second.restoreWindowsAtLaunch()
        XCTAssertEqual(second.detachedPanels, [.bible, .notes], "Restoring twice must not duplicate windows")

        first.detachedWindows.redockAll()
        first.detachedWindows.detach(.sources)
        first.reopenDetachedWindows = false
        let third = relaunch(defaults)
        third.restoreWindowsAtLaunch()
        XCTAssertTrue(third.detachedPanels.isEmpty)
        first.detachedWindows.redockAll()
    }

    func testStartupLayoutWindowsWinOverLastSession() throws {
        let defaults = ephemeralDefaults()
        let first = relaunch(defaults)
        first.windowsReady = true
        first.detachedWindows.detach(.notes)
        let id = try XCTUnwrap(first.layouts.save("Startup", recipe: first.workspaceRecipe()))
        first.layouts.setStartup(id)
        first.detachedWindows.redockAll()
        first.detachedWindows.detach(.bible)  // last session: Bible only
        let second = relaunch(defaults)
        defer { second.detachedWindows.redockAll(); first.detachedWindows.redockAll() }
        second.restoreWindowsAtLaunch()
        XCTAssertEqual(second.detachedPanels, [.notes])
        XCTAssertEqual(second.activeLayoutID, id)
    }

    func testSavedFramesAreUsedOnlyWhenReachableOnAScreen() {
        let screen = NSRect(x: 0, y: 0, width: 1440, height: 875)
        XCTAssertEqual(DetachedWindowManager.placeableFrame([100, 100, 600, 700], screens: [screen]), NSRect(x: 100, y: 100, width: 600, height: 700))
        XCTAssertNil(DetachedWindowManager.placeableFrame([3000, 100, 600, 700], screens: [screen]), "Disconnected display")
        XCTAssertNil(DetachedWindowManager.placeableFrame([.nan, 0, 600, 700], screens: [screen]))
        XCTAssertNil(DetachedWindowManager.placeableFrame([0, 0, 600], screens: [screen]))
        let clamped = DetachedWindowManager.placeableFrame([1200, 80, 600, 800], screens: [screen])
        XCTAssertEqual(clamped?.maxX, screen.maxX); XCTAssertEqual(clamped?.maxY, screen.maxY)
        let second = NSRect(x: 1440, y: 0, width: 1920, height: 1080)
        XCTAssertEqual(DetachedWindowManager.placeableFrame([1600, 200, 800, 700], screens: [screen, second])?.minX, 1600)
    }
}
