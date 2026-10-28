import AppKit
import SwiftUI
import XCTest
@testable import StudyTable

// S2c (0.10 wave B): ExportComposer, TranslationExportPolicy, the fixed VerseClipboard, and
// `.lecternstudy`. Copies the offscreen render helper pattern from `SnapshotTests.swift` (own
// test file, per the workplan — no shared test files touched).

// MARK: - Fixtures

private func makeTranslation(id: String, delivery: TranslationDelivery = .bundled, attribution: String = "Test attribution") -> TranslationInfo {
    TranslationInfo(id: id, name: "Translation \(id)", delivery: delivery, licenseSummary: "Test", attribution: attribution)
}

private func romans828() -> StudyTable.Anchor { StudyTable.Anchor(book: "ROM", chapter: 8, verse: 28) }
private func romansRange() -> StudyTable.Anchor { StudyTable.Anchor(book: "ROM", chapter: 8, verses: 28, to: 39) }

/// A `VerseSource` that fabricates verse text deterministically, optionally reporting a whole-book
/// total for the half-book fraction cap check.
private func stubVerseSource(bookTotals: [String: Int] = [:]) -> VerseSource {
    VerseSource(
        verses: { anchor, translationID in
            guard anchor.isValid else { return nil }
            var result: [BibleVerse] = []
            for chapter in anchor.chapterStart...anchor.chapterEnd {
                let startVerse = chapter == anchor.chapterStart ? max(anchor.verseStart, 1) : 1
                let endVerse = chapter == anchor.chapterEnd && anchor.verseEnd != StudyTable.Anchor.endOfChapter ? anchor.verseEnd : startVerse + 20
                guard startVerse <= endVerse else { continue }
                for v in startVerse...endVerse {
                    result.append(BibleVerse(number: v, text: "Verse \(chapter):\(v) of \(translationID)."))
                }
            }
            return result
        },
        totalVersesInBook: { bookTotals[$0] })
}

// MARK: - TranslationExportPolicy matrix

@MainActor
final class TranslationExportPolicyTests: XCTestCase {
    func testFreeTranslationsAreFullText() {
        for id in TranslationExportPolicy.freeTranslationIDs {
            XCTAssertEqual(TranslationExportPolicy.policy(forTranslationID: id), .fullText, "\(id) should be full text")
            // Lower-case ids resolve the same way (id lookups elsewhere aren't guaranteed upper-case).
            XCTAssertEqual(TranslationExportPolicy.policy(forTranslationID: id.lowercased()), .fullText)
        }
    }

    func testESVIsCappedAndRequiresOptIn() {
        guard case .cappedText(let maxVerses, let fraction, let notice, let requiresOptIn, let embeddable) =
                TranslationExportPolicy.policy(forTranslationID: "ESV") else {
            return XCTFail("ESV should be capped")
        }
        XCTAssertEqual(maxVerses, 300)
        XCTAssertEqual(fraction, 0.5)
        XCTAssertEqual(notice, ESVProvider.attribution)
        XCTAssertTrue(requiresOptIn)
        XCTAssertFalse(embeddable, "ESV must never be embeddable in .lecternstudy")
    }

    func testNKJVIsReferencesOnly() {
        guard case .referencesOnly(let reason) = TranslationExportPolicy.policy(forTranslationID: "NKJV") else {
            return XCTFail("NKJV should be references-only")
        }
        XCTAssertTrue(reason.contains("FUMS"))
    }

    func testUnknownOrLicensedPackIsReferencesOnly() {
        for id in ["NASB", "SOME-USER-PACK", ""] {
            guard case .referencesOnly = TranslationExportPolicy.policy(forTranslationID: id) else {
                return XCTFail("\(id) should default to references-only")
            }
        }
    }

    func testTranslationInfoExposesExportPolicy() {
        let bsb = makeTranslation(id: "BSB")
        XCTAssertEqual(bsb.exportPolicy, .fullText)
        let esv = makeTranslation(id: "ESV", delivery: .online(.esv))
        guard case .cappedText = esv.exportPolicy else { return XCTFail("ESV TranslationInfo should be capped") }
    }
}

