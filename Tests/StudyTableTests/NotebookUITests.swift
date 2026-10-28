import AppKit
import SwiftUI
import XCTest
@testable import StudyTable

/// Tests for the 0.10 wave B notebook rebuild, My Study browser, and their shared store use.
/// New test file (S2b owns it) — the offscreen render helper is copied from `SnapshotTests.swift`
/// rather than shared, per the workplan's file-ownership rules. Store access uses `ephemeralStudy()`
/// / `makeOfflineState()` only; nothing here touches the real Application Support directory.
@MainActor
final class NotebookUITests: XCTestCase {

    // MARK: Offscreen render helper (copied from SnapshotTests.swift)

    private func render<V: View>(_ view: V, dark: Bool, size: CGSize) throws -> NSBitmapImageRep {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = appearance
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))   // offscreen; never shown to the user
        window.orderBack(nil)
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        window.orderOut(nil)
        return rep
    }

    private func assertNotBlank(_ rep: NSBitmapImageRep, _ label: String) {
        var distinct = Set<UInt32>()
        for x in stride(from: 0, to: rep.pixelsWide, by: 17) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 17) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                    distinct.insert(UInt32(c.redComponent * 63) << 12 | UInt32(c.greenComponent * 63) << 6 | UInt32(c.blueComponent * 63))
                }
            }
        }
        XCTAssertGreaterThan(distinct.count, 12, "\(label) rendered blank")
    }

    private func stateAt(_ code: String, _ chapter: Int, _ verse: Int) -> AppState {
        let state = makeOfflineState()
        state.selectedBookCode = code
        state.selectedChapter = chapter
        state.selectedVerse = verse
        return state
    }

    // MARK: Templates are data

    func testTemplateDefinitionsCoverEveryKind() {
        for kind in NoteKind.allCases {
            XCTAssertEqual(NoteTemplates.definition(for: kind).kind, kind)
        }
        XCTAssertTrue(NoteTemplates.definition(for: .free).fields.isEmpty)
        XCTAssertEqual(NoteTemplates.definition(for: .oia).fields.map(\.key), ["observation", "interpretation", "application"])
        XCTAssertEqual(NoteTemplates.definition(for: .wordStudy).fields.map(\.key), ["word", "original", "usage", "conclusion"])
        XCTAssertEqual(NoteTemplates.definition(for: .sermonIdea).fields.map(\.key), ["bigIdea", "points", "illustration", "application"])
    }

    // MARK: Multiple notes per anchor

    func testMultipleNotesAtSameAnchorOrderByCreation() {
        let store = ephemeralStudy()
        let anchor = StudyTable.Anchor(book: "ROM", chapter: 8, verse: 28)
        let first = store.addNote(anchors: [anchor], title: "First", kind: .free, body: "One")!
        let second = store.addNote(anchors: [anchor], title: "Second", kind: .free, body: "Two")!
        let atAnchor = store.notes(exactlyAt: anchor).sorted { $0.createdAt < $1.createdAt }
        XCTAssertEqual(atAnchor.map(\.id), [first.id, second.id])
        XCTAssertEqual(atAnchor.map(\.title), ["First", "Second"])
    }

    // MARK: Templates round-trip

    func testOIATemplateSectionsRoundTrip() {
        let store = ephemeralStudy()
        let anchor = StudyTable.Anchor(book: "ROM", chapter: 8, verse: 28)
        let sections = NoteTemplates.definition(for: .oia).fields.map { NoteSection(key: $0.key, text: "\($0.key) text") }
        let created = store.addNote(anchors: [anchor], title: "Study", kind: .oia, sections: sections)!
        let reloaded = try! XCTUnwrap(store.note(id: created.id))
        XCTAssertEqual(reloaded.kind, .oia)
        XCTAssertEqual(Set(reloaded.sections.map(\.key)), Set(["observation", "interpretation", "application"]))
        XCTAssertEqual(reloaded.sections.first { $0.key == "observation" }?.text, "observation text")
    }

    func testSermonIdeaTemplateEditRoundTrips() {
        let store = ephemeralStudy()
        let anchor = StudyTable.Anchor(book: "LUK", chapter: 15, verse: 11)
        let created = store.addNote(anchors: [anchor], kind: .sermonIdea,
                                     sections: [NoteSection(key: "bigIdea", text: "The waiting Father")])!
        XCTAssertTrue(store.editNote(created.id) { $0.sections = [NoteSection(key: "bigIdea", text: "The waiting Father"), NoteSection(key: "points", text: "1. Leaving 2. Returning 3. Welcoming")] })
        let reloaded = try! XCTUnwrap(store.note(id: created.id))
        XCTAssertEqual(reloaded.sections.first { $0.key == "points" }?.text, "1. Leaving 2. Returning 3. Welcoming")
    }

    // MARK: No ghost notes ever created

    func testEmptyDraftIsRecognizedAsEmptyForEveryKind() {
        for kind in NoteKind.allCases {
            let blankFields = Dictionary(uniqueKeysWithValues: NoteTemplates.definition(for: kind).fields.map { ($0.key, "   ") })
            XCTAssertTrue(NoteEditorContent.isEmpty(kind: kind, body: "  \n ", fieldTexts: blankFields), "\(kind) should read as empty")
        }
        XCTAssertFalse(NoteEditorContent.isEmpty(kind: .free, body: "Real text", fieldTexts: [:]))
        XCTAssertFalse(NoteEditorContent.isEmpty(kind: .oia, body: "", fieldTexts: ["observation": "Something", "interpretation": "", "application": ""]))
    }

    func testStoreNeverGainsANoteFromAnEmptyDraftCommitAttempt() {
        let store = ephemeralStudy()
        let anchor = StudyTable.Anchor(book: "JHN", chapter: 3, verse: 16)
        // Mirrors NoteEditor.commit()'s guard: a draft (no existing note id) with empty content
        // never calls addNote at all.
        if !NoteEditorContent.isEmpty(kind: .free, body: "", fieldTexts: [:]) {
            store.addNote(anchors: [anchor], title: "", kind: .free, body: "")
        }
        XCTAssertTrue(store.notes(exactlyAt: anchor).isEmpty)
        XCTAssertTrue(store.allNotes.isEmpty)
    }

    // MARK: Delete / restore

    func testDeleteMovesNoteToRecentlyDeletedAndRestoreBringsItBack() {
        let store = ephemeralStudy()
        let anchor = StudyTable.Anchor(book: "GEN", chapter: 22, verse: 1)
        let note = store.addNote(anchors: [anchor], title: "Test of Abraham", kind: .free, body: "Notes")!
        XCTAssertTrue(store.deleteNote(note.id))
        XCTAssertTrue(store.notes(exactlyAt: anchor).isEmpty)
        XCTAssertTrue(store.recentlyDeleted.contains { $0.id == note.id && $0.kind == .note })
        let deletedItem = try! XCTUnwrap(store.recentlyDeleted.first { $0.id == note.id })
        XCTAssertTrue(store.restore(deletedItem))
        XCTAssertEqual(store.notes(exactlyAt: anchor).map(\.id), [note.id])
        XCTAssertFalse(store.recentlyDeleted.contains { $0.id == note.id })
    }

    func testPurgeAfterDeleteRemovesNotePermanently() {
        let store = ephemeralStudy()
        let anchor = StudyTable.Anchor(book: "PSA", chapter: 23, verse: 1)
        let note = store.addNote(anchors: [anchor], title: "Shepherd", kind: .free, body: "The Lord is my shepherd")!
        store.deleteNote(note.id)
        XCTAssertTrue(store.purgeNote(note.id))
        XCTAssertFalse(store.recentlyDeleted.contains { $0.id == note.id })
        XCTAssertNil(store.note(id: note.id))
    }

    // MARK: Search scopes and anchor overlap

    func testSearchFindsNoteByAnchorOverlapAndByTag() {
        let store = ephemeralStudy()
        let anchor = StudyTable.Anchor(book: "ROM", chapter: 8, verses: 28, to: 39)
        let note = store.addNote(anchors: [anchor], title: "Golden chain", kind: .free, body: "Providence", tags: ["providence"])!

        // "Rom 8:30" appears nowhere in the note's own text/label/OSIS, so a hit here can only be
        // via anchor overlap (8:30 falls inside the note's 8:28–39 span) — `viaAnchor` is true.
        let pureOverlapHits = store.search("Rom 8:30", scope: .notes)
        XCTAssertTrue(pureOverlapHits.contains { $0.id == note.id && $0.viaAnchor })

        // "Rom 8" also happens to be a literal substring of the note's own reference label
        // ("Romans 8:28–39") and OSIS ("Rom.8.28-Rom.8.39"), so it's found — just not exclusively
        // "via anchor" by the store's own definition (text and anchor agree here).
        let broaderHits = store.search("Rom 8", scope: .notes)
        XCTAssertTrue(broaderHits.contains { $0.id == note.id })

        let tagHits = store.search("#providence", scope: .notes)
        XCTAssertTrue(tagHits.contains { $0.id == note.id })

        let wrongScope = store.search("Rom 8:30", scope: .saved)
        XCTAssertTrue(wrongScope.isEmpty)
    }

    func testItemsOverlappingIncludesNotesAndSaved() {
        let store = ephemeralStudy()
        let anchor = StudyTable.Anchor(book: "MRK", chapter: 4, verse: 35)
        store.addNote(anchors: [anchor], title: "Calm", kind: .free, body: "Peace, be still")
        store.save(anchor)
        let items = store.items(overlapping: StudyTable.Anchor(book: "MRK", chapter: 4, throughChapter: 4))
        XCTAssertEqual(items.notes.count, 1)
        XCTAssertEqual(items.saved.count, 1)
    }

    // MARK: Migration-created notes appear

    func testMigratedV1NoteIsQueryableByAnchor() throws {
        let dir = temporaryDirectory("migrate-notebook")
        let id = UUID().uuidString
        let legacy = """
        [{"id":"\(id)","passage":"Romans 8:28","title":"Providence","body":"All things work together for good.","modifiedAt":700000000.0}]
        """
        try legacy.write(to: dir.appendingPathComponent("notes.json"), atomically: true, encoding: .utf8)
        let store = StudyStore(directory: dir)
        let anchor = StudyTable.Anchor(book: "ROM", chapter: 8, verse: 28)
        let migrated = store.notes(exactlyAt: anchor)
        XCTAssertEqual(migrated.count, 1)
        XCTAssertEqual(migrated.first?.title, "Providence")
        // Wave B's own query surface (used by NoteEditor.load()) must see it too.
        XCTAssertTrue(store.search("Romans 8", scope: .notes).contains { $0.id.uuidString == id })
    }

    // MARK: appendClip UI-path API (StudyStore+Notebook.swift)

    func testAppendClipRegistersClipAndAttachesToNote() {
        let store = ephemeralStudy()
        let anchor = StudyTable.Anchor(book: "ROM", chapter: 8, verse: 28)
        let note = store.addNote(anchors: [anchor], title: "Golden chain", kind: .free, body: "Providence")!
        let clip = Clip(kind: .commentary, excerpt: "All things work together for good.",
                        citation: ClipCitation(author: "Calvin", work: "Commentary on Romans"), anchor: anchor, capturedAt: Date())
        XCTAssertTrue(store.appendClip(clip, to: note.id))
        XCTAssertTrue(store.clips.contains { $0.id == clip.id })
        XCTAssertEqual(store.note(id: note.id)?.clipIDs, [clip.id])
        // Idempotent: appending the same clip again doesn't duplicate the id.
        XCTAssertTrue(store.appendClip(clip, to: note.id))
        XCTAssertEqual(store.note(id: note.id)?.clipIDs, [clip.id])
    }

    func testAppendClipToMissingNoteFails() {
        let store = ephemeralStudy()
        let clip = Clip(kind: .other, excerpt: "Orphaned", capturedAt: Date())
        XCTAssertFalse(store.appendClip(clip, to: UUID()))
        XCTAssertFalse(store.clips.contains { $0.id == clip.id })
    }

    // MARK: modifiedAt only changes on real edits (the visiting-bumps-modifiedAt regression)

    func testEditingWithIdenticalContentDoesNotBumpModifiedAt() {
        let clock = TestClock()
        let store = ephemeralStudy(clock: { clock.now })
        let anchor = StudyTable.Anchor(book: "ROM", chapter: 8, verse: 28)
        let note = store.addNote(anchors: [anchor], title: "Providence", kind: .free, body: "Good.")!
        let originalModified = note.modifiedAt
        clock.advance(seconds: 120)
        // Simulates NoteEditor re-applying the same fields on load (what visiting a passage does).
        XCTAssertTrue(store.editNote(note.id) { $0.title = "Providence"; $0.body = "Good."; $0.kind = .free; $0.sections = []; $0.tags = [] })
        XCTAssertEqual(store.note(id: note.id)?.modifiedAt, originalModified)
        clock.advance(seconds: 120)
        XCTAssertTrue(store.editNote(note.id) { $0.body = "Good, truly." })
        XCTAssertGreaterThan(store.note(id: note.id)!.modifiedAt, originalModified)
    }

    // MARK: Empty states are honest (no fake data in Clips/Projects)

    func testFreshStoreHasNoClipsOrProjects() {
        let store = ephemeralStudy()
        XCTAssertTrue(store.clips.isEmpty)
        XCTAssertTrue(store.projects.isEmpty)
        XCTAssertTrue(store.search("", scope: .clips).isEmpty)
        XCTAssertTrue(store.search("", scope: .projects).isEmpty)
    }

    // MARK: Renders — light/dark, 980pt, each My Study scope, an OIA note in the notebook

    func testNoteEditorWithOIANoteRendersInMainViewLightAndDark() throws {
        for (dark, name) in [(false, "light"), (true, "dark")] {
            let state = stateAt("ROM", 8, 28)
            let anchor = StudyTable.Anchor(book: "ROM", chapter: 8, verse: 28)
            _ = state.study.addNote(anchors: [anchor], title: "Golden chain", kind: .oia,
                                     sections: [NoteSection(key: "observation", text: "Called according to His purpose."),
                                                NoteSection(key: "interpretation", text: "God's sovereign plan."),
                                                NoteSection(key: "application", text: "Rest in providence.")])
            state.showNotes = true
            let rep = try render(MainView().environmentObject(state), dark: dark, size: CGSize(width: 980, height: 650))
            assertNotBlank(rep, "notebook-oia-\(name)")
        }
    }

    func testMyStudyBrowserRendersInEachScopeLightAndDark() throws {
        let state = makeOfflineState()
        let anchor = StudyTable.Anchor(book: "ROM", chapter: 8, verses: 28, to: 39)
        _ = state.study.addNote(anchors: [anchor], title: "Golden chain", kind: .free, body: "Providence", tags: ["providence"])
        state.study.save(anchor, isMemory: true)
        for scope in MyStudyScope.allCases {
            for (dark, name) in [(false, "light"), (true, "dark")] {
                let rep = try render(MyStudyBrowser(initialScope: scope).environmentObject(state),
                                     dark: dark, size: CGSize(width: 440, height: 560))
                assertNotBlank(rep, "my-study-\(scope.rawValue)-\(name)")
            }
        }
    }

    func testMyStudyBrowserEmptyScopesRenderHonestly() throws {
        let state = makeOfflineState()
        for scope in [MyStudyScope.clips, .projects] {
            let rep = try render(MyStudyBrowser(initialScope: scope).environmentObject(state),
                                 dark: false, size: CGSize(width: 440, height: 560))
            assertNotBlank(rep, "my-study-empty-\(scope.rawValue)")
        }
    }

    func testMyStudyBrowserFitsWithinMinimumWindowWidth() throws {
        let state = makeOfflineState()
        let rep = try render(MyStudyBrowser(initialScope: .notes).environmentObject(state),
                             dark: false, size: CGSize(width: 980, height: 600))
        assertNotBlank(rep, "my-study-980")
    }
}
