import Foundation
import StudyTableCore

/// Which original language a tagged word belongs to. Hebrew and Aramaic share the Old Testament
/// (Daniel 2:4b-7:28, Ezra 4:8-6:18 + 7:12-26, and Jeremiah 10:11 are Aramaic, tagged word-by-word
/// by STEPBible's own "A" morphology prefix — this is a per-*word* distinction, not per-chapter,
/// since a chapter like Daniel 2 mixes both in the same verse range).
enum InterlinearLanguage: String, Codable, Sendable {
    case hebrew = "H"
    case aramaic = "A"
    case greek = "G"
}

/// One original-language word (or, rarely — STEPBible tags ~40 cases this way across the whole
/// Hebrew OT — a tightly bound two-word phrase under one reference position), in source order.
///
/// `strongs` carries the *content* Strong's number first (the one STEPBible itself brackets as
/// the word's lexical root), then any attached grammatical-formative numbers in their original
/// left-to-right order (a prefixed article/preposition/conjunction) — the same "primary first"
/// convention `WordTag.strongs` already uses, so call sites that already know that pattern
/// (`if let first = tag.strongs.first`) work unchanged here.
///
/// `lemma` is resolved at *build time* against the app's own already-verified, already-shipped
/// `Resources/Lexicon/strongs-hebrew.json` / `strongs-greek.json` (workstream D, 0.7) wherever the
/// Strong's number is classical (H1-H8674, G1-G5624); STEPBible's own numbering extends past that
/// range for bare grammatical formatives (its own "9xxx"/"6xxx" series — a preposition or article
/// was never given a classical Strong's number), where `lemma` falls back to STEPBible's own
/// inline dictionary-form text instead. See `scripts/build-interlinear.py` and
/// `Resources/Licenses/interlinear-stepbible.txt` for the exact provenance and the measured
/// lookup-miss rate (all misses are STEPBible-extension numbers, not real content-word misses).
///
/// `morphDescription` is decoded from STEPBible's own TEHMC/TEGMC code tables ("Translators
/// Expansion of Hebrew/Greek Morphology Codes" — same CC BY 4.0 source, same repository), not a
/// hand-written decoder: e.g. `V-AAI-3S` -> "Verb Aorist Active Indicative 3rd Singular",
/// `HVqp3ms` -> "Verb : Qal (Simple, Active) Perfect (Past/present Indicative) Third Singular
/// Masculine". A multi-morpheme Hebrew word (a prefixed preposition/article/conjunction fused to
/// its root, e.g. `HR/Ncfsa`) decodes each morpheme and joins them with " + ", in the same
/// left-to-right order the original word's own prefix-then-root text reads.
///
/// `variant` (0.10) is present only on the ~2% of words the source flags as a textual variant or
/// an edition difference — see `WordVariant`. Absent means "the source records nothing", which for
/// the Hebrew OT is weaker than it sounds (see `VariantLegend.caveats`).
///
/// `surface` and `gloss` carry no attached punctuation as of 0.10: the source's trailing comma,
/// full stop, sof pasuq, maqaf, paseq or `¶` is split off at build time, so views no longer need to
/// trim it (the trimming some views still do is harmless).
struct InterlinearWord: Codable, Sendable, Equatable {
    let surface: String
    let transliteration: String
    let gloss: String
    let lemma: String
    let strongs: [String]
    let morphCode: String
    let morphDescription: String
    let language: InterlinearLanguage
    var variant: WordVariant?

    private enum CodingKeys: String, CodingKey {
        case surface = "w", transliteration = "t", gloss = "g", lemma = "l"
        case strongs = "n", morphCode = "m", morphDescription = "d", language = "L"
        case variant = "v"
    }
}

/// One other occurrence of a lemma (by its base Strong's number) elsewhere in the tagged corpus —
/// the Hebrew/Aramaic Old Testament or the Greek New Testament, matching which testament the
/// number's own letter can appear in (same restriction `LexiconStore.bookCodes(matching:)` uses).
struct InterlinearOccurrence: Codable, Sendable, Equatable, Identifiable {
    let bookCode: String
    let chapter: Int
    let verse: Int
    let surface: String
    let gloss: String
    var id: String { "\(bookCode).\(chapter).\(verse).\(surface)" }

