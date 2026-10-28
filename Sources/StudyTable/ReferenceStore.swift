import Foundation

// MARK: - Data model
//
// Matches the schema `scripts/build-reference.py` writes to `Resources/Reference/`. See
// `scripts/reference-sources/SOURCES.md` for provenance and licence evidence for every
// dataset (Nave's Topical Bible, Easton's Bible Dictionary, STEPBible TIPNR).

/// One verse or single-chapter verse range a Nave's topic (or TIPNR name) cites — the same
/// single-chapter-per-ref convention `CrossReference`/`StandardProof` already use elsewhere
/// in this app.
struct ReferenceRef: Codable, Hashable, Sendable, Identifiable {
    let code: String
    let chapter: Int
    let start: Int
    let end: Int
    var id: String { "\(code).\(chapter).\(start)-\(end)" }
}

/// A run of a Nave's topic's own references grouped under the topic's own "→ SUBHEADING"
/// label (e.g. LOVE has "OF MAN FOR GOD", "OF GOD", "OF CHILDREN FOR PARENTS"...). Topics
/// with no internal subheadings have a single unlabeled section holding every ref.
struct NaveSection: Codable, Hashable, Sendable {
    let heading: String
    let refs: [ReferenceRef]
}

/// One Nave's Topical Bible entry: every verse it cites (flat, deduplicated), any other
/// topics it points to ("see also"), and the same refs grouped by the topic's own
/// subheadings for a more useful "topic → all verses" display than one flat list.
struct NaveTopic: Codable, Hashable, Sendable {
    let refs: [ReferenceRef]
    let seeAlso: [String]
    let sections: [NaveSection]
}

/// One Easton's Bible Dictionary article.
struct EastonArticle: Codable, Hashable, Sendable {
    let title: String
    let text: String
}

/// One verse a TIPNR person/place/other name is mentioned in.
struct TIPNRRef: Codable, Hashable, Sendable, Identifiable {
    let code: String
    let chapter: Int
    let verse: Int
    var id: String { "\(code).\(chapter).\(verse)" }
}

/// One STEPBible TIPNR proper name: a disambiguated individual person, place, or other
/// proper noun (a deity's title, a people-group name, a language...), with a compact
/// STEPBible-authored description and every verse it is mentioned in.
struct TIPNRName: Codable, Hashable, Sendable {
    let name: String
    let kind: String  // "person" | "place" | "other"
    let description: String
    let refs: [TIPNRRef]

    var isPerson: Bool { kind == "person" }
    var isPlace: Bool { kind == "place" }
}

struct ReferenceAttribution: Codable, Sendable {
    let nave: String
    let easton: String
    let tipnr: String
}

private struct ReferenceMeta: Codable { let schema: Int; let attribution: ReferenceAttribution }

/// Loads Study Table's Passage Guide reference data: Nave's Topical Bible (verse → topics,
/// topic → all verses), Easton's Bible Dictionary (articles + book introductions), and
/// STEPBible TIPNR (people & places). Lazy and cached throughout: a verse's topic/headword/
/// name *list* is a small per-book file (`.../verse-index/<BOOK>.json`); the full text of one
/// topic/article/name lives in an A–Z-sharded detail file that is only decoded the first time
/// something in that shard is actually opened (`scripts/build-reference.py`'s `shard_letter`)
/// — so rendering a desk section's collapsed one-line summary, which only needs names, never
/// touches the (multi-hundred-KB) detail shards at all. See `ReferenceTests.swift` for the
/// measured cold-load budget.
@MainActor
final class ReferenceStore {
    static let shared = ReferenceStore()

    private let root: URL?
    private var naveVerseIndex: [String: [String: [String]]] = [:]      // book -> "c:v" -> topic names, ranked
    private var naveMoreIndex: [String: [String: [String]]] = [:]       // book -> "c:v" -> wider-passage topics, ranked
    private var eastonMoreIndex: [String: [String: [String]]] = [:]
    private var naveTopicShards: [String: [String: NaveTopic]] = [:]     // shard letter -> topic name -> topic
    private var eastonVerseIndex: [String: [String: [String]]] = [:]     // book -> "c:v" -> headwords
    private var eastonArticleShards: [String: [String: EastonArticle]] = [:]
    private var eastonBookIntros: [String: String]?
    private var tipnrVerseIndex: [String: [String: [String]]] = [:]      // book -> "c:v" -> name IDs
    private var tipnrNameShards: [String: [String: TIPNRName]] = [:]
    private var meta: ReferenceMeta?
    /// Problems found while loading (missing/unreadable files). Empty is healthy.
    private(set) var diagnostics: [String] = []

