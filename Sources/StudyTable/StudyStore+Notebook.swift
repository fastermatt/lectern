import Foundation

// Small store addition for wave B (S2b), kept in its own extension file per WORKPLAN-0.10-B.md
// file-ownership rules rather than touching StudyStore.swift directly.

extension StudyStore {
    /// UI-path API other views can call to attach a clip to a note: registers the clip in the
    /// store (idempotent — `addClip` no-ops if the id already exists) and appends its id to the
    /// note's `clipIDs` (deduped). No clipping UI calls this yet (0.10 wave B ships only the
    /// function); a future "Clip" button on `DeskCard`/`SingleWordCard`/etc. wires into it.
    /// Returns `false` when the note doesn't exist (or is soft-deleted) or the store is read-only.
    @discardableResult
    func appendClip(_ clip: Clip, to noteID: UUID) -> Bool {
        guard note(id: noteID) != nil else { return false }
        addClip(clip)
        return editNote(noteID) { note in
            if !note.clipIDs.contains(clip.id) { note.clipIDs.append(clip.id) }
        }
    }
}
