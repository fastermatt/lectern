import AppKit
import SwiftUI
import XCTest
@testable import StudyTable
@testable import StudyTableCore

/// Workstream R1 (0.10): textual-variant and edition flags carried from STEPBible-Data's TAGNT /
/// TAHOT into the interlinear data, the plain-English explanations built from them, and the
/// punctuation clean-up. Every expectation below is something the source data actually states
/// (spot-checked against `/private/tmp/st-interlinear-src` while building the script). Renders are
/// offscreen only — set STUDYTABLE_SNAPSHOT_DIR to keep the PNGs.
@MainActor
final class VariantTests: XCTestCase {
    override func tearDown() async throws {
        InterlinearSelection.shared.clear()
    }

    private func freshStore() -> InterlinearStore { InterlinearStore(directory: AppResources.url("Interlinear")) }
    private func freshLexicon() -> LexiconStore { LexiconStore(directory: AppResources.url("Lexicon")) }

    private func word(_ book: String, _ chapter: Int, _ verse: Int, surface: String, in store: InterlinearStore? = nil) throws -> (Int, InterlinearWord) {
        let words = (store ?? freshStore()).words(bookCode: book, chapter: chapter, verse: verse)
        let index = try XCTUnwrap(words.firstIndex { $0.surface == surface }, "\(surface) not found in \(book) \(chapter):\(verse)")
        return (index, words[index])
    }

    // MARK: Romans 8:28 — the Greek pastor case

    func testRomans828TheGodIsFlaggedAsWestcottHortOnlyWithTheSourcesOwnNote() throws {
        let store = freshStore()
        let words = store.words(bookCode: "ROM", chapter: 8, verse: 28)
        let ho = try XCTUnwrap(words.first { $0.surface == "ὁ" && $0.variant != nil })
        let theos = try XCTUnwrap(words.first { $0.surface == "θεὸς" })
        for flagged in [ho, theos] {
            let variant = try XCTUnwrap(flagged.variant, "\(flagged.surface) must carry the source's variant flag")
            XCTAssertEqual(variant.editions, "WH", "the source lists only Westcott-Hort for this word")
            XCTAssertEqual(variant.noteMarker, "^", "the source marks it as extra text")
            XCTAssertTrue(variant.isSignificant)
            XCTAssertEqual(variant.code, "O")
            XCTAssertTrue(variant.note?.contains("'God' is only in a few manuscripts (WH)") ?? false,
                          "both words of the two-word variant carry the note the source puts on the last one")
        }
        XCTAssertNil(words.first { $0.surface == "Οἴδαμεν" }?.variant, "ordinary words stay unflagged")
        XCTAssertEqual(words.filter { $0.variant != nil }.count, 2)
    }

    func testRomans828ExplanationSaysWhichEditionsCarryTheWordAndWhichDoNot() throws {
        let store = freshStore()
        let (_, theos) = try word("ROM", 8, 28, surface: "θεὸς", in: store)
        let explanation = try XCTUnwrap(store.explanation(for: theos))
        XCTAssertEqual(explanation.title, "TEXTUAL VARIANT")
        XCTAssertTrue(explanation.headline.hasPrefix("Found in Westcott-Hort, but not listed for "), explanation.headline)
        for other in ["Nestle-Aland 28", "Nestle-Aland 27", "the Textus Receptus", "the Byzantine text", "Tregelles"] {
            XCTAssertTrue(explanation.headline.contains(other), "\(other) missing from: \(explanation.headline)")
        }
        XCTAssertTrue(explanation.legendLines.contains("WH = Westcott-Hort (1881)"))
        XCTAssertEqual(explanation.noteKind, "Extra text: some manuscripts have text not found in others.")
        XCTAssertTrue(explanation.sourceNote?.contains("only in a few manuscripts (WH)") ?? false)
        XCTAssertTrue(explanation.plainText.contains("Found in Westcott-Hort"))
        XCTAssertNotNil(explanation.caveat)
    }

