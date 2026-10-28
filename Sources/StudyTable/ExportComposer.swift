import Foundation

// ExportComposer — S2c (0.10 wave B). Pure, testable composition of notes / saved passages /
// collections / a bare selection into plain text, Markdown, or PDF `Data`, honoring
// `TranslationExportPolicy` and reporting exactly what (if anything) was left out and why
// (PASTOR-QA-0.10 §Sharing: "ExportReport states exactly what was omitted and why").
//
// Verse text is never read from a stored model — `Note`/`SavedPassage` carry only `Anchor`s — it
// is materialized here, at compose time, from whatever translation the caller selects, via the
// injected `VerseSource`. That keeps this file free of any dependency on `ScriptureLibrary`
// (a `@MainActor` class this workstream does not own); `ScriptureLibrary+Export.swift` supplies
// the real adapter the app will use.
//
// ── PUBLIC API ────────────────────────────────────────────────────────────────────────────────
//  ExportFormat        .plainText, .markdown, .pdf
//  ExportItem          .note(Note) · .saved(SavedPassage) · .collection(StudyCollection,
//                       members: [SavedPassage]) · .selection(Anchor)
//  VerseSource          verses(anchor:translationID:) -> [BibleVerse]? · totalVersesInBook(_:) -> Int?
//  ExportOptions        translation, includeNotes, includeScripture, cappedTranslationOptIn,
//                       title, author, forLecternStudyFile, clipLookup
//  ExportReportLine     .info / .omitted + message
//  ExportReport         lines: [ExportReportLine]
//  ExportResult         text: String? (plainText/markdown) · data: Data? (pdf) · report: ExportReport
//  ExportComposer.compose(items:format:options:verses:) -> ExportResult

enum ExportFormat: String, Sendable, CaseIterable, Identifiable {
    case plainText, markdown, pdf
    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .plainText: "Plain Text"
        case .markdown: "Markdown"
        case .pdf: "PDF"
        }
    }
}

/// What the composer accepts as input, per PASTOR-QA-0.10 §"ExportComposer": "notes / saved
/// passages / a collection / a selection."
enum ExportItem {
    case note(Note)
    case saved(SavedPassage)
    /// `members` is the collection's own resolved order (`StudyStore.savedPassages(in:)`) —
    /// the composer does no store lookups of its own.
    case collection(StudyCollection, members: [SavedPassage])
    /// A bare passage with no saved/note metadata (e.g. the reader's current selection).
    case selection(Anchor)
}

/// How the composer materializes Scripture text — injected so this file never touches
/// `ScriptureLibrary` directly. See `ScriptureLibrary.exportVerseSource()` for the real adapter;
/// tests supply a stub.
struct VerseSource {
    /// Verses covering `anchor` in `translationID`, synchronously, from whatever is already
    /// loaded (a local pack, or an online translation's on-disk cache) — `nil` when unavailable.
    var verses: (_ anchor: Anchor, _ translationID: String) -> [BibleVerse]?
    /// Total verse count across the whole book (every chapter) — used only to enforce "never
    /// more than half a book" for a capped translation. `nil` when unknown: the flat verse cap
    /// (`TranslationExportPolicy.cappedText.maxVerses`) still applies on its own.
    var totalVersesInBook: (_ bookCode: String) -> Int?

    init(verses: @escaping (Anchor, String) -> [BibleVerse]?, totalVersesInBook: @escaping (String) -> Int? = { _ in nil }) {
        self.verses = verses
        self.totalVersesInBook = totalVersesInBook
    }

    /// A source with nothing loaded (every lookup misses) — a fresh instance each access, so it
    /// carries no shared global state under strict concurrency checking.
    static var empty: VerseSource { VerseSource(verses: { _, _ in nil }) }
}

struct ExportOptions {
    var translation: TranslationInfo
    var includeNotes: Bool = true
    var includeScripture: Bool = true
    /// Required, per export, before a capped translation's (ESV) text may appear at all.
    /// Ignored for `.fullText`/`.referencesOnly` policies.
    var cappedTranslationOptIn: Bool = false
    var title: String?
    var author: String?
    /// Set only by the `.lecternstudy` writer: a capped translation's text is never embedded in
    /// a study file even when the caller opted in for this one export.
    var forLecternStudyFile: Bool = false
    /// Resolved `Clip`s for any `Note.clipIDs` in this export (the composer never looks the
    /// store up itself) — e.g. `Dictionary(uniqueKeysWithValues: store.clips.map { ($0.id, $0) })`.
    var clipLookup: [UUID: Clip] = [:]