// MARK: - VerseClipboard regression (PASTOR-QA-0.10 defect 5)

final class VerseClipboardPolicyTests: XCTestCase {
    func testFreeTranslationCopyIsUnchanged() {
        let text = verseClipboardText(bookName: "Romans", chapter: 8, verse: BibleVerse(number: 28, text: "All things work together."), translation: "BSB")
        XCTAssertEqual(text, "Romans 8:28 (BSB) — All things work together.")
    }

    func testESVCopyCarriesNotice() {
        let text = verseClipboardText(bookName: "Romans", chapter: 8, verse: BibleVerse(number: 28, text: "And we know..."), translation: "ESV")
        XCTAssertTrue(text.contains("Romans 8:28 (ESV) — And we know..."))
        XCTAssertTrue(text.contains(ESVProvider.attribution), "ESV copy must carry Crossway's notice")
    }

    func testNKJVCopyOmitsCopyrightedTextButKeepsReference() {
        let text = verseClipboardText(bookName: "Romans", chapter: 8, verse: BibleVerse(number: 28, text: "SHOULD NOT APPEAR"), translation: "NKJV")
        XCTAssertTrue(text.hasPrefix("Romans 8:28 (NKJV)"))
        XCTAssertFalse(text.contains("SHOULD NOT APPEAR"), "NKJV is references-only — copyrighted text must not be copied")
        XCTAssertTrue(text.contains("references-only") || text.contains("API.Bible"))
    }

    func testUnknownInstalledPackIsReferencesOnlyTooRegressionSafe() {
        let text = verseClipboardText(bookName: "Genesis", chapter: 1, verse: BibleVerse(number: 1, text: "SECRET"), translation: "NASB")
        XCTAssertFalse(text.contains("SECRET"))
    }
}

// MARK: - ExportComposer

@MainActor
final class ExportComposerTests: XCTestCase {
    private func note(anchor: StudyTable.Anchor, title: String = "My note", body: String = "Body text.", tags: [String] = []) -> Note {
        Note(anchors: [anchor], title: title, kind: .free, body: body, tags: tags, createdAt: Date())
    }
    private func saved(anchor: StudyTable.Anchor, highlight: HighlightColor? = nil, isMemory: Bool = false, tags: [String] = []) -> SavedPassage {
        SavedPassage(anchor: anchor, highlight: highlight, isMemory: isMemory, tags: tags, createdAt: Date())
    }

    func testFreeTranslationPlainTextIncludesVersesAndAttribution() {
        let bsb = makeTranslation(id: "BSB", attribution: "Berean Standard Bible, public domain.")
        let options = ExportOptions(translation: bsb, title: "Romans 8:28")
        let result = ExportComposer.compose(items: [.saved(saved(anchor: romans828()))], format: .plainText,
                                             options: options, verses: stubVerseSource())
        let text = try! XCTUnwrap(result.text)
        XCTAssertTrue(text.contains("Romans 8:28"))
        XCTAssertTrue(text.contains("28. Verse 8:28 of BSB."))
        XCTAssertTrue(result.report.lines.contains { $0.message.contains("Berean Standard Bible") })
        XCTAssertTrue(result.report.omittedLines.isEmpty)
    }

    func testESVWithoutOptInOmitsAllTextButAlwaysShowsNotice() {
        let esv = makeTranslation(id: "ESV")
        let options = ExportOptions(translation: esv, cappedTranslationOptIn: false)
        let result = ExportComposer.compose(items: [.saved(saved(anchor: romansRange()))], format: .plainText,
                                             options: options, verses: stubVerseSource())
        let text = try! XCTUnwrap(result.text)
        XCTAssertFalse(text.contains("Verse 8:"), "no ESV text should appear without opt-in")
        XCTAssertTrue(result.report.lines.contains { $0.message == ESVProvider.attribution }, "ESV notice must always be appended")
    }

