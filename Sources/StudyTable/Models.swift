import Foundation

// MARK: - Scripture

struct BibleVerse: Identifiable, Hashable, Sendable {
    /// 0 is the unnumbered superscription (e.g. a Psalm title).
    let number: Int
    let text: String
    var id: Int { number }
}

struct BookSummary: Identifiable, Hashable, Sendable {
    let code: String
    let name: String
    /// Verse counts for chapters 1...n (superscriptions excluded).
    let verseCounts: [Int]
    var id: String { code }
    var chapterCount: Int { verseCounts.count }
    var chapterNumbers: [Int] { Array(1...max(chapterCount, 1)) }
    func verseCount(chapter: Int) -> Int {
        verseCounts.indices.contains(chapter - 1) ? verseCounts[chapter - 1] : 0
    }
}

// MARK: - Study sources

enum SourceTradition: String, CaseIterable, Identifiable, Codable, Sendable {
    case fathers = "Fathers"
    case reformed = "Reformed"
    /// New in 0.7 wave 2: Tier-2 whole-Bible exegetes who are genuinely valuable, historic
    /// witnesses but are not confessionally Reformed — John Gill (Particular Baptist, moved
    /// out of the Reformed bank per Matt's original spec), Keil & Delitzsch (Lutheran, OT),
    /// Jamieson-Fausset-Brown (Presbyterian & Anglican). "REFORMED" now means Tier 1 only.
    case exegetes = "Exegetes"
    case crossReferences = "Cross-References"
    var id: String { rawValue }
}

/// What kind of material a card is. Deliberately says nothing about doctrinal
/// agreement: a Reformed source is not thereby "Westminster-aligned".
enum SourceClass: Sendable {
    case receivedFather, reformedSource, exegete, canonicalIndex, contrastView, researchOnly

    var label: String {
        switch self {
        case .receivedFather: "RECEIVED FATHER"
        case .reformedSource: "REFORMED SOURCE"
        case .exegete: "EXEGETE"
        case .canonicalIndex: "CANONICAL LINKS"
        case .contrastView: "CONTRAST VIEW"
        case .researchOnly: "RESEARCH ONLY"
        }
    }
}

/// Confessional-Reformed standing, on the tiering Matt specified: Tier 1 may appear in the
/// default commentary view; Tier 2 is genuinely historic and orthodox but must never be
/// presented as confessionally Reformed; Tier 3 is excluded from default results entirely and
/// surfaces only in an opt-in research view. This is a standing, not a doctrinal verdict on the
/// person — it answers "does this belong in the default Reformed study view," nothing more.
enum ConfessionalTier: String, Codable, Sendable, CaseIterable {
    case tier1Confessional = "tier1"
    case tier2HistoricWitness = "tier2"
    case tier3ResearchOnly = "tier3"

    /// Required disclaimer text for Tier 2; Tier 1 carries none, Tier 3 is opt-in and carries
    /// its own separate warning (see `ConfessionalTier.researchWarning`).
    var disclaimer: String? {
        switch self {
        case .tier1Confessional: nil
        case .tier2HistoricWitness: "Historic Christian witness — not uniformly confessional Reformed."
        case .tier3ResearchOnly: "Research-only: significant doctrinal controversy or departure from the confessional standard."
        }
    }

    static let researchWarning = "Research-only excerpts are hidden from default passage results. Their profiles distinguish council judgments, schism and early refutations, with sources and dates where known. This is not a label for every non-Reformed author. Origen and Tertullian remain in the historic-witness category, with their controversies explained in their profiles. Availability also depends on the edition’s distribution permissions."
}