    private enum CodingKeys: String, CodingKey {
        case bookCode = "b", chapter = "c", verse = "v", surface = "w", gloss = "g"
    }
}

private struct InterlinearChapterFile: Codable {
    let code: String
    let chapter: Int
    let verses: [String: [InterlinearWord]]
}

/// Word-level original-language data: STEPBible-Data's TAHOT (Hebrew/Aramaic OT) and TAGNT
/// (Greek NT), word-per-verse, decoded parsing, reusing `LexiconStore`'s own dictionaries for the
/// lemma text wherever the numbering lines up. See `scripts/build-interlinear.py` for the full
/// build pipeline and `Resources/Licenses/interlinear-stepbible.txt` for licence + attribution.
///
/// Lazy and cached exactly like `StudyResourceStore`/`LexiconStore`: one chapter file read per
/// book+chapter on first use (measured cold: comfortably under the 50ms/chapter budget — see
/// `InterlinearTests`), a lemma's concordance decoded once per testament and cached after that.
@MainActor
final class InterlinearStore {
    /// A single shared instance, same rationale as `LexiconStore.shared`: `AppState` doesn't own
    /// an interlinear property (out of scope for this workstream — `AppState.swift` is read-only
    /// for G), so views default to this rather than constructing a fresh, cold store per render.
    static let shared = InterlinearStore()

    private let directory: URL?
    private var chapterCache: [String: [String: [InterlinearWord]]] = [:]
    private var availableBookCodes: Set<String>?
    private var hebrewConcordance: [String: [InterlinearOccurrence]]?
    private var greekConcordance: [String: [InterlinearOccurrence]]?
    private var legendCache: VariantLegend?

    init(directory: URL? = AppResources.url("Interlinear")) {
        self.directory = directory
    }

    // MARK: Per-verse words

    /// Every original-language word tagged for one verse, in source order. Empty for a verse
    /// STEPBible doesn't cover (rare — see the versification report for the ~18 New Testament
    /// verses genuinely absent because BSB's critical text omits them) or a book with no data.
    func words(bookCode: String, chapter: Int, verse: Int) -> [InterlinearWord] {
        load(bookCode: bookCode, chapter: chapter)["\(verse)"] ?? []
    }

    /// The source legends the variant explanations use (`Interlinear/variant-legend.json`); an empty
    /// legend when the file is missing, in which case explanations fall back to the bare source codes.
    func variantLegend() -> VariantLegend {
        if let legendCache { return legendCache }
        var legend = VariantLegend.empty
        if let url = directory?.appendingPathComponent("variant-legend.json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(VariantLegend.self, from: data) {
            legend = decoded
        }
        legendCache = legend
        return legend
    }

    /// Reader-facing explanation of one word's variant flag (nil when the word carries none).
    func explanation(for word: InterlinearWord) -> VariantExplanation? {
        word.variant.map { VariantExplainer.explain($0, language: word.language, legend: variantLegend()) }
    }

    /// True if this book has any interlinear data at all (every one of the 66 bundled books does,
    /// as of this build — this stays honest if a future data swap ever narrows coverage).
    func hasData(bookCode: String) -> Bool {
        allBookCodes().contains(bookCode)
    }

    private func load(bookCode: String, chapter: Int) -> [String: [InterlinearWord]] {
        let key = "\(bookCode).\(chapter)"
        if let cached = chapterCache[key] { return cached }
        guard let url = directory?.appendingPathComponent(bookCode).appendingPathComponent("\(chapter).json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(InterlinearChapterFile.self, from: data) else {
            chapterCache[key] = [:]
            return [:]
        }
        chapterCache[key] = decoded.verses
        return decoded.verses
    }

    private func allBookCodes() -> Set<String> {
        if let cached = availableBookCodes { return cached }
        guard let directory,
              let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else {
            availableBookCodes = []
            return []
        }
        let codes = Set(contents.filter { Canon.order[$0.lastPathComponent] != nil }.map(\.lastPathComponent))
        availableBookCodes = codes
        return codes
    }

    // MARK: Lemma concordance ("Bible Word Study" — how a lemma is glossed across the Bible)

