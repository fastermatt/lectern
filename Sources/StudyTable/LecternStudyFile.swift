import Foundation
import CryptoKit

// `.lecternstudy` — S2c (0.10 wave B). Pure logic + tests only: no UI hookup, no Info.plist edit
// (Claude registers the document type after all three wave-B workstreams land, per
// WORKPLAN-0.10-B.md). A single JSON file carrying OSIS anchors, tags, notes (with their
// structure), clips (with citations), highlight/memory flags, and Scripture text ONLY for
// translations whose `TranslationExportPolicy` allows embedding — never ESV, never NKJV, never a
// licensed pack, regardless of any per-export opt-in a live share/export might have used.
//
// Untrusted input: this file is designed to be received from someone else's Mac, so
// `LecternStudyReader.parse` treats it like attacker-controlled data — hard size/count/length
// caps, tolerant `Anchor`/`NoteSection`/`ClipCitation` decoding (already lenient — see
// `StudyModels.swift`) so a damaged record cannot crash the decode, and no field is ever
// interpreted as a file path, URL to load, or command.
//
// ── PUBLIC API ────────────────────────────────────────────────────────────────────────────────
//  LecternStudyFile         format/version/kind/title/author/created/items (Codable)
//  LecternStudyItem         anchor, tags, note* fields, highlight, isMemory, scripture, clips
//  LecternStudyWriter.make(...)   builds a file from live store data, respecting export policy
//  LecternStudyWriter.encode(_:) -> Data
//  LecternStudyReader.parse(_:) throws -> LecternStudyFile   (hostile-input-safe)
//  LecternStudyImporter.preview(data:existing:) throws -> LecternStudyImportPreview
//  LecternStudyImporter.apply(_:into:) -> LecternStudyApplyResult   (never overwrites)

enum LecternStudyKind: String, Codable, Sendable, CaseIterable {
    case collection, project, noteSet
}

// Every type below decodes tolerantly (missing/wrong-typed fields fall back to a default, a bad
// array element is skipped rather than failing the whole array) using the same
// `KeyedDecodingContainer.lenient`/`lossyArray` helpers `StudyModels.swift` defines for exactly
// this reason: `.lecternstudy` is designed to arrive from someone else's Mac, so it is treated
// like attacker-controlled input, the same way a v1 `notes.json` is (PASTOR-QA-0.10 defect 1).
// Swift's synthesized `Decodable` does NOT apply a stored property's default value when its key
// is simply absent from the JSON (that only affects the memberwise initializer) — a hand-shared
// `.lecternstudy` routinely omits optional-ish fields (a saved passage with no note, a note with
// no tags), so without a custom, tolerant `init(from:)` those ordinary files would fail to decode
// at all.

struct LecternStudyVerseText: Codable, Sendable, Equatable {
    var translationID: String
    var attribution: String
    var verses: [RemoteVerse]

    init(translationID: String, attribution: String, verses: [RemoteVerse]) {
        self.translationID = translationID
        self.attribution = attribution
        self.verses = verses
    }

    private enum CodingKeys: String, CodingKey { case translationID, attribution, verses }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        translationID = c.lenient(String.self, .translationID) ?? ""
        attribution = c.lenient(String.self, .attribution) ?? ""
        verses = c.lossyArray(RemoteVerse.self, .verses)
    }
}

struct LecternStudyClip: Codable, Sendable, Equatable {
    var excerpt: String
    var citation: ClipCitation

    init(excerpt: String, citation: ClipCitation = ClipCitation()) {
        self.excerpt = excerpt
        self.citation = citation
    }

    private enum CodingKeys: String, CodingKey { case excerpt, citation }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        excerpt = c.lenient(String.self, .excerpt) ?? ""
        citation = c.lenient(ClipCitation.self, .citation) ?? ClipCitation()
    }
}

