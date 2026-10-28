import AppKit
import SwiftUI
import XCTest
@testable import StudyTable

/// The word-study flow end to end: selection model, desk landing, reader highlight, accessibility
/// route, regression of the verse row's look, and offscreen renders (set STUDYTABLE_SNAPSHOT_DIR to
/// keep the PNGs).
@MainActor
final class WordStudyDeskTests: XCTestCase {
    private let library = ScriptureLibrary()

    override func tearDown() async throws {
        InterlinearSelection.shared.clear()
    }

    // MARK: Helpers

    private func verse(_ translation: String, _ book: String, _ chapter: Int, _ number: Int) throws -> BibleVerse {
        try XCTUnwrap(library.chapter(translation: translation, bookCode: book, chapter: chapter)?.first { $0.number == number })
    }

    private func hit(_ word: String, in verse: BibleVerse, occurrence: Int = 0) throws -> WordHit {
        let key = WordTokenizer.normalizedKey(word)
        let token = try XCTUnwrap(WordTokenizer.tokens(in: verse.text).first { $0.key == key && $0.occurrence == occurrence })
        return token.asHit
    }

    private func state(_ book: String, _ chapter: Int, _ verse: Int, translation: String = "BSB") -> AppState {
        let state = makeOfflineState()
        state.translationID = translation
        state.navigate(bookCode: book, chapter: chapter, verse: verse)
        return state
    }

    @discardableResult
    private func study(_ word: String, _ book: String, _ chapter: Int, _ number: Int, translation: String = "BSB",
                       occurrence: Int = 0, in state: AppState) throws -> InterlinearSelection.StudiedWord {
        let v = try verse(translation, book, chapter, number)
        InterlinearSelection.shared.studyWord(try hit(word, in: v, occurrence: occurrence), in: v, state: state)
        return try XCTUnwrap(InterlinearSelection.shared.studied(for: "\(book).\(chapter).\(number)"))
    }

    // MARK: Selection model

    func testStudyWordSelectsTheVerseRevealsTheDeskAndIsScopedToItsPassage() throws {
        let state = state("JHN", 3, 15)
        state.showStudyDesk = false
        state.focusMode = true
        state.setDeskSectionVisible(.originalLanguage, false)
        let studied = try study("loved", "JHN", 3, 16, in: state)
        XCTAssertEqual(state.selectedVerse, 16)
        XCTAssertEqual(state.suppressScrollForVerse, 16, "choosing a word in Scripture must not scroll the reader")
        XCTAssertTrue(state.showStudyDesk)
        XCTAssertFalse(state.focusMode)
        XCTAssertTrue(state.visibleDeskSections.contains(.originalLanguage))
        XCTAssertEqual(studied.result.match?.method, .kjvTag)
        XCTAssertTrue(InterlinearSelection.shared.hasFocus(for: "JHN.3.16"))
        XCTAssertFalse(InterlinearSelection.shared.hasFocus(for: "JHN.3.17"), "a word never leaks into another verse")
        XCTAssertNil(InterlinearSelection.shared.focusedIndex(for: "ROM.8.28"))
        XCTAssertEqual(InterlinearSelection.shared.mode(for: "JHN.3.16"), .single)
    }

    func testChoosingAnotherVerseDropsTheStaleWord() throws {
        let state = state("JHN", 3, 16)
        try study("world", "JHN", 3, 16, in: state)
        InterlinearSelection.shared.clear(unlessPassage: "JHN.3.16")
        XCTAssertTrue(InterlinearSelection.shared.hasFocus(for: "JHN.3.16"), "same passage keeps the word")
        InterlinearSelection.shared.clear(unlessPassage: "JHN.3.17")
        XCTAssertFalse(InterlinearSelection.shared.hasFocus(for: "JHN.3.16"))
        XCTAssertNil(InterlinearSelection.shared.studied(for: "JHN.3.16"), "gone, not merely hidden")
    }

    func testLCDWordsOpenTheSameSingleWordView() {
        let state = state("ROM", 8, 28)
        let selection = InterlinearSelection.shared
        let before = selection.requestToken
        selection.reveal(wordIndex: 3, state: state)
        XCTAssertEqual(selection.mode(for: "ROM.8.28"), .single)
        XCTAssertEqual(selection.focusedIndex(for: "ROM.8.28"), 3)
        XCTAssertNil(selection.studied(for: "ROM.8.28"), "an LCD word has no English word behind it")
        XCTAssertGreaterThan(selection.requestToken, before)
        XCTAssertNil(selection.highlightRange(passage: "ROM.8.28", translationID: "BSB"), "nothing to highlight in the reader")
    }