    /// Every other tagged occurrence of `strong`'s *base* Strong's number (a disambiguated tag
    /// like "H7225G" and the plain "H7225" share one concordance, the same normalization
    /// `scripts/build-interlinear.py` used when building the reverse index) — precomputed at
    /// build time into one file per testament, so a lookup here is a single small-file decode
    /// (cached after) rather than a full-corpus scan.
    func occurrences(strong: String) -> [InterlinearOccurrence] {
        guard let base = Self.baseStrong(strong) else { return [] }
        let table = base.hasPrefix("H") ? hebrewConcordanceTable() : greekConcordanceTable()
        return table[base] ?? []
    }

    func occurrenceCount(strong: String) -> Int { occurrences(strong: strong).count }

    private func hebrewConcordanceTable() -> [String: [InterlinearOccurrence]] {
        if let cached = hebrewConcordance { return cached }
        let decoded = Self.decodeConcordance(directory?.appendingPathComponent("concordance/hebrew-concordance.json"))
        hebrewConcordance = decoded
        return decoded
    }

    private func greekConcordanceTable() -> [String: [InterlinearOccurrence]] {
        if let cached = greekConcordance { return cached }
        let decoded = Self.decodeConcordance(directory?.appendingPathComponent("concordance/greek-concordance.json"))
        greekConcordance = decoded
        return decoded
    }

    private static func decodeConcordance(_ url: URL?) -> [String: [InterlinearOccurrence]] {
        guard let url, let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [InterlinearOccurrence]].self, from: data) else { return [:] }
        return decoded
    }

    /// "H7225G" -> "H7225"; "G0025" -> "G25". `nil` for anything that isn't a recognizable
    /// Strong's tag at all.
    nonisolated static func baseStrong(_ raw: String) -> String? {
        guard let letter = raw.first, letter == "H" || letter == "G" else { return nil }
        let digits = raw.dropFirst().prefix { $0.isNumber }
        guard let number = Int(digits) else { return nil }
        return "\(letter)\(number)"
    }
}

// MARK: - Textual variants and edition flags (0.10)

/// One textual-variant / edition flag on an original-language word, exactly as STEPBible-Data states
/// it (TAGNT for the Greek NT, TAHOT for the Hebrew/Aramaic OT). Built by `scripts/build-interlinear.py`.
///
/// What each field is — and nothing here is inferred by the app:
/// - `code`: the source's own type code. Greek: `NKO` (identical everywhere, never flagged) or a
///   variation such as `K` (only in the Textus Receptus text), `O` (only in "other" editions),
///   `N(k)O` (a minor difference in the traditional text). Hebrew: `L` (Leningrad, never flagged),
///   `Q(K)` (Qere followed, Ketiv is the variant), `L(D)` (Leningrad, with a Dead Sea Scrolls
///   variant), `X` (extra words converted back from the Greek), `R` (restored text).
/// - `isSignificant`: the source's own rating. Its legend says an upper-case letter in the code is a
///   difference that can affect translation and a lower-case one is "too minor" to.
/// - `editions` (Greek): the editions that carry this exact word, e.g. `TR+Byz`.
/// - `noteMarker` / `note` (Greek): the source's `^` (extra text) / `v` (different wording) marker
///   and its explanatory sentence.
/// - `alternates`: the other readings the source records (`Meaning variants` column).
///
/// Use `VariantExplainer.explain(_:language:legend:)` to turn one into reader-facing English.
struct WordVariant: Codable, Sendable, Equatable {
    /// One alternate reading of a word, with the manuscripts/editions the source says carry it.
    struct Reading: Codable, Sendable, Equatable {
        let text: String
        let transliteration: String?
        let gloss: String?
        let strongs: [String]
        let morphCode: String?
        let morphDescription: String?
        /// Greek: edition codes such as `TR+Byz`. Hebrew: source letters such as `D` or `AH`.
        let witnesses: String?

        private enum CodingKeys: String, CodingKey {
            case text = "r", transliteration = "t", gloss = "g", strongs = "n"
            case morphCode = "m", morphDescription = "d", witnesses = "w"
        }