    init(translation: TranslationInfo, includeNotes: Bool = true, includeScripture: Bool = true,
         cappedTranslationOptIn: Bool = false, title: String? = nil, author: String? = nil,
         forLecternStudyFile: Bool = false, clipLookup: [UUID: Clip] = [:]) {
        self.translation = translation
        self.includeNotes = includeNotes
        self.includeScripture = includeScripture
        self.cappedTranslationOptIn = cappedTranslationOptIn
        self.title = title
        self.author = author
        self.forLecternStudyFile = forLecternStudyFile
        self.clipLookup = clipLookup
    }
}

struct ExportReportLine: Sendable, Equatable, Identifiable, Hashable {
    enum Kind: Sendable, Hashable { case info, omitted }
    var kind: Kind
    var message: String
    var id: String { "\(kind)|\(message)" }
}

struct ExportReport: Sendable, Equatable {
    var lines: [ExportReportLine] = []
    var isEmpty: Bool { lines.isEmpty }
    var omittedLines: [ExportReportLine] { lines.filter { $0.kind == .omitted } }
    mutating func info(_ message: String) {
        guard !lines.contains(where: { $0.kind == .info && $0.message == message }) else { return }
        lines.append(.init(kind: .info, message: message))
    }
    mutating func omitted(_ message: String) { lines.append(.init(kind: .omitted, message: message)) }
}

struct ExportResult {
    var text: String?
    var data: Data?
    var report: ExportReport
}

/// One composed unit of output — a note, a saved passage, or a bare selection, with whatever
/// Scripture text policy allowed materialized alongside it. Shared by the plain-text, Markdown,
/// and PDF renderers so all three make identical inclusion/omission decisions.
struct ExportBlock {
    struct VerseGroup {
        var anchor: Anchor
        var lines: [(number: Int, text: String)]
    }
    var referenceLabel: String
    var verseGroups: [VerseGroup]
    var noteTitle: String?
    var noteBody: String?
    var noteSections: [NoteSection]
    var tags: [String]
    var highlight: HighlightColor?
    var isMemory: Bool
    var clips: [Clip]

    var hasVerseText: Bool { verseGroups.contains { !$0.lines.isEmpty } }
}

@MainActor
enum ExportComposer {
    // MARK: Compose

    static func compose(items: [ExportItem], format: ExportFormat, options: ExportOptions, verses source: VerseSource) -> ExportResult {
        var report = ExportReport()
        let policy = options.translation.exportPolicy
        var collectionHeading: String?
        var blocks: [ExportBlock] = []

        for item in items {
            switch item {
            case .note(let note):
                blocks.append(block(anchors: note.anchors, referenceLabel: note.referenceLabel, note: note,
                                     saved: nil, options: options, policy: policy, source: source, report: &report))
            case .saved(let saved):
                blocks.append(block(anchors: [saved.anchor], referenceLabel: saved.anchor.displayString,
                                     note: nil, saved: saved, options: options, policy: policy,
                                     source: source, report: &report))
            case .collection(let collection, let members):
                collectionHeading = collection.name
                for saved in members {
                    blocks.append(block(anchors: [saved.anchor], referenceLabel: saved.anchor.displayString,
                                         note: nil, saved: saved, options: options, policy: policy,
                                         source: source, report: &report))
                }
            case .selection(let anchor):
                blocks.append(block(anchors: [anchor], referenceLabel: anchor.displayString, note: nil,
                                     saved: nil, options: options, policy: policy, source: source, report: &report))
            }
        }

        enforceCappedLimits(&blocks, policy: policy, options: options, source: source, report: &report)
        appendPolicyNotice(policy: policy, options: options, report: &report)

        switch format {
        case .plainText:
            return ExportResult(text: renderPlainText(blocks: blocks, collectionHeading: collectionHeading, options: options, policy: policy, report: report),
                                 data: nil, report: report)
        case .markdown:
            return ExportResult(text: renderMarkdown(blocks: blocks, collectionHeading: collectionHeading, options: options, policy: policy, report: report),
                                 data: nil, report: report)
        case .pdf:
            let data = ExportPDFRenderer.render(blocks: blocks, collectionHeading: collectionHeading, options: options, policy: policy, report: report)
            return ExportResult(text: nil, data: data, report: report)
        }
    }

    // MARK: One block

