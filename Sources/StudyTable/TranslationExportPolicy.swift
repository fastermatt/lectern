import Foundation

// Translation export/share/`.lecternstudy` policy — PASTOR-QA-0.10 §"Translation export policy"
// and CONTENT-SOURCES.md. Every place Scripture
// text can leave the app (single-verse Copy, `ExportComposer`, `.lecternstudy`) asks this one
// classification, so the rule lives in exactly one place.
//
// Classification is keyed by translation id alone (upper-cased), not by a full `TranslationInfo`
// instance, so it works from just an abbreviation string — `VerseClipboard.swift`'s
// `verseClipboardText` only ever has `translation: String`, never the catalog entry.

/// How much Scripture text (if any) a translation may contribute to something that leaves the
/// app: a clipboard copy, a plain-text/Markdown/PDF export, or a `.lecternstudy` file.
enum TranslationExportPolicy: Sendable, Equatable {
    /// Public-domain or otherwise redistribution-compatible text: full text may be copied,
    /// exported, and embedded in `.lecternstudy` files. Attribution comes from the translation's
    /// own `TranslationInfo.attribution` (varies per pack) — this case carries none of its own.
    case fullText
    /// A licensed translation available through the user's own publisher key (ESV/API.Bible).
    /// Text may appear only up to `maxVerses` total, and never more than `maxBookFraction` of any
    /// one book, only when the caller has explicitly opted in for that export, `notice` must
    /// always be shown alongside whatever text does appear (even when the cap omits all of it),
    /// and — regardless of opt-in — the text is never written into a `.lecternstudy` file
    /// (`embeddableInStudyFile` is always `false`; `.lecternstudy` carries references only there).
    case cappedText(maxVerses: Int, maxBookFraction: Double, notice: String, requiresOptIn: Bool, embeddableInStudyFile: Bool)
    /// No Scripture text leaves the app under this translation/policy — only the reference
    /// ("Romans 8:28") may be copied, exported, or embedded.
    case referencesOnly(reason: String)

    /// BSB/KJV (bundled) plus the public-domain packs `BibleDownloads.catalog` can install.
    /// Spelled the way `TranslationInfo.id` / `BibleDownload.id` actually spell them — not the
    /// display names PASTOR-QA-0.10 uses ("Darby" is id `DBY`, "Webster" is `WBS`, "Ostervald"
    /// is `FOB`; read the actual source, per the workplan, rather than trusting the prose).
    static let freeTranslationIDs: Set<String> = Set(["BSB", "KJV", "WEB"] + BibleDownload.catalog.map(\.id))

    /// Crossway's ESV API notice (`OnlineTranslations.swift`'s `ESVProvider.attribution`) —
    /// reused verbatim, never restated, per the workplan.
    static let esvNotice = ESVProvider.attribution

    /// NKJV is references-only pending API.Bible terms review — reusing `OnlineProvider.apiBible`'s
    /// own `termsSummary` wording (`OnlineTranslations.swift`) rather than inventing new text.
    static var nkjvReferencesOnlyReason: String {
        "NKJV text is references-only in exports and shares. " + OnlineProvider.apiBible.termsSummary
    }

    /// Any other installed pack not on the free list (e.g. NASB, or a user-installed licensed
    /// pack `ScriptureLibrary` reports as `.installedPack`/`.licensePackRequired`) — PASTOR-QA-0.10
    /// §Sharing: "user-installed licensed packs → references-only by default."
    static let licensedPackReferencesOnlyReason =
        "This translation is a user-installed or licensed pack; full text in exports and shares is references-only by default until its offline redistribution rights are confirmed and recorded (see the wiki's Licensing Position)."

    static let esvMaxVerses = 300
    static let esvMaxBookFraction = 0.5

    static func policy(forTranslationID id: String) -> TranslationExportPolicy {
        switch id.uppercased() {
        case "ESV":
            .cappedText(maxVerses: esvMaxVerses, maxBookFraction: esvMaxBookFraction, notice: esvNotice,
                        requiresOptIn: true, embeddableInStudyFile: false)
        case "NKJV":
            .referencesOnly(reason: nkjvReferencesOnlyReason)
        case let upper where freeTranslationIDs.contains(upper):
            .fullText
        default:
            .referencesOnly(reason: licensedPackReferencesOnlyReason)
        }
    }

    /// Whether this policy would ever allow this translation's Scripture text into a
    /// `.lecternstudy` file (independent of any per-export opt-in for a live share/export).
    var embeddableInLecternStudyFile: Bool {
        switch self {
        case .fullText: true
        case .cappedText(_, _, _, _, let embeddable): embeddable
        case .referencesOnly: false
        }
    }
}

extension TranslationInfo {
    /// See `TranslationExportPolicy`. Looked up by `id` alone; two packs sharing an id would
    /// share a policy, which cannot happen — `ScriptureLibrary.rescan()` de-duplicates by id.
    var exportPolicy: TranslationExportPolicy { TranslationExportPolicy.policy(forTranslationID: id) }
}
