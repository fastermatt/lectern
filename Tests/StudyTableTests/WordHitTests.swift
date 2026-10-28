import AppKit
import SwiftUI
import XCTest
@testable import StudyTable

/// Pure TextKit hit-testing (`wordHit`) plus the double-click event path.
@MainActor
final class WordHitTests: XCTestCase {
    private let library = ScriptureLibrary()

    private func verse(_ translation: String, _ book: String, _ chapter: Int, _ number: Int) throws -> String {
        try XCTUnwrap(library.chapter(translation: translation, bookCode: book, chapter: chapter)?.first { $0.number == number }?.text)
    }

    // MARK: Pure hit-testing

    func testEveryWordOfAWrappedVerseIsHitAtItsCentre() throws {
        let text = try verse("BSB", "JHN", 3, 16)
        let layout = ReaderTextLayout(text: text, fontSize: 20, lineSpacing: 8, width: 300)
        XCTAssertGreaterThanOrEqual(layout.lineCount, 4, "the sample verse must wrap over several lines")
        for token in layout.tokens {
            for rect in layout.rects(for: token) {
                let hit = try XCTUnwrap(layout.hit(at: CGPoint(x: rect.midX, y: rect.midY)), "no word at centre of \(token.text)")
                XCTAssertEqual(hit.word, token.text)
                XCTAssertEqual(hit.occurrence, token.occurrence)
                XCTAssertEqual(hit.tokenIndex, token.index)
                XCTAssertEqual((text as NSString).substring(with: hit.range), token.text)
            }
        }
        XCTAssertEqual(layout.tokens.count, WordTokenizer.tokens(in: text).count)
    }

    func testTheFreeFunctionMatchesTheLayoutAndReportsOccurrences() throws {
        let text = try verse("KJV", "JHN", 3, 16)
        let layout = ReaderTextLayout(text: text, fontSize: 20, lineSpacing: 8, width: 300)
        let thats = layout.tokens.filter { $0.key == "that" }
        XCTAssertEqual(thats.count, 2)
        for token in thats {
            let rect = try XCTUnwrap(layout.rects(for: token).first)
            let hit = try XCTUnwrap(wordHit(text: text, fontSize: 20, lineSpacing: 8, width: 300, point: CGPoint(x: rect.midX, y: rect.midY)))
            XCTAssertEqual(hit.word, "that")
            XCTAssertEqual(hit.occurrence, token.occurrence)
        }
    }

    func testPointsOutsideTheTextAreNotWords() throws {
        let text = try verse("BSB", "JHN", 3, 16)
        let layout = ReaderTextLayout(text: text, fontSize: 20, lineSpacing: 8, width: 300)
        let used = layout.usedRect
        XCTAssertNil(layout.hit(at: CGPoint(x: -20, y: 10)), "left margin")
        XCTAssertNil(layout.hit(at: CGPoint(x: 310, y: 10)), "right margin")
        XCTAssertNil(layout.hit(at: CGPoint(x: 100, y: -12)), "above the text")
        XCTAssertNil(layout.hit(at: CGPoint(x: 100, y: used.maxY + 30)), "below the last line")
        // Empty space after a short last line.
        let last = try XCTUnwrap(layout.tokens.last)
        let lastRect = try XCTUnwrap(layout.rects(for: last).last)
        XCTAssertNil(layout.hit(at: CGPoint(x: lastRect.maxX + 60, y: lastRect.midY)), "past the end of the last line")
        XCTAssertNil(wordHit(text: "", fontSize: 20, lineSpacing: 8, width: 300, point: CGPoint(x: 5, y: 5)))
    }

    func testTheGapBetweenTwoWordsIsNotAWordButTheEdgesAre() throws {
        let layout = ReaderTextLayout(text: "alpha beta gamma", fontSize: 32, lineSpacing: 0, width: 600)
        let alpha = try XCTUnwrap(layout.rects(for: layout.tokens[0]).first)
        let beta = try XCTUnwrap(layout.rects(for: layout.tokens[1]).first)
        let gap = beta.minX - alpha.maxX
        XCTAssertGreaterThan(gap, 5.5, "the space must be wider than twice the hit slop for this test to mean anything")
        XCTAssertNil(layout.hit(at: CGPoint(x: (alpha.maxX + beta.minX) / 2, y: alpha.midY)), "middle of the space")
        XCTAssertEqual(layout.hit(at: CGPoint(x: alpha.maxX + 1.5, y: alpha.midY))?.word, "alpha", "just right of alpha")
        XCTAssertEqual(layout.hit(at: CGPoint(x: beta.minX - 1.5, y: beta.midY))?.word, "beta", "just left of beta")
    }