    private static func block(anchors: [Anchor], referenceLabel: String, note: Note?, saved: SavedPassage?,
                               options: ExportOptions, policy: TranslationExportPolicy, source: VerseSource,
                               report: inout ExportReport) -> ExportBlock {
        var groups: [ExportBlock.VerseGroup] = []
        if options.includeScripture {
            for anchor in anchors {
                let lines = fetchAllowedVerses(anchor: anchor, options: options, policy: policy, source: source, report: &report)
                groups.append(.init(anchor: anchor, lines: lines))
            }
        }
        let clips = options.includeNotes ? (note?.clipIDs.compactMap { options.clipLookup[$0] } ?? []) : []
        return ExportBlock(referenceLabel: referenceLabel, verseGroups: groups,
                            noteTitle: options.includeNotes ? note?.title : nil,
                            noteBody: options.includeNotes ? note?.body : nil,
                            noteSections: options.includeNotes ? (note?.sections ?? []) : [],
                            tags: (note?.tags.isEmpty == false ? note?.tags : saved?.tags) ?? [],
                            highlight: saved?.highlight, isMemory: saved?.isMemory ?? false, clips: clips)
    }

    /// Whether *any* text may be fetched for this policy at all, ignoring the aggregate cap
    /// (`enforceCappedLimits` trims afterward). `referencesOnly` never fetches; a capped
    /// translation only fetches when the caller opted in for this export and it isn't destined
    /// for a `.lecternstudy` file (never embedded there regardless of opt-in).
    private static func fetchAllowedVerses(anchor: Anchor, options: ExportOptions, policy: TranslationExportPolicy,
                                            source: VerseSource, report: inout ExportReport) -> [(number: Int, text: String)] {
        switch policy {
        case .referencesOnly:
            return []
        case .cappedText(_, _, _, let requiresOptIn, let embeddable):
            if options.forLecternStudyFile && !embeddable { return [] }
            if requiresOptIn && !options.cappedTranslationOptIn { return [] }
        case .fullText:
            break
        }
        guard let verses = source.verses(anchor, options.translation.id), !verses.isEmpty else {
            report.omitted("Verse text unavailable for \(anchor.displayString): \(options.translation.name) is not loaded offline for this passage.")
            return []
        }
        return verses.map { (number: $0.number, text: $0.text) }
    }

    // MARK: Aggregate cap enforcement (ESV: ≤300 verses total, never >½ a book)

    private static func enforceCappedLimits(_ blocks: inout [ExportBlock], policy: TranslationExportPolicy,
                                             options: ExportOptions, source: VerseSource, report: inout ExportReport) {
        guard case .cappedText(let maxVerses, let maxFraction, _, let requiresOptIn, let embeddable) = policy else { return }
        if requiresOptIn && !options.cappedTranslationOptIn { return }   // already all omitted in fetchAllowedVerses
        if options.forLecternStudyFile && !embeddable { return }         // already all omitted in fetchAllowedVerses

        var perBookKept: [String: Int] = [:]
        var totalKept = 0
        var omittedCount = 0

        for bi in blocks.indices {
            for gi in blocks[bi].verseGroups.indices {
                let bookCode = blocks[bi].verseGroups[gi].anchor.book
                let bookCap = source.totalVersesInBook(bookCode).map { Int((Double($0) * maxFraction).rounded(.down)) }
                var kept: [(number: Int, text: String)] = []
                for line in blocks[bi].verseGroups[gi].lines {
                    let wouldExceedGlobal = totalKept + kept.count + 1 > maxVerses
                    let wouldExceedBook = bookCap.map { (perBookKept[bookCode] ?? 0) + kept.count + 1 > $0 } ?? false
                    if wouldExceedGlobal || wouldExceedBook {
                        omittedCount += 1
                        continue
                    }
                    kept.append(line)
                }
                perBookKept[bookCode, default: 0] += kept.count
                totalKept += kept.count
                blocks[bi].verseGroups[gi].lines = kept
            }
        }
        if omittedCount > 0 {
            report.omitted("\(options.translation.name) text omitted for \(omittedCount) verse\(omittedCount == 1 ? "" : "s"): publisher limits (\(maxVerses)-verse export cap, never more than half of any one book).")
        }
    }

    /// "Notice always appended" (PASTOR-QA-0.10 §Sharing) — a capped translation's own required
    /// notice, and a references-only translation's reason, are shown even when no text at all
    /// made it into the export, not merely alongside text that did.
    private static func appendPolicyNotice(policy: TranslationExportPolicy, options: ExportOptions, report: inout ExportReport) {
        switch policy {
        case .fullText:
            report.info(options.translation.attribution)
        case .cappedText(_, _, let notice, _, let embeddable):
            report.info(notice)
            if options.forLecternStudyFile && !embeddable {
                report.info("\(options.translation.name) text is never embedded in a .lecternstudy file — references only.")
            }
        case .referencesOnly(let reason):
            report.info(reason)
        }
    }
}