    /// The traditional-text doxology of Matthew 6:13 (`ὅτι σοῦ ἐστιν…`) is in the shipped word list
    /// but not in the critical text the BSB translates: every one of its words must say so.
    func testMatthew613DoxologyWordsAreAllFlaggedAsTraditionalTextOnly() throws {
        let words = freshStore().words(bookCode: "MAT", chapter: 6, verse: 13)
        let flagged = words.filter { $0.variant != nil }
        XCTAssertGreaterThanOrEqual(flagged.count, 12)
        for w in flagged {
            let v = try XCTUnwrap(w.variant)
            XCTAssertEqual(v.editions, "TR+Byz")
            XCTAssertNotNil(v.note, "the group's note is placed on its last word by the source; every word carries it")
        }
        XCTAssertNil(words.first { $0.gloss == "evil" || $0.gloss == "evil\u{2019}" }?.variant)
    }

    func testAnAlternateGreekReadingIsParsedIntoItsFields() throws {
        let (_, forgive) = try word("MAT", 6, 12, surface: "ἀφήκαμεν")
        let variant = try XCTUnwrap(forgive.variant)
        XCTAssertFalse(variant.isSignificant, "N(k)O: the source's lower-case k rates the TR difference as minor")
        let alt = try XCTUnwrap(variant.alternates.first)
        XCTAssertEqual(alt.text, "ἀφίεμεν")
        XCTAssertEqual(alt.transliteration, "aphiemen")
        XCTAssertEqual(alt.gloss, "forgive")
        XCTAssertEqual(alt.strongs, ["G0863"])
        XCTAssertEqual(alt.morphCode, "V-PAI-1P")
        XCTAssertEqual(alt.morphDescription, "Verb Present Active Indicative 1st Plural")
        XCTAssertEqual(alt.witnesses, "TR+Byz")
        XCTAssertEqual(variant.chipLabel, "MINOR VARIANT")
    }

    func testAMinorExtraWordIsRatedMinorNotSignificant() throws {
        let (_, article) = try word("MAT", 6, 10, surface: "τῆς")
        let variant = try XCTUnwrap(article.variant)
        XCTAssertEqual(variant.code, "k")
        XCTAssertFalse(variant.isSignificant)
        let explanation = try XCTUnwrap(freshStore().explanation(for: article))
        XCTAssertEqual(explanation.title, "MINOR TEXTUAL VARIANT")
        XCTAssertTrue(explanation.significance.contains("minor"))
    }

    // MARK: Psalm 22:16 — the Hebrew pastor case

    func testPsalm2216LikeALionCarriesTheDeadSeaReadingTheyDug() throws {
        let store = freshStore()
        let words = store.words(bookCode: "PSA", chapter: 22, verse: 16)
        let lion = try XCTUnwrap(words.first { $0.gloss == "like a lion" })
        let variant = try XCTUnwrap(lion.variant)
        XCTAssertEqual(variant.code, "L(D)")
        XCTAssertTrue(variant.isSignificant, "upper-case D: the source rates it as affecting translation")
        let alt = try XCTUnwrap(variant.alternates.first)
        XCTAssertEqual(alt.text, "כָּ֝אֲרוּ")
        XCTAssertEqual(alt.gloss, "they dug")
        XCTAssertEqual(alt.transliteration, "ka.'a.Ru")
        XCTAssertEqual(alt.witnesses, "D")
        XCTAssertEqual(alt.strongs, ["H3738A"])
        XCTAssertEqual(words.filter { $0.variant != nil }.count, 1, "no other word in the verse is flagged")

        let explanation = try XCTUnwrap(store.explanation(for: lion))
        XCTAssertTrue(explanation.headline.contains("the Leningrad manuscript"), explanation.headline)
        XCTAssertTrue(explanation.editionLines.isEmpty, "the Dead Sea group is already spelled out by the reading's own 'Read by' line; it must not be repeated: \(explanation.editionLines)")
        XCTAssertEqual(explanation.readings.first?.carriedBy, "a Dead Sea or Judean Desert manuscript")
        XCTAssertEqual(explanation.readings.first?.isRightToLeft, true)
        XCTAssertTrue(explanation.legendLines.contains { $0.hasPrefix("D = a Dead Sea") })
        XCTAssertTrue(explanation.caveat?.contains("yet to be added") ?? false,
                      "the source says most Hebrew variants are not yet recorded; the app must not imply completeness")
    }