        init(text: String, transliteration: String? = nil, gloss: String? = nil, strongs: [String] = [],
             morphCode: String? = nil, morphDescription: String? = nil, witnesses: String? = nil) {
            self.text = text
            self.transliteration = transliteration
            self.gloss = gloss
            self.strongs = strongs
            self.morphCode = morphCode
            self.morphDescription = morphDescription
            self.witnesses = witnesses
        }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            text = try c.decode(String.self, forKey: .text)
            transliteration = try c.decodeIfPresent(String.self, forKey: .transliteration)
            gloss = try c.decodeIfPresent(String.self, forKey: .gloss)
            strongs = try c.decodeIfPresent([String].self, forKey: .strongs) ?? []
            morphCode = try c.decodeIfPresent(String.self, forKey: .morphCode)
            morphDescription = try c.decodeIfPresent(String.self, forKey: .morphDescription)
            witnesses = try c.decodeIfPresent(String.self, forKey: .witnesses)
        }
    }

    let code: String
    let isSignificant: Bool
    let editions: String?
    let noteMarker: String?
    let note: String?
    let alternates: [Reading]

    private enum CodingKeys: String, CodingKey {
        case code = "c", isSignificant = "s", editions = "e", noteMarker = "k", note = "t", alternates = "a"
    }

    init(code: String, isSignificant: Bool = false, editions: String? = nil, noteMarker: String? = nil,
         note: String? = nil, alternates: [Reading] = []) {
        self.code = code
        self.isSignificant = isSignificant
        self.editions = editions
        self.noteMarker = noteMarker
        self.note = note
        self.alternates = alternates
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        code = try c.decodeIfPresent(String.self, forKey: .code) ?? ""
        isSignificant = try c.decodeIfPresent(Bool.self, forKey: .isSignificant) ?? false
        editions = try c.decodeIfPresent(String.self, forKey: .editions)
        noteMarker = try c.decodeIfPresent(String.self, forKey: .noteMarker)
        note = try c.decodeIfPresent(String.self, forKey: .note)
        alternates = try c.decodeIfPresent([Reading].self, forKey: .alternates) ?? []
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(code, forKey: .code)
        if isSignificant { try c.encode(true, forKey: .isSignificant) }
        try c.encodeIfPresent(editions, forKey: .editions)
        try c.encodeIfPresent(noteMarker, forKey: .noteMarker)
        try c.encodeIfPresent(note, forKey: .note)
        if !alternates.isEmpty { try c.encode(alternates, forKey: .alternates) }
    }

    /// The compact marker's text. Two shapes, so the difference never rests on colour: a solid chip
    /// for a difference the source rates as significant, a dashed one for a minor difference.
    var chipLabel: String { isSignificant ? "VARIANT" : "MINOR VARIANT" }
}

/// The source header legends the variant explanations draw on, shipped as
/// `Resources/Interlinear/variant-legend.json` (built from — and verified against — the TAGNT/TAHOT
/// header text; see `scripts/build-interlinear.py`). Every string is either quoted or lightly
/// condensed from the source's own legend.
struct VariantLegend: Codable, Sendable, Equatable {
    var greekEditions: [String: String] = [:]
    var greekEditionShort: [String: String] = [:]
    var greekEditionOrder: [String] = []
    var greekOtherTokens: [String: String] = [:]
    var greekNoteMarkers: [String: String] = [:]
    var greekTypeLetters: [String: String] = [:]
    var greekNoteVocabulary: String = ""
    var hebrewSources: [String: String] = [:]
    var hebrewSourceShort: [String: String] = [:]
    var caveats: [String: String] = [:]

    static let empty = VariantLegend()

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        greekEditions = try c.decodeIfPresent([String: String].self, forKey: .greekEditions) ?? [:]
        greekEditionShort = try c.decodeIfPresent([String: String].self, forKey: .greekEditionShort) ?? [:]
        greekEditionOrder = try c.decodeIfPresent([String].self, forKey: .greekEditionOrder) ?? []
        greekOtherTokens = try c.decodeIfPresent([String: String].self, forKey: .greekOtherTokens) ?? [:]
        greekNoteMarkers = try c.decodeIfPresent([String: String].self, forKey: .greekNoteMarkers) ?? [:]
        greekTypeLetters = try c.decodeIfPresent([String: String].self, forKey: .greekTypeLetters) ?? [:]
        greekNoteVocabulary = try c.decodeIfPresent(String.self, forKey: .greekNoteVocabulary) ?? ""
        hebrewSources = try c.decodeIfPresent([String: String].self, forKey: .hebrewSources) ?? [:]
        hebrewSourceShort = try c.decodeIfPresent([String: String].self, forKey: .hebrewSourceShort) ?? [:]
        caveats = try c.decodeIfPresent([String: String].self, forKey: .caveats) ?? [:]
    }
}

