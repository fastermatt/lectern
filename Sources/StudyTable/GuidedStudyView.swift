import SwiftUI

enum GuidedStudyStep: Int, CaseIterable, Identifiable {
    case read, words, grammar, reflect
    var id: Int { rawValue }
    var title: String {
        switch self {
        case .read: "Read"
        case .words: "Words"
        case .grammar: "Grammar"
        case .reflect: "Reflect"
        }
    }
}

/// A passage-linked teaching surface. No network, model, or inferred English alignment.
struct GuidedStudyView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var study: StudyStore
    @State private var step = GuidedStudyStep.read
    @State private var wordIndex: Int?
    @AppStorage("learning.showEmphasis") private var showEmphasis = false
    var interlinear: InterlinearStore = .shared
    var lexicon: LexiconStore = .shared

    init(study: StudyStore, initialStep: GuidedStudyStep = .read, initialWordIndex: Int? = nil) {
        self.study = study
        _step = State(initialValue: initialStep)
        _wordIndex = State(initialValue: initialWordIndex)
    }

    private var verse: Int? { state.selectedVerse.flatMap { $0 > 0 ? $0 : nil } }
    private var words: [InterlinearWord] {
        guard let verse else { return [] }
        return interlinear.words(bookCode: state.selectedBookCode, chapter: state.selectedChapter, verse: verse)
    }
    private var selectedWord: InterlinearWord? {
        guard let wordIndex, words.indices.contains(wordIndex) else { return nil }
        return words[wordIndex]
    }
    private var anchor: Anchor? {
        verse.map { Anchor(book: state.selectedBookCode, chapter: state.selectedChapter, verse: $0) }
    }
    private var identity: String { "\(state.selectedBookCode).\(state.selectedChapter).\(verse ?? 0)" }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("Study this passage").font(.title3.weight(.semibold))
            if let anchor {
                Text("\(anchor.displayString) · \(state.translationID)").foregroundStyle(STColor.secondary)
                steps
                stepContent(anchor)
                navigation
            } else {
                Text("Select a verse in the Bible to begin. This guide follows one verse at a time; read its surrounding paragraph for context.")
            }
        }
        .font(.system(size: 13)).foregroundStyle(STColor.ink)
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .onChange(of: identity) { _, _ in step = .read; wordIndex = nil }
        .onChange(of: state.translationID) { _, _ in step = .read }
    }

    private var steps: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading, spacing: 6) {
            ForEach(GuidedStudyStep.allCases) { choice in
                Button { step = choice } label: {
                    HStack(spacing: 4) {
                        if step == choice { Image(systemName: "arrow.right").accessibilityHidden(true) }
                        Text("\(choice.rawValue + 1). \(choice.title)")
                    }
                    .font(.system(size: 12, weight: step == choice ? .semibold : .regular))
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityAddTraits(step == choice ? .isSelected : [])
            }
        }
    }

    @ViewBuilder private func stepContent(_ anchor: Anchor) -> some View {
        switch step {
        case .read: reading
        case .words: wordStudy
        case .grammar: grammarStudy
        case .reflect: GuidedReflectionView(study: study, anchor: anchor).id(anchor)
        }
    }

    @ViewBuilder private var reading: some View {
        Text("Read the surrounding paragraph. Who is speaking, to whom, and about what?")
        switch state.chapterLoad {
        case .loading: ProgressView("Loading the passage…")
        case .unavailable(let reason): Text(reason).foregroundStyle(STColor.secondary)
        case .loaded(let content):
            if let current = content.verses.first(where: { $0.number == verse }) {
                GuidedPassageText(text: current.text,
                    emphasis: PassageEmphasis.note(book: state.selectedBookCode, chapter: state.selectedChapter,
                        verse: current.number, translation: state.translationID, text: current.text),
                    showEmphasis: $showEmphasis)
                Text(content.attribution).font(.caption).foregroundStyle(STColor.secondary)
            } else {
                Text("This verse is not present in the selected edition.").foregroundStyle(STColor.secondary)
            }
        }
        Button("Open linked sources") { state.deskMode = .sources }
        Text("Continue with Words to explore the original text. The guide does not replace reading the whole paragraph.")
            .font(.caption).foregroundStyle(STColor.secondary)
    }

    @ViewBuilder private var wordStudy: some View {
        Text("Choose an original word. Its gloss is a starting point, not every possible meaning in every passage.")
        wordPicker
        if let word = selectedWord {
            LearningWordHeading(word: word)
            ForEach(word.strongs, id: \.self) { number in
                if let entry = lexicon.entry(for: InterlinearStore.baseStrong(number) ?? number) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("\(number) · Strong’s dictionary").fontWeight(.semibold)
                        Text(entry.definition).textSelection(.enabled)
                    }
                }
            }
            OriginalConcordanceDisclosure(strong: word.strongs.first ?? "", lemma: word.lemma, store: interlinear) { hit in
                state.navigate(bookCode: hit.bookCode, chapter: hit.chapter, verse: hit.verse)
            }
            if word.variant != nil { VariantDisclosure(word: word, store: interlinear) }
            Text("Dictionary: public-domain Strong’s. Word parsing and gloss: STEPBible · CC BY 4.0. English and original-language word order differ; no English-word match is assumed here.")
                .font(.caption).foregroundStyle(STColor.secondary)
        }
    }

    @ViewBuilder private var grammarStudy: some View {
        Text("See what the word’s grammatical form can tell you, then test that observation against the sentence.")
        wordPicker
        if let word = selectedWord {
            LearningWordHeading(word: word)
            Text(word.morphDescription).fontWeight(.medium).textSelection(.enabled)
            if GrammarLessons.lessons(for: word).isEmpty {
                Text("There is no teaching note for this form yet. The source parsing is shown above; avoid drawing a conclusion from its label alone.")
                    .foregroundStyle(STColor.secondary)
            } else {
                GrammarHelpView(word: word, expanded: true)
            }
            Text("Try a tagged verb for lessons about an action’s viewpoint or a direction to someone.")
                .font(.caption).foregroundStyle(STColor.secondary)
        }
        repetitionStudy
    }

    @ViewBuilder private var wordPicker: some View {
        if words.isEmpty {
            Text("No original-language data is available at this reference. Tagged-source versification can differ from your translation.")
                .foregroundStyle(STColor.secondary)
        } else {
            Picker("Original word", selection: Binding(get: { wordIndex ?? -1 }, set: { wordIndex = $0 < 0 ? nil : $0 })) {
                Text("Choose a word…").tag(-1)
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    Text("\(index + 1). \(word.surface) — \(word.gloss)\(word.variant == nil ? "" : " [variant]")").tag(index)
                }
            }
            .pickerStyle(.menu)
        }
    }

    @ViewBuilder private var repetitionStudy: some View {
        let repetitions = PassageLearning.repetitions(in: words)
        if !repetitions.isEmpty {
            Divider()
            Text("Repeated vocabulary").fontWeight(.semibold)
            ForEach(repetitions) { group in
                let word = words[group.indexes[0]]
                Button("\(word.lemma) · \(group.indexes.count) occurrences") { wordIndex = group.indexes[0] }
            }
            Text("Counted from STEPBible’s non-variant rows in this verse. Repetition is worth exploring; it does not automatically establish emphasis or authorial intent.")
                .font(.caption).foregroundStyle(STColor.secondary)
        }
    }

    private var navigation: some View {
        HStack {
            Button("Back") { step = GuidedStudyStep(rawValue: step.rawValue - 1) ?? .read }.disabled(step == .read)
            Spacer()
            Button(step == .reflect ? "Read again" : "Next: \(GuidedStudyStep(rawValue: step.rawValue + 1)?.title ?? "Read")") {
                step = GuidedStudyStep(rawValue: step.rawValue + 1) ?? .read
            }
        }.padding(.top, 6)
    }
}