struct LecternStudyItem: Codable, Sendable, Equatable {
    var anchor: Anchor
    var tags: [String] = []
    var noteTitle: String? = nil
    var noteKind: NoteKind? = nil
    var noteSections: [NoteSection] = []
    var noteBody: String? = nil
    var highlight: HighlightColor? = nil
    var isMemory: Bool = false
    /// Present only when the source translation's `exportPolicy.embeddableInLecternStudyFile` is
    /// true — see `LecternStudyWriter`.
    var scripture: [LecternStudyVerseText] = []
    var clips: [LecternStudyClip] = []

    init(anchor: Anchor, tags: [String] = [], noteTitle: String? = nil, noteKind: NoteKind? = nil,
         noteSections: [NoteSection] = [], noteBody: String? = nil, highlight: HighlightColor? = nil,
         isMemory: Bool = false, scripture: [LecternStudyVerseText] = [], clips: [LecternStudyClip] = []) {
        self.anchor = anchor
        self.tags = tags
        self.noteTitle = noteTitle
        self.noteKind = noteKind
        self.noteSections = noteSections
        self.noteBody = noteBody
        self.highlight = highlight
        self.isMemory = isMemory
        self.scripture = scripture
        self.clips = clips
    }

    var hasNoteContent: Bool {
        (noteTitle?.isEmpty == false) || (noteBody?.isEmpty == false)
            || noteSections.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    private enum CodingKeys: String, CodingKey {
        case anchor, tags, noteTitle, noteKind, noteSections, noteBody, highlight, isMemory, scripture, clips
    }

    /// The wire form carries `anchor` as an OSIS reference string ("Rom.8.28", "Rom.8.28-Rom.8.39")
    /// — per PASTOR-QA-0.10 §"`.lecternstudy`": "carrying OSIS anchors" — rather than the app's
    /// internal positional struct, so the file stays a plain, portable, human-readable reference
    /// even outside Lectern. `Anchor` already has both directions (`osis`, `init?(osis:)`).
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let osis = c.lenient(String.self, .anchor), let parsed = Anchor(osis: osis) {
            anchor = parsed
        } else {
            anchor = Anchor(book: "", chapter: 1, verse: 0)   // invalid on purpose — caught by `isValid` checks
        }
        tags = StudyTag.normalized(c.lossyArray(String.self, .tags))
        noteTitle = c.lenient(String.self, .noteTitle)
        noteKind = c.lenient(NoteKind.self, .noteKind)
        noteSections = c.lossyArray(NoteSection.self, .noteSections)
        noteBody = c.lenient(String.self, .noteBody)
        highlight = c.lenient(HighlightColor.self, .highlight)
        isMemory = c.lenient(Bool.self, .isMemory) ?? false
        scripture = c.lossyArray(LecternStudyVerseText.self, .scripture)
        clips = c.lossyArray(LecternStudyClip.self, .clips)
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(anchor.osis, forKey: .anchor)
        try c.encode(tags, forKey: .tags)
        try c.encodeIfPresent(noteTitle, forKey: .noteTitle)
        try c.encodeIfPresent(noteKind, forKey: .noteKind)
        try c.encode(noteSections, forKey: .noteSections)
        try c.encodeIfPresent(noteBody, forKey: .noteBody)
        try c.encodeIfPresent(highlight, forKey: .highlight)
        try c.encode(isMemory, forKey: .isMemory)
        try c.encode(scripture, forKey: .scripture)
        try c.encode(clips, forKey: .clips)
    }
}

struct LecternStudyFile: Codable, Sendable, Equatable {
    static let formatTag = "lectern-study"
    static let currentVersion = 1

    var format: String
    var version: Int
    var kind: LecternStudyKind
    var title: String
    var author: String?
    var created: Date
    var items: [LecternStudyItem]

    init(kind: LecternStudyKind, title: String, author: String? = nil, created: Date = Date(), items: [LecternStudyItem]) {
        self.format = Self.formatTag
        self.version = Self.currentVersion
        self.kind = kind
        self.title = title
        self.author = author
        self.created = created
        self.items = items
    }
}

// MARK: - Writing

