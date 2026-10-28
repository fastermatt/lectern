import Foundation
import StudyTableCore

/// One tagged word in a KJV verse, in source order. `strongs` is almost always a single
/// number (`349,308` tags in the bundled KJV each carry exactly one), but is kept as an
/// array because the side-channel format allows a token to carry more than one.
struct WordTag: Codable, Sendable, Equatable {
    let word: String
    let strongs: [String]

    private enum CodingKeys: String, CodingKey {
        case word = "w"
        case strongs = "s"
    }
}

/// One Strong's dictionary entry (Hebrew or Greek), independently derived from the 1890/1894
/// public-domain Strong's e-text — see `Resources/Licenses/lexicon-greek.txt` /
/// `lexicon-hebrew.txt` for the exact source and licence evidence.
struct LexiconEntry: Codable, Sendable, Equatable {
    let lemma: String
    let translit: String
    let pronunciation: String
    let definition: String
    let kjvUsage: String?
}

/// One occurrence of a Strong's number elsewhere in the KJV, for a concordance list.
struct ConcordanceHit: Sendable, Equatable, Identifiable {
    let bookCode: String
    let chapter: Int
    let verse: Int
    let word: String
    var id: String { "\(bookCode).\(chapter).\(verse).\(word)" }
}

/// Word-study data: per-verse Strong's tagging extracted from the bundled KJV's own USFM
/// source (a side channel — `USFMParser` itself never sees or exposes these tags), plus the
/// Hebrew/Greek dictionaries those numbers resolve against.
///
/// Everything is lazy and cached: book tag files are decoded on first use per book, the two
/// dictionaries are decoded on first lookup, and a concordance is computed once per Strong's
/// number and cached after that. See `Tests/StudyTableTests/LexiconTests.swift` for the
/// measured budgets (book tags ≤ 50ms cold, concordance ≤ 500ms first time).
///
/// Label used in the interface: **"Word tagging from the KJV (Strong's numbers)"** — the
/// tagging follows the King James Version's own words even when a different translation is
/// on screen.
@MainActor
final class LexiconStore {
    /// A single shared instance so verse-to-verse navigation reuses per-book and concordance
    /// caches instead of re-decoding JSON on every view re-render. `AppState` doesn't own a
    /// lexicon property (this workstream doesn't edit `AppState.swift`), so `WordStudySection`
    /// defaults to this rather than constructing a fresh, cold store per render.
    static let shared = LexiconStore()

    private let directory: URL?
    private var bookCache: [String: [String: [WordTag]]] = [:]
    private var greekDictionary: [String: LexiconEntry]?
    private var hebrewDictionary: [String: LexiconEntry]?
    private var concordanceCache: [String: [ConcordanceHit]] = [:]

    /// Books actually bundled (a book with zero Strong's-tagged words, if any, simply has no
    /// file and is treated as empty rather than an error).
    private var availableBookCodes: Set<String>?

    init(directory: URL? = AppResources.url("Lexicon")) {
        self.directory = directory
    }

    // MARK: Per-verse tagging

    /// Every tagged word in one verse, in source order. Empty if the book has no lexicon
    /// data, the reference has no tagged words (older-book coverage varies), or verse 0
    /// (an unnumbered superscription) is asked for a book without one.
    func tags(bookCode: String, chapter: Int, verse: Int) -> [WordTag] {
        load(bookCode: bookCode)["\(chapter):\(verse)"] ?? []
    }

    /// True if this book has any Strong's tagging at all (both testaments are tagged in the
    /// bundled KJV, but this stays honest if a future translation swap ever lacks one).
    func hasTags(bookCode: String) -> Bool {
        !load(bookCode: bookCode).isEmpty
    }

    private func load(bookCode: String) -> [String: [WordTag]] {
        if let cached = bookCache[bookCode] { return cached }
        guard let url = directory?.appendingPathComponent("kjv-tags/\(bookCode).json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [WordTag]].self, from: data) else {
            bookCache[bookCode] = [:]
            return [:]
        }
        bookCache[bookCode] = decoded
        return decoded
    }

