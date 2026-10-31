import Foundation
import os
import StudyTableCore

// StudyStore — the single owner of the reader's own study data (notes, saved passages,
// collections, clips, projects). Replaces `NotesStore` (`typealias NotesStore = StudyStore`).
//
// ── DATA SAFETY (this file's first job; PASTOR-QA-0.10 defect 1) ─────────────────────────────
//  • The store never falls back to "empty" and then overwrites. Every failure path either
//    recovers (salvage / backup) or runs READ-ONLY and tells the user via `alert`.
//  • Decoding is tolerant: a missing or wrong-typed field takes a default, unknown keys are
//    ignored, an unusable array element is skipped (and the original file is preserved).
//  • Writes are atomic (`Data.write(.atomic)`), and the previous good file is rotated to
//    `study.json.bak` (first save of each launch, then at most every 5 minutes) plus one dated
//    snapshot per day in `Backups/study-YYYYMMDD.json` (newest 14 kept).
//  • A file that fails to decode is renamed `study.corrupt-<ts>.json` (never deleted); recovery
//    tries `.bak`, then the dated snapshots. No good copy → read-only until the user chooses
//    `resumeEditing()`. A file written by a NEWER schema is also opened read-only.
//  • v1 `notes.json` (a bare array) migrates once into `study.json` (schema 2): the raw file is
//    copied to `Backups/notes-v1-<ts>.json` FIRST (no backup → no migration), a truncated file is
//    salvaged object-by-object, empty-body "Observation" ghosts are dropped from live data (kept
//    in the backup, listed in `loadReport`), and `notes.json` itself is left untouched.
//
// ── PUBLIC API (module-internal; wave B builds on this) ──────────────────────────────────────
//  Lifecycle    init(directory:clock:) · loadReport · isReadOnly · alert / dismissAlert() ·
//               resumeEditing() · hasUnsavedChanges
//  Notes        allNotes · note(id:) · addNote(anchors:title:kind:body:sections:tags:) ·
//               editNote(_:_:) (modifiedAt moves ONLY on content change) · deleteNote(_:) (soft) ·
//               restoreNote(_:) · purgeNote(_:) · notes(overlapping:) · notes(exactlyAt:) ·
//               notes(taggedWith:)
//  Saved        savedPassages · savedPassage(id:) · savedPassage(matching:) · isSaved(_:) ·
//               save(_:highlight:isMemory:tags:collectionIDs:) · toggleSaved(_:) · editSaved(_:_:) ·
//               setHighlight/setMemory/setTags · unsave(_:) (soft) · restoreSaved(_:) · purgeSaved(_:)
//  Collections  collections · createCollection(name:) · renameCollection · deleteCollection ·
//               addToCollection/removeFromCollection · savedPassages(in:) · setOrder
//  Tags         tagCounts() · setTags(noteID:tags:) · setTags(savedID:tags:) · savedPassages(taggedWith:)
//  Clips/Proj   clips · addClip · removeClip · projects · upsertProject · deleteProject
//  Queries      items(overlapping:) → StudyItems · search(_:scope:) → [StudySearchHit]
//  Deleted      recentlyDeleted → [DeletedItem] · restore(_:) · purgeExpired() · emptyRecentlyDeleted()
//               (30-day retention; expired items are purged at launch)
//  Legacy       NotesStore.swift adapts `notes` / `note(for:)` / `update(passage:title:body:)` /
//               `delete(passage:)` so today's UI compiles and stops misbehaving unchanged.

// MARK: - Status types

/// What the UI should tell the user (bind a `.alert` to `StudyStore.alert`).
struct StudyStoreAlert: Identifiable, Equatable {
    enum Severity: Equatable { case info, warning, error }
    let id = UUID()
    let severity: Severity
    let title: String
    let message: String
}

/// How the store came up. Tests and diagnostics read this; the UI reads `alert`.
enum StudyLoadOutcome: Equatable {
    case fresh
    case loaded
    case migratedFromV1(notes: Int, backup: URL)
    /// v1 file was damaged; `recovered` notes were salvaged (original kept at `backup`).
    case salvagedFromV1(recovered: Int, backup: URL)
    case recoveredFromBackup(source: URL, damagedFile: URL?)
    /// Nothing usable — running read-only. `damagedFile` is where the bad file was moved.
    case corrupt(damagedFile: URL?)
    case newerSchema(Int)
    case unreadable
}

struct LegacyGhost: Equatable { let id: UUID; let passage: String }

struct StudyLoadReport: Equatable {
    var outcome: StudyLoadOutcome = .fresh
    /// v1 empty-body "Observation" notes left out of live data (they remain in the backup).
    var droppedGhosts: [LegacyGhost] = []
    /// v1 passages that could not be parsed into an `Anchor` (kept verbatim on the note).
    var unparsedPassages: [String] = []
    /// Array elements too damaged to use (the original file was preserved).
    var skippedElements = 0
    var purgedExpired = 0
}

enum StudySearchScope: CaseIterable, Sendable { case all, notes, saved, clips, projects }

struct StudyItems: Equatable {
    var notes: [Note] = []
    var saved: [SavedPassage] = []
    var clips: [Clip] = []
    var projects: [StudyProject] = []
    var isEmpty: Bool { notes.isEmpty && saved.isEmpty && clips.isEmpty && projects.isEmpty }
}