enum LecternStudyWriter {
    /// Builds a file from live data. `notes`/`saved` are whatever the caller already selected
    /// (a collection's members, a project's referenced items, …) — this never queries the store
    /// itself, matching `ExportComposer`'s "caller resolves, composer only shapes" split.
    static func makeFile(kind: LecternStudyKind, title: String, author: String? = nil,
                          notes: [Note] = [], saved: [SavedPassage] = [],
                          clipLookup: [UUID: Clip] = [:], translation: TranslationInfo,
                          verses source: VerseSource, created: Date = Date()) -> LecternStudyFile {
        let policy = translation.exportPolicy
        var items: [LecternStudyItem] = []

        for saved in saved {
            items.append(item(anchor: saved.anchor, tags: saved.tags, highlight: saved.highlight,
                               isMemory: saved.isMemory, note: nil, clips: [], translation: translation,
                               policy: policy, source: source))
        }
        for note in notes {
            let clips = note.clipIDs.compactMap { clipLookup[$0] }
            guard let anchor = note.anchors.first else {
                // No anchor at all (a legacy/unparsed note, kept verbatim as `legacyPassage` by
                // `StudyStore`) — `.lecternstudy` items are always anchored to a Scripture
                // position (`LecternStudyReader` rejects an item that isn't), so there is no valid
                // representation for one here; skip it rather than emit a file that would reject
                // itself on import. The caller's own UI is the place to warn about this, not this
                // pure builder.
                continue
            }
            items.append(item(anchor: anchor, tags: note.tags, highlight: nil, isMemory: false,
                               note: note, clips: clips, translation: translation, policy: policy, source: source))
        }
        return LecternStudyFile(kind: kind, title: title, author: author, created: created, items: items)
    }

    private static func item(anchor: Anchor, tags: [String], highlight: HighlightColor?, isMemory: Bool,
                              note: Note?, clips: [Clip], translation: TranslationInfo, policy: TranslationExportPolicy,
                              source: VerseSource) -> LecternStudyItem {
        var scripture: [LecternStudyVerseText] = []
        if policy.embeddableInLecternStudyFile, let verses = source.verses(anchor, translation.id), !verses.isEmpty {
            scripture = [LecternStudyVerseText(translationID: translation.id, attribution: translation.attribution,
                                                verses: verses.map { RemoteVerse(n: $0.number, t: $0.text) })]
        }
        return LecternStudyItem(anchor: anchor, tags: tags, noteTitle: note?.title, noteKind: note?.kind,
                                 noteSections: note?.sections ?? [], noteBody: note?.body, highlight: highlight,
                                 isMemory: isMemory, scripture: scripture,
                                 clips: clips.map { LecternStudyClip(excerpt: $0.excerpt, citation: $0.citation) })
    }

    static func encode(_ file: LecternStudyFile) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(file)
    }
}

// MARK: - Reading (untrusted input)

enum LecternStudyLimits {
    static let maxFileBytes = 8 * 1024 * 1024
    static let maxItems = 2_000
    static let maxFieldLength = 20_000
    static let maxTagsPerItem = 50
    static let maxClipsPerItem = 20
}

enum LecternStudyError: Error, LocalizedError, Equatable {
    case tooLarge(Int)
    case notJSON
    case wrongFormat(String)
    case unsupportedVersion(Int)
    case malformed(String)
    case tooManyItems(Int)
    case fieldTooLong(String)

    var errorDescription: String? {
        switch self {
        case .tooLarge(let n): "This file is \(n) bytes — larger than Throughline accepts for a study file."
        case .notJSON: "This isn't a valid Throughline study file (not readable JSON)."
        case .wrongFormat(let format): "This file's format is \"\(format)\", not a Throughline study file."
        case .unsupportedVersion(let v): "This file was made by a newer version of Throughline (format version \(v)) and can't be opened."
        case .malformed(let reason): "This Throughline study file is damaged: \(reason)."
        case .tooManyItems(let n): "This file has \(n) items — more than Throughline will import at once."
        case .fieldTooLong(let field): "This file's \(field) field is unreasonably long and was rejected."
        }
    }
}