    // MARK: Dictionaries

    /// Resolves one Strong's number ("G2316", "H430") to its dictionary entry. `nil` means a
    /// genuine miss (see `LexiconTests` for the measured miss rate — 0% against the bundled
    /// KJV's own tagging as of the 2026-09-22 build).
    func entry(for strong: String) -> LexiconEntry? {
        guard let letter = strong.first else { return nil }
        if letter == "G" { return greek()[strong] }
        if letter == "H" { return hebrew()[strong] }
        return nil
    }

    private func greek() -> [String: LexiconEntry] {
        if let cached = greekDictionary { return cached }
        let decoded = Self.decodeDictionary(directory?.appendingPathComponent("strongs-greek.json"))
        greekDictionary = decoded
        return decoded
    }

    private func hebrew() -> [String: LexiconEntry] {
        if let cached = hebrewDictionary { return cached }
        let decoded = Self.decodeDictionary(directory?.appendingPathComponent("strongs-hebrew.json"))
        hebrewDictionary = decoded
        return decoded
    }

    private static func decodeDictionary(_ url: URL?) -> [String: LexiconEntry] {
        guard let url, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: LexiconEntry].self, from: data) else { return [:] }
        return decoded
    }

    // MARK: Concordance

    /// Every KJV verse using a given Strong's number, across all 66 books, sorted in canonical
    /// book order then chapter/verse. Computed once per number and cached — the first call for
    /// a common word (e.g. G26, ἀγάπη, 117 occurrences) scans every book's tag file, so callers
    /// should treat it as a background/on-demand action, not something run for every tag on
    /// screen.
    func concordance(for strong: String) -> [ConcordanceHit] {
        if let cached = concordanceCache[strong] { return cached }
        var hits: [ConcordanceHit] = []
        for code in bookCodes(matching: strong) {
            for (ref, tagList) in load(bookCode: code) {
                guard let colon = ref.firstIndex(of: ":"),
                      let chapter = Int(ref[ref.startIndex..<colon]),
                      let verse = Int(ref[ref.index(after: colon)...]) else { continue }
                for tag in tagList where tag.strongs.contains(strong) {
                    hits.append(ConcordanceHit(bookCode: code, chapter: chapter, verse: verse, word: tag.word))
                }
            }
        }
        hits.sort { a, b in
            let orderA = Canon.order[a.bookCode] ?? Int.max
            let orderB = Canon.order[b.bookCode] ?? Int.max
            if orderA != orderB { return orderA < orderB }
            if a.chapter != b.chapter { return a.chapter < b.chapter }
            return a.verse < b.verse
        }
        concordanceCache[strong] = hits
        return hits
    }

    /// Occurrence count without materializing the full hit list unnecessarily — same cache.
    func occurrenceCount(for strong: String) -> Int { concordance(for: strong).count }

    /// Restricts the scan to one testament when the number's own prefix makes the other
    /// testament impossible: a Greek (G-) number can only tag a New Testament word and a
    /// Hebrew/Aramaic (H-) number only an Old Testament word — true of Strong's tagging by
    /// construction, and verified against the full bundled corpus (zero cross-testament tags).
    /// Roughly halves the books scanned on a first, uncached concordance lookup.
    private func bookCodes(matching strong: String) -> [String] {
        let all = allBookCodes()
        guard let testamentBoundary = Canon.order["MAT"] else { return all }
        if strong.hasPrefix("G") { return all.filter { (Canon.order[$0] ?? 0) >= testamentBoundary } }
        if strong.hasPrefix("H") { return all.filter { (Canon.order[$0] ?? 0) < testamentBoundary } }
        return all
    }

    private func allBookCodes() -> [String] {
        if let cached = availableBookCodes { return Array(cached) }
        guard let directory = directory?.appendingPathComponent("kjv-tags"),
              let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            availableBookCodes = []
            return []
        }
        let codes = Set(contents.filter { $0.pathExtension == "json" }.map { $0.deletingPathExtension().lastPathComponent })
        availableBookCodes = codes
        return Array(codes)
    }
}