    func testShowAllClearAndRowSelectionTransitions() throws {
        let state = state("JHN", 3, 16)
        let selection = InterlinearSelection.shared
        try study("loved", "JHN", 3, 16, in: state)
        let studiedIndex = selection.focusedIndex(for: "JHN.3.16")
        let token = selection.requestToken
        selection.showAll()
        XCTAssertEqual(selection.mode(for: "JHN.3.16"), .all)
        XCTAssertEqual(selection.focusedIndex(for: "JHN.3.16"), studiedIndex, "the word stays highlighted in the full list")
        XCTAssertGreaterThan(selection.requestToken, token, "switching view re-scrolls the desk")
        // Choosing a row in the list moves the highlight without leaving the list or scrolling.
        let after = selection.requestToken
        selection.select(wordIndex: 0, passage: "JHN.3.16")
        XCTAssertEqual(selection.focusedIndex(for: "JHN.3.16"), 0)
        XCTAssertEqual(selection.mode(for: "JHN.3.16"), .all)
        XCTAssertEqual(selection.requestToken, after)
        XCTAssertNil(selection.studied(for: "JHN.3.16"), "the English word no longer applies once another row is chosen")
        selection.showSingle()
        XCTAssertEqual(selection.mode(for: "JHN.3.16"), .single)
        selection.clear()
        XCTAssertFalse(selection.hasFocus(for: "JHN.3.16"))
    }

    func testTranslationChangeKeepsTheWordOnlyWhenItStillResolvesToTheSameOriginalWord() throws {
        let state = state("JHN", 3, 16)
        let selection = InterlinearSelection.shared
        for (word, expectKept) in [("world", true), ("loved", true), ("believes", true), ("everyone", false)] {
            selection.clear()
            state.translationID = "BSB"
            try study(word, "JHN", 3, 16, in: state)
            let before = selection.focusedIndex(for: "JHN.3.16")
            state.translationID = "KJV"
            let content = ChapterContent(verses: try XCTUnwrap(library.chapter(translation: "KJV", bookCode: "JHN", chapter: 3)),
                                         origin: .offline, attribution: "")
            selection.reconcile(with: content, state: state)
            XCTAssertEqual(selection.hasFocus(for: "JHN.3.16"), expectKept, "\"\(word)\" BSB -> KJV")
            if expectKept {
                XCTAssertEqual(selection.focusedIndex(for: "JHN.3.16"), before, "\"\(word)\" must keep the same original word")
                XCTAssertEqual(selection.studied(for: "JHN.3.16")?.translationID, "KJV")
                XCTAssertNotNil(selection.highlightRange(passage: "JHN.3.16", translationID: "KJV"))
            }
        }
        // Same translation: reconcile is a no-op.
        selection.clear()
        state.translationID = "BSB"
        try study("world", "JHN", 3, 16, in: state)
        let content = ChapterContent(verses: try XCTUnwrap(library.chapter(translation: "BSB", bookCode: "JHN", chapter: 3)), origin: .offline, attribution: "")
        selection.reconcile(with: content, state: state)
        XCTAssertTrue(selection.hasFocus(for: "JHN.3.16"))
    }

    func testTranslationChangeClearsWhenTheVerseIsMissingFromTheNewText() throws {
        let state = state("JHN", 3, 16)
        try study("world", "JHN", 3, 16, in: state)
        state.translationID = "KJV"
        let content = ChapterContent(verses: [BibleVerse(number: 1, text: "Only verse one.")], origin: .offline, attribution: "")
        InterlinearSelection.shared.reconcile(with: content, state: state)
        XCTAssertFalse(InterlinearSelection.shared.hasFocus(for: "JHN.3.16"))
    }

    func testWordPickerRequestTargetsTheSelectedVerse() {
        let state = state("JHN", 3, 16)
        state.requestWordPicker()
        XCTAssertEqual(state.wordPickerVerse, 16)
        state.wordPickerVerse = nil
        state.selectedVerse = 0
        state.requestWordPicker()
        XCTAssertNil(state.wordPickerVerse, "verse 0 (a superscription) has no word list")
    }