/// What kind of engagement with the passage a source represents — the distinction between "this
/// verse is commented on directly" and "this document happens to cite the verse as support."
enum ContentKind: String, Codable, Sendable, CaseIterable {
    /// Direct verse-by-verse commentary (Calvin's per-verse entries).
    case verseCommentary = "verse-commentary"
    /// Commentary spanning a passage, chapter or pericope rather than one verse.
    case passageCommentary = "passage-commentary"
    /// A sermon or homily preached from the passage.
    case sermon = "sermon"
    /// A confessional document (WCF, Belgic Confession, Canons of Dort...) citing the verse as a proof text.
    case confessionalProofText = "confessional-proof-text"
    /// A catechism question and answer citing the verse as a proof text.
    case catechismProofText = "catechism-proof-text"
    /// A theological work substantially discussing the passage without being verse-by-verse commentary.
    case theologicalDiscussion = "theological-discussion"
    /// A canonical cross-reference index entry: not commentary of any kind, a Scripture-to-Scripture link.
    case canonicalIndex = "canonical-index"
    /// General historical, devotional or topical material that must never be presented as direct
    /// commentary on the verse it happens to be filed under.
    case generalWork = "general-work"

    var label: String {
        switch self {
        case .verseCommentary: "VERSE COMMENTARY"
        case .passageCommentary: "PASSAGE COMMENTARY"
        case .sermon: "SERMON"
        case .confessionalProofText: "CONFESSIONAL PROOF TEXT"
        case .catechismProofText: "CATECHISM PROOF TEXT"
        case .theologicalDiscussion: "THEOLOGICAL DISCUSSION"
        case .canonicalIndex: "CANONICAL INDEX"
        case .generalWork: "GENERAL WORK"
        }
    }
}

/// How the verse range of a source was established.
enum RangeBasis: String, Codable, Sendable {
    /// The source itself states the range (a heading, a verse marker, or catalogue data).
    case stated
    /// The source attaches the text to one verse; how far it reaches is not stated.
    case anchored
    /// One block the source repeats across a run of verses; the run is its span.
    case block

    var caption: String {
        switch self {
        case .stated: "Range stated by the source"
        case .anchored: "Attached to this verse; extent not stated"
        case .block: "One block spanning these verses"
        }
    }
}

/// How an entry was obtained. It never means "theologically approved".
enum ReviewState: String, Codable, Sendable {
    case sourceAttributed = "source-attributed"
    case automatedFilter = "automated-filter"
    case datasetSupplied = "dataset-supplied"

    var label: String {
        switch self {
        case .sourceAttributed: "SOURCE-ATTRIBUTED"
        case .automatedFilter: "AUTO-FILTERED"
        case .datasetSupplied: "DATASET LINKS"
        }
    }
}

struct ReviewInfo: Codable, Hashable, Sendable {
    let state: ReviewState
    let note: String
}

struct SourceRecord: Codable, Hashable, Sendable {
    let title: String
    let short: String
    let publisher: String
    let url: URL
    let license: String
    let review: ReviewInfo
}

/// One canonical cross-reference target, parsed at build time from a TSK reference token
/// ("Prov 8:22-24"). Lets the desk navigate directly instead of leaving the reference as text.
struct CrossReference: Codable, Hashable, Sendable, Identifiable {
    let code: String
    let chapter: Int
    let start: Int
    let end: Int
    let label: String
    var id: String { "\(code).\(chapter).\(start)-\(end)" }
}

struct StudySource: Identifiable, Hashable, Codable, Sendable {
    let id: String
    let chapter: Int
    let startVerse: Int
    let endVerse: Int
    let rangeBasis: RangeBasis
    let author: String
    let work: String
    let era: String
    let tradition: SourceTradition
    let source: String
    let excerpt: String
    let sourceURL: URL?
    let isExactQuote: Bool
    let truncated: Bool?
    let crossRefs: [CrossReference]
    let tier: ConfessionalTier
    let contentKind: ContentKind
    /// The author's own confessional/denominational tradition, shown as a label on every card
    /// in the Exegetes bank (John Gill "Particular Baptist", Keil & Delitzsch "Lutheran",
    /// Jamieson-Fausset-Brown "Presbyterian & Anglican") — new in 0.7 wave 2. `nil` for every
    /// other bank; decodes as `nil` for any older bundled entry that predates this field.
    let authorTradition: String?

