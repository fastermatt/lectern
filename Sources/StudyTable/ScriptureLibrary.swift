import Foundation
import StudyTableCore

enum TranslationDelivery: Hashable, Sendable {
    /// Compact pack shipped inside the app (public-domain text only).
    case bundled
    /// A pack the user installed in Application Support (e.g. a licensed ESV/NASB/NKJV pack).
    case installedPack
    /// Fetched on demand from a publisher API with the user's own key.
    case online(OnlineProvider)
    /// Known translation for which no offline text is installed.
    case licensePackRequired
}

struct TranslationInfo: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let delivery: TranslationDelivery
    let licenseSummary: String
    let attribution: String

    var abbreviation: String { id }
    var isOffline: Bool { delivery == .bundled || delivery == .installedPack }

    /// One-line status for menus.
    var detail: String {
        switch delivery {
        case .bundled: "Offline · \(licenseSummary)"
        case .installedPack: "Offline · \(licenseSummary)"
        case .online(let provider): "Online · \(provider.displayName)"
        case .licensePackRequired: "License pack required"
        }
    }
}

/// The translation catalog and all locally stored Scripture. Bundled packs and packs the
/// user installed share one format (`StudyTableCore.TranslationManifest` + per-book files),
/// so startup reads only the small manifests and each book loads lazily when opened.
@MainActor
final class ScriptureLibrary: ObservableObject {
    @Published private(set) var translations: [TranslationInfo] = []
    @Published private(set) var books: [BookSummary] = []
    @Published private(set) var loadError: String?

    private struct Local { let manifest: TranslationManifest; let directory: URL; let bundled: Bool }
    private var local: [String: Local] = [:]
    private var searchRevision = UUID()
    private var bookCache: [String: BookPack] = [:]
    private var pericopeCache: [String: [Pericope]] = [:]
    private let bundledRoot: URL?
    private let userRoot: URL

    init(bundledRoot: URL? = AppResources.url("Scripture"),
         userRoot: URL = AppResources.userTranslationsDirectory) {
        self.bundledRoot = bundledRoot
        self.userRoot = userRoot
        rescan()
    }