enum LecternStudyReader {
    /// Parses and validates untrusted bytes. Never throws a Swift runtime error for garbage
    /// input — every rejection is a typed, user-presentable `LecternStudyError`.
    static func parse(_ data: Data) throws -> LecternStudyFile {
        guard data.count <= LecternStudyLimits.maxFileBytes else { throw LecternStudyError.tooLarge(data.count) }
        guard let raw = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
              let object = raw as? [String: Any] else { throw LecternStudyError.notJSON }
        let format = object["format"] as? String
        guard format == LecternStudyFile.formatTag else { throw LecternStudyError.wrongFormat(format ?? "?") }
        let version = object["version"] as? Int ?? -1
        guard version >= 1, version <= LecternStudyFile.currentVersion else { throw LecternStudyError.unsupportedVersion(version) }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let file = try? decoder.decode(LecternStudyFile.self, from: data) else {
            throw LecternStudyError.malformed("its item list could not be read")
        }
        guard file.items.count <= LecternStudyLimits.maxItems else { throw LecternStudyError.tooManyItems(file.items.count) }
        guard file.title.count <= LecternStudyLimits.maxFieldLength else { throw LecternStudyError.fieldTooLong("title") }
        for item in file.items {
            guard item.anchor.isValid else { throw LecternStudyError.malformed("an item has an invalid Scripture reference") }
            guard item.tags.count <= LecternStudyLimits.maxTagsPerItem else { throw LecternStudyError.malformed("an item has too many tags") }
            guard item.clips.count <= LecternStudyLimits.maxClipsPerItem else { throw LecternStudyError.malformed("an item has too many clips") }
            if let title = item.noteTitle, title.count > LecternStudyLimits.maxFieldLength { throw LecternStudyError.fieldTooLong("note title") }
            if let body = item.noteBody, body.count > LecternStudyLimits.maxFieldLength { throw LecternStudyError.fieldTooLong("note body") }
            for section in item.noteSections where section.text.count > LecternStudyLimits.maxFieldLength {
                throw LecternStudyError.fieldTooLong("note section")
            }
            for clip in item.clips where clip.excerpt.count > LecternStudyLimits.maxFieldLength {
                throw LecternStudyError.fieldTooLong("clip excerpt")
            }
            for verseText in item.scripture where verseText.verses.count > 2_000 {
                throw LecternStudyError.malformed("a scripture block has an implausible number of verses")
            }
        }
        return file
    }
}

// MARK: - Content hash (dedup)

/// A stable (not `Hasher`-salted) fingerprint of a note's anchor + content, so re-importing the
/// same file — or a file that overlaps one already imported — never creates a duplicate note.
func lecternStudyContentHash(anchorOSIS: String, title: String, body: String, sections: [NoteSection]) -> String {
    var combined = "\(anchorOSIS)|\(title)|\(body)"
    for section in sections { combined += "|\(section.key)=\(section.text)" }
    let digest = SHA256.hash(data: Data(combined.utf8))
    return digest.map { String(format: "%02x", $0) }.joined()
}

// MARK: - Import preview & apply

struct LecternStudyImportPreview {
    var title: String
    var kind: LecternStudyKind
    var author: String?
    var totalItems: Int
    var newSavedCount: Int
    var duplicateSavedCount: Int
    var newNoteCount: Int
    var duplicateNoteCount: Int
    var newClipCount: Int
    /// Human-readable notes about what will happen — duplicates skipped, invalid entries, etc.
    var conflicts: [String]
    fileprivate var file: LecternStudyFile
}

struct LecternStudyApplyResult {
    var collectionID: UUID? = nil
    var addedSavedIDs: [UUID] = []
    var addedNoteIDs: [UUID] = []
    var addedClipCount: Int = 0
    var skippedDuplicateSaved: Int = 0
    var skippedDuplicateNotes: Int = 0
}