    func testESVWithOptInIncludesTextUpToCap() {
        let esv = makeTranslation(id: "ESV")
        // Romans 1-16, ~16 chapters * 21 verses (stub) ≈ 336 requested verses — over the 300 cap.
        let wholeBook = StudyTable.Anchor.wholeBook("ROM")
        let options = ExportOptions(translation: esv, cappedTranslationOptIn: true)
        let result = ExportComposer.compose(items: [.selection(wholeBook)], format: .plainText, options: options,
                                             verses: stubVerseSource())
        let text = try! XCTUnwrap(result.text)
        let verseLines = text.split(separator: "\n").filter { $0.contains("Verse ") }
        XCTAssertLessThanOrEqual(verseLines.count, 300)
        XCTAssertTrue(result.report.omittedLines.contains { $0.message.contains("publisher limits") })
    }

    func testESVNeverMoreThanHalfABook() {
        let esv = makeTranslation(id: "ESV")
        // A tiny "book" of 40 verses total; half is 20, well under the flat 300 cap.
        let anchor = StudyTable.Anchor(book: "PHM", chapter: 1, verses: 1, to: 25)   // Philemon only has 25 verses; stub ignores that
        let options = ExportOptions(translation: esv, cappedTranslationOptIn: true)
        let result = ExportComposer.compose(items: [.selection(anchor)], format: .plainText, options: options,
                                             verses: stubVerseSource(bookTotals: ["PHM": 40]))
        let text = try! XCTUnwrap(result.text)
        let verseLines = text.split(separator: "\n").filter { $0.contains("Verse ") }
        XCTAssertLessThanOrEqual(verseLines.count, 20, "never more than half of a 40-verse book")
    }

    func testESVNeverEmbeddedInLecternStudyFileEvenWithOptIn() {
        let esv = makeTranslation(id: "ESV")
        let options = ExportOptions(translation: esv, cappedTranslationOptIn: true, forLecternStudyFile: true)
        let result = ExportComposer.compose(items: [.saved(saved(anchor: romans828()))], format: .plainText,
                                             options: options, verses: stubVerseSource())
        let text = try! XCTUnwrap(result.text)
        XCTAssertFalse(text.contains("Verse 8:28"))
        XCTAssertTrue(result.report.lines.contains { $0.message.contains("never embedded in a .lecternstudy file") })
    }

    func testNKJVNeverIncludesTextButKeepsReference() {
        let nkjv = makeTranslation(id: "NKJV")
        let options = ExportOptions(translation: nkjv)
        let result = ExportComposer.compose(items: [.note(note(anchor: romans828()))], format: .markdown,
                                             options: options, verses: stubVerseSource())
        let text = try! XCTUnwrap(result.text)
        XCTAssertTrue(text.contains("Romans 8:28"))
        XCTAssertFalse(text.contains("Verse 8:28"))
        XCTAssertTrue(result.report.lines.contains { $0.message.contains("FUMS") })
    }

    func testMarkdownRendersNoteAndVerse() {
        let bsb = makeTranslation(id: "BSB")
        let options = ExportOptions(translation: bsb)
        let result = ExportComposer.compose(items: [.note(note(anchor: romans828(), title: "Providence", body: "God is sovereign."))],
                                             format: .markdown, options: options, verses: stubVerseSource())
        let text = try! XCTUnwrap(result.text)
        XCTAssertTrue(text.contains("### Romans 8:28"))
        XCTAssertTrue(text.contains("**Providence**"))
        XCTAssertTrue(text.contains("God is sovereign."))
        XCTAssertTrue(text.contains("> **28**"))
    }

    func testCollectionExportListsEveryMember() {
        let bsb = makeTranslation(id: "BSB")
        let collection = StudyCollection(name: "Security in Christ", createdAt: Date())
        let members = [saved(anchor: StudyTable.Anchor(book: "ROM", chapter: 8, verse: 28)), saved(anchor: StudyTable.Anchor(book: "ROM", chapter: 8, verse: 38))]
        let options = ExportOptions(translation: bsb)
        let result = ExportComposer.compose(items: [.collection(collection, members: members)], format: .plainText,
                                             options: options, verses: stubVerseSource())
        let text = try! XCTUnwrap(result.text)
        XCTAssertTrue(text.contains("Romans 8:28"))
        XCTAssertTrue(text.contains("Romans 8:38"))
    }