    init(directory: URL? = AppResources.url("Reference")) {
        self.root = directory
    }

    // MARK: Attribution

    var attribution: ReferenceAttribution {
        if let meta { return meta.attribution }
        guard let url = root?.appendingPathComponent("meta.json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(ReferenceMeta.self, from: data) else {
            diagnostics.append("meta.json: missing or unreadable")
            let fallback = ReferenceAttribution(nave: "Nave's Topical Bible (1896) — Public Domain.",
                                                 easton: "Easton's Bible Dictionary (1897) — Public Domain.",
                                                 tipnr: "Proper names data from TIPNR, STEPBible.org (CC BY).")
            meta = ReferenceMeta(schema: 1, attribution: fallback)
            return fallback
        }
        meta = decoded
        return decoded.attribution
    }

    // MARK: Nave's Topics

    /// Topic names that cite this verse *directly* — the narrowest span that cites it is at most 10
    /// verses, or the topic is named in the verse's own text — most specific first (narrowest citing
    /// span, then the smaller topic, then name). At most 12. The build (`scripts/build-reference.py`,
    /// "Specificity ranking") keeps a topic that merely cites the whole chapter or a long run out of
    /// this list; those are `moreTopics`. Empty for the many verses Nave's doesn't index.
    func topics(bookCode: String, chapter: Int, verse: Int) -> [String] {
        loadNaveVerseIndex(bookCode)[verseKey(chapter, verse)] ?? []
    }

    /// The rest of the topics that cover this verse — direct overflow past the cap, and topics that
    /// cite it only inside a wider passage (a bare chapter, a section, a cross-chapter run) — ranked
    /// the same way. Nothing the earlier index attached is dropped; it is reachable here.
    func moreTopics(bookCode: String, chapter: Int, verse: Int) -> [String] {
        loadMoreIndex(&naveMoreIndex, dataset: "nave", bookCode)[verseKey(chapter, verse)] ?? []
    }

    /// The full topic — every verse it cites (optionally grouped by its own subheadings) and
    /// any other topics it points to. `nil` only if the name doesn't resolve (shouldn't
    /// happen for a name this store itself returned from `topics(...)`).
    func topic(named name: String) -> NaveTopic? {
        let letter = Self.shardLetter(name)
        if naveTopicShards[letter] == nil {
            naveTopicShards[letter] = decode([String: NaveTopic].self,
                                              at: "nave/topics/\(letter).json", label: "nave topic shard \(letter)")
        }
        return naveTopicShards[letter]?[name]
    }

    private func loadNaveVerseIndex(_ bookCode: String) -> [String: [String]] {
        if let cached = naveVerseIndex[bookCode] { return cached }
        let decoded = decode([String: [String]].self, at: "nave/verse-index/\(bookCode).json",
                              label: "nave verse-index \(bookCode)", missingIsOK: true) ?? [:]
        naveVerseIndex[bookCode] = decoded
        return decoded
    }

    // MARK: Easton's Dictionary

    /// Headwords linked directly from this verse — because the article's own text cites this verse
    /// narrowly (or names it), or because a Nave's topic resolved for it shares the article's exact
    /// name (`scripts/build-reference.py`'s `build_easton`) — most specific first, at most 8.
    func dictionaryHeadwords(bookCode: String, chapter: Int, verse: Int) -> [String] {
        loadEastonVerseIndex(bookCode)[verseKey(chapter, verse)] ?? []
    }

    /// Headwords that reach this verse only through a wide citation (or past the cap), ranked.
    func moreDictionaryHeadwords(bookCode: String, chapter: Int, verse: Int) -> [String] {
        loadMoreIndex(&eastonMoreIndex, dataset: "easton", bookCode)[verseKey(chapter, verse)] ?? []
    }

    func article(headword: String) -> EastonArticle? {
        let letter = Self.shardLetter(headword)
        if eastonArticleShards[letter] == nil {
            eastonArticleShards[letter] = decode([String: EastonArticle].self,
                                                  at: "easton/articles/\(letter).json", label: "easton article shard \(letter)")
        }
        return eastonArticleShards[letter]?[headword]
    }

