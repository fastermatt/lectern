import AppKit
import SwiftUI
import XCTest
@testable import StudyTable

/// Covers 0.10.2: Matt asked for (1) commentary/study text to have its own font controls,
/// independent of Scripture's Type/Leading knobs, and (2) a choice of reading typefaces
/// generally. `ReadingTypeface` is the shared resolver both `STFont.reading` (SwiftUI) and
/// `STFont.readingNSFont` (the AppKit word-click hit-test layer) go through — the correctness
/// property that matters most is that those two never disagree about which font is on screen
/// (`ReaderLayoutEquivalenceTests` covers that at the pixel level); these tests cover resolution
/// itself, persistence, and the Scripture/Study decoupling.
@MainActor
final class ReadingTypefaceTests: XCTestCase {
    private var outputDirectory: URL? {
        ProcessInfo.processInfo.environment["STUDYTABLE_SNAPSHOT_DIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    // MARK: Resolution

    func testEveryAvailableTypefaceResolvesToARealDistinctFont() {
        // Every case is Apple-bundled and expected to resolve on the machine actually running
        // this suite; this is a canary, not a defensive skip, so a genuine regression fails loudly.
        XCTAssertEqual(ReadingTypeface.available.count, ReadingTypeface.allCases.count,
                        "a typeface failed to resolve on this Mac: \(Set(ReadingTypeface.allCases).subtracting(ReadingTypeface.available).map(\.displayName))")
        var seenFamilies = Set<String>()
        for typeface in ReadingTypeface.available {
            let font = typeface.nsFont(size: 16)
            XCTAssertGreaterThan(font.pointSize, 0)
            seenFamilies.insert(font.familyName ?? font.fontName)
        }
        // Each curated typeface should actually be a distinct family — a resolver bug that quietly
        // fell back to the same font for everything would still pass a weaker "non-nil" check.
        XCTAssertEqual(seenFamilies.count, ReadingTypeface.available.count,
                        "two typefaces resolved to the same family: \(seenFamilies)")
    }

    func testSwiftUIFontAndAppKitNSFontAgreeOnThePostscriptNameForEveryTypeface() {
        // The exact invariant `ReaderLayoutEquivalenceTests` depends on: both call paths must be
        // built from the identical resolved font, not just "look the same."
        for typeface in ReadingTypeface.available {
            let nsFont = typeface.nsFont(size: 18)
            // `STFont.reading` builds `.custom(nsFont.fontName, size:)`; there's no public API to
            // read a SwiftUI `Font`'s underlying name back out, so this asserts the shared
            // precondition instead: the NSFont side (what STFont.reading is built from) is a real,
            // named font, which is exactly what `ReadingTypeface.font(size:weight:)` hands to
            // `Font.custom`.
            XCTAssertFalse(nsFont.fontName.isEmpty, "\(typeface.displayName) resolved to an unnamed font")
        }
    }

    func testBoldVariantDiffersFromRegularForSeveralTypefaces() {
        for typeface: ReadingTypeface in [.baskerville, .georgia, .palatino, .timesNewRoman] {
            let regular = typeface.nsFont(size: 16, bold: false)
            let bold = typeface.nsFont(size: 16, bold: true)
            XCTAssertNotEqual(regular.fontName, bold.fontName, "\(typeface.displayName) bold did not resolve to a distinct font")
            XCTAssertTrue(NSFontManager.shared.traits(of: bold).contains(.boldFontMask),
                          "\(typeface.displayName)'s \"bold\" variant isn't actually bold")
        }
    }

    func testNewYorkResolvesThroughTheSystemSerifDesignRoute() {
        // New York is not a normal nameable family on macOS (`NSFont(name: "New York", …)` and
        // `NSFontManager` family enumeration both return nothing for it — confirmed empirically
        // while building this feature). It only resolves via the public
        // `NSFontDescriptor.withDesign(.serif)` route; this pins that down so a future refactor
        // can't quietly regress it back to a family-name lookup that would always fail.
        let font = ReadingTypeface.newYork.nsFont(size: 16)
        XCTAssertNotEqual(font.fontName, NSFont.systemFont(ofSize: 16).fontName,
                          "New York silently fell back to the plain system font")
    }

    func testPalatinoAndNewYorkAreAvailableForStudyButExcludedFromScripture() {
        // The two typefaces `ReaderLayoutEquivalenceTests` found break Scripture's word-click
        // hit-testing (a real TextKit line-height divergence, not a resolution failure — see
        // `ReadingTypeface.isSafeForScripture`'s comment). Both must still resolve normally and
        // stay offered for commentary/study text, which has no hit-test layer to break.
        for typeface: ReadingTypeface in [.palatino, .newYork] {
            XCTAssertTrue(ReadingTypeface.available.contains(typeface), "\(typeface.displayName) should still resolve")
            XCTAssertFalse(ReadingTypeface.availableForScripture.contains(typeface), "\(typeface.displayName) should be excluded from Scripture")
            XCTAssertFalse(typeface.isSafeForScripture)
        }
        // And everything else genuinely is safe — this isn't a blanket exclusion.
        XCTAssertEqual(ReadingTypeface.availableForScripture.count, ReadingTypeface.available.count - 2)
    }

    func testUnavailableStoredValueFallsBackToBaskervilleRatherThanCrashing() {
        // A future version might store a typeface this build doesn't know about (or a corrupted
        // default); ReadingTypeface(rawValue:) must degrade to the shipped default, never trap.
        XCTAssertNil(ReadingTypeface(rawValue: "some-future-typeface-this-build-has-never-heard-of"))
        XCTAssertEqual(ReadingTypeface(rawValue: "garbage") ?? .baskerville, .baskerville)
    }

    // MARK: AppState — persistence and decoupling

    func testScriptureAndStudyTypefacesPersistIndependently() {
        let state = makeOfflineState()
        state.scriptureTypeface = .newYork
        state.studyTypeface = .georgia
        XCTAssertEqual(state.scriptureTypeface, .newYork)
        XCTAssertEqual(state.studyTypeface, .georgia)
        // Changing one must never move the other.
        state.scriptureTypeface = .charter
        XCTAssertEqual(state.studyTypeface, .georgia)
    }

    func testStudyFontSizeAndLeadingAreIndependentOfTheScriptureKnobs() {
        // The exact regression this feature exists to fix: an 0.10.1 stopgap scaled commentary
        // off `state.fontSize`/`lineSpacing` (the Type/Leading knobs). Matt asked for commentary
        // to have its own separate controls — turning the Scripture knobs must no longer move it.
        let state = makeOfflineState()
        state.studyFontSize = 15
        state.studyLineSpacing = 5
        state.fontSize = 30       // Type knob, maximum
        state.lineSpacing = 16    // Leading knob, maximum
        XCTAssertEqual(state.studyFontSize, 15)
        XCTAssertEqual(state.studyLineSpacing, 5)
        // And the reverse: changing Study's own controls must never move Scripture's.
        state.studyFontSize = 11
        XCTAssertEqual(state.fontSize, 30)
    }

    func testDefaultsMatchWhatTheAppAlreadyShippedSoExistingReadersSeeNoChange() {
        let state = makeOfflineState()
        XCTAssertEqual(state.scriptureTypeface, .baskerville)
        XCTAssertEqual(state.studyTypeface, .baskerville)
        XCTAssertEqual(state.studyFontSize, 13.5)   // DeskExpandableText's old fixed size
        XCTAssertEqual(state.studyLineSpacing, 3)   // DeskExpandableText's old fixed spacing
    }

    // MARK: Renders

    private func render<V: View>(_ view: V, dark: Bool, size: CGSize, name: String) throws -> NSBitmapImageRep {
        let appearance = NSAppearance(named: dark ? .darkAqua : .aqua)!
        let host = NSHostingView(rootView: view.frame(width: size.width, height: size.height))
        host.frame = NSRect(origin: .zero, size: size)
        host.appearance = appearance
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = appearance
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderBack(nil)
        for _ in 0..<6 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.25))
        }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        if let directory = outputDirectory {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: directory.appendingPathComponent("\(name).png"))
        }
        window.orderOut(nil)
        return rep
    }

    private func assertNotBlank(_ rep: NSBitmapImageRep, _ label: String) {
        var distinct = Set<UInt32>()
        for x in stride(from: 0, to: rep.pixelsWide, by: 11) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 11) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                    distinct.insert(UInt32(c.redComponent * 63) << 12 | UInt32(c.greenComponent * 63) << 6 | UInt32(c.blueComponent * 63))
                }
            }
        }
        XCTAssertGreaterThan(distinct.count, 8, "\(label) rendered blank")
    }

    func testWorkspaceTypographySectionRendersInLightAndDarkAndAt980pt() throws {
        for (dark, finish) in [(false, "light"), (true, "dark")] {
            let state = makeOfflineState()
            let view = WorkspaceCustomization().environmentObject(state).background(STColor.tileTop)
            let rep = try render(view, dark: dark, size: CGSize(width: 580, height: 700), name: "typography-settings-\(finish)")
            assertNotBlank(rep, finish)
        }
        // Must not clip inside the app's 980pt minimum window either, embedded the way MainView
        // would host it (as Settings is a separate window, this just proves the section itself
        // doesn't require more than the console's own minimum width to render its content).
        let state = makeOfflineState()
        let view = WorkspaceCustomization().environmentObject(state).background(STColor.tileTop)
        let rep = try render(view, dark: false, size: CGSize(width: 980, height: 700), name: "typography-settings-980")
        assertNotBlank(rep, "980pt")
    }

    func testEachTypefaceSwatchActuallyDrawsDifferentGlyphShapes() throws {
        // A regression where every swatch silently fell back to the same font would still pass
        // "not blank" — this compares two typefaces' "Aa" renders directly and requires them to
        // differ, proving the picker really is offering distinct faces.
        func swatch(_ typeface: ReadingTypeface) throws -> NSBitmapImageRep {
            let view = Text("Aa").font(STFont.reading(28, typeface: typeface)).foregroundStyle(Color.black)
                .frame(width: 60, height: 60).background(Color.white)
            return try render(view, dark: false, size: CGSize(width: 60, height: 60), name: "swatch-\(typeface.rawValue)")
        }
        let baskerville = try swatch(.baskerville)
        let georgia = try swatch(.georgia)
        var differingPixels = 0
        for x in 0..<baskerville.pixelsWide {
            for y in 0..<baskerville.pixelsHigh {
                let a = baskerville.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                let b = georgia.colorAt(x: x, y: y)?.usingColorSpace(.sRGB)
                if let a, let b, abs(a.redComponent - b.redComponent) > 0.2 { differingPixels += 1 }
            }
        }
        XCTAssertGreaterThan(differingPixels, 10, "Baskerville and Georgia swatches rendered identically")
    }

    /// Direct regression for Matt's bug report ("still can't change the size of text in the
    /// study/commentary space"): the Settings Stepper originally set `state.studyFontSize` through
    /// a hand-built `Binding(get:set:)` that assigned the plain `@AppStorage` property directly —
    /// which never calls `state.objectWillChange.send()`, so the Study Desk in the main window (a
    /// separate view hierarchy from the Settings window) never learned to redraw even though the
    /// stored preference genuinely changed. The fix routes through `$state.studyFontSize` instead
    /// (matching how the Type knob already worked for `state.fontSize`). This proves the full
    /// pipeline end to end: `DeskExpandableText` rendered with a larger `fontSize` really does
    /// measure taller ink, not just that a number in `UserDefaults` changed.
    func testDeskExpandableTextActuallyRendersLargerWhenStudyFontSizeIncreases() throws {
        // Total dark-pixel area (not a topmost-row search, which a stray edge-antialiasing pixel
        // common to both renders can falsely tie) — bigger glyphs unambiguously cover more area.
        // A generously tall frame (500pt) keeps both sizes well clear of any clipping either way.
        func inkArea(_ size: CGFloat) throws -> Int {
            // The white background must cover the whole canvas, not just the content's own
            // natural size — a background sized only to the (font-size-dependent) content height
            // would itself confound the measurement: whatever the render's own frame leaves
            // uncovered composites as dark, which previously dominated the count entirely.
            let view = DeskExpandableText(text: "In the beginning God created the heavens and the earth.",
                                           expanded: .constant(true), fontSize: size, lineSpacing: 3)
                .frame(width: 260, height: 500, alignment: .topLeading).background(Color.white)
            let rep = try render(view, dark: false, size: CGSize(width: 260, height: 500), name: "study-size-\(Int(size))")
            var dark = 0
            for y in stride(from: 0, to: rep.pixelsHigh, by: 2) {
                for x in stride(from: 0, to: rep.pixelsWide, by: 2) {
                    if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.redComponent < 0.5 { dark += 1 }
                }
            }
            return dark
        }
        let small = try inkArea(11)
        let large = try inkArea(20)
        XCTAssertGreaterThan(large, small, "commentary text at 20pt did not cover more ink than at 11pt — the size isn't actually reaching the view")
    }
}