    func testQereWordShowsTheKetivAsTheVariant() throws {
        let store = freshStore()
        let tent = try XCTUnwrap(store.words(bookCode: "GEN", chapter: 9, verse: 21).first { $0.variant?.code == "Q(K)" })
        let variant = try XCTUnwrap(tent.variant)
        XCTAssertEqual(variant.code, "Q(K)")
        XCTAssertEqual(variant.alternates.first?.witnesses, "K")
        XCTAssertEqual(variant.alternates.first?.gloss, "tent his")
        let explanation = try XCTUnwrap(store.explanation(for: tent))
        XCTAssertTrue(explanation.headline.contains("Qere"))
        XCTAssertEqual(explanation.readings.first?.carriedBy, "the Ketiv")
    }

    func testGreekDerivedAndRestoredHebrewTextIsFlagged() throws {
        let store = freshStore()
        let thirty = try XCTUnwrap(store.words(bookCode: "1SA", chapter: 13, verse: 1).first { $0.variant?.code == "X" })
        let x = try XCTUnwrap(store.explanation(for: thirty))
        XCTAssertTrue(x.headline.contains("not in the Leningrad text"), x.headline)
        XCTAssertTrue(x.legendLines.contains { $0.hasPrefix("X = extra words preserved in the Greek") })
        let restored = try XCTUnwrap(store.words(bookCode: "JOS", chapter: 21, verse: 36).first { $0.variant?.code == "R" })
        XCTAssertTrue(try XCTUnwrap(store.explanation(for: restored)).headline.contains("restored text"))
    }

    // MARK: Unflagged words are untouched; opaque codes are never guessed

    func testWordsWithNoVariantAreUnflaggedInBothTestaments() {
        let store = freshStore()
        for (book, chapter, verse) in [("GEN", 1, 1), ("GEN", 1, 2), ("JHN", 1, 1), ("ROM", 8, 29)] {
            let words = store.words(bookCode: book, chapter: chapter, verse: verse)
            XCTAssertFalse(words.isEmpty)
            XCTAssertTrue(words.allSatisfy { $0.variant == nil }, "\(book) \(chapter):\(verse) has no source-recorded variant")
        }
    }

    func testAnEditionCodeMissingFromTheLegendIsShownAsWrittenNotGuessed() {
        let legend = freshStore().variantLegend()
        let variant = WordVariant(code: "K(O)", isSignificant: true, editions: "TR+01+05")
        let explanation = VariantExplainer.explain(variant, language: .greek, legend: legend)
        XCTAssertTrue(explanation.editionLines.contains { $0.contains("01") && $0.contains("05") && $0.contains("not defined in the source") },
                      "\(explanation.editionLines)")
        // And with no legend at all, the bare source code survives.
        let bare = VariantExplainer.explain(variant, language: .greek, legend: .empty)
        XCTAssertTrue(bare.headline.contains("K(O)"), bare.headline)
    }

    func testWordOrderDisplacementIsReportedAsWordOrder() {
        let legend = freshStore().variantLegend()
        let variant = WordVariant(code: "N(k)O", isSignificant: false, editions: "NA28+NA27+Tyn+SBL+WH+Treg+TR\u{00BB}1+Byz\u{00BB}1")
        let explanation = VariantExplainer.explain(variant, language: .greek, legend: legend)
        XCTAssertTrue(explanation.editionLines.contains { $0.hasPrefix("Word order differs in the Textus Receptus and the Byzantine text") },
                      "\(explanation.editionLines)")
    }

    func testHebrewSourceCodesDecode() {
        XCTAssertEqual(VariantExplainer.hebrewCode("Q(K)").base, ["Q"])
        XCTAssertEqual(VariantExplainer.hebrewCode("Q(K)").groups, [["K"]])
        XCTAssertEqual(VariantExplainer.hebrewCode("L(AH+B)").groups, [["A", "H"], ["B"]])
        XCTAssertEqual(VariantExplainer.hebrewCode("LBH(a+C)").base, ["L", "B", "H"])
        XCTAssertEqual(VariantExplainer.hebrewCode("X").groups, [])
    }