    init(id: String, chapter: Int, startVerse: Int, endVerse: Int, rangeBasis: RangeBasis, author: String,
         work: String, era: String, tradition: SourceTradition, source: String, excerpt: String,
         sourceURL: URL?, isExactQuote: Bool, truncated: Bool?, crossRefs: [CrossReference] = [],
         tier: ConfessionalTier = .tier1Confessional, contentKind: ContentKind = .passageCommentary,
         authorTradition: String? = nil) {
        self.id = id; self.chapter = chapter; self.startVerse = startVerse; self.endVerse = endVerse
        self.rangeBasis = rangeBasis; self.author = author; self.work = work; self.era = era
        self.tradition = tradition; self.source = source; self.excerpt = excerpt; self.sourceURL = sourceURL
        self.isExactQuote = isExactQuote; self.truncated = truncated; self.crossRefs = crossRefs
        self.tier = tier; self.contentKind = contentKind; self.authorTradition = authorTradition
    }

    var sourceClass: SourceClass {
        switch tradition {
        // Tier 3 fathers are explicitly not "received" in the sense the chip otherwise
        // claims — the badge must agree with the disclaimer below it, not contradict it.
        case .fathers: tier == .tier3ResearchOnly ? .researchOnly : .receivedFather
        case .reformed: .reformedSource
        case .exegetes: .exegete
        case .crossReferences: .canonicalIndex
        }
    }

    func covers(verse: Int) -> Bool { startVerse <= verse && endVerse >= verse }
    var spanCount: Int { endVerse - startVerse + 1 }

    /// "John 1:1", "John 1:1–5".
    func rangeLabel(bookName: String) -> String {
        startVerse == endVerse
            ? "\(bookName) \(chapter):\(startVerse)"
            : "\(bookName) \(chapter):\(startVerse)–\(endVerse)"
    }
}

/// Whether `provenanceURL` points at this excerpt's own work or only at the source database it
/// came from. Workstream M's 0.9.5 audit found 9,372 Fathers entries (6,714 distinct works) with
/// no per-row `sourceURL`, silently falling back to the whole-repository link — indistinguishable
/// on the card from a real, specific citation. That's a provenance overclaim: never let a generic
/// database link read the same as a verified work-specific one.
enum ProvenanceScope: Sendable {
    case specificWork
    case sourceDatabaseOnly
}

/// A study source resolved for the selected passage: the entry, its registry
/// record (provenance) and any curated confession links.
struct ResolvedSource: Identifiable, Hashable, Sendable {
    let entry: StudySource
    let record: SourceRecord?
    let confessionLinks: [ConfessionLink]
    let passage: String
    var id: String { entry.id }
    /// The most specific provenance link available.
    var provenanceURL: URL? { entry.sourceURL ?? record?.url }
    /// See `ProvenanceScope`. `entry.sourceURL` is a hand-verified or per-row citation of this
    /// exact excerpt's work; falling through to `record?.url` means only the source database as a
    /// whole is linked, not this specific work.
    var provenanceScope: ProvenanceScope { entry.sourceURL != nil ? .specificWork : .sourceDatabaseOnly }
}

struct StudyBookIndex: Codable, Sendable {
    let schema: Int
    let code: String
    let book: String
    let entries: [StudySource]
}

struct SourceRegistry: Codable, Sendable {
    let schema: Int
    let sources: [String: SourceRecord]
}

// MARK: - Father theological profiles (0.8, workstream I)
//
// Matt: "I don't want only reformed church fathers listed, but I want the user to know the
// church fathers' theological bent." Every field here is written from a specific, cited
// public-domain source (see `Resources/Study/fathers-profiles.json`, generated from
// `work-content/fathers-profiles.source.json` by `scripts/build-study-resources.py`) — never
// guessed. A profile omits any field its sources didn't support rather than inventing one, so
// every non-nil field is backed by at least one entry in `sources`. This describes an author's
// historical standing; it never claims doctrinal agreement with Lectern's own Westminster
// baseline (the same non-negotiable the tier system and source-class labels already hold to).

/// A specific conciliar or synodal judgment against an author — only present when a real,
/// citable source names the council/synod and year. Deliberately absent (not a placeholder
/// string) for a condemned author whose sources document no such formal action (e.g. a
/// pre-conciliar Gnostic refuted by Irenaeus's own writing, not by any council) — see
/// `FatherProfile.controversies` for the honest account in that case instead.
struct ConciliarJudgment: Codable, Hashable, Sendable {
    let council: String
    let year: Int
    let note: String?

