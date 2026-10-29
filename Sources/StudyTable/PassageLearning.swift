import Foundation

/// Small, explicit editorial dataset. No generated word-order or doctrinal verdicts.
/// BSB anchors are verified against the displayed text before any highlighting occurs.
struct PassageEmphasis: Identifiable, Sendable {
    let book: String
    let chapter: Int
    let verse: Int
    let title: String
    let phrases: [String]
    let explanation: String
    var id: String { "\(book).\(chapter).\(verse)" }
    var source: URL { URL(string: "https://berean.bible/")! }

    static func note(book: String, chapter: Int, verse: Int, translation: String, text: String) -> Self? {
        guard translation == "BSB" else { return nil }
        return examples.first {
            $0.book == book && $0.chapter == chapter && $0.verse == verse
                && $0.phrases.allSatisfy { text.contains($0) }
        }
    }

    static let examples: [Self] = [
        Self(book: "PHP", chapter: 4, verse: 4, title: "Notice the repetition", phrases: ["Rejoice"],
             explanation: "Paul repeats the instruction to rejoice and explicitly says he is saying it again. Read verses 4–7 together before deciding how to apply it."),
        Self(book: "JHN", chapter: 20, verse: 28, title: "Notice the repeated address", phrases: ["My Lord", "my God"],
             explanation: "Thomas's reply places two personal addresses together. Compare the reply with Jesus's words in verse 29 and the purpose statement in verses 30–31."),
        Self(book: "EPH", chapter: 2, verse: 9, title: "Follow the contrast", phrases: ["not by works", "no one can boast"],
             explanation: "The negative phrases connect the source of salvation with the exclusion of boasting. Keep verses 8–10 together, including the reference to good works in verse 10.")
    ]
}

struct RepeatedWord: Identifiable, Equatable {
    let key: String
    let indexes: [Int]
    var id: String { key }
}

enum PassageLearning {
    /// Repetition is an observable source feature, not proof of special emphasis. Exclude
    /// variant rows so alternatives never masquerade as repetitions in one textual edition.
    static func repetitions(in words: [InterlinearWord]) -> [RepeatedWord] {
        var groups: [String: [Int]] = [:]
        for (index, word) in words.enumerated() where word.variant == nil {
            guard let number = word.strongs.first, let base = InterlinearStore.baseStrong(number),
                  word.morphDescription.hasPrefix("Verb") || word.morphDescription.hasPrefix("Noun")
                    || word.morphDescription.hasPrefix("Adjective") else { continue }
            // Preserve STEPBible lexical disambiguation; don't combine homonyms sharing a base.
            let key = "\(word.language.rawValue):\(base):\(number):\(word.lemma)"
            groups[key, default: []].append(index)
        }
        return groups.filter { $0.value.count > 1 }
            .map { RepeatedWord(key: $0.key, indexes: $0.value) }
            .sorted { $0.indexes[0] < $1.indexes[0] }
    }
}

/// Uses the existing atomic/backup-protected notes store, never a second notes file.
@MainActor
enum GuidedReflection {
    static let tag = "lectern-guided-study"

    static func note(in study: StudyStore, at anchor: Anchor) -> Note? {
        study.allNotes.first { $0.tags.contains(tag) && $0.anchors == [anchor] }
    }

    @discardableResult
    static func update(_ body: String, at anchor: Anchor, in study: StudyStore) -> Bool {
        guard !study.isReadOnly else { return false }
        if let note = note(in: study, at: anchor) {
            return study.editNote(note.id) { $0.body = body }
        }
        guard !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return true }
        return study.addNote(anchors: [anchor], title: "Guided study · \(anchor.displayString)",
                             body: body, tags: [tag]) != nil
    }
}
