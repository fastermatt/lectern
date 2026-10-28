import Foundation

// Real `VerseSource` adapters for `ExportComposer` — kept in their own file (not
// `ExportComposer.swift`) because the `ScriptureLibrary` extension below is `@MainActor`, while
// the composer itself is not.

/// One already-fetched chapter, from either a local pack (`ScriptureLibrary.chapter`) or an
/// online translation (`OnlineTranslationService.load`, awaited by the caller beforehand —
/// `OnlineChapterCache` is an actor, so bridging it into `ExportComposer`'s synchronous
/// `VerseSource` needs the fetch to already have happened; this composer never performs I/O).
struct PrefetchedChapter {
    var translationID: String
    var bookCode: String
    var chapter: Int
    var verses: [BibleVerse]
}

extension VerseSource {
    /// Builds a `VerseSource` purely from chapters the caller already has in hand — works
    /// identically whether they came from a local pack or an awaited online fetch, since by the
    /// time this runs it's just an array. `bookVerseCounts` (whole-book totals, all chapters) is
    /// only needed when the selected translation is a capped one (ESV) that enforces "never more
    /// than half a book"; omit it and the flat verse cap still applies on its own.
    static func prefetched(_ chapters: [PrefetchedChapter], bookVerseCounts: [String: Int] = [:]) -> VerseSource {
        var index: [String: [BibleVerse]] = [:]
        for chapter in chapters {
            index[key(chapter.translationID, chapter.bookCode, chapter.chapter)] = chapter.verses
        }
        return VerseSource(
            verses: { anchor, translationID in
                guard anchor.isValid, anchor.chapterStart <= anchor.chapterEnd else { return nil }
                var result: [BibleVerse] = []
                for ch in anchor.chapterStart...anchor.chapterEnd {
                    guard let verses = index[key(translationID, anchor.book, ch)] else { continue }
                    result.append(contentsOf: verses.filter { anchor.contains(chapter: ch, verse: $0.number) })
                }
                return result.isEmpty ? nil : result
            },
            totalVersesInBook: { bookCode in bookVerseCounts[bookCode] })
    }

    private static func key(_ translationID: String, _ bookCode: String, _ chapter: Int) -> String {
        "\(translationID.uppercased())|\(bookCode)|\(chapter)"
    }
}

@MainActor
extension ScriptureLibrary {
    /// Synchronous `VerseSource` backed only by locally loaded packs (bundled or user-installed —
    /// covers every free translation in `TranslationExportPolicy.freeTranslationIDs`). An online
    /// translation (ESV/NKJV) is never fetched here (`chapter(translation:bookCode:chapter:)`
    /// only reads local packs); it always reports unavailable so `ExportComposer` records an
    /// honest "not loaded offline" omission rather than silently fetching over the network mid
    /// export. A caller that wants ESV/NKJV text should `await OnlineTranslationService.load(...)`
    /// first and hand the result to `VerseSource.prefetched(_:)` instead (merge the two with
    /// `VerseSource(verses: { a, t in localSource.verses(a, t) ?? onlineSource.verses(a, t) })`).
    func localPackVerseSource() -> VerseSource {
        VerseSource(
            verses: { [weak self] anchor, translationID in
                guard let self, anchor.isValid, anchor.chapterStart <= anchor.chapterEnd else { return nil }
                var result: [BibleVerse] = []
                for ch in anchor.chapterStart...anchor.chapterEnd {
                    guard let verses = self.chapter(translation: translationID, bookCode: anchor.book, chapter: ch) else { continue }
                    result.append(contentsOf: verses.filter { anchor.contains(chapter: ch, verse: $0.number) })
                }
                return result.isEmpty ? nil : result
            },
            totalVersesInBook: { [weak self] bookCode in
                self?.summary(code: bookCode)?.verseCounts.reduce(0, +)
            })
    }
}