@MainActor
enum LecternStudyImporter {
    /// Parses, validates, and classifies against the store's *current* state — nothing is
    /// written yet.
    static func preview(data: Data, existing store: StudyStore) throws -> LecternStudyImportPreview {
        let file = try LecternStudyReader.parse(data)
        var newSaved = 0, dupSaved = 0, newNotes = 0, dupNotes = 0, newClips = 0
        var conflicts: [String] = []

        for item in file.items where item.anchor.isValid {
            if store.isSaved(item.anchor) { dupSaved += 1 } else { newSaved += 1 }
            if item.hasNoteContent {
                let hash = lecternStudyContentHash(anchorOSIS: item.anchor.osis, title: item.noteTitle ?? "",
                                                    body: item.noteBody ?? "", sections: item.noteSections)
                let exists = store.notes(exactlyAt: item.anchor).contains {
                    lecternStudyContentHash(anchorOSIS: item.anchor.osis, title: $0.title, body: $0.body, sections: $0.sections) == hash
                }
                if exists { dupNotes += 1; conflicts.append("A note at \(item.anchor.displayString) is already in My Study — skipped.") }
                else { newNotes += 1 }
            }
            newClips += item.clips.count
        }
        if file.items.contains(where: { !$0.anchor.isValid }) {
            conflicts.append("Some items had invalid Scripture references and will be skipped.")
        }
        return LecternStudyImportPreview(title: file.title, kind: file.kind, author: file.author,
                                          totalItems: file.items.count, newSavedCount: newSaved, duplicateSavedCount: dupSaved,
                                          newNoteCount: newNotes, duplicateNoteCount: dupNotes, newClipCount: newClips,
                                          conflicts: conflicts, file: file)
    }

    /// Applies a previously computed preview. Never overwrites existing content: a saved passage
    /// already at that anchor is left untouched (only added to the new collection); a note whose
    /// anchor+content hash already exists is skipped entirely. Every note/saved passage this
    /// creates is tagged with the file's origin.
    @discardableResult
    static func apply(_ preview: LecternStudyImportPreview, into store: StudyStore) -> LecternStudyApplyResult {
        let originTag = StudyTag.normalize("Imported: \(preview.title.isEmpty ? "Untitled study" : preview.title)")
        var result = LecternStudyApplyResult()

        let hasSavedItems = preview.file.items.contains { $0.anchor.isValid }
        var collectionID: UUID?
        if hasSavedItems {
            let name = uniqueCollectionName(base: preview.title.isEmpty ? "Imported study" : preview.title, existing: store.collections)
            collectionID = store.createCollection(name: name)?.id
        }
        result.collectionID = collectionID

        for item in preview.file.items where item.anchor.isValid {
            let tags = StudyTag.normalized(item.tags + [originTag])
            let wasAlreadySaved = store.isSaved(item.anchor)
            if let saved = store.save(item.anchor, highlight: item.highlight, isMemory: item.isMemory, tags: tags) {
                if let collectionID { store.addToCollection(savedID: saved.id, collectionID: collectionID) }
                if wasAlreadySaved { result.skippedDuplicateSaved += 1 } else { result.addedSavedIDs.append(saved.id) }
            }

            if item.hasNoteContent {
                let hash = lecternStudyContentHash(anchorOSIS: item.anchor.osis, title: item.noteTitle ?? "",
                                                    body: item.noteBody ?? "", sections: item.noteSections)
                let exists = store.notes(exactlyAt: item.anchor).contains {
                    lecternStudyContentHash(anchorOSIS: item.anchor.osis, title: $0.title, body: $0.body, sections: $0.sections) == hash
                }
                if exists {
                    result.skippedDuplicateNotes += 1
                } else if let note = store.addNote(anchors: [item.anchor], title: item.noteTitle ?? "",
                                                    kind: item.noteKind ?? .free, body: item.noteBody ?? "",
                                                    sections: item.noteSections, tags: tags) {
                    result.addedNoteIDs.append(note.id)
                }
            }

            for clip in item.clips {
                if store.addClip(Clip(kind: .other, excerpt: clip.excerpt, citation: clip.citation, anchor: item.anchor, capturedAt: Date())) {
                    result.addedClipCount += 1
                }
            }
        }
        return result
    }

    private static func uniqueCollectionName(base: String, existing: [StudyCollection]) -> String {
        let names = Set(existing.map { $0.name.lowercased() })
        guard names.contains(base.lowercased()) else { return base }
        var n = 2
        while names.contains("\(base) (\(n))".lowercased()) { n += 1 }
        return "\(base) (\(n))"
    }
}