private struct LearningWordHeading: View {
    let word: InterlinearWord
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(word.surface).font(STFont.original(28)).textSelection(.enabled)
                .environment(\.layoutDirection, word.language == .greek ? .leftToRight : .rightToLeft)
            Text("\(word.transliteration) · \(word.gloss)")
        }
    }
}

struct GuidedPassageText: View {
    let text: String
    let emphasis: PassageEmphasis?
    @Binding var showEmphasis: Bool
    private var annotated: AttributedString {
        var value = AttributedString(text)
        guard showEmphasis, let emphasis else { return value }
        for phrase in emphasis.phrases {
            var start = value.startIndex
            while let range = value[start...].range(of: phrase) {
                value[range].font = .system(size: 18, weight: .bold, design: .serif)
                value[range].underlineStyle = .single
                start = range.upperBound
            }
        }
        return value
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(annotated).font(.system(size: 18, design: .serif)).textSelection(.enabled)
            Toggle("Show emphasis notes", isOn: $showEmphasis)
            if showEmphasis {
                if let emphasis {
                    Text(emphasis.title).fontWeight(.semibold)
                    Text(emphasis.explanation)
                    Link("Text evidence: BSB · \(emphasis.book) \(emphasis.chapter):\(emphasis.verse)", destination: emphasis.source)
                    Text("Throughline editorial observation of this English text. Bold underlining marks the phrases discussed; it is not an original-language emphasis verdict.")
                        .font(.caption).foregroundStyle(STColor.secondary)
                } else {
                    Text("No editorial emphasis note for this verse and translation. Nothing is highlighted. Try BSB Philippians 4:4, John 20:28, or Ephesians 2:9.")
                        .font(.caption).foregroundStyle(STColor.secondary)
                }
            }
        }
    }
}

struct GuidedReflectionView: View {
    @ObservedObject var study: StudyStore
    let anchor: Anchor
    private var reflection: Binding<String> {
        Binding(get: { GuidedReflection.note(in: study, at: anchor)?.body ?? "" },
                set: { GuidedReflection.update($0, at: anchor, in: study) })
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Write your reflection").fontWeight(.semibold)
            Text("What did you observe? What does the context support? What question remains, and how might you respond?")
            TextEditor(text: reflection).font(.body).frame(minHeight: 180)
                .accessibilityLabel("Reflection for \(anchor.displayString)")
                .disabled(study.isReadOnly)
                .overlay(Rectangle().stroke(STColor.hairline, lineWidth: 1))
            Text(study.isReadOnly ? "Notes are read-only. Check the notes warning before editing."
                 : study.hasUnsavedChanges ? "Changes are still in memory. Throughline could not save them; check the notes warning."
                 : "Your reflection saves automatically as a passage-linked note. Find it in Notes or Library & notes search.")
                .font(.caption).foregroundStyle(STColor.secondary)
        }
    }
}