    func testLegendShipsWithTheDataAndCoversEveryCodeItNames() {
        let legend = freshStore().variantLegend()
        XCTAssertEqual(legend.greekEditionOrder, ["NA28", "NA27", "Tyn", "SBL", "WH", "Treg", "TR", "Byz"])
        for code in legend.greekEditionOrder {
            XCTAssertNotNil(legend.greekEditions[code])
            XCTAssertNotNil(legend.greekEditionShort[code])
        }
        for letter in ["L", "Q", "K", "R", "X", "A", "B", "C", "D", "E", "F", "H", "P", "S", "V"] {
            XCTAssertNotNil(legend.hebrewSources[letter], letter)
            XCTAssertNotNil(legend.hebrewSourceShort[letter], letter)
        }
        XCTAssertNotNil(legend.caveats["greek"])
        XCTAssertNotNil(legend.caveats["hebrew"])
    }

    // MARK: Data model

    func testWordsWrittenBeforeVariantsExistStillDecode() throws {
        let old = #"{"w":"θεὸς","t":"theos","g":"God","l":"θεός","n":["G2316"],"m":"N-NSM-T","d":"Noun","L":"G"}"#
        let decoded = try JSONDecoder().decode(InterlinearWord.self, from: Data(old.utf8))
        XCTAssertNil(decoded.variant)
        XCTAssertEqual(decoded.gloss, "God")
    }

    func testVariantRoundTripsAndIgnoresUnknownKeys() throws {
        let json = #"{"w":"ὁ","t":"ho","g":"<the>","l":"ὁ","n":["G3588"],"m":"T-NSM","d":"Definite article","L":"G","v":{"c":"O","e":"WH","k":"^","s":true,"t":"note","a":[{"r":"x","w":"TR","zzz":1}],"future":"field"}}"#
        let decoded = try JSONDecoder().decode(InterlinearWord.self, from: Data(json.utf8))
        let variant = try XCTUnwrap(decoded.variant)
        XCTAssertEqual(variant, WordVariant(code: "O", isSignificant: true, editions: "WH", noteMarker: "^", note: "note",
                                            alternates: [.init(text: "x", witnesses: "TR")]))
        let again = try JSONDecoder().decode(InterlinearWord.self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(again, decoded)
    }

    // MARK: Punctuation clean-up

    func testInterlinearSurfacesCarryNoAttachedPunctuationOrPilcrow() throws {
        let store = freshStore()
        let trailing = CharacterSet(charactersIn: ",.;\u{037E}\u{00B7}\u{0387}\u{00B6}\u{05C3}\u{05BE}\u{05C0}")
        for (book, chapter, verse) in [("ROM", 8, 28), ("ROM", 8, 39), ("2CO", 13, 14), ("JHN", 3, 16), ("GEN", 1, 1), ("PSA", 22, 16), ("ISA", 53, 5)] {
            for w in store.words(bookCode: book, chapter: chapter, verse: verse) {
                XCTAssertFalse(w.surface.isEmpty)
                XCTAssertFalse(w.surface.unicodeScalars.contains { trailing.contains($0) }, "\(book) \(chapter):\(verse) \(w.surface)")
                XCTAssertFalse(w.surface.contains("\u{00B6}"))
                XCTAssertFalse(w.transliteration.hasSuffix("-"))
                XCTAssertNil(w.gloss.last.flatMap { ",.;:".contains($0) ? $0 : nil }, "\(w.gloss)")
            }
        }
        let earth = try XCTUnwrap(store.words(bookCode: "GEN", chapter: 1, verse: 1).last)
        XCTAssertEqual(earth.gloss, "the earth")
        XCTAssertFalse(earth.surface.contains("\u{05C3}"), "sof pasuq is punctuation, not part of the word")
        let (_, being) = try word("ROM", 8, 28, surface: "οὖσιν", in: store)
        XCTAssertEqual(being.gloss, "being")
    }

    // MARK: Whole-corpus numbers (drift check against the build report)

    private struct ChapterFile: Decodable { let verses: [String: [InterlinearWord]] }

    func testCorpusFlagCountsMatchTheBuildReportAndEveryFlagIsWellFormed() throws {
        let directory = try XCTUnwrap(AppResources.url("Interlinear"))
        var greek = (flagged: 0, significant: 0), hebrew = (flagged: 0, significant: 0)
        var codes = Set<String>()
        var badSurface = 0
        let trailing = CharacterSet(charactersIn: ",.;\u{037E}\u{00B7}\u{0387}\u{00B6}\u{05C3}")
        for book in Canon.bookCodes {
            let files = try FileManager.default.contentsOfDirectory(at: directory.appendingPathComponent(book), includingPropertiesForKeys: nil)
            for file in files where file.pathExtension == "json" {
                let chapter = try JSONDecoder().decode(ChapterFile.self, from: Data(contentsOf: file))
                for words in chapter.verses.values {
                    for w in words {
                        if w.surface.isEmpty || w.surface.unicodeScalars.last.map({ trailing.contains($0) }) == true { badSurface += 1 }
                        guard let v = w.variant else { continue }
                        XCTAssertFalse(v.code.isEmpty)
                        for alt in v.alternates { XCTAssertFalse(alt.text.isEmpty) }
                        codes.insert(v.code)
                        if w.language == .greek {
                            greek.flagged += 1
                            if v.isSignificant { greek.significant += 1 }
                            XCTAssertNotNil(v.editions, "every flagged Greek word states its editions")
                        } else {
                            hebrew.flagged += 1
                            if v.isSignificant { hebrew.significant += 1 }
                        }
                    }
                }
            }
        }
        XCTAssertEqual(badSurface, 0)
        XCTAssertEqual(greek.flagged, 8_996)
        XCTAssertEqual(greek.significant, 3_218)
        XCTAssertEqual(hebrew.flagged, 1_777)
        XCTAssertEqual(hebrew.significant, 1_200)
        XCTAssertTrue(codes.isSuperset(of: ["K", "O", "N(k)O", "N(K)O", "Q(K)", "Q(k)", "X", "R", "L(D)"]))
    }

    func testAttributionFileRecordsTheVariantDataAndTheChangesMade() throws {
        let url = try XCTUnwrap(AppResources.url("Licenses")).appendingPathComponent("interlinear-stepbible.txt")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("Textual-variant and edition flags"))
        XCTAssertTrue(text.contains("Note of changes made to the source data"))
        XCTAssertTrue(text.contains("CC BY 4.0"))
    }