    var label: String { "\(council), \(String(year))" }
}

/// One citation backing a profile's facts — a public-domain reference work, per the app's
/// standing licensing discipline (never a claim without a checkable source).
struct ProfileSource: Codable, Hashable, Sendable {
    let title: String
    let url: URL?
}

/// A sourced, neutral theological characterization of one patristic (or condemned-heretic)
/// author — school/tradition, region, era, ecclesial standing, emphases, and any conciliar
/// judgment against them. Looked up by exact author name via `FatherProfileStore`.
struct FatherProfile: Codable, Hashable, Sendable, Identifiable {
    let name: String
    let dates: String?
    let region: String?
    let see: String?
    let language: String?
    /// e.g. "Alexandrian — allegorical exegesis", "Antiochene — literal-historical exegesis",
    /// "Cappadocian", "Latin North African", "Syriac".
    let school: String?
    /// e.g. "Saint and Doctor of the Church, East and West".
    let ecclesialRecognition: String?
    /// 1–3 short, neutral phrases naming what the author is chiefly known for emphasizing.
    let emphases: [String]
    /// Neutral account of any doctrinal controversy, conciliar judgment, or disputed reception —
    /// present for both the default bank (e.g. Origen's posthumously disputed anathemas) and the
    /// condemned bucket (where it explains the judgment even when `conciliarJudgment` is nil).
    let controversies: String?
    /// How the Reformers or the Reformed tradition specifically received this author — included
    /// only where a source actually documents it; nil far more often than not (see workstream
    /// I's final report for exactly how many profiles carry this field and why the rest don't).
    let receptionByReformers: String?
    /// Non-nil only for the Tier-3 condemned bucket, and only when a source names a specific
    /// council/synod + year — never a generic "condemned" label.
    let conciliarJudgment: ConciliarJudgment?
    let sources: [ProfileSource]

    var id: String { name }
}

struct FatherProfileFile: Codable, Sendable {
    let schema: Int
    let profiles: [FatherProfile]
}

// MARK: - Westminster Confession

struct ConfessionRef: Codable, Hashable, Sendable {
    let chapter: Int
    let section: Int?
    var label: String { section.map { "WCF \(chapter).\($0)" } ?? "WCF \(chapter)" }
}

enum LinkRelation: String, Codable, Sendable {
    case affirms, discusses, qualifies
}

enum LinkState: String, Codable, Sendable {
    case candidate, curated, rejected
}

/// A human-reviewed statement that one source excerpt bears on one WCF article.
struct ConfessionLink: Codable, Hashable, Sendable, Identifiable {
    let entryID: String
    let wcf: ConfessionRef
    let relation: LinkRelation
    let state: LinkState
    let reviewer: String?
    let reviewedOn: String?
    let note: String?
    let excerptPreview: String?
    var id: String { "\(entryID)#\(wcf.label)" }

    /// Only a named reviewer with a date can make a link displayable.
    var isDisplayable: Bool {
        state == .curated
            && !(reviewer ?? "").trimmingCharacters(in: .whitespaces).isEmpty
            && !(reviewedOn ?? "").isEmpty
    }
}

struct ConfessionChapter: Codable, Hashable, Sendable {
    let n: Int
    let title: String
    let sections: Int
}

/// One of the ecumenical creeds (Apostles', Nicene, Chalcedonian Definition) — full reference
/// text, browsable but not linked to individual verses; creeds state doctrine, they don't cite
/// proof texts the way the Reformation-era confessions and catechisms do.
struct Creed: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let era: String
    let text: String
    let note: String
}

// MARK: - Notes and preferences

struct StudyNote: Identifiable, Codable, Hashable {
    let id: UUID
    var passage: String
    var title: String
    var body: String
    var modifiedAt: Date
}

enum AppTheme: String, CaseIterable, Identifiable {
    case system = "System"
    case light = "Light"
    case dark = "Dark"
    var id: String { rawValue }
}

enum LayoutPreset: String, CaseIterable, Identifiable {
    case reading = "Reading"
    case study = "Study"
    case research = "Research"
    var id: String { rawValue }
}
