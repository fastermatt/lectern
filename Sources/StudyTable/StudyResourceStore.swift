import Foundation

/// One chapter's worth of study entries, as written by `scripts/build-study-resources.py`
/// to `Resources/Study/<CODE>/<CHAPTER>.json`. Schema 3, same entry shape as before — only the
/// on-disk granularity changed (see `StudyResourceStore` doc comment for why).
private struct StudyChapterIndex: Codable {
    let schema: Int
    let code: String
    let book: String
    let chapter: Int
    let entries: [StudySource]
}

@MainActor
final class StudyResourceStore {
    let confession: ConfessionStore
    private let studyDirectory: URL?
    var searchDirectory: URL? { studyDirectory }
    /// Keyed "<CODE>.<CHAPTER>"; this is the hot path (`sources`/`coverage`), so a cold miss
    /// reads exactly one small chapter file, never a whole book. A missing/empty chapter is
    /// cached as `[]` too, so a repeat visit to a genuinely uncovered chapter is also free.
    private var chapterCache: [String: [StudySource]] = [:]
    private var coverageCache: [String: [SourceTradition: Set<Int>]] = [:]
    private(set) var registry: [String: SourceRecord] = [:]
    /// Defects found while loading (duplicate IDs, unsupported schemas). Empty is healthy.
    private(set) var diagnostics: [String] = []

    init(confession: ConfessionStore = ConfessionStore(),
         studyDirectory: URL? = AppResources.url("Study")) {
        self.confession = confession
        self.studyDirectory = studyDirectory
        if let url = studyDirectory?.appendingPathComponent("sources.json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(SourceRegistry.self, from: data) {
            registry = decoded.sources
        } else {
            diagnostics.append("source registry missing")
        }
    }

    /// Tier 3 (research-only) entries are excluded unless the reader explicitly opts in — see
    /// `ConfessionalTier.tier3ResearchOnly`. Every other tier is included by default.
    func sources(bookCode: String, bookName: String, chapter: Int, verse: Int, includeResearchTier: Bool = false) -> [ResolvedSource] {
        let passage = "\(bookName) \(chapter):\(verse)"
        return loadChapter(bookCode: bookCode, chapter: chapter)
            .filter { $0.covers(verse: verse) }
            .filter { includeResearchTier || $0.tier != .tier3ResearchOnly }
            .map {
                ResolvedSource(entry: $0, record: registry[$0.source],
                               confessionLinks: confession.links(forEntryID: $0.id), passage: passage)
            }
    }

    /// Which verses of a chapter have at least one source in each bank (for the LCD chapter map).
    func coverage(bookCode: String, chapter: Int) -> [SourceTradition: Set<Int>] {
        let key = "\(bookCode).\(chapter)"
        if let cached = coverageCache[key] { return cached }
        var result: [SourceTradition: Set<Int>] = [:]
        for entry in loadChapter(bookCode: bookCode, chapter: chapter) {
            for verse in entry.startVerse...max(entry.startVerse, entry.endVerse) {
                result[entry.tradition, default: []].insert(verse)
            }
        }
        coverageCache[key] = result
        return result
    }

    /// Every entry of one book (tests and tooling only — not on the app's hot path, so reading
    /// every chapter file in the book is an acceptable cost here).
    func entries(bookCode: String) -> [StudySource] { load(bookCode: bookCode)?.entries ?? [] }

    /// One chapter file, decoded and de-duplicated. `[]` for a chapter with no study entries at
    /// all (not a defect — most chapters have partial coverage) as well as for a missing book.
    private func loadChapter(bookCode: String, chapter: Int) -> [StudySource] {
        let key = "\(bookCode).\(chapter)"
        if let cached = chapterCache[key] { return cached }
        guard let url = studyDirectory?.appendingPathComponent(bookCode).appendingPathComponent("\(chapter).json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(StudyChapterIndex.self, from: data) else {
            chapterCache[key] = []
            return []
        }
        guard decoded.schema == 3 else {
            diagnostics.append("\(bookCode) \(chapter): unsupported schema \(decoded.schema)")
            chapterCache[key] = []
            return []
        }
        // IDs are chapter-scoped by construction (they embed the chapter number), so a
        // duplicate can only occur within this one file, never across chapters.
        var seen = Set<String>()
        var unique: [StudySource] = []
        for entry in decoded.entries {
            if seen.insert(entry.id).inserted { unique.append(entry) }
            else { diagnostics.append("\(bookCode) \(chapter): duplicate entry \(entry.id)") }
        }
        chapterCache[key] = unique
        return unique
    }

    /// Whole-book aggregate, built by reading every chapter file present for `bookCode`. Only
    /// tests and tooling need this; the running app never loads a book's every chapter at once.
    func load(bookCode: String) -> StudyBookIndex? {
        guard let bookDirectory = studyDirectory?.appendingPathComponent(bookCode),
              let names = try? FileManager.default.contentsOfDirectory(atPath: bookDirectory.path) else {
            return nil
        }
        let chapters = names
            .compactMap { name -> Int? in
                guard name.hasSuffix(".json") else { return nil }
                return Int(name.dropLast(5))
            }
            .sorted()
        guard !chapters.isEmpty else { return nil }
        var bookName = bookCode
        var allEntries: [StudySource] = []
        for chapter in chapters {
            guard let data = try? Data(contentsOf: bookDirectory.appendingPathComponent("\(chapter).json")),
                  let decoded = try? JSONDecoder().decode(StudyChapterIndex.self, from: data) else { continue }
            guard decoded.schema == 3 else {
                diagnostics.append("\(bookCode) \(chapter): unsupported schema \(decoded.schema)")
                return nil
            }
            bookName = decoded.book
            allEntries.append(contentsOf: decoded.entries)
        }
        var seen = Set<String>()
        var unique: [StudySource] = []
        for entry in allEntries {
            if seen.insert(entry.id).inserted { unique.append(entry) }
            else { diagnostics.append("\(bookCode): duplicate entry \(entry.id)") }
        }
        return StudyBookIndex(schema: 3, code: bookCode, book: bookName, entries: unique)
    }
}