struct StudySearchHit: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable { case note, saved, clip, project }
    let id: UUID
    let kind: Kind
    let title: String
    let snippet: String
    let anchors: [Anchor]
    let date: Date
    /// True when the hit came from passage overlap ("Rom 8" finds Romans 8:28), not text.
    let viaAnchor: Bool
}

struct DeletedItem: Identifiable, Equatable, Sendable {
    enum Kind: Sendable { case note, saved }
    let id: UUID
    let kind: Kind
    let title: String
    let deletedAt: Date
    let expiresAt: Date
}

// MARK: - Store

@MainActor
final class StudyStore: ObservableObject {
    static let retention: TimeInterval = 30 * 86_400
    private static let backupRotationInterval: TimeInterval = 300
    private static let keptDailySnapshots = 14
    private static let log = Logger(subsystem: "com.fastermatt.studytable", category: "StudyStore")

    @Published private(set) var data = StudyEnvelope()
    @Published private(set) var isReadOnly = false
    @Published private(set) var hasUnsavedChanges = false
    @Published var alert: StudyStoreAlert?
    private(set) var loadReport = StudyLoadReport()

    let directory: URL
    private let clock: () -> Date
    private var lastBackupRotation: Date?
    private var saveFailureAlerted = false
    private var anchorCache: [String: Anchor?] = [:]

    var studyURL: URL { directory.appendingPathComponent("study.json") }
    var backupURL: URL { directory.appendingPathComponent("study.json.bak") }
    var legacyNotesURL: URL { directory.appendingPathComponent("notes.json") }
    /// Written after a v1 migration so `notes.json` (left in place) is never migrated twice.
    var migrationMarkerURL: URL { directory.appendingPathComponent("notes-v1.migrated") }
    var backupsDirectory: URL { directory.appendingPathComponent("Backups", isDirectory: true) }

    /// `directory` defaults to the real `~/Library/Application Support/StudyTable` but is
    /// injectable — tests must pass an ephemeral directory (`ephemeralStudy()`).
    init(directory: URL = AppResources.supportDirectory, clock: @escaping () -> Date = Date.init) {
        self.directory = directory
        self.clock = clock
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        load()
    }

    private var now: Date { clock() }

    // MARK: Loading

    private func load() {
        let fm = FileManager.default
        if fm.fileExists(atPath: studyURL.path) {
            loadStudyFile()
        } else if let (recovered, source) = firstValidBackup() {
            data = recovered
            loadReport.outcome = .recoveredFromBackup(source: source, damagedFile: nil)
            raise(.warning, "Your study data was restored from a backup",
                  "study.json was missing, so Thruline restored your notes from \(source.lastPathComponent).")
            persist()
        } else if fm.fileExists(atPath: legacyNotesURL.path), !fm.fileExists(atPath: migrationMarkerURL.path) {
            migrateLegacyNotes()
        } else {
            loadReport.outcome = .fresh
        }
        if !isReadOnly { purgeExpiredOnLaunch() }
    }

    private func loadStudyFile() {
        guard let raw = try? Data(contentsOf: studyURL) else {
            isReadOnly = true
            loadReport.outcome = .unreadable
            raise(.error, "Thruline can't read your study data",
                  "study.json exists but could not be read. Nothing has been changed. Check the file's permissions, then relaunch.")
            return
        }
        do {
            let decoded = try StudyEnvelope.decodeTolerant(raw, fallbackDate: now)
            data = decoded.envelope
            loadReport.outcome = .loaded
            if decoded.envelope.schema > StudyEnvelope.currentSchema {
                isReadOnly = true
                loadReport.outcome = .newerSchema(decoded.envelope.schema)
                raise(.warning, "Your study data is from a newer version of Thruline",
                      "It was saved with schema \(decoded.envelope.schema), which this version can't safely edit. It is open read-only so nothing is overwritten. Update Thruline to keep editing.")
            } else if decoded.skipped > 0 {
                loadReport.skippedElements = decoded.skipped
                let kept = preserve(raw, named: "study-partial")
                raise(.warning, "Some study items were unreadable",
                      "\(decoded.skipped) item(s) in study.json were damaged and were skipped. The original file was kept\(kept.map { " as \($0.lastPathComponent) in Backups" } ?? "").")
            }
        } catch {
            recoverFromCorruptStudyFile()
        }
    }

    /// study.json failed to decode: move it aside (never delete), then try the backups.
    private func recoverFromCorruptStudyFile() {
        let damaged = moveAside(studyURL, base: "study.corrupt")
        if let (recovered, source) = firstValidBackup() {
            data = recovered
            loadReport.outcome = .recoveredFromBackup(source: source, damagedFile: damaged)
            raise(.warning, "Your study data was restored from a backup",
                  "study.json was damaged, so Thruline restored your notes from \(source.lastPathComponent). The damaged file was kept as \(damaged?.lastPathComponent ?? "a .corrupt file") in the StudyTable folder.")
            persist()
        } else {
            data = StudyEnvelope()
            isReadOnly = true
            loadReport.outcome = .corrupt(damagedFile: damaged)
            raise(.error, "Your study data could not be read",
                  "study.json is damaged and no backup was usable. It was kept as \(damaged?.lastPathComponent ?? "a .corrupt file") in the StudyTable folder — nothing was deleted. Thruline is read-only this session so it can't overwrite anything.")
        }
    }

