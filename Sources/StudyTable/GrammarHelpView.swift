import SwiftUI

struct GrammarHelpView: View {
    let word: InterlinearWord
    var expanded = false

    var body: some View {
        let lessons = GrammarLessons.lessons(for: word)
        if !lessons.isEmpty {
            GrammarLessonDisclosure(lessons: lessons, expanded: expanded)
                .id(word.surface + word.morphCode) // Reset when the focused form changes.
        }
    }
}

private struct GrammarLessonDisclosure: View {
    let lessons: [GrammarLesson]
    @State private var expanded: Bool

    init(lessons: [GrammarLesson], expanded: Bool) {
        self.lessons = lessons
        _expanded = State(initialValue: expanded)
    }

    var body: some View {
        DisclosureGroup("Grammar in plain English", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 14) {
                ForEach(lessons) { lesson in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(lesson.title).fontWeight(.semibold)
                        Text(lesson.explanation)
                        Text(lesson.question).italic()
                        Link("Reference: unfoldingWord grammar", destination: lesson.source)
                    }
                }
                Text("General grammar help, not a new translation. Explanations adapted from unfoldingWord · CC BY-SA 4.0. Word parsing: STEPBible · CC BY 4.0.")
                    .font(.caption).foregroundStyle(STColor.secondary)
            }
            .padding(.top, 8).textSelection(.enabled)
        }
        .font(.system(size: 12)).foregroundStyle(STColor.ink)
        .fixedSize(horizontal: false, vertical: true)
    }
}