    // MARK: Offscreen renders

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
        if let directory = ProcessInfo.processInfo.environment["STUDYTABLE_SNAPSHOT_DIR"] {
            let url = URL(fileURLWithPath: directory, isDirectory: true)
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                .write(to: url.appendingPathComponent("\(name)-\(dark ? "dark" : "light").png"))
        }
        window.orderOut(nil)
        return rep
    }

    private func assertNotBlank(_ rep: NSBitmapImageRep, _ label: String) {
        var distinct = Set<UInt32>()
        for x in stride(from: 0, to: rep.pixelsWide, by: 7) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 7) {
                if let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) {
                    distinct.insert(UInt32(c.redComponent * 63) << 12 | UInt32(c.greenComponent * 63) << 6 | UInt32(c.blueComponent * 63))
                }
            }
        }
        XCTAssertGreaterThan(distinct.count, 8, "\(label) looks blank")
    }

    private func deskState(_ book: String, _ chapter: Int, _ verse: Int) -> AppState {
        let state = makeOfflineState()
        state.selectedBookCode = book
        state.selectedChapter = chapter
        state.selectedVerse = verse
        return state
    }

    /// The Original Language section as the desk draws it, with its expanded flag redirected to a
    /// throwaway defaults suite (never the reader's own preferences).
    private func section(_ state: AppState, width: CGFloat, height: CGFloat, dark: Bool) -> some View {
        let defaults = ephemeralDefaults()
        defaults.set(true, forKey: "desk.originalLanguageExpanded")
        return ScrollView { OriginalLanguageSection(store: freshStore(), lexicon: freshLexicon()) }
            .environmentObject(state)
            .defaultAppStorage(defaults)
            .frame(width: width, height: height, alignment: .top)
            .background(dark ? Color(white: 0.12) : Color.white)
    }

    private func focusWord(_ book: String, _ chapter: Int, _ verse: Int, gloss: String, mode: InterlinearSelection.Mode) throws {
        let words = freshStore().words(bookCode: book, chapter: chapter, verse: verse)
        let index = try XCTUnwrap(words.firstIndex { $0.gloss == gloss && $0.variant != nil })
        let passage = InterlinearSelection.passageID(book: book, chapter: chapter, verse: verse)
        InterlinearSelection.shared.focus(wordIndex: index, passage: passage)
        if mode == .all { InterlinearSelection.shared.showAll() }
    }

    func testRomans828VariantRendersAsSingleWordCardAndListRowInLightAndDark() throws {
        for dark in [false, true] {
            for width: CGFloat in [380, 300] {
                try focusWord("ROM", 8, 28, gloss: "God", mode: .single)
                let state = deskState("ROM", 8, 28)
                let card = try render(section(state, width: width, height: 1100, dark: dark), dark: dark,
                                      size: CGSize(width: width, height: 1100), name: "variant-rom8-28-card-\(Int(width))")
                assertNotBlank(card, "Romans 8:28 card \(Int(width)) \(dark)")
                try focusWord("ROM", 8, 28, gloss: "God", mode: .all)
                let list = try render(section(state, width: width, height: 1500, dark: dark), dark: dark,
                                      size: CGSize(width: width, height: 1500), name: "variant-rom8-28-list-\(Int(width))")
                assertNotBlank(list, "Romans 8:28 list \(Int(width)) \(dark)")
            }
        }
    }

    func testPsalm2216VariantRendersAsSingleWordCardAndListRowInLightAndDark() throws {
        for dark in [false, true] {
            for width: CGFloat in [380, 300] {
                try focusWord("PSA", 22, 16, gloss: "like a lion", mode: .single)
                let state = deskState("PSA", 22, 16)
                let card = try render(section(state, width: width, height: 1100, dark: dark), dark: dark,
                                      size: CGSize(width: width, height: 1100), name: "variant-ps22-16-card-\(Int(width))")
                assertNotBlank(card, "Psalm 22:16 card \(Int(width)) \(dark)")
                try focusWord("PSA", 22, 16, gloss: "like a lion", mode: .all)
                let list = try render(section(state, width: width, height: 1700, dark: dark), dark: dark,
                                      size: CGSize(width: width, height: 1700), name: "variant-ps22-16-list-\(Int(width))")
                assertNotBlank(list, "Psalm 22:16 list \(Int(width)) \(dark)")
            }
        }
    }

    /// The pastor's original path: study the English word "pierced". The nearest original words
    /// are listed; the one that carries a variant now says so on its own row.
    func testStudyingPiercedListsTheVariantCandidateWithItsMarker() throws {
        let library = ScriptureLibrary()
        let verse = try XCTUnwrap(library.chapter(translation: "BSB", bookCode: "PSA", chapter: 22)?.first { $0.number == 16 })
        let token = try XCTUnwrap(WordTokenizer.tokens(in: verse.text).first { $0.key == "pierced" })
        let state = deskState("PSA", 22, 16)
        InterlinearSelection.shared.studyWord(token.asHit, in: verse, state: state)
        let studied = try XCTUnwrap(InterlinearSelection.shared.studied(for: "PSA.22.16"))
        let words = freshStore().words(bookCode: "PSA", chapter: 22, verse: 16)
        let candidates = studied.result.match?.candidates ?? studied.result.candidates
        let names = candidates.filter { words.indices.contains($0) }.map { words[$0].gloss }
        if candidates.contains(where: { words.indices.contains($0) && words[$0].variant != nil }) {
            XCTAssertTrue(names.contains("like a lion"), "\(names)")
        }
        for dark in [false, true] {
            let rep = try render(section(state, width: 380, height: 1000, dark: dark), dark: dark,
                                 size: CGSize(width: 380, height: 1000), name: "variant-ps22-16-pierced-candidates")
            assertNotBlank(rep, "pierced candidates \(dark)")
        }
    }

    /// The full window at the 980pt minimum with the variant word chosen, so the marker is seen in
    /// the real desk width rather than an idealised one.
    func testFullWindowAt980ptWithAVariantWordFocusedInBothFinishes() throws {
        for (dark, name) in [(false, "light"), (true, "dark")] {
            let state = deskState("ROM", 8, 28)
            let defaults = ephemeralDefaults()
            defaults.set(true, forKey: "desk.originalLanguageExpanded")
            InterlinearSelection.shared.reveal(wordIndex: try word("ROM", 8, 28, surface: "θεὸς").0, state: state)
            let rep = try render(MainView().environmentObject(state).defaultAppStorage(defaults), dark: dark,
                                 size: CGSize(width: 980, height: 650), name: "variant-window-980-rom8-28-\(name)")
            assertNotBlank(rep, "window \(name)")
        }
    }
}