    /// Re-reads bundled and user packs. Call after the user installs a pack.
    func rescan() {
        searchRevision = UUID()
        local = [:]
        bookCache = [:]
        pericopeCache = [:]
        for (root, bundled) in [(bundledRoot, true), (userRoot, false)] {
            guard let root else { continue }
            let folders = (try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)) ?? []
            for folder in folders.sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                guard let data = try? Data(contentsOf: folder.appendingPathComponent("manifest.json")),
                      let manifest = try? JSONDecoder().decode(TranslationManifest.self, from: data),
                      ScripturePackBuilder.supportedSchemas.contains(manifest.schema),
                      manifest.books.count == Canon.bookCodes.count else { continue }
                // A bundled public-domain pack always wins over a same-named user folder.
                if local[manifest.id] == nil { local[manifest.id] = Local(manifest: manifest, directory: folder, bundled: bundled) }
            }
        }
        let reference = local["BSB"] ?? local.values.sorted { $0.manifest.id < $1.manifest.id }.first
        books = reference?.manifest.books.map {
            BookSummary(code: $0.code, name: $0.name, verseCounts: $0.verses)
        } ?? []
        loadError = books.isEmpty ? "Offline Bible resources are missing." : nil
        translations = Self.catalog(local: local.values.map { ($0.manifest, $0.bundled) })
    }

    private static func catalog(local: [(TranslationManifest, Bool)]) -> [TranslationInfo] {
        var result: [TranslationInfo] = []
        let bundled = local.filter { $0.1 }.map(\.0).sorted { order($0.id) < order($1.id) }
        let installed = local.filter { !$0.1 }.map(\.0).sorted { $0.id < $1.id }
        for manifest in bundled + installed {
            result.append(TranslationInfo(
                id: manifest.id, name: manifest.name,
                delivery: local.first { $0.0.id == manifest.id }?.1 == true ? .bundled : .installedPack,
                licenseSummary: manifest.license.summary, attribution: manifest.license.attribution))
        }
        let have = Set(result.map(\.id))
        if !have.contains("ESV") {
            result.append(TranslationInfo(id: "ESV", name: "English Standard Version", delivery: .online(.esv),
                                          licenseSummary: "Crossway", attribution: ESVProvider.attribution))
        }
        if !have.contains("NKJV") {
            result.append(TranslationInfo(id: "NKJV", name: "New King James Version", delivery: .online(.apiBible),
                                          licenseSummary: "Thomas Nelson",
                                          attribution: "New King James Version®. Copyright © 1982 by Thomas Nelson. Used by permission. All rights reserved."))
        }
        if !have.contains("NASB") {
            result.append(TranslationInfo(id: "NASB", name: "New American Standard Bible", delivery: .licensePackRequired,
                                          licenseSummary: "The Lockman Foundation", attribution: ""))
        }
        return result
    }

    private static func order(_ id: String) -> Int { ["BSB": 0, "KJV": 1, "WEB": 2][id] ?? 9 }

    func translation(id: String) -> TranslationInfo? { translations.first { $0.id == id } }
    func summary(code: String) -> BookSummary? { books.first { $0.code == code } }

    /// Verses of one chapter from an installed pack, or nil when the translation is not local.
    func chapter(translation id: String, bookCode: String, chapter: Int) -> [BibleVerse]? {
        guard let pack = book(translation: id, code: bookCode),
              let found = pack.chapters.first(where: { $0.n == chapter }) else { return nil }
        return zip(found.v, found.t).map { BibleVerse(number: $0, text: $1) }
    }

    private func book(translation id: String, code: String) -> BookPack? {
        let key = "\(id)/\(code)"
        if let cached = bookCache[key] { return cached }
        guard let entry = local[id],
              let data = try? Data(contentsOf: entry.directory.appendingPathComponent("\(code).json")),
              let pack = try? JSONDecoder().decode(BookPack.self, from: data) else { return nil }
        bookCache[key] = pack
        return pack
    }

    /// Sendable local-file handle for the background search actor. Online caches are deliberately
    /// absent from this catalog; pack rescans produce a fresh revision for cache invalidation.
    func searchSource(translationID id: String) -> BibleSearchSource? {
        guard let entry = local[id] else { return nil }
        let codes = Set(entry.manifest.books.map(\.code))
        guard codes == Set(Canon.bookCodes) else { return nil }
        return BibleSearchSource(translationID: id, directory: entry.directory,
                                 bookCodes: Canon.bookCodes, revision: searchRevision)
    }

    /// Validates navigation against actual verse identifiers in the selected local edition,
    /// falling back to BSB for an online edition. Manifest counts are not verse endpoints.
    func navigationAnchor(for reference: String, translationID: String) -> Anchor? {
        guard let anchor = Anchor.parse(reference), let summary = summary(code: anchor.book), summary.chapterCount > 0,
              (1...summary.chapterCount).contains(anchor.chapterStart),
              (1...summary.chapterCount).contains(anchor.chapterEnd) else { return nil }
        func numbers(_ chapterNumber: Int) -> Set<Int> {
            let verses = chapter(translation: translationID, bookCode: anchor.book, chapter: chapterNumber)
                ?? chapter(translation: "BSB", bookCode: anchor.book, chapter: chapterNumber)
            return Set((verses ?? []).filter { $0.number > 0 }.map(\.number))
        }
        let first = numbers(anchor.chapterStart), last = numbers(anchor.chapterEnd)
        guard !first.isEmpty, !last.isEmpty,
              anchor.verseStart == 0 || first.contains(anchor.verseStart),
              anchor.verseEnd == Anchor.endOfChapter || last.contains(anchor.verseEnd) else { return nil }
        return anchor
    }

    /// Where a user drops licensed packs.
    var userPackDirectory: URL { userRoot }

    // MARK: Section headings, parallel references, paragraph starts (schema 2 packs)

    /// The structure of one chapter as the pack carries it, or nil when the pack is not local,
    /// predates schema 2, or has no headings and no paragraph marks for this chapter. Online
    /// translations never have structure.
    func structure(translation id: String, bookCode: String, chapter: Int) -> ChapterStructure? {
        guard let pack = book(translation: id, code: bookCode),
              let found = pack.chapters.first(where: { $0.n == chapter }) else { return nil }
        let headings = found.s ?? [], starts = found.p ?? []
        guard !headings.isEmpty || !starts.isEmpty else { return nil }
        return ChapterStructure(verseNumbers: found.v, headings: headings, paragraphStarts: Set(starts))
    }

    /// Every heading of a book with its verse span, in reading order (levels 0...3).
    /// `translation` defaults to BSB, the only bundled translation whose headings are real
    /// pericope titles, and the versification the study store anchors to.
    func allPericopes(bookCode: String, translation id: String = "BSB") -> [Pericope] {
        let key = "\(id)/\(bookCode)"
        if let cached = pericopeCache[key] { return cached }
        guard let pack = book(translation: id, code: bookCode) else { return [] }
        let result = PericopeIndex.pericopes(in: pack)
        pericopeCache[key] = result
        return result
    }

    /// The headings that START in `chapter`, with spans that may run on into later chapters.
    /// `maxLevel` 2 (default) gives sections and subsections; pass 1 for sections only, 3 to add
    /// Psalm 119's acrostic letters, 0 to add the Psalter's "BOOK I..V" divisions.
    func pericopes(bookCode: String, chapter: Int, translation id: String = "BSB", maxLevel: Int = 2) -> [Pericope] {
        allPericopes(bookCode: bookCode, translation: id).filter { $0.startChapter == chapter && $0.level <= maxLevel && $0.level >= 1 }
    }

    /// The section containing a verse. With `level == nil` the innermost heading of level 1...2
    /// wins (a subsection if there is one); pass `level: 1` for the enclosing section. Two headings
    /// of the same level over the same verse (Hebrews 11:30) resolve to the first.
    func pericope(containing chapter: Int, verse: Int, bookCode: String, translation id: String = "BSB", level: Int? = nil) -> Pericope? {
        let containing = allPericopes(bookCode: bookCode, translation: id).filter { $0.contains(chapter: chapter, verse: verse) }
        let candidates = level.map { wanted in containing.filter { $0.level == wanted } }
            ?? containing.filter { (1...2).contains($0.level) }
        return candidates.max { ($0.level, -$0.ordinal) < ($1.level, -$1.ordinal) }
    }

    // MARK: Full-text search

    /// Legacy compatibility API for existing integrations/tests; the app UI now uses
    /// `BibleSearchEngine` and never invokes this synchronous capped scan.
    /// Loads (and caches) every book of `id`, then scans for `query` as a case- and
    /// diacritic-insensitive substring. First call for a translation is the slow path (decodes
    /// all 66 books); every call after is served from the per-book cache `chapter(translation:)`
    /// already fills, so a second search of the same translation is effectively free.
    func search(translationID id: String, query: String, limit: Int = 60) -> [ScriptureSearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard needle.count >= 3, let entry = local[id] else { return [] }
        var hits: [ScriptureSearchHit] = []
        for code in Canon.bookCodes {
            guard let pack = book(translation: id, code: code) else { continue }
            let name = books.first { $0.code == code }?.name ?? pack.name
            for chapter in pack.chapters {
                for (number, text) in zip(chapter.v, chapter.t) where number > 0 {
                    guard text.range(of: needle, options: [.caseInsensitive, .diacriticInsensitive]) != nil else { continue }
                    hits.append(ScriptureSearchHit(bookCode: code, bookName: name, chapter: chapter.n, verse: number, text: text))
                    if hits.count >= limit { return hits }
                }
            }
        }
        _ = entry
        return hits
    }
}

/// Editorial structure of one chapter for the reader. Never affects verse text.
struct ChapterStructure: Equatable, Sendable {
    /// The pack's verse numbers, so the reader can confirm the structure belongs to the verses it shows.
    let verseNumbers: [Int]
    let headings: [SectionHeading]
    let paragraphStarts: Set<Int>

    /// Headings that sit above `verse`, in source order (a section, then its subsection, ...).
    func headings(before verse: Int) -> [SectionHeading] { headings.filter { $0.verse == verse } }
    func startsParagraph(_ verse: Int) -> Bool { paragraphStarts.contains(verse) }
    var hasHeadings: Bool { !headings.isEmpty }
}

struct ScriptureSearchHit: Identifiable, Hashable, Sendable {
    let bookCode: String
    let bookName: String
    let chapter: Int
    let verse: Int
    let text: String
    var id: String { "\(bookCode).\(chapter).\(verse)" }
    var reference: String { "\(bookName) \(chapter):\(verse)" }
}