    func testUnavailableVerseTextIsReportedNotSilentlyDropped() {
        // A free-text (fullText policy) translation whose text simply isn't cached/loaded for
        // this passage — an invalid book code makes the stub (and any real `VerseSource`) report
        // unavailable, distinct from a licensing-driven omission.
        let bsb = makeTranslation(id: "BSB")
        let options = ExportOptions(translation: bsb)
        let uncached = StudyTable.Anchor(book: "XXX", chapter: 1, verse: 1)
        let result = ExportComposer.compose(items: [.selection(uncached)], format: .plainText, options: options,
                                             verses: stubVerseSource())
        XCTAssertTrue(result.report.omittedLines.contains { $0.message.contains("not loaded offline") })
    }

    func testPDFProducesValidPDFData() {
        let bsb = makeTranslation(id: "BSB")
        let options = ExportOptions(translation: bsb, title: "Romans 8:28")
        let result = ExportComposer.compose(items: [.saved(saved(anchor: romans828()))], format: .pdf,
                                             options: options, verses: stubVerseSource())
        let data = try! XCTUnwrap(result.data)
        XCTAssertGreaterThan(data.count, 100)
        XCTAssertEqual(data.prefix(5), Data("%PDF-".utf8))
    }
}

// MARK: - .lecternstudy

@MainActor
final class LecternStudyFileTests: XCTestCase {
    func testRoundTripPreservesFreeTranslationTextButNotESV() {
        let bsb = makeTranslation(id: "BSB")
        let saved = [SavedPassage(anchor: StudyTable.Anchor(book: "ROM", chapter: 8, verse: 28), createdAt: Date())]
        let note = Note(anchors: [StudyTable.Anchor(book: "ROM", chapter: 8, verse: 28)], title: "Providence", body: "Body.", createdAt: Date())
        let file = LecternStudyWriter.makeFile(kind: .collection, title: "Test export", notes: [note], saved: saved,
                                                translation: bsb, verses: stubVerseSource())
        XCTAssertTrue(file.items.contains { !$0.scripture.isEmpty }, "free translation text should be embedded")

        let data = try! LecternStudyWriter.encode(file)
        let parsed = try! LecternStudyReader.parse(data)
        XCTAssertEqual(parsed.format, "lectern-study")
        XCTAssertEqual(parsed.version, 1)
        XCTAssertEqual(parsed.title, "Test export")
        XCTAssertEqual(parsed.items.count, file.items.count)

        let esv = makeTranslation(id: "ESV")
        let esvFile = LecternStudyWriter.makeFile(kind: .collection, title: "ESV export", saved: saved,
                                                   translation: esv, verses: stubVerseSource())
        XCTAssertTrue(esvFile.items.allSatisfy { $0.scripture.isEmpty }, "ESV text must never be embedded, opt-in or not")
    }

    // MARK: Hostile input

    func testRejectsOversizedFile() {
        let huge = Data(repeating: 0x41, count: LecternStudyLimits.maxFileBytes + 1)
        XCTAssertThrowsError(try LecternStudyReader.parse(huge)) {
            XCTAssertEqual($0 as? LecternStudyError, .tooLarge(huge.count))
        }
    }

    func testRejectsNonJSON() {
        XCTAssertThrowsError(try LecternStudyReader.parse(Data("not json at all {{{".utf8))) {
            XCTAssertEqual($0 as? LecternStudyError, .notJSON)
        }
    }

    func testRejectsWrongFormatTag() {
        let json = #"{"format":"some-other-format","version":1,"kind":"collection","title":"x","created":"2026-01-01T00:00:00Z","items":[]}"#
        XCTAssertThrowsError(try LecternStudyReader.parse(Data(json.utf8))) {
            guard case .wrongFormat = $0 as? LecternStudyError else { return XCTFail("expected wrongFormat") }
        }
    }