    /// Candidates: `study.json.bak`, then dated snapshots newest → oldest.
    private func firstValidBackup() -> (StudyEnvelope, URL)? {
        var candidates = [backupURL]
        if let names = try? FileManager.default.contentsOfDirectory(atPath: backupsDirectory.path) {
            candidates += names.filter(Self.isDailySnapshotName).sorted(by: >).map { backupsDirectory.appendingPathComponent($0) }
        }
        for url in candidates {
            guard let raw = try? Data(contentsOf: url),
                  let decoded = try? StudyEnvelope.decodeTolerant(raw, fallbackDate: now),
                  decoded.envelope.schema <= StudyEnvelope.currentSchema else { continue }
            return (decoded.envelope, url)
        }
        return nil
    }

    private static func isDailySnapshotName(_ name: String) -> Bool {
        name.count == "study-YYYYMMDD.json".count && name.hasPrefix("study-") && name.hasSuffix(".json")
            && name.dropFirst(6).dropLast(5).allSatisfy(\.isNumber)
    }

    // MARK: v1 → v2 migration

    /// Lenient v1 record — every field optional so one bad field can't sink the array.
    private struct LegacyNote: Decodable {
        var id: UUID?
        var passage: String?
        var title: String?
        var body: String?
        var modifiedAt: Date?
        private enum CodingKeys: String, CodingKey { case id, passage, title, body, modifiedAt }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            id = c.lenient(UUID.self, .id)
            passage = c.lenient(String.self, .passage)
            title = c.lenient(String.self, .title)
            body = c.lenient(String.self, .body)
            modifiedAt = c.lenientDate(.modifiedAt)
        }
    }

    private struct LegacyFile: Decodable {
        var notes: [LegacyNote] = []
        var skipped = 0
        init(from decoder: Decoder) throws {
            var list = try decoder.unkeyedContainer()
            while !list.isAtEnd {
                if let note = try? list.decode(LegacyNote.self) { notes.append(note) }
                else { skipped += 1; _ = try? list.decode(AnyJSON.self) }
            }
        }
    }

    private struct AnyJSON: Decodable { init(from decoder: Decoder) throws {} }

    private func migrateLegacyNotes() {
        guard let raw = try? Data(contentsOf: legacyNotesURL) else {
            isReadOnly = true
            loadReport.outcome = .unreadable
            raise(.error, "Thruline can't read your notes",
                  "notes.json exists but could not be read. Nothing has been changed. Check the file's permissions, then relaunch.")
            return
        }
        // 1. Backup FIRST. No backup → no migration (and nothing is touched).
        guard let backup = writeBackup(raw, base: "notes-v1") else {
            isReadOnly = true
            loadReport.outcome = .unreadable
            raise(.error, "Thruline couldn't back up your notes",
                  "Before upgrading your notes, Thruline makes a safety copy — and that copy couldn't be written. Nothing was changed; your notes are safe in notes.json. Free some disk space or check permissions, then relaunch.")
            return
        }

        // 2. Parse (tolerantly). A damaged tail is salvaged object by object.
        var legacy: [LegacyNote] = []
        var skipped = 0
        var salvaged = false
        let blank = raw.allSatisfy { $0 == 0x20 || $0 == 0x0A || $0 == 0x0D || $0 == 0x09 }
        if !blank {
            if let file = try? JSONDecoder().decode(LegacyFile.self, from: raw) {
                legacy = file.notes; skipped = file.skipped
            } else {
                salvaged = true
                for object in JSONSalvage.completeObjects(inArray: raw) {
                    if let note = try? JSONDecoder().decode(LegacyNote.self, from: object) { legacy.append(note) } else { skipped += 1 }
                }
            }
        }

        // Damaged with nothing recoverable: move aside, run read-only, keep everything.
        if salvaged && legacy.isEmpty {
            let damaged = moveAside(legacyNotesURL, base: "notes.corrupt")
            isReadOnly = true
            loadReport.outcome = .corrupt(damagedFile: damaged)
            raise(.error, "Your notes file could not be read",
                  "notes.json is damaged and no notes could be recovered from it. It was kept as \(damaged?.lastPathComponent ?? "a .corrupt file") (with a copy in Backups) — nothing was deleted. Thruline is read-only this session so it can't overwrite anything.")
            return
        }

        // 3. Convert.
        let fileDate = (try? FileManager.default.attributesOfItem(atPath: legacyNotesURL.path))?[.modificationDate] as? Date
        let fallback = fileDate ?? now
        var envelope = StudyEnvelope()
        for item in legacy {
            let body = item.body ?? "", title = item.title ?? ""
            let bodyEmpty = body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            let cleanTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
            if bodyEmpty && (cleanTitle.isEmpty || cleanTitle == "Observation") {
                loadReport.droppedGhosts.append(LegacyGhost(id: item.id ?? UUID(), passage: item.passage ?? ""))
                Self.log.info("migration: dropped empty ghost note \(item.passage ?? "(no passage)", privacy: .public)")
                continue
            }
            let parsed = item.passage.flatMap { Anchor.parse($0) }
            if parsed == nil, let passage = item.passage { loadReport.unparsedPassages.append(passage) }
            let modified = item.modifiedAt ?? fallback
            envelope.notes.append(Note(id: item.id ?? UUID(), anchors: parsed.map { [$0] } ?? [],
                                       legacyPassage: parsed == nil ? item.passage : nil,
                                       title: title, kind: .free, body: body,
                                       createdAt: modified, modifiedAt: modified))
        }
        data = envelope
        loadReport.skippedElements = skipped

        // 4. Write study.json. notes.json is left exactly as it was.
        loadReport.outcome = salvaged
            ? .salvagedFromV1(recovered: envelope.notes.count, backup: backup)
            : .migratedFromV1(notes: envelope.notes.count, backup: backup)
        if salvaged {
            raise(.warning, "Some notes were recovered from a damaged file",
                  "notes.json was damaged (probably cut off). Thruline recovered \(legacy.count) note(s) and kept a full copy of the original in Backups/\(backup.lastPathComponent).")
        } else if skipped > 0 {
            raise(.warning, "Some notes were unreadable",
                  "\(skipped) entr\(skipped == 1 ? "y" : "ies") in notes.json couldn't be read and were left out. A full copy of the original is in Backups/\(backup.lastPathComponent).")
        }
        if persist() {
            try? Data("migrated \(Self.timestamp(now))\n".utf8).write(to: migrationMarkerURL, options: .atomic)
        }
    }

    // MARK: Persistence

    /// Writes the whole envelope atomically, rotating backups first. Returns success.
    @discardableResult
    private func persist() -> Bool {
        guard !isReadOnly else { return false }
        do {
            let out = try StudyEnvelope.encode(data)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            rotateBackupsIfNeeded()
            try out.write(to: studyURL, options: .atomic)
            hasUnsavedChanges = false
            saveFailureAlerted = false
            return true
        } catch {
            hasUnsavedChanges = true
            Self.log.error("save failed: \(error.localizedDescription, privacy: .public)")
            if !saveFailureAlerted {
                saveFailureAlerted = true
                raise(.error, "Your latest changes couldn't be saved",
                      "Thruline couldn't write study.json (\(error.localizedDescription)). Your work is still on screen and will be retried on the next change. Free some disk space or check folder permissions.")
            }
            return false
        }
    }

    /// Before overwriting a GOOD study.json: refresh `.bak` (first save each launch, then ≤ every
    /// 5 minutes) and keep one dated snapshot per day. A file that doesn't decode is never rotated
    /// over a good backup.
    private func rotateBackupsIfNeeded() {
        let fm = FileManager.default
        guard fm.fileExists(atPath: studyURL.path) else { return }
        let stamp = Self.dayStamp(now)
        let dailyURL = backupsDirectory.appendingPathComponent("study-\(stamp).json")
        let needBak = !fm.fileExists(atPath: backupURL.path) || lastBackupRotation.map { now.timeIntervalSince($0) >= Self.backupRotationInterval } ?? true
        let needDaily = !fm.fileExists(atPath: dailyURL.path)
        guard needBak || needDaily else { return }
        guard let current = try? Data(contentsOf: studyURL),
              (try? StudyEnvelope.decodeTolerant(current, fallbackDate: now)) != nil else { return }
        if needBak, (try? current.write(to: backupURL, options: .atomic)) != nil { lastBackupRotation = now }
        if needDaily {
            try? fm.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            try? current.write(to: dailyURL, options: .atomic)
            pruneDailySnapshots()
        }
    }

    private func pruneDailySnapshots() {
        guard let names = try? FileManager.default.contentsOfDirectory(atPath: backupsDirectory.path) else { return }
        for name in names.filter(Self.isDailySnapshotName).sorted(by: >).dropFirst(Self.keptDailySnapshots) {
            try? FileManager.default.removeItem(at: backupsDirectory.appendingPathComponent(name))
        }
    }

    /// Applies `change` to a copy; commits and saves only if it actually changed something.
    /// Returns false (and does nothing) when read-only.
    @discardableResult
    private func mutate(_ change: (inout StudyEnvelope) -> Void) -> Bool {
        guard !isReadOnly else { return false }
        var copy = data
        change(&copy)
        guard copy != data else { return true }
        data = copy
        persist()
        return true
    }

    // MARK: File helpers

    private static func timestamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyyMMdd-HHmmss"
        return f.string(from: date)
    }

    private static func dayStamp(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = .current
        f.dateFormat = "yyyyMMdd"
        return f.string(from: date)
    }

    private func uniqueURL(in folder: URL, base: String) -> URL {
        var url = folder.appendingPathComponent("\(base)-\(Self.timestamp(now)).json")
        var n = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base)-\(Self.timestamp(now))-\(n).json"); n += 1
        }
        return url
    }

    private func writeBackup(_ raw: Data, base: String) -> URL? {
        do {
            try FileManager.default.createDirectory(at: backupsDirectory, withIntermediateDirectories: true)
            let url = uniqueURL(in: backupsDirectory, base: base)
            try raw.write(to: url, options: .atomic)
            return url
        } catch { return nil }
    }

    /// Copies `raw` into Backups/<base>-<ts>.json.
    private func preserve(_ raw: Data, named base: String) -> URL? { writeBackup(raw, base: base) }

    /// Renames `url` → `<base>-<ts>.json` in the same folder. Returns the new location.
    private func moveAside(_ url: URL, base: String) -> URL? {
        let destination = uniqueURL(in: url.deletingLastPathComponent(), base: base)
        do { try FileManager.default.moveItem(at: url, to: destination); return destination }
        catch { Self.log.error("could not move damaged file aside: \(error.localizedDescription, privacy: .public)"); return nil }
    }

    private func raise(_ severity: StudyStoreAlert.Severity, _ title: String, _ message: String) {
        alert = StudyStoreAlert(severity: severity, title: title, message: message)
    }

    // MARK: Status control

    func dismissAlert() { alert = nil }

    /// After a `.corrupt` / `.unreadable`-empty session the user may choose to carry on with a
    /// fresh library (the damaged file is already safe on disk). Refused for `.newerSchema`.
    @discardableResult
    func resumeEditing() -> Bool {
        if case .newerSchema = loadReport.outcome { return false }
        if case .unreadable = loadReport.outcome, FileManager.default.fileExists(atPath: studyURL.path) { return false }
        isReadOnly = false
        alert = nil
        return true
    }

    // MARK: Notes

    /// Live (not soft-deleted) notes, in storage order (newest created first).
    var allNotes: [Note] { data.notes.filter { !$0.isDeleted } }

    func note(id: UUID) -> Note? { data.notes.first { $0.id == id && !$0.isDeleted } }

    @discardableResult
    func addNote(anchors: [Anchor] = [], title: String = "", kind: NoteKind = .free, body: String = "",
                 sections: [NoteSection] = [], tags: [String] = [], legacyPassage: String? = nil) -> Note? {
        let note = Note(anchors: anchors, legacyPassage: legacyPassage, title: title, kind: kind, sections: sections,
                        body: body, tags: tags, createdAt: now)
        return mutate { $0.notes.insert(note, at: 0) } ? note : nil
    }

    /// Edits a note in place. `modifiedAt` advances ONLY when the edit changed something —
    /// re-saving identical content (e.g. an editor loading a note) is a no-op.
    @discardableResult
    func editNote(_ id: UUID, _ edit: (inout Note) -> Void) -> Bool {
        let stamp = now
        guard let index = data.notes.firstIndex(where: { $0.id == id }) else { return false }
        return mutate { env in
            let before = env.notes[index]
            var after = before
            edit(&after)
            after.id = before.id
            after.tags = StudyTag.normalized(after.tags)
            var comparable = after
            comparable.modifiedAt = before.modifiedAt
            if comparable != before { after.modifiedAt = stamp; env.notes[index] = after }
        }
    }

    func notes(overlapping anchor: Anchor) -> [Note] {
        allNotes.filter { $0.anchors.contains { $0.overlaps(anchor) } }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func notes(exactlyAt anchor: Anchor) -> [Note] {
        allNotes.filter { $0.anchors.contains { $0.sameSpan(as: anchor) } }.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    func notes(taggedWith tag: String) -> [Note] {
        let key = StudyTag.normalize(tag).lowercased()
        return allNotes.filter { $0.tags.contains { $0.lowercased() == key } }
    }

    /// Soft delete — recoverable for 30 days from `recentlyDeleted`.
    @discardableResult func deleteNote(_ id: UUID) -> Bool {
        let stamp = now
        return mutate { env in
            guard let i = env.notes.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else { return }
            env.notes[i].deletedAt = stamp
        }
    }

    @discardableResult func restoreNote(_ id: UUID) -> Bool {
        mutate { env in
            guard let i = env.notes.firstIndex(where: { $0.id == id }) else { return }
            env.notes[i].deletedAt = nil
        }
    }

    /// Permanent removal (also detaches the note from projects' item refs).
    @discardableResult func purgeNote(_ id: UUID) -> Bool {
        mutate { $0.notes.removeAll { $0.id == id } }
    }

    // MARK: Saved passages

    /// Live saved passages in canonical order (book, then position).
    var savedPassages: [SavedPassage] {
        data.saved.filter { !$0.isDeleted }.sorted { ($0.anchor, $0.createdAt) < ($1.anchor, $1.createdAt) }
    }

    func savedPassage(id: UUID) -> SavedPassage? { data.saved.first { $0.id == id && !$0.isDeleted } }
    func savedPassage(matching anchor: Anchor) -> SavedPassage? {
        data.saved.first { !$0.isDeleted && $0.anchor.sameSpan(as: anchor) }
    }
    func isSaved(_ anchor: Anchor) -> Bool { savedPassage(matching: anchor) != nil }

    /// Saves a passage. Idempotent: an already-saved span is returned untouched; a soft-deleted
    /// one is restored. Returns nil only when read-only.
    @discardableResult
    func save(_ anchor: Anchor, highlight: HighlightColor? = nil, isMemory: Bool = false,
              tags: [String] = [], collectionIDs: [UUID] = []) -> SavedPassage? {
        if let existing = savedPassage(matching: anchor) { return existing }
        let fresh = SavedPassage(anchor: anchor, highlight: highlight, isMemory: isMemory, tags: tags,
                                 collectionIDs: collectionIDs, createdAt: now)
        var result: SavedPassage = fresh
        let applied = mutate { env in
            if let i = env.saved.firstIndex(where: { $0.anchor.sameSpan(as: anchor) && $0.deletedAt != nil }) {
                env.saved[i].deletedAt = nil
                if let highlight { env.saved[i].highlight = highlight }
                if isMemory { env.saved[i].isMemory = true }
                result = env.saved[i]
            } else {
                env.saved.append(fresh)
            }
        }
        return applied ? result : nil
    }

    /// ⌘D: saves if unsaved, un-saves (soft delete) if saved. Returns the new saved state.
    @discardableResult
    func toggleSaved(_ anchor: Anchor) -> Bool {
        if let existing = savedPassage(matching: anchor) { unsave(existing.id); return false }
        return save(anchor) != nil
    }

    @discardableResult
    func editSaved(_ id: UUID, _ edit: (inout SavedPassage) -> Void) -> Bool {
        mutate { env in
            guard let i = env.saved.firstIndex(where: { $0.id == id }) else { return }
            var item = env.saved[i]
            edit(&item)
            item.id = env.saved[i].id
            item.tags = StudyTag.normalized(item.tags)
            env.saved[i] = item
        }
    }

    @discardableResult func setHighlight(_ id: UUID, _ color: HighlightColor?) -> Bool { editSaved(id) { $0.highlight = color } }
    @discardableResult func setMemory(_ id: UUID, _ isMemory: Bool) -> Bool { editSaved(id) { $0.isMemory = isMemory } }
    @discardableResult func setTags(savedID: UUID, tags: [String]) -> Bool { editSaved(savedID) { $0.tags = tags } }
    @discardableResult func setTags(noteID: UUID, tags: [String]) -> Bool { editNote(noteID) { $0.tags = tags } }

    @discardableResult func unsave(_ id: UUID) -> Bool {
        let stamp = now
        return mutate { env in
            guard let i = env.saved.firstIndex(where: { $0.id == id && $0.deletedAt == nil }) else { return }
            env.saved[i].deletedAt = stamp
        }
    }

    @discardableResult func restoreSaved(_ id: UUID) -> Bool {
        mutate { env in
            guard let i = env.saved.firstIndex(where: { $0.id == id }) else { return }
            env.saved[i].deletedAt = nil
        }
    }

    @discardableResult func purgeSaved(_ id: UUID) -> Bool {
        mutate { env in
            env.saved.removeAll { $0.id == id }
            for i in env.collections.indices { env.collections[i].order.removeAll { $0 == id } }
        }
    }

    func savedPassages(taggedWith tag: String) -> [SavedPassage] {
        let key = StudyTag.normalize(tag).lowercased()
        return savedPassages.filter { $0.tags.contains { $0.lowercased() == key } }
    }

    // MARK: Collections

    var collections: [StudyCollection] { data.collections.sorted { $0.createdAt < $1.createdAt } }

    /// Creates a collection (trimmed name, case-insensitively unique — an existing one is returned).
    @discardableResult
    func createCollection(name: String) -> StudyCollection? {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return nil }
        if let existing = data.collections.first(where: { $0.name.caseInsensitiveCompare(clean) == .orderedSame }) { return existing }
        let collection = StudyCollection(name: clean, createdAt: now)
        return mutate { $0.collections.append(collection) } ? collection : nil
    }

    @discardableResult
    func renameCollection(_ id: UUID, to name: String) -> Bool {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty else { return false }
        return mutate { env in
            guard let i = env.collections.firstIndex(where: { $0.id == id }) else { return }
            env.collections[i].name = clean
        }
    }

    /// Removes the collection only; its passages stay saved.
    @discardableResult
    func deleteCollection(_ id: UUID) -> Bool {
        mutate { env in
            env.collections.removeAll { $0.id == id }
            for i in env.saved.indices { env.saved[i].collectionIDs.removeAll { $0 == id } }
        }
    }

    @discardableResult
    func addToCollection(savedID: UUID, collectionID: UUID) -> Bool {
        guard data.collections.contains(where: { $0.id == collectionID }) else { return false }
        return editSaved(savedID) { if !$0.collectionIDs.contains(collectionID) { $0.collectionIDs.append(collectionID) } }
    }

    @discardableResult
    func removeFromCollection(savedID: UUID, collectionID: UUID) -> Bool {
        editSaved(savedID) { $0.collectionIDs.removeAll { $0 == collectionID } }
    }

    /// Members in the collection's chosen order, then any unordered members by date.
    func savedPassages(in collectionID: UUID) -> [SavedPassage] {
        let members = savedPassages.filter { $0.collectionIDs.contains(collectionID) }
        let order = data.collections.first { $0.id == collectionID }?.order ?? []
        let position = Dictionary(order.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        return members.sorted {
            switch (position[$0.id], position[$1.id]) {
            case let (a?, b?): return a < b
            case (.some, nil): return true
            case (nil, .some): return false
            default: return $0.createdAt < $1.createdAt
            }
        }
    }

    @discardableResult
    func setOrder(collectionID: UUID, order: [UUID]) -> Bool {
        mutate { env in
            guard let i = env.collections.firstIndex(where: { $0.id == collectionID }) else { return }
            env.collections[i].order = order
        }
    }

    // MARK: Tags

    /// Every tag on live notes and saved passages with its usage count (most used first).
    func tagCounts() -> [(tag: String, count: Int)] {
        var counts: [String: (display: String, n: Int)] = [:]
        for tag in allNotes.flatMap(\.tags) + savedPassages.flatMap(\.tags) {
            let key = tag.lowercased()
            counts[key] = (counts[key]?.display ?? tag, (counts[key]?.n ?? 0) + 1)
        }
        return counts.values.map { (tag: $0.display, count: $0.n) }
            .sorted { $0.count != $1.count ? $0.count > $1.count : $0.tag.localizedCaseInsensitiveCompare($1.tag) == .orderedAscending }
    }

    // MARK: Clips & projects (model + persistence now; UI in a later wave)

    var clips: [Clip] { data.clips }
    var projects: [StudyProject] { data.projects }

    @discardableResult func addClip(_ clip: Clip) -> Bool {
        mutate { if !$0.clips.contains(where: { $0.id == clip.id }) { $0.clips.append(clip) } }
    }

    @discardableResult func removeClip(_ id: UUID) -> Bool {
        mutate { env in
            env.clips.removeAll { $0.id == id }
            for i in env.notes.indices { env.notes[i].clipIDs.removeAll { $0 == id } }
        }
    }

    @discardableResult func upsertProject(_ project: StudyProject) -> Bool {
        let stamp = now
        return mutate { env in
            if let i = env.projects.firstIndex(where: { $0.id == project.id }) {
                var updated = project
                updated.modifiedAt = updated == env.projects[i] ? env.projects[i].modifiedAt : stamp
                env.projects[i] = updated
            } else { env.projects.append(project) }
        }
    }

    @discardableResult func deleteProject(_ id: UUID) -> Bool { mutate { $0.projects.removeAll { $0.id == id } } }

    // MARK: Queries

    /// Everything that touches `anchor` (any overlap): "Rom 8" finds items at Romans 8:28.
    func items(overlapping anchor: Anchor) -> StudyItems {
        StudyItems(
            notes: notes(overlapping: anchor),
            saved: savedPassages.filter { $0.anchor.overlaps(anchor) },
            clips: data.clips.filter { $0.anchor?.overlaps(anchor) ?? false }.sorted { $0.capturedAt > $1.capturedAt },
            projects: data.projects.filter { $0.primaryAnchor?.overlaps(anchor) ?? false })
    }

    private static func fold(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    /// Full-text + reference search. All words must match (AND) across title/body/sections/tags/
    /// collection names/passage text; a `#tag` word matches tags only; a query that reads as a
    /// passage ("Rom 8", "Romans 8:28–39") also matches by anchor overlap. Empty query → everything
    /// in scope. Newest first.
    func search(_ query: String, scope: StudySearchScope = .all) -> [StudySearchHit] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let reference = Anchor.parse(trimmed)
        var textTokens: [String] = [], tagTokens: [String] = []
        for word in trimmed.split(whereSeparator: { $0.isWhitespace }) {
            let w = String(word)
            if w.hasPrefix("#") { let t = StudyTag.normalize(w); if !t.isEmpty { tagTokens.append(Self.fold(t)) } }
            else { textTokens.append(Self.fold(w)) }
        }
        let unfiltered = trimmed.isEmpty
        let collectionNames = Dictionary(data.collections.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })

        func evaluate(anchors: [Anchor], haystack: [String], tags: [String]) -> (matches: Bool, viaAnchor: Bool) {
            if unfiltered { return (true, false) }
            let viaAnchor = reference.map { ref in anchors.contains { $0.overlaps(ref) } } ?? false
            let hay = Self.fold(haystack.joined(separator: "\n"))
            let foldedTags = tags.map(Self.fold)
            let tagsOK = tagTokens.allSatisfy { t in foldedTags.contains { $0.contains(t) } }
            let textOK = textTokens.allSatisfy { hay.contains($0) }
            let textMatch = (!textTokens.isEmpty || !tagTokens.isEmpty) && tagsOK && textOK
            return (viaAnchor || textMatch, viaAnchor && !textMatch)
        }
        func snippet(_ text: String) -> String {
            let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ").trimmingCharacters(in: .whitespaces)
            return flat.count > 160 ? String(flat.prefix(160)) + "…" : flat
        }

        var hits: [StudySearchHit] = []
        if scope == .all || scope == .notes {
            for note in allNotes {
                let label = note.referenceLabel
                let r = evaluate(anchors: note.anchors,
                                 haystack: [note.title, note.plainText, label, note.anchors.map(\.osis).joined(separator: " ")] + note.tags,
                                 tags: note.tags)
                if r.matches {
                    hits.append(StudySearchHit(id: note.id, kind: .note,
                                               title: note.title.isEmpty ? label : note.title,
                                               snippet: snippet(note.plainText.isEmpty ? label : note.plainText),
                                               anchors: note.anchors, date: note.modifiedAt, viaAnchor: r.viaAnchor))
                }
            }
        }
        if scope == .all || scope == .saved {
            for item in savedPassages {
                let names = item.collectionIDs.compactMap { collectionNames[$0] }
                let r = evaluate(anchors: [item.anchor],
                                 haystack: [item.anchor.displayString, item.anchor.osis, item.highlight?.rawValue ?? "",
                                            item.isMemory ? "memory verse" : ""] + item.tags + names,
                                 tags: item.tags)
                if r.matches {
                    hits.append(StudySearchHit(id: item.id, kind: .saved, title: item.anchor.displayString,
                                               snippet: snippet((item.tags.map { "#\($0)" } + names).joined(separator: " ")),
                                               anchors: [item.anchor], date: item.createdAt, viaAnchor: r.viaAnchor))
                }
            }
        }
        if scope == .all || scope == .clips {
            for clip in data.clips {
                let anchors = clip.anchor.map { [$0] } ?? []
                let r = evaluate(anchors: anchors,
                                 haystack: [clip.excerpt, clip.citation.author, clip.citation.work, clip.anchor?.displayString ?? ""],
                                 tags: [])
                if r.matches {
                    hits.append(StudySearchHit(id: clip.id, kind: .clip, title: clip.citation.author.isEmpty ? "Clip" : clip.citation.author,
                                               snippet: snippet(clip.excerpt), anchors: anchors, date: clip.capturedAt, viaAnchor: r.viaAnchor))
                }
            }
        }
        if scope == .all || scope == .projects {
            for project in data.projects {
                func flatten(_ nodes: [OutlineNode]) -> [String] { nodes.flatMap { [$0.title, $0.text] + flatten($0.children) } }
                let anchors = project.primaryAnchor.map { [$0] } ?? []
                let r = evaluate(anchors: anchors, haystack: [project.title, project.kind.rawValue] + flatten(project.outline), tags: [])
                if r.matches {
                    hits.append(StudySearchHit(id: project.id, kind: .project, title: project.title,
                                               snippet: snippet(flatten(project.outline).joined(separator: " ")),
                                               anchors: anchors, date: project.modifiedAt, viaAnchor: r.viaAnchor))
                }
            }
        }
        return hits.sorted { $0.date > $1.date }
    }

    // MARK: Recently deleted (30-day retention)

    var recentlyDeleted: [DeletedItem] {
        let notes = data.notes.compactMap { n -> DeletedItem? in
            guard let d = n.deletedAt else { return nil }
            return DeletedItem(id: n.id, kind: .note, title: n.title.isEmpty ? n.referenceLabel : n.title,
                               deletedAt: d, expiresAt: d.addingTimeInterval(Self.retention))
        }
        let saved = data.saved.compactMap { s -> DeletedItem? in
            guard let d = s.deletedAt else { return nil }
            return DeletedItem(id: s.id, kind: .saved, title: s.anchor.displayString, deletedAt: d, expiresAt: d.addingTimeInterval(Self.retention))
        }
        return (notes + saved).sorted { $0.deletedAt > $1.deletedAt }
    }

    @discardableResult
    func restore(_ item: DeletedItem) -> Bool {
        switch item.kind { case .note: restoreNote(item.id); case .saved: restoreSaved(item.id) }
    }

    /// Permanently removes soft-deleted items older than 30 days. Returns how many were purged.
    @discardableResult
    func purgeExpired() -> Int {
        let cutoff = now.addingTimeInterval(-Self.retention)
        let expiredNotes = data.notes.filter { ($0.deletedAt ?? .distantFuture) < cutoff }.map(\.id)
        let expiredSaved = data.saved.filter { ($0.deletedAt ?? .distantFuture) < cutoff }.map(\.id)
        guard !expiredNotes.isEmpty || !expiredSaved.isEmpty else { return 0 }
        let applied = mutate { env in
            env.notes.removeAll { expiredNotes.contains($0.id) }
            env.saved.removeAll { expiredSaved.contains($0.id) }
            for i in env.collections.indices { env.collections[i].order.removeAll { expiredSaved.contains($0) } }
        }
        return applied ? expiredNotes.count + expiredSaved.count : 0
    }

    private func purgeExpiredOnLaunch() { loadReport.purgedExpired = purgeExpired() }

    /// "Empty Recently Deleted": permanently removes everything soft-deleted now.
    @discardableResult
    func emptyRecentlyDeleted() -> Int {
        let count = data.notes.filter(\.isDeleted).count + data.saved.filter(\.isDeleted).count
        mutate { env in
            env.notes.removeAll(where: \.isDeleted)
            let gone = Set(env.saved.filter(\.isDeleted).map(\.id))
            env.saved.removeAll(where: \.isDeleted)
            for i in env.collections.indices { env.collections[i].order.removeAll { gone.contains($0) } }
        }
        return count
    }

    // MARK: Legacy string lookups (used by NotesStore.swift)

    /// Parsed anchor for a display string, cached (verse rows call this once per verse per render).
    func legacyAnchor(_ passage: String) -> Anchor? {
        if let cached = anchorCache[passage] { return cached }
        let parsed = Anchor.parse(passage)
        if anchorCache.count > 4_000 { anchorCache.removeAll() }
        anchorCache[passage] = .some(parsed)
        return parsed
    }

    /// Storage index of the live free-text note the string-keyed API addresses for `passage`.
    func legacyNoteIndex(for passage: String) -> Int? {
        let parsed = legacyAnchor(passage)
        return data.notes.firstIndex { note in
            guard !note.isDeleted, note.kind == .free else { return false }
            if let parsed { return note.anchors.count == 1 && note.anchors[0] == parsed }
            return note.anchors.isEmpty && note.legacyPassage == passage
        }
    }
}