    func testWordChoiceTitlesDisambiguateRepeatedWords() throws {
        let tokens = WordTokenizer.tokens(in: "that he gave, that whosoever believeth")
        XCTAssertEqual(wordChoiceTitle(tokens[0], in: tokens), "that (1 of 2)")
        XCTAssertEqual(wordChoiceTitle(tokens[3], in: tokens), "that (2 of 2)")
        XCTAssertEqual(wordChoiceTitle(tokens[1], in: tokens), "he")
    }

    // MARK: Accessibility route

    /// SwiftUI only builds its accessibility tree when an assistive client is attached, so the custom
    /// action cannot be introspected in-process (an NSHostingView reports zero children here). This
    /// guards the three pointer-free routes at the source level and exercises what they call.
    func testPointerFreeRoutesToWordStudyExist() throws {
        let panes = try String(contentsOf: TestPaths.root.appendingPathComponent("Sources/StudyTable/Panes.swift"), encoding: .utf8)
        XCTAssertTrue(panes.contains(".accessibilityAction(named: \"Study a word"), "VoiceOver custom action on the verse row")
        XCTAssertTrue(panes.contains("Menu(\"Study a word\")"), "context-menu word list")
        XCTAssertTrue(panes.contains("VerseWordPicker(verse: verse)"), "popover word list opened by the action and the command")
        let app = try String(contentsOf: TestPaths.root.appendingPathComponent("Sources/StudyTable/StudyTableApp.swift"), encoding: .utf8)
        XCTAssertTrue(app.contains("Study a Word in the Selected Verse") && app.contains("requestWordPicker()"), "menu command with a shortcut")
    }

    func testEveryWordOfAVerseCanBeChosenFromTheListAndStudied() throws {
        // What the popover / context menu do for each button: build the hit from the token and study it.
        let state = state("JHN", 3, 16)
        let v = try verse("BSB", "JHN", 3, 16)
        for token in WordTokenizer.tokens(in: v.text) {
            InterlinearSelection.shared.studyWord(token.asHit, in: v, state: state)
            let studied = try XCTUnwrap(InterlinearSelection.shared.studied(for: "JHN.3.16"), token.text)
            XCTAssertEqual(studied.word, token.text)
            XCTAssertTrue(studied.result.match != nil || studied.result.gap != nil)
        }
        XCTAssertEqual(state.selectedVerse, 16)
    }

    func testTheWordListPopoverRenders() throws {
        for dark in [false, true] {
            let v = try verse("BSB", "JHN", 3, 16)
            let rep = try render(VerseWordPicker(verse: v) { _ in }.background(STColor.tileTop), dark: dark,
                                 size: CGSize(width: 300, height: 190), name: "word-picker")
            assertNotBlank(rep, "word picker")
        }
    }

    // MARK: Regression: the verse row must look exactly as it did

    /// The row as it was before word study (Button + plain Text, no AppKit layer behind the text).
    private struct LegacyVerseRow: View {
        @EnvironmentObject private var state: AppState
        let verse: BibleVerse
        private var selected: Bool { state.selectedVerse == verse.number }
        var body: some View {
            Button { state.selectedVerse = verse.number } label: {
                HStack(alignment: .firstTextBaseline, spacing: 11) {
                    Text("\(verse.number)")
                        .font(STFont.numeral(12, weight: selected ? .semibold : .light)).monospacedDigit()
                        .foregroundStyle(selected ? STColor.ink : STColor.secondary)
                        .frame(width: 24, alignment: .trailing)
                    Text(verse.text)
                        .font(STFont.reading(state.fontSize))
                        .lineSpacing(state.lineSpacing)
                        .foregroundStyle(STColor.ink)
                        .multilineTextAlignment(.leading)
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(selected ? STColor.orange.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 3))
                .padding(.trailing, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
    }

    private func bitmap<V: View>(_ view: V, dark: Bool, size: CGSize) throws -> NSBitmapImageRep {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height).background(STColor.paper))
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = appearance
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderBack(nil)
        defer { window.contentView = nil; window.orderOut(nil) }
        for _ in 0..<6 { host.layoutSubtreeIfNeeded(); RunLoop.main.run(until: Date().addingTimeInterval(0.08)) }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep
    }