/// Reader-facing English for one `WordVariant`, composed only from the variant's own fields and the
/// source's legend. Where a code is not in the legend it is shown as the bare code, with a line
/// saying so, instead of being guessed at.
struct VariantExplanation: Equatable, Sendable {
    struct ReadingLine: Equatable, Sendable, Identifiable {
        var id: Int
        let text: String
        let transliteration: String
        let gloss: String
        let strongs: [String]
        let morphDescription: String
        /// "Textus Receptus and Byzantine text", "a Dead Sea or Judean Desert manuscript", …
        let carriedBy: String
        let isRightToLeft: Bool
    }

    let title: String
    let headline: String
    let significance: String
    let sourceNote: String?
    let noteKind: String?
    let readings: [ReadingLine]
    let editionLines: [String]
    let codeLine: String
    let legendLines: [String]
    let caveat: String?

    /// Everything as one string: the VoiceOver label and the test surface.
    var plainText: String {
        var parts: [String] = [title + ".", headline]
        if let noteKind { parts.append(noteKind) }
        if let sourceNote { parts.append("Source note: \(sourceNote)") }
        for reading in readings {
            var line = reading.text
            if !reading.transliteration.isEmpty { line += " (\(reading.transliteration))" }
            if !reading.gloss.isEmpty { line += ", \u{201C}\(reading.gloss)\u{201D}" }
            if !reading.carriedBy.isEmpty { line += ". Read by \(reading.carriedBy)" }
            parts.append("Other reading: \(line).")
        }
        parts.append(contentsOf: editionLines)
        parts.append(significance)
        parts.append(codeLine)
        if let caveat { parts.append(caveat) }
        return parts.joined(separator: " ")
    }
}

enum VariantExplainer {
    static func explain(_ variant: WordVariant, language: InterlinearLanguage, legend: VariantLegend) -> VariantExplanation {
        language == .greek ? explainGreek(variant, legend: legend) : explainHebrew(variant, language: language, legend: legend)
    }

    // MARK: Shared