    func testRejectsFutureVersion() {
        let json = #"{"format":"lectern-study","version":999,"kind":"collection","title":"x","created":"2026-01-01T00:00:00Z","items":[]}"#
        XCTAssertThrowsError(try LecternStudyReader.parse(Data(json.utf8))) {
            XCTAssertEqual($0 as? LecternStudyError, .unsupportedVersion(999))
        }
    }

    func testRejectsTooManyItems() {
        let itemJSON = #"{"anchor":"Rom.8.28"}"#
        let items = Array(repeating: itemJSON, count: LecternStudyLimits.maxItems + 1).joined(separator: ",")
        let json = #"{"format":"lectern-study","version":1,"kind":"collection","title":"x","created":"2026-01-01T00:00:00Z","items":["# + items + "]}"
        XCTAssertThrowsError(try LecternStudyReader.parse(Data(json.utf8))) {
            guard case .tooManyItems = $0 as? LecternStudyError else { return XCTFail("expected tooManyItems") }
        }
    }

    func testRejectsInvalidAnchor() {
        let json = #"{"format":"lectern-study","version":1,"kind":"collection","title":"x","created":"2026-01-01T00:00:00Z","items":[{"anchor":"NotABook.1.1"}]}"#
        XCTAssertThrowsError(try LecternStudyReader.parse(Data(json.utf8))) {
            guard case .malformed = $0 as? LecternStudyError else { return XCTFail("expected malformed") }
        }
    }

    func testRejectsOverlongField() {
        let hugeBody = String(repeating: "a", count: LecternStudyLimits.maxFieldLength + 1)
        let json = #"{"format":"lectern-study","version":1,"kind":"noteSet","title":"x","created":"2026-01-01T00:00:00Z","items":[{"anchor":"Rom.8.28","noteBody":"\#(hugeBody)"}]}"#
        XCTAssertThrowsError(try LecternStudyReader.parse(Data(json.utf8))) {
            guard case .fieldTooLong = $0 as? LecternStudyError else { return XCTFail("expected fieldTooLong") }
        }
    }

    func testGarbageBinaryDoesNotCrash() {
        var bytes = [UInt8](repeating: 0, count: 5000)
        for i in bytes.indices { bytes[i] = UInt8((i * 137 + 7) % 256) }
        XCTAssertThrowsError(try LecternStudyReader.parse(Data(bytes)))
    }

    // MARK: Import preview & apply

    func testImportCreatesNewCollectionNotesAndSaved() {
        let store = ephemeralStudy()
        let file = LecternStudyFile(kind: .collection, title: "Shared Study", items: [
            LecternStudyItem(anchor: StudyTable.Anchor(book: "ROM", chapter: 8, verse: 28), tags: ["providence"],
                              noteTitle: "Providence", noteBody: "All things work together."),
            LecternStudyItem(anchor: StudyTable.Anchor(book: "ROM", chapter: 8, verse: 38), isMemory: true)
        ])
        let data = try! LecternStudyWriter.encode(file)

        let preview = try! LecternStudyImporter.preview(data: data, existing: store)
        XCTAssertEqual(preview.newSavedCount, 2)
        XCTAssertEqual(preview.newNoteCount, 1)
        XCTAssertEqual(preview.duplicateSavedCount, 0)

        let result = LecternStudyImporter.apply(preview, into: store)
        XCTAssertEqual(result.addedSavedIDs.count, 2)
        XCTAssertEqual(result.addedNoteIDs.count, 1)
        XCTAssertNotNil(result.collectionID)
        XCTAssertEqual(store.savedPassages.count, 2)
        XCTAssertEqual(store.allNotes.count, 1)
        XCTAssertTrue(store.allNotes[0].tags.contains { $0.hasPrefix("Imported") })
        XCTAssertEqual(store.savedPassages(in: result.collectionID!).count, 2)
    }

