import Foundation

// Explanatory prose in this file is adapted from unfoldingWord Greek/Hebrew Grammar,
// © unfoldingWord, CC BY-SA 4.0. See Resources/Licenses/grammar-help.txt.
// Matching logic is original Thruline code (MIT). These are general grammatical lessons,
// not verse-specific translations, doctrinal conclusions, or Discovery Bible content.
struct GrammarLesson: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let explanation: String
    let question: String
    let source: URL
}

enum GrammarLessons {
    static func lessons(for word: InterlinearWord) -> [GrammarLesson] {
        switch word.language {
        case .greek: greekLessons(word)
        case .hebrew: hebrewLessons(word)
        case .aramaic: [] // Hebrew explanations must not silently be applied to Aramaic.
        }
    }

    private static func greekLessons(_ word: InterlinearWord) -> [GrammarLesson] {
        guard word.morphCode.hasPrefix("V-") else { return [] }
        let terms = Set(word.morphDescription.lowercased().split { !$0.isLetter }.map(String.init))
        return greek.filter { terms.contains($0.id) }
    }

    private static func hebrewLessons(_ word: InterlinearWord) -> [GrammarLesson] {
        // TEHMC encodes each fused morpheme separately: HR/Vqp3ms, HVqw3ms, etc.
        // Match the verbal conjugation position, never the word "perfect" inside "imperfect".
        let forms = word.morphCode.split(separator: "/").compactMap { segment -> Character? in
            let code = Array(segment.hasPrefix("H") ? segment.dropFirst() : segment[...])
            guard code.count > 2, code[0] == "V" else { return nil }
            return code[2]
        }
        return hebrew.filter { forms.contains($0.0) }.map(\.1)
    }

    private static func lesson(_ id: String, _ title: String, _ text: String, _ question: String,
                               _ page: String, hebrew: Bool = false) -> GrammarLesson {
        GrammarLesson(id: id, title: title, explanation: text, question: question,
            source: URL(string: "https://\(hebrew ? "uhg" : "ugg").readthedocs.io/en/latest/\(page).html")!)
    }

    static let greek: [GrammarLesson] = [
        lesson("aorist", "A whole-event view", "The aorist presents an event as a whole. It does not, by itself, say that the event was instantaneous, happened only once, or can never happen again. Past time is usual in the indicative; other uses depend on context.",
               "What does the surrounding sentence tell you about when and how this happened?", "tense_aorist"),
        lesson("present", "An action in view", "The present form often presents an action in progress or as a general pattern. Context may instead supply a simple statement or a vivid description of a past event. The form alone does not prove uninterrupted action.",
               "Is the author describing an unfolding action, a habit, or a general truth?", "tense_present"),
        lesson("imperfect", "An action in the past", "The imperfect usually portrays a past action from within its unfolding course. Depending on context, it can describe a repeated action, its beginning, or an attempted action.",
               "How does this action set the scene for what comes next?", "tense_imperfect"),
        lesson("perfect", "A resulting state", "The perfect commonly brings a resulting state into view. A past event may account for that state, but the form itself does not promise that the state will last forever.",
               "Which state or result matters at this point in the passage?", "tense_perfect"),
        lesson("imperative", "A direction to someone", "An imperative directs someone to act. It may express a command, an invitation, or a request. Identify who speaks and who is addressed before applying the instruction.",
               "Who is being asked to do what, and why?", "mood_imperative"),
        lesson("participle", "A verbal description", "A participle combines verbal features with features of an adjective. It can describe someone or something, or supply circumstances for another action. Its relationship to the rest of the sentence must be worked out in context.",
               "What person or action does this description connect with?", "mood_participle")
    ]

    static let hebrew: [(Character, GrammarLesson)] = [
        ("p", lesson("hebrew-perfect", "An event seen as complete", "The Hebrew perfect often presents an event as complete. It can refer to past, present, or future situations; the surrounding discourse determines how it should be translated.",
                     "What time and setting does the surrounding passage supply?", "verb_perfect", hebrew: true)),
        ("i", lesson("hebrew-imperfect", "An event still open", "The Hebrew imperfect can describe an incomplete, habitual, present, or future action. It also has other uses, including some instructions. It is not simply an English future tense.",
                     "Does the context describe a pattern, a possibility, or something still to come?", "verb_imperfect", hebrew: true)),
        ("w", lesson("hebrew-sequential-imperfect", "The story moves forward", "The sequential imperfect often links an event to an earlier event in a narrative. It is a distinct conjugation; do not read it as an ordinary imperfect merely because its name contains that word.",
                     "How does this event continue the sequence of the story?", "verb_sequential_imperfect", hebrew: true)),
        ("v", lesson("hebrew-imperative", "A direct instruction", "The Hebrew imperative addresses another person with a positive direction. Its force may be a command, request, invitation, or permission. The speaker and situation help determine which.",
                     "Who gives this direction, to whom, and in what situation?", "verb_imperative", hebrew: true))
    ]
}