    private func differingFraction(_ a: NSBitmapImageRep, _ b: NSBitmapImageRep) -> Double {
        guard a.pixelsWide == b.pixelsWide, a.pixelsHigh == b.pixelsHigh else { return 1 }
        var different = 0
        for y in 0..<a.pixelsHigh {
            for x in 0..<a.pixelsWide {
                guard let p = a.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), let q = b.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if abs(p.redComponent - q.redComponent) > 0.03 || abs(p.greenComponent - q.greenComponent) > 0.03
                    || abs(p.blueComponent - q.blueComponent) > 0.03 { different += 1 }
            }
        }
        return Double(different) / Double(a.pixelsWide * a.pixelsHigh)
    }

    func testVerseTextRendersIdenticallyToTheOldRowWhenNoWordIsHighlighted() throws {
        var worst = 0.0
        for (size, spacing) in [(16.0, 4.0), (24.0, 10.0)] {
            for dark in [false, true] {
                let state = state("JHN", 3, 16)
                state.fontSize = size
                state.lineSpacing = spacing
                let verses = try [16, 17].map { try verse("BSB", "JHN", 3, $0) }
                let new = VStack(alignment: .leading, spacing: 0) { ForEach(verses) { VerseRow(verse: $0) } }.environmentObject(state)
                let old = VStack(alignment: .leading, spacing: 0) { ForEach(verses) { LegacyVerseRow(verse: $0) } }.environmentObject(state)
                let canvas = CGSize(width: 420, height: 330)
                let fraction = differingFraction(try bitmap(new, dark: dark, size: canvas), try bitmap(old, dark: dark, size: canvas))
                worst = max(worst, fraction)
            }
        }
        XCTAssertLessThanOrEqual(worst, 0.01, "verse rows differ from the old rendering by \(worst * 100)% of pixels")
        print("VERSE ROW PIXEL DIFFERENCE vs OLD ROW (2 sizes x light/dark): worst \(worst * 100)%")
    }