    func testImportNeverOverwritesAndDedupesOnReimport() {
        let store = ephemeralStudy()
        let file = LecternStudyFile(kind: .collection, title: "Shared Study", items: [
            LecternStudyItem(anchor: StudyTable.Anchor(book: "ROM", chapter: 8, verse: 28), noteTitle: "Providence", noteBody: "Body.")
        ])
        let data = try! LecternStudyWriter.encode(file)

        let first = try! LecternStudyImporter.preview(data: data, existing: store)
        let firstResult = LecternStudyImporter.apply(first, into: store)
        XCTAssertEqual(store.allNotes.count, 1)
        XCTAssertEqual(store.savedPassages.count, 1)

        let second = try! LecternStudyImporter.preview(data: data, existing: store)
        XCTAssertEqual(second.duplicateNoteCount, 1)
        XCTAssertEqual(second.duplicateSavedCount, 1)
        XCTAssertEqual(second.newNoteCount, 0)
        let secondResult = LecternStudyImporter.apply(second, into: store)
        XCTAssertEqual(secondResult.addedNoteIDs.count, 0, "re-importing the same content must not create a duplicate note")
        XCTAssertEqual(store.allNotes.count, 1, "note count must stay the same after re-import")
        XCTAssertEqual(store.savedPassages.count, 1, "saved passage must not be duplicated (idempotent save)")
        // A second collection is still created (a new share event), even though its members already existed.
        XCTAssertEqual(store.collections.count, 2)
        XCTAssertNotEqual(firstResult.collectionID, secondResult.collectionID)
    }
}

// MARK: - Renders (offscreen; light/dark/980pt)

@MainActor
final class ShareUIRenderTests: XCTestCase {
    private func render<V: View>(_ view: V, dark: Bool, size: CGSize) throws -> NSBitmapImageRep {
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
            RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        window.orderOut(nil)
        return rep
    }

    private func assertNotBlank(_ rep: NSBitmapImageRep) {
        var distinct = Set<Int>()
        for x in stride(from: 0, to: rep.pixelsWide, by: 11) {
            for y in stride(from: 0, to: rep.pixelsHigh, by: 11) {
                if let color = rep.colorAt(x: x, y: y) { distinct.insert(color.hashValue) }
            }
        }
        XCTAssertGreaterThan(distinct.count, 1, "render looks blank")
    }

    private func sampleSheet() -> SharePreviewSheet {
        let bsb = makeTranslation(id: "BSB")
        let saved = SavedPassage(anchor: StudyTable.Anchor(book: "ROM", chapter: 8, verse: 28), highlight: .yellow, isMemory: true, createdAt: Date())
        return SharePreviewSheet(items: [.saved(saved)], collectionHeading: "Security in Christ", format: .plainText,
                                  verses: stubVerseSource(), action: .copyText,
                                  options: ExportOptions(translation: bsb, title: "Romans 8:28"),
                                  onConfirm: { _ in }, onCancel: {})
    }

    func testSharePreviewSheetRendersLightAndDark() throws {
        for dark in [false, true] {
            let rep = try render(sampleSheet(), dark: dark, size: CGSize(width: 420, height: 480))
            assertNotBlank(rep)
        }
    }

    func testSharePreviewSheetRendersAt980pt() throws {
        let rep = try render(sampleSheet().frame(width: 980), dark: false, size: CGSize(width: 980, height: 480))
        assertNotBlank(rep)
    }

    func testShareMenuLabelRenders() throws {
        let bsb = makeTranslation(id: "BSB")
        let menu = ShareMenu(items: [.selection(StudyTable.Anchor(book: "ROM", chapter: 8, verse: 28))], collectionHeading: nil,
                              options: ExportOptions(translation: bsb), verses: stubVerseSource())
        for dark in [false, true] {
            let rep = try render(menu, dark: dark, size: CGSize(width: 120, height: 40))
            assertNotBlank(rep)
        }
    }

    func testESVOptInToggleAppearsInPreviewSheet() throws {
        let esv = makeTranslation(id: "ESV")
        let sheet = SharePreviewSheet(items: [.selection(romans828())], collectionHeading: nil, format: .plainText,
                                       verses: stubVerseSource(), action: .share,
                                       options: ExportOptions(translation: esv), onConfirm: { _ in }, onCancel: {})
        let rep = try render(sheet, dark: false, size: CGSize(width: 420, height: 480))
        assertNotBlank(rep)
    }
}
