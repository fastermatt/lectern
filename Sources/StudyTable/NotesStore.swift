import Foundation

/// `NotesStore` is now `StudyStore` (see StudyStore.swift). Every pre-0.10 call site keeps
/// compiling through this alias plus the string-keyed adapter below.
typealias NotesStore = StudyStore

// MARK: - Legacy string-keyed API (single note per display string, as the 0.9 UI uses it)
//
// Wave B replaces these call sites with anchor-based APIs; until then the adapter makes the old
// UI behave correctly:
//  • `update` never bumps `modifiedAt` (or creates a note) when nothing changed, and an empty
//    body never creates a note — so merely visiting a verse no longer reorders "recent first".
//  • `notes` hides notes with no text (ghosts), so a cleared note no longer lingers in the list.
//  • `delete(passage:)` exists (soft delete, recoverable for 30 days).
//  • Range strings ("Romans 8:28–39") resolve through `Anchor`, not by exact string equality.

extension StudyStore {
    /// Live, non-empty notes as the legacy list model. `passage` is the note's display reference
    /// (an en-dash range for range notes; the verbatim v1 string if it never parsed).
    var notes: [StudyNote] {
        allNotes.compactMap { note in
            guard note.hasContent else { return nil }
            let text = note.body.isEmpty ? note.plainText : note.body
            return StudyNote(id: note.id, passage: note.referenceLabel, title: note.title, body: text, modifiedAt: note.modifiedAt)
        }
    }

    /// The free-text note stored for exactly this passage string, if any.
    func note(for passage: String) -> StudyNote? {
        guard let index = legacyNoteIndex(for: passage) else { return nil }
        let note = data.notes[index]
        return StudyNote(id: note.id, passage: passage, title: note.title, body: note.body, modifiedAt: note.modifiedAt)
    }

    /// Creates or edits the free-text note for `passage`.
    /// - Unchanged title/body → no write, `modifiedAt` untouched.
    /// - No existing note and a blank body → nothing is created.
    func update(passage: String, title: String, body: String) {
        if let index = legacyNoteIndex(for: passage) {
            let id = data.notes[index].id
            editNote(id) { $0.title = title; $0.body = body }
        } else if !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let parsed = legacyAnchor(passage)
            addNote(anchors: parsed.map { [$0] } ?? [], title: title, kind: .free, body: body,
                    legacyPassage: parsed == nil ? passage : nil)
        }
    }

    /// Soft-deletes the free-text note for `passage` (recoverable from Recently Deleted).
    @discardableResult
    func delete(passage: String) -> Bool {
        guard let index = legacyNoteIndex(for: passage) else { return false }
        return deleteNote(data.notes[index].id)
    }
}
