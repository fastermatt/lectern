import Foundation

/// Right-clicking does not necessarily select the row first. Cite the copied row, not the
/// currently selected verse, and retain the translation abbreviation for notes/research.
///
/// Respects `TranslationExportPolicy` (PASTOR-QA-0.10 defect 5 — the pre-0.10 version copied ESV
/// and NKJV text with no copyright notice or verse-limit awareness): a free translation copies
/// the verse text verbatim, unchanged from before; ESV appends Crossway's required notice (a
/// single verse is far under the publisher's export cap, so the text itself is always included);
/// a references-only translation (NKJV, or any other licensed/installed pack whose policy is
/// references-only) never copies the copyrighted text — only the reference, with a one-line
/// reason a user can read without leaving the app.
func verseClipboardText(bookName: String, chapter: Int, verse: BibleVerse, translation: String) -> String {
    let reference = "\(bookName) \(chapter):\(verse.number)"
    switch TranslationExportPolicy.policy(forTranslationID: translation) {
    case .fullText:
        return "\(reference) (\(translation)) — \(verse.text)"
    case .cappedText(_, _, let notice, _, _):
        return "\(reference) (\(translation)) — \(verse.text)\n\(notice)"
    case .referencesOnly(let reason):
        return "\(reference) (\(translation)) — [Verse text not copied: \(reason)]"
    }
}