    /// The Easton headword that introduces this whole book (e.g. "JOHN, GOSPEL OF" for JHN),
    /// when Easton has one — all 66 canon books resolve as of the 0.8 build.
    func bookIntroHeadword(bookCode: String) -> String? {
        if eastonBookIntros == nil {
            eastonBookIntros = decode([String: String].self, at: "easton/book-intros.json",
                                       label: "easton book-intros") ?? [:]
        }
        return eastonBookIntros?[bookCode]
    }

    func bookIntroArticle(bookCode: String) -> EastonArticle? {
        guard let headword = bookIntroHeadword(bookCode: bookCode) else { return nil }
        return article(headword: headword)
    }

    private func loadEastonVerseIndex(_ bookCode: String) -> [String: [String]] {
        if let cached = eastonVerseIndex[bookCode] { return cached }
        let decoded = decode([String: [String]].self, at: "easton/verse-index/\(bookCode).json",
                              label: "easton verse-index \(bookCode)", missingIsOK: true) ?? [:]
        eastonVerseIndex[bookCode] = decoded
        return decoded
    }

    // MARK: STEPBible TIPNR (people & places)

    /// Every TIPNR person/place/other-noun record mentioned in this verse, people first then
    /// places then other, each group alphabetical by name.
    func names(bookCode: String, chapter: Int, verse: Int) -> [TIPNRName] {
        let ids = loadTIPNRVerseIndex(bookCode)[verseKey(chapter, verse)] ?? []
        let resolved = ids.compactMap { name(id: $0) }
        return resolved.sorted { a, b in
            if a.kind != b.kind { return Self.kindOrder(a.kind) < Self.kindOrder(b.kind) }
            return a.name.localizedStandardCompare(b.name) == .orderedAscending
        }
    }

    func name(id: String) -> TIPNRName? {
        let letter = Self.shardLetter(id)
        if tipnrNameShards[letter] == nil {
            tipnrNameShards[letter] = decode([String: TIPNRName].self,
                                              at: "tipnr/names/\(letter).json", label: "tipnr name shard \(letter)")
        }
        return tipnrNameShards[letter]?[id]
    }

    private static func kindOrder(_ kind: String) -> Int {
        switch kind { case "person": 0; case "place": 1; default: 2 }
    }

    private func loadTIPNRVerseIndex(_ bookCode: String) -> [String: [String]] {
        if let cached = tipnrVerseIndex[bookCode] { return cached }
        let decoded = decode([String: [String]].self, at: "tipnr/verse-index/\(bookCode).json",
                              label: "tipnr verse-index \(bookCode)", missingIsOK: true) ?? [:]
        tipnrVerseIndex[bookCode] = decoded
        return decoded
    }

    // MARK: Shared helpers

    private func loadMoreIndex(_ cache: inout [String: [String: [String]]], dataset: String,
                               _ bookCode: String) -> [String: [String]] {
        if let cached = cache[bookCode] { return cached }
        let decoded = decode([String: [String]].self, at: "\(dataset)/verse-index-more/\(bookCode).json",
                              label: "\(dataset) verse-index-more \(bookCode)", missingIsOK: true) ?? [:]
        cache[bookCode] = decoded
        return decoded
    }

    private func verseKey(_ chapter: Int, _ verse: Int) -> String { "\(chapter):\(verse)" }

    /// The A–Z (or "0-9"/"_") bucket `write_sharded` in `scripts/build-reference.py` grouped
    /// this key's detail record into.
    private static func shardLetter(_ key: String) -> String {
        for ch in key {
            if ch.isLetter { return String(ch).uppercased() }
            if ch.isNumber { return "0-9" }
        }
        return "_"
    }

    private func decode<T: Decodable>(_ type: T.Type, at relativePath: String, label: String, missingIsOK: Bool = false) -> T? {
        guard let url = root?.appendingPathComponent(relativePath) else {
            if !missingIsOK { diagnostics.append("\(label): Reference resources not found") }
            return nil
        }
        guard let data = try? Data(contentsOf: url) else {
            if !missingIsOK { diagnostics.append("\(label): missing") }
            return nil
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            diagnostics.append("\(label): \(error.localizedDescription)")
            return nil
        }
    }
}