    static func joined(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default: return items.dropLast().joined(separator: ", ") + " and " + items[items.count - 1]
        }
    }

    private static func significanceLine(_ variant: WordVariant) -> String {
        variant.isSignificant
            ? "The source rates this as a difference that can change how the word is translated."
            : "The source rates this as a minor difference, too small to necessarily change how the word is translated."
    }

    // MARK: Greek (TAGNT)

    struct EditionToken: Equatable {
        let base: String
        let displacement: String?
    }

    /// `"NA28+TR»1+Byz«3"` → tokens. `»n` / `«n` is the source's word-order displacement marker.
    static func editionTokens(_ raw: String?) -> [EditionToken] {
        guard let raw, !raw.isEmpty else { return [] }
        return raw.split(separator: "+").compactMap { piece in
            let text = piece.trimmingCharacters(in: .whitespaces)
            guard !text.isEmpty else { return nil }
            if let marker = text.firstIndex(where: { $0 == "\u{00BB}" || $0 == "\u{00AB}" }) {
                return EditionToken(base: String(text[..<marker]), displacement: String(text[marker...]))
            }
            return EditionToken(base: text, displacement: nil)
        }
    }

    private static func editionName(_ code: String, legend: VariantLegend) -> String {
        legend.greekEditionShort[code] ?? legend.greekEditions[code] ?? legend.greekOtherTokens[code] ?? code
    }

    private static func explainGreek(_ variant: WordVariant, legend: VariantLegend) -> VariantExplanation {
        let tokens = editionTokens(variant.editions)
        let order = legend.greekEditionOrder
        let listed = order.filter { code in tokens.contains { $0.base == code } }
        let notListed = order.filter { !listed.contains($0) }
        let moved = order.filter { code in tokens.contains { $0.base == code && $0.displacement != nil } }
        let extras = tokens.map(\.base).filter { legend.greekEditions[$0] == nil }
        let definedExtras = extras.filter { legend.greekOtherTokens[$0] != nil }
        let undefined = extras.filter { legend.greekOtherTokens[$0] == nil }

        var headline: String
        if legend.greekEditions.isEmpty || tokens.isEmpty {
            headline = "The source flags this word as differing between Greek editions (source code \(variant.code))."
        } else if listed.isEmpty {
            headline = "The source lists this word only for \(joined(extras.map { editionName($0, legend: legend) }))."
        } else if notListed.isEmpty {
            headline = "Every edition in the source lists this word, but the source records a difference."
        } else {
            headline = "Found in \(joined(listed.map { editionName($0, legend: legend) })), but not listed for \(joined(notListed.map { editionName($0, legend: legend) }))."
        }

        var editionLines: [String] = []
        if !moved.isEmpty {
            editionLines.append("Word order differs in \(joined(moved.map { editionName($0, legend: legend) })) (the source records the displacement).")
        }
        for token in definedExtras {
            editionLines.append("Also listed: \(legend.greekOtherTokens[token] ?? token).")
        }
        if !undefined.isEmpty {
            editionLines.append("Source code\(undefined.count == 1 ? "" : "s") \(joined(undefined)) \(undefined.count == 1 ? "is" : "are") not defined in the source's legend, so \(undefined.count == 1 ? "it is" : "they are") shown as written.")
        }

        var readings: [VariantExplanation.ReadingLine] = []
        for (index, alt) in variant.alternates.enumerated() {
            readings.append(.init(id: index, text: alt.text, transliteration: alt.transliteration ?? "", gloss: alt.gloss ?? "",
                                  strongs: alt.strongs, morphDescription: alt.morphDescription ?? "",
                                  carriedBy: greekWitnesses(alt.witnesses, legend: legend), isRightToLeft: false))
        }

        var noteKind: String?
        if let marker = variant.noteMarker { noteKind = legend.greekNoteMarkers[marker] }

        var legendLines: [String] = []
        for code in listed + moved.filter({ !listed.contains($0) }) {
            if let label = legend.greekEditions[code] { legendLines.append("\(code) = \(label)") }
        }
        for alt in variant.alternates {
            for token in editionTokens(alt.witnesses) where legend.greekEditions[token.base] != nil {
                let line = "\(token.base) = \(legend.greekEditions[token.base] ?? token.base)"
                if !legendLines.contains(line) { legendLines.append(line) }
            }
        }
        for token in definedExtras {
            let line = "\(token) = \(legend.greekOtherTokens[token] ?? token)"
            if !legendLines.contains(line) { legendLines.append(line) }
        }

        var codeLine = "Source code \(variant.code)."
        let letters = variant.code.filter(\.isLetter).map { String($0).uppercased() }
        var seen: [String] = []
        for letter in letters where !seen.contains(letter) && legend.greekTypeLetters[letter] != nil { seen.append(letter) }
        if !seen.isEmpty {
            codeLine += " " + seen.map { "\($0) = \(legend.greekTypeLetters[$0] ?? $0)" }.joined(separator: "; ") + "."
        }
        if !legend.greekNoteVocabulary.isEmpty, variant.note != nil { codeLine += " " + legend.greekNoteVocabulary }

        return VariantExplanation(
            title: variant.isSignificant ? "TEXTUAL VARIANT" : "MINOR TEXTUAL VARIANT",
            headline: headline, significance: significanceLine(variant), sourceNote: variant.note, noteKind: noteKind,
            readings: readings, editionLines: editionLines, codeLine: codeLine, legendLines: legendLines,
            caveat: legend.caveats["greek"])
    }

    private static func greekWitnesses(_ raw: String?, legend: VariantLegend) -> String {
        let tokens = editionTokens(raw)
        guard !tokens.isEmpty else { return "" }
        return joined(tokens.map { token in
            let name = editionName(token.base, legend: legend)
            let known = legend.greekEditions[token.base] != nil || legend.greekOtherTokens[token.base] != nil
            return known ? name : "\(name) (code not defined in the source legend)"
        })
    }

    // MARK: Hebrew / Aramaic (TAHOT)

    /// `"Q(K)"` → base letters `["Q"]`, variant groups `[["K"]]`. `"LA(BH)"` → `["L","A"]`, `[["B","H"]]`.
    /// `"L(AH+B)"` → `["L"]`, `[["A","H"],["B"]]`.
    static func hebrewCode(_ code: String) -> (base: [String], groups: [[String]]) {
        guard let open = code.firstIndex(of: "("), code.hasSuffix(")") else {
            return (code.map { String($0) }, [])
        }
        let base = code[..<open].map { String($0) }
        let inner = code[code.index(after: open)..<code.index(before: code.endIndex)]
        let groups = inner.split(separator: "+").map { $0.map { String($0) } }
        return (base, groups)
    }

    private static func hebrewSourceName(_ letter: String, legend: VariantLegend) -> String {
        legend.hebrewSourceShort[letter.uppercased()] ?? legend.hebrewSources[letter.uppercased()] ?? letter
    }

    private static func hebrewWitnesses(_ raw: String?, legend: VariantLegend) -> String {
        guard let raw, !raw.isEmpty else { return "" }
        return joined(raw.map { hebrewSourceName(String($0), legend: legend) })
    }

    private static func explainHebrew(_ variant: WordVariant, language: InterlinearLanguage, legend: VariantLegend) -> VariantExplanation {
        let (base, groups) = hebrewCode(variant.code)
        let first = base.first ?? ""
        var headline: String
        var editionLines: [String] = []
        var legendLines: [String] = []
        func addLegend(_ letter: String) {
            let key = letter.uppercased()
            guard let label = legend.hebrewSources[key] else { return }
            let line = "\(key) = \(label)"
            if !legendLines.contains(line) { legendLines.append(line) }
        }

        switch first {
        case "X":
            headline = "This word is not in the Leningrad text. The source adds it from Greek sources and writes it back into Hebrew."
            addLegend("X")
        case "R":
            headline = "This word is restored text, not the Leningrad reading."
            addLegend("R")
        case "Q":
            headline = "This word follows the Qere, the scribal marginal correction that translators normally follow. The Ketiv (as written) is the variant."
            addLegend("Q"); addLegend("K")
        default:
            let carriers = base.map { hebrewSourceName($0, legend: legend) }
            headline = "The word as shown is the reading of \(joined(carriers)). The source records a different reading in another source."
            base.forEach(addLegend)
        }

        let alternateLetters = Set(variant.alternates.compactMap(\.witnesses).joined().map { String($0).uppercased() })
        for group in groups {
            // A group already spelled out by an alternate reading's "Read by" line is not repeated.
            if group.allSatisfy({ alternateLetters.contains($0.uppercased()) }) { group.forEach(addLegend); continue }
            let names = joined(group.map { hebrewSourceName($0, legend: legend) })
            let minor = group.allSatisfy { $0 == $0.lowercased() }
            editionLines.append("Variant in \(names)\(minor ? " (minor)" : "").")
            group.forEach(addLegend)
        }

        var readings: [VariantExplanation.ReadingLine] = []
        for (index, alt) in variant.alternates.enumerated() {
            readings.append(.init(id: index, text: alt.text, transliteration: alt.transliteration ?? "", gloss: alt.gloss ?? "",
                                  strongs: alt.strongs, morphDescription: alt.morphDescription ?? "",
                                  carriedBy: hebrewWitnesses(alt.witnesses, legend: legend), isRightToLeft: true))
            alt.witnesses?.forEach { addLegend(String($0)) }
        }

        return VariantExplanation(
            title: variant.isSignificant ? "TEXTUAL VARIANT" : "MINOR TEXTUAL VARIANT",
            headline: headline, significance: significanceLine(variant), sourceNote: nil, noteKind: nil,
            readings: readings, editionLines: editionLines, codeLine: "Source code \(variant.code).",
            legendLines: legendLines, caveat: legend.caveats["hebrew"])
    }
}