    /// The highlight box must sit on the word SwiftUI drew, and only on it.
    func testHighlightIsDrawnBehindTheStudiedWordOnly() throws {
        let state = state("JHN", 3, 16)
        let v = try verse("BSB", "JHN", 3, 16)
        state.selectedVerse = 15   // an unselected row so the wash does not add orange elsewhere
        let canvas = CGSize(width: 420, height: 170)
        let plain = try bitmap(VerseRow(verse: v).environmentObject(state), dark: false, size: canvas)
        try study("loved", "JHN", 3, 16, in: state)
        state.selectedVerse = 15
        let lit = try bitmap(VerseRow(verse: v).environmentObject(state), dark: false, size: canvas)
        XCTAssertGreaterThan(differingFraction(plain, lit), 0, "the highlight must be visible")

        // Bounding box of everything that changed, in points.
        let scale = CGFloat(plain.pixelsWide) / canvas.width
        var minX = Int.max, minY = Int.max, maxX = -1, maxY = -1
        for y in 0..<plain.pixelsHigh {
            for x in 0..<plain.pixelsWide {
                guard let p = plain.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), let q = lit.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { continue }
                if abs(p.redComponent - q.redComponent) > 0.02 || abs(p.greenComponent - q.greenComponent) > 0.02 || abs(p.blueComponent - q.blueComponent) > 0.02 {
                    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
                }
            }
        }
        let changed = CGRect(x: CGFloat(minX) / scale, y: CGFloat(minY) / scale,
                             width: CGFloat(maxX - minX + 1) / scale, height: CGFloat(maxY - minY + 1) / scale)
        // Independent expectation: lay the verse out at the text's width and find "loved".
        let text = v.text
        // The text column: 420 - 9 (row padding) - 24 (number) - 11 (gap) - 9 - 12 (trailing padding).
        let layout = ReaderTextLayout(text: text, fontSize: 20, lineSpacing: 8, width: 420 - 9 - 24 - 11 - 9 - 12)
        let token = try XCTUnwrap(layout.tokens.first { $0.key == "loved" })
        let word = try XCTUnwrap(layout.rects(for: token).first)
        let expectedX = 9 + 24 + 11 + word.minX
        XCTAssertEqual(changed.minX, expectedX - 1.5, accuracy: 2.5, "highlight left edge")
        XCTAssertEqual(changed.width, word.width + 3, accuracy: 4, "highlight width")
        XCTAssertLessThan(changed.height, 30, "the highlight covers one word on one line, not the verse")
    }

    // MARK: Renders (evidence PNGs when STUDYTABLE_SNAPSHOT_DIR is set)

    private func render<V: View>(_ view: V, dark: Bool, size: CGSize, name: String) throws -> NSBitmapImageRep {
        let rep = try bitmap(view, dark: dark, size: size)
        if let directory = ProcessInfo.processInfo.environment["STUDYTABLE_SNAPSHOT_DIR"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                .write(to: url.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        }
        return rep
    }

    private func assertNotBlank(_ rep: NSBitmapImageRep, _ label: String) {
        var distinct = Set<UInt32>()
        for x in stride(from: 0, to: rep.pixelsWide, by: 13) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 13) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                    distinct.insert(UInt32(c.redComponent * 63) << 12 | UInt32(c.greenComponent * 63) << 6 | UInt32(c.blueComponent * 63))
                }
            }
        }
        XCTAssertGreaterThan(distinct.count, 8, "\(label) rendered blank")
    }

    private func deskRender(name: String, dark: Bool, state: AppState, size: CGSize = CGSize(width: 360, height: 760)) throws {
        let defaults = ephemeralDefaults()
        let view = SourcesPane().tileFace().environmentObject(state).defaultAppStorage(defaults)
            .environment(\.colorScheme, dark ? .dark : .light)
        assertNotBlank(try render(view, dark: dark, size: size, name: name), name)
    }

    func testDeskRendersTheSingleGreekWordCard() throws {
        for dark in [false, true] {
            let state = state("JHN", 3, 16)
            try study("loved", "JHN", 3, 16, in: state)
            try deskRender(name: "desk-word-greek", dark: dark, state: state)
        }
    }

    func testDeskRendersTheSingleHebrewWordCard() throws {
        for dark in [false, true] {
            let state = state("GEN", 1, 1)
            try study("created", "GEN", 1, 1, in: state)
            try deskRender(name: "desk-word-hebrew", dark: dark, state: state)
        }
    }

    func testDeskRendersTheNoSingleOriginalWordState() throws {
        for dark in [false, true] {
            let state = state("JHN", 3, 16)
            let studied = try study("one", "JHN", 3, 16, in: state)
            XCTAssertNil(studied.result.match)
            try deskRender(name: "desk-word-nomatch", dark: dark, state: state)
        }
    }

    func testDeskRendersAHeuristicMatchAndAnArticle() throws {
        for dark in [false, true] {
            let state = state("JHN", 3, 16)
            let studied = try study("believes", "JHN", 3, 16, in: state)
            XCTAssertTrue(studied.result.isHeuristic)
            try deskRender(name: "desk-word-heuristic", dark: dark, state: state)
            try study("the", "JHN", 3, 16, in: state)
            try deskRender(name: "desk-word-article", dark: dark, state: state)
        }
    }

    func testDeskRendersTheFullListWithTheWordStillFocused() throws {
        let state = state("JHN", 3, 16)
        try study("loved", "JHN", 3, 16, in: state)
        InterlinearSelection.shared.showAll()
        try deskRender(name: "desk-word-list", dark: false, state: state)
    }

    func testScriptureRendersTheHighlightedWord() throws {
        for dark in [false, true] {
            let state = state("JHN", 3, 16)
            try study("loved", "JHN", 3, 16, in: state)
            assertNotBlank(try render(ScripturePane().environmentObject(state).background(STColor.paper), dark: dark,
                                      size: CGSize(width: 560, height: 420), name: "scripture-word"), "scripture")
        }
    }

    func testWholeConsoleAtMinimumAndDefaultWidthsWithAStudiedWord() throws {
        for (width, height, tag) in [(980.0, 650.0, "min-980"), (1143.0, 797.0, "default")] {
            for dark in [false, true] {
                let state = state("JHN", 3, 16)
                state.showStudyDesk = false
                let v = try verse("BSB", "JHN", 3, 16)
                InterlinearSelection.shared.studyWord(try hit("loved", in: v), in: v, state: state)
                let defaults = ephemeralDefaults()
                let view = MainView().environmentObject(state).defaultAppStorage(defaults)
                assertNotBlank(try render(view, dark: dark, size: CGSize(width: width, height: height), name: "console-word-\(tag)"), tag)
                InterlinearSelection.shared.clear()
            }
        }
    }
}