// MARK: - Truncated-JSON salvage

enum JSONSalvage {
    /// The complete top-level `{…}` objects of a JSON array, in order — including from a file that
    /// was cut off mid-way. String- and escape-aware; stops at the first incomplete object.
    static func completeObjects(inArray data: Data) -> [Data] {
        let bytes = [UInt8](data)
        var i = 0
        while i < bytes.count, [0x20, 0x0A, 0x0D, 0x09].contains(bytes[i]) || (i < 3 && bytes[i] >= 0xEF) { i += 1 }
        guard i < bytes.count, bytes[i] == UInt8(ascii: "[") else { return [] }
        i += 1
        var objects: [Data] = []
        var depth = 0, start = -1
        var inString = false, escaped = false
        while i < bytes.count {
            let b = bytes[i]
            if inString {
                if escaped { escaped = false }
                else if b == UInt8(ascii: "\\") { escaped = true }
                else if b == UInt8(ascii: "\"") { inString = false }
            } else {
                switch b {
                case UInt8(ascii: "\""): inString = true
                case UInt8(ascii: "{"): if depth == 0 { start = i }; depth += 1
                case UInt8(ascii: "["): depth += 1
                case UInt8(ascii: "}"):
                    depth -= 1
                    if depth == 0, start >= 0 { objects.append(Data(bytes[start...i])); start = -1 }
                    if depth < 0 { return objects }
                case UInt8(ascii: "]"):
                    if depth == 0 { return objects }
                    depth -= 1
                default: break
                }
            }
            i += 1
        }
        return objects
    }
}