    func testPunctuationIsNotPartOfTheWordButClickingItStillFindsTheWord() throws {
        let text = "For God so loved the world, that he gave."
        let layout = ReaderTextLayout(text: text, fontSize: 22, lineSpacing: 4, width: 700)
        let world = try XCTUnwrap(layout.tokens.first { $0.key == "world" })
        let rect = try XCTUnwrap(layout.rects(for: world).first)
        let hit = try XCTUnwrap(layout.hit(at: CGPoint(x: rect.maxX + 2, y: rect.midY)))   // on the comma
        XCTAssertEqual(hit.word, "world")
        XCTAssertEqual((text as NSString).substring(with: hit.range), "world")
    }

    func testPossessivesHyphensAndCurlyQuotes() throws {
        let text = "\u{201C}God\u{2019}s God-fearing servant,\u{201D} said the man\u{2019}s friend."
        let layout = ReaderTextLayout(text: text, fontSize: 22, lineSpacing: 4, width: 800)
        func hit(_ needle: String) throws -> WordHit {
            let token = try XCTUnwrap(layout.tokens.first { $0.text == needle }, "token \(needle)")
            let rect = try XCTUnwrap(layout.rects(for: token).first)
            return try XCTUnwrap(layout.hit(at: CGPoint(x: rect.midX, y: rect.midY)))
        }
        let possessive = try hit("God\u{2019}s")
        XCTAssertEqual(possessive.word, "God\u{2019}s")
        XCTAssertEqual(possessive.key, "god", "possessive matches the base word for alignment")
        XCTAssertEqual(try hit("God").word, "God", "the hyphenated word's first part")
        XCTAssertEqual(try hit("fearing").word, "fearing")
        XCTAssertEqual(try hit("man\u{2019}s").key, "man")
        // "God" (the hyphen part) and "God's" share a key, so they are occurrences 0 and 1.
        XCTAssertEqual(try hit("God\u{2019}s").occurrence, 0)
        XCTAssertEqual(try hit("God").occurrence, 1)
    }

    func testClickInTheLeadingBetweenLinesLandsOnTheNearestLine() throws {
        let layout = ReaderTextLayout(text: "one two three four five six seven eight nine ten", fontSize: 24, lineSpacing: 12, width: 160)
        XCTAssertGreaterThan(layout.lineCount, 2)
        let first = try XCTUnwrap(layout.rects(for: layout.tokens[0]).first)
        // 3pt below the first line's box is in the line spacing: still that word's line.
        XCTAssertEqual(layout.hit(at: CGPoint(x: first.midX, y: first.maxY + 3))?.word, layout.tokens[0].text)
    }

    func testLayoutMatchesTheTokenizerForAccentedAndNonEnglishText() throws {
        let text = "La Tierra estaba desordenada y vac\u{00ED}a, y las tinieblas cubr\u{00ED}an la superficie"
        let layout = ReaderTextLayout(text: text, fontSize: 20, lineSpacing: 8, width: 260)
        for token in layout.tokens {
            let rect = try XCTUnwrap(layout.rects(for: token).first)
            XCTAssertEqual(layout.hit(at: CGPoint(x: rect.midX, y: rect.midY))?.word, token.text)
        }
    }

    // MARK: Event path through the real reader

    @MainActor private final class Harness {
        let host: NSHostingView<AnyView>
        let window: NSWindow
        init<V: View>(_ view: V, size: CGSize, dark: Bool = false) {
            host = NSHostingView(rootView: AnyView(view.frame(width: size.width, height: size.height)))
            host.frame = NSRect(origin: .zero, size: size)
            let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
            host.appearance = appearance
            window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
            window.appearance = appearance
            window.contentView = host
            window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))   // offscreen; never shown to the user
            window.orderBack(nil)
            pump()
        }
        func pump(_ passes: Int = 6) {
            for _ in 0..<passes {
                host.layoutSubtreeIfNeeded()
                RunLoop.main.run(until: Date().addingTimeInterval(0.08))
            }
        }
        func close() { host.rootView = AnyView(EmptyView()); pump(3); window.contentView = nil; window.orderOut(nil) }
        func layers() -> [WordHitNSView] {
            var found: [WordHitNSView] = []
            func walk(_ view: NSView) {
                if let layer = view as? WordHitNSView { found.append(layer) }
                view.subviews.forEach(walk)
            }
            walk(host)
            return found
        }
        func scrollView() -> NSScrollView? {
            var result: NSScrollView?
            func walk(_ view: NSView) {
                if result == nil, let scroll = view as? NSScrollView { result = scroll }
                view.subviews.forEach(walk)
            }
            walk(host)
            return result
        }
    }

    private func mouseDown(at windowPoint: NSPoint, in window: NSWindow, clickCount: Int) -> NSEvent {
        NSEvent.mouseEvent(with: .leftMouseDown, location: windowPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 1, clickCount: clickCount, pressure: 1)!
    }

    private func mouseUp(at windowPoint: NSPoint, in window: NSWindow, clickCount: Int) -> NSEvent {
        NSEvent.mouseEvent(with: .leftMouseUp, location: windowPoint, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                           windowNumber: window.windowNumber, context: nil, eventNumber: 2, clickCount: clickCount, pressure: 0)!
    }

    /// Where the centre of `word` (first occurrence) is, in window coordinates.
    private func windowPoint(of word: String, in layer: WordHitNSView) throws -> NSPoint {
        let token = try XCTUnwrap(layer.layout.tokens.first { $0.text == word }, "\(word) not in layer")
        let rect = try XCTUnwrap(layer.layout.rects(for: token).first)
        return layer.convert(NSPoint(x: rect.midX, y: rect.midY), to: nil)
    }

    private func scriptureState(_ translation: String = "BSB") -> AppState {
        let state = makeOfflineState()
        state.translationID = translation
        state.navigate(bookCode: "JHN", chapter: 3, verse: 16)
        state.showStudyDesk = false      // prove that studying a word reveals the desk
        return state
    }

    func testDoubleClickThroughTheMonitorStudiesTheWordAndRevealsTheDesk() throws {
        let state = scriptureState()
        state.focusMode = true
        let harness = Harness(ScripturePane().environmentObject(state), size: CGSize(width: 560, height: 520))
        defer { harness.close(); InterlinearSelection.shared.clear() }
        let layer = try XCTUnwrap(harness.layers().first { $0.text.hasPrefix("For God so loved") })
        XCTAssertGreaterThan(WordClickMonitor.shared.registeredCount, 0)
        XCTAssertTrue(WordClickMonitor.shared.isInstalled)

        let point = try windowPoint(of: "loved", in: layer)
        // A single click is observed and ignored.
        XCTAssertNil(WordClickMonitor.shared.process(mouseDown(at: point, in: harness.window, clickCount: 1)))
        XCTAssertNil(InterlinearSelection.shared.studied(for: "JHN.3.16"))
        // The second click of a double-click studies the word.
        let hit = try XCTUnwrap(WordClickMonitor.shared.process(mouseDown(at: point, in: harness.window, clickCount: 2)))
        XCTAssertEqual(hit.word, "loved")
        let studied = try XCTUnwrap(InterlinearSelection.shared.studied(for: "JHN.3.16"))
        XCTAssertEqual(studied.word, "loved")
        XCTAssertEqual(studied.translationID, "BSB")
        XCTAssertEqual(studied.result.match?.confidence, .high)
        XCTAssertEqual(InterlinearSelection.shared.mode(for: "JHN.3.16"), .single)
        let words = InterlinearStore.shared.words(bookCode: "JHN", chapter: 3, verse: 16)
        XCTAssertEqual(InterlinearSelection.shared.focusedIndex(for: "JHN.3.16").map { words[$0].lemma }, "ἀγαπάω")
        XCTAssertTrue(state.showStudyDesk, "the double-click must reveal a hidden desk")
        XCTAssertFalse(state.focusMode)
        XCTAssertTrue(state.visibleDeskSections.contains(.originalLanguage))
        XCTAssertEqual(InterlinearSelection.shared.highlightRange(passage: "JHN.3.16", translationID: "BSB"), studied.range)
        XCTAssertNil(InterlinearSelection.shared.highlightRange(passage: "JHN.3.16", translationID: "KJV"),
                     "the highlight belongs to the translation it was chosen in")
        XCTAssertNil(InterlinearSelection.shared.highlightRange(passage: "JHN.3.17", translationID: "BSB"))
    }

    func testDoubleClickOnAGapOrAnotherWindowIsIgnored() throws {
        let state = scriptureState()
        let harness = Harness(ScripturePane().environmentObject(state), size: CGSize(width: 560, height: 520))
        defer { harness.close(); InterlinearSelection.shared.clear() }
        let layer = try XCTUnwrap(harness.layers().first { $0.text.hasPrefix("For God so loved") })
        // Far right of the text block, inside the row but beyond any word.
        let empty = layer.convert(NSPoint(x: layer.bounds.maxX - 0.5, y: layer.bounds.maxY - 0.5), to: nil)
        XCTAssertNil(WordClickMonitor.shared.process(mouseDown(at: empty, in: harness.window, clickCount: 2)))
        // A double-click delivered for some other window must not reach these layers.
        let other = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 50, height: 50), styleMask: [.borderless], backing: .buffered, defer: false)
        let point = try windowPoint(of: "loved", in: layer)
        XCTAssertNil(WordClickMonitor.shared.process(mouseDown(at: point, in: other, clickCount: 2)))
        // Right-clicks and third clicks are not double-clicks.
        XCTAssertNil(WordClickMonitor.shared.process(mouseDown(at: point, in: harness.window, clickCount: 3)))
        XCTAssertNil(InterlinearSelection.shared.studied(for: "JHN.3.16"))
    }

    func testSyntheticEventsThroughTheApplicationSelectAVerseAndStudyAWord() throws {
        let state = scriptureState()
        state.navigate(bookCode: "JHN", chapter: 3, verse: 15)
        let harness = Harness(ScripturePane().environmentObject(state), size: CGSize(width: 560, height: 520))
        defer { harness.close(); InterlinearSelection.shared.clear() }
        let layer = try XCTUnwrap(harness.layers().first { $0.text.hasPrefix("For God so loved") })
        let scroll = try XCTUnwrap(harness.scrollView())
        let before = scroll.contentView.bounds.origin.y
        let point = try windowPoint(of: "world", in: layer)
        XCTAssertEqual(state.selectedVerse, 15)

        // A real double-click sequence delivered through NSApplication: local monitors + the row's Button.
        for (down, clicks) in [(true, 1), (false, 1), (true, 2), (false, 2)] {
            let event = down ? mouseDown(at: point, in: harness.window, clickCount: clicks) : mouseUp(at: point, in: harness.window, clickCount: clicks)
            NSApp.sendEvent(event)
            harness.pump(3)
        }
        XCTAssertEqual(state.selectedVerse, 16, "the first click selects the verse through the row's Button")
        XCTAssertEqual(InterlinearSelection.shared.studied(for: "JHN.3.16")?.word, "world")
        XCTAssertEqual(scroll.contentView.bounds.origin.y, before, accuracy: 0.5,
                       "clicking a verse must not scroll it out from under the pointer (the second click would miss)")
    }

    func testLayersUnregisterWhenTheirViewsGoAway() throws {
        let state = scriptureState()
        let baseline = WordClickMonitor.shared.registeredCount
        let harness = Harness(ScripturePane().environmentObject(state), size: CGSize(width: 560, height: 520))
        XCTAssertGreaterThan(WordClickMonitor.shared.registeredCount, baseline)
        harness.close()
        harness.pump(3)
        XCTAssertLessThanOrEqual(WordClickMonitor.shared.registeredCount, baseline)
    }

    func testNoHitTestingLayerInterceptsMouseEvents() throws {
        let layer = WordHitNSView()
        layer.frame = NSRect(x: 0, y: 0, width: 300, height: 100)
        XCTAssertNil(layer.hitTest(NSPoint(x: 10, y: 10)))
        XCTAssertFalse(layer.isAccessibilityElement())
    }
}
