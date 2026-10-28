import SwiftUI

/// The Study Desk's focused view of one word: what double-clicking a word in Scripture (or a word
/// on the LCD) opens. The full word-by-word list stays one click away ("Show all N words").
///
/// It is honest about how the word was found. A studied English word carries a
/// `WordAlignmentResult`; the chip under the original word says whether that came through the KJV's
/// Strong's tagging, a best guess from the gloss, or nothing at all — and with no match it lists
/// candidates instead of pretending.
struct SingleWordCard: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var selection = InterlinearSelection.shared
    let words: [InterlinearWord]
    let passage: String
    let store: InterlinearStore
    let lexicon: LexiconStore
    var onNavigate: (InterlinearOccurrence) -> Void = { _ in }

    private var studied: InterlinearSelection.StudiedWord? { selection.studied(for: passage) }
    private var word: InterlinearWord? {
        guard let index = selection.focusedIndex(for: passage), words.indices.contains(index) else { return nil }
        return words[index]
    }
    private var result: WordAlignmentResult? { studied?.result }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            toolbar
            if let studied { studiedLine(studied) }
            if let word {
                wordBlock(word)
                if word.variant != nil { VariantDisclosure(word: word, store: store) }
                if let result, result.match != nil { provenance(result) }
                alternatives
                parsing(word)
                strongs(word)
                entries(word)
                OriginalConcordanceDisclosure(strong: word.strongs.first ?? "", lemma: word.lemma, store: store,
                                              showsCountUpfront: true, onNavigate: onNavigate)
            } else if let result {
                noMatchBlock(result)
            }
            showAllButton
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(STColor.tileWell)
        .overlay(alignment: .leading) { Rectangle().fill(STColor.orange).frame(width: 2) }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Word study")
    }

    // MARK: Pieces

    private var toolbar: some View {
        HStack(spacing: 6) {
            Image(systemName: "scope").font(.system(size: 10, weight: .semibold)).accessibilityHidden(true)
            Text("ONE WORD").font(STFont.legend(9)).tracking(0.9)
            Spacer(minLength: 4)
            Button { selection.clear() } label: {
                HStack(spacing: 3) {
                    Image(systemName: "xmark").font(.system(size: 8, weight: .bold))
                    Text("CLEAR WORD").font(STFont.legend(9)).tracking(0.6)
                }
                .padding(.horizontal, 6).padding(.vertical, 3)
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(STColor.keyRim, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Leave the single-word view")
            .accessibilityLabel("Clear word")
        }
        .foregroundStyle(STColor.ink)
    }

    private func studiedLine(_ studied: InterlinearSelection.StudiedWord) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Text("\u{201C}\(studied.word)\u{201D}").font(STFont.reading(17, weight: .semibold)).foregroundStyle(STColor.ink)
            Text("in \(studied.translationID)").font(.system(size: 11, design: .rounded)).foregroundStyle(STColor.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Word chosen: \(studied.word) in \(studied.translationID)")
    }

    private func wordBlock(_ word: InterlinearWord) -> some View {
        let rtl = word.language != .greek
        let script = word.surface.trimmingCharacters(in: CharacterSet(charactersIn: ",.;:\u{00B7}\u{05C3}\u{2014} "))
        return VStack(alignment: rtl ? .trailing : .leading, spacing: 3) {
            Text(script)
                .font(STFont.original(34, weight: .medium))
                .foregroundStyle(STColor.ink)
                .environment(\.layoutDirection, rtl ? .rightToLeft : .leftToRight)
                .textSelection(.enabled)
            Text(word.transliteration)
                .font(.system(size: 13, design: .rounded)).foregroundStyle(STColor.secondary)
            Text(word.gloss)
                .font(.system(size: 13.5, weight: .semibold, design: .rounded)).foregroundStyle(STColor.ink)
        }
        .frame(maxWidth: .infinity, alignment: rtl ? .trailing : .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(word.surface), \(word.transliteration), \(word.gloss)")
    }

    private func provenance(_ result: WordAlignmentResult) -> some View {
        let firm = !result.isHeuristic
        return HStack(alignment: .top, spacing: 6) {
            Image(systemName: firm ? "checkmark.seal" : "questionmark.circle")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(STColor.ink).accessibilityHidden(true)
            Text(result.provenanceLine)
                .font(.system(size: 11, design: .rounded)).foregroundStyle(STColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(7)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(STColor.tileTop.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(STColor.hairline, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("How this word was matched. \(result.provenanceLine)")
    }

    /// Other original words that fit as well (only worth showing when the match is not firm).
    @ViewBuilder private var alternatives: some View {
        if let result, let match = result.match, match.confidence < .high, !match.candidates.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("ALSO POSSIBLE").font(STFont.legend(9)).tracking(0.6).foregroundStyle(STColor.secondary)
                candidateRows(match.candidates)
            }
        }
    }

    private func parsing(_ word: InterlinearWord) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("PARSING").font(STFont.legend(9)).tracking(0.6).foregroundStyle(STColor.secondary)
            Text(word.morphDescription).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(STColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func strongs(_ word: InterlinearWord) -> some View {
        HStack(spacing: 4) {
            Text("STRONG\u{2019}S").font(STFont.legend(9)).tracking(0.6).foregroundStyle(STColor.secondary)
            ForEach(word.strongs, id: \.self) { OriginalStrongChip(number: $0) }
        }
    }

    @ViewBuilder private func entries(_ word: InterlinearWord) -> some View {
        let classical = word.strongs.filter { lexicon.entry(for: InterlinearStore.baseStrong($0) ?? $0) != nil }
        let formatives = word.strongs.filter { !classical.contains($0) }
        ForEach(classical, id: \.self) { number in
            SingleWordEntry(number: number, entry: lexicon.entry(for: InterlinearStore.baseStrong(number) ?? number))
        }
        if classical.isEmpty {
            Text("This word has no classical Strong\u{2019}s dictionary entry (a grammatical formative such as an article, preposition or conjunction).")
                .font(.system(size: 10.5, design: .rounded)).foregroundStyle(STColor.secondary)
        } else if !formatives.isEmpty {
            Text("Also carries \(formatives.joined(separator: ", ")) \u{2014} a prefixed article, preposition or conjunction with no dictionary entry of its own.")
                .font(.system(size: 10.5, design: .rounded)).foregroundStyle(STColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func noMatchBlock(_ result: WordAlignmentResult) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "minus.circle").font(.system(size: 12, weight: .semibold)).accessibilityHidden(true)
                Text(result.gap == .noOriginalData ? "No original-language data" : "No single original word")
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(STColor.ink)
            Text(result.provenanceLine)
                .font(.system(size: 11.5, design: .rounded)).foregroundStyle(STColor.ink)
                .fixedSize(horizontal: false, vertical: true)
            if let why = result.gapExplanation {
                Text(why)
                    .font(.system(size: 10.5, design: .rounded)).foregroundStyle(STColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !result.candidates.isEmpty {
                Text("NEAREST WORDS IN THE ORIGINAL").font(STFont.legend(9)).tracking(0.6).foregroundStyle(STColor.secondary)
                candidateRows(result.candidates)
            }
        }
        .accessibilityElement(children: .contain)
    }

    private func candidateRows(_ indices: [Int]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(indices.filter { words.indices.contains($0) }, id: \.self) { index in
                let candidate = words[index]
                Button { selection.focus(wordIndex: index, passage: passage) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(candidate.surface.trimmingCharacters(in: CharacterSet(charactersIn: ",.;:\u{00B7}\u{05C3} ")))
                            .font(STFont.original(15, weight: .medium))
                            .environment(\.layoutDirection, candidate.language == .greek ? .leftToRight : .rightToLeft)
                        Text(candidate.transliteration).font(.system(size: 11, design: .rounded)).foregroundStyle(STColor.secondary)
                        Text(candidate.gloss).font(.system(size: 11.5, weight: .medium, design: .rounded))
                        Spacer(minLength: 0)
                        if let variant = candidate.variant { VariantChip(variant: variant) }
                    }
                    .foregroundStyle(STColor.ink)
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .background(STColor.tileTop.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(STColor.keyRim, lineWidth: 1))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Study \(candidate.surface), \(candidate.transliteration), \(candidate.gloss)"
                                    + (candidate.variant.map { $0.isSignificant ? ", textual variant" : ", minor textual variant" } ?? ""))
            }
        }
    }

    private var showAllButton: some View {
        Button { selection.showAll() } label: {
            HStack(spacing: 5) {
                Image(systemName: "list.bullet")
                Text(words.isEmpty ? "SHOW THE VERSE'S WORD LIST" : "SHOW ALL \(words.count) WORDS")
            }
            .font(STFont.legend(9)).tracking(0.6).foregroundStyle(STColor.ink)
            .padding(.horizontal, 8).padding(.vertical, 5)
            .background(STColor.keyTop, in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(STColor.keyRim, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .disabled(words.isEmpty)
        .accessibilityLabel(words.isEmpty ? "No word list for this verse" : "Show all \(words.count) original-language words")
    }
}

/// The single-word card's variant block: the compact marker as a disclosure header, open by default
/// (a reader who chose this word wants to know the source flags it) and collapsible.
struct VariantDisclosure: View {
    let word: InterlinearWord
    let store: InterlinearStore
    @State private var expanded = true

    var body: some View {
        if let variant = word.variant, let explanation = store.explanation(for: word) {
            VStack(alignment: .leading, spacing: 6) {
                Button { expanded.toggle() } label: {
                    HStack(spacing: 6) {
                        VariantChip(variant: variant)
                        Text(expanded ? "HIDE WHAT THIS MEANS" : "WHAT THIS MEANS")
                            .font(STFont.legend(9)).tracking(0.6).foregroundStyle(STColor.secondary)
                        Image(systemName: expanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 9, weight: .semibold)).foregroundStyle(STColor.secondary)
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(expanded ? "Hide textual variant explanation" : "Show textual variant explanation")
                if expanded { VariantDetail(explanation: explanation) }
            }
        }
    }
}

/// Dictionary entry for one Strong's number inside the single-word card: lemma, transliteration,
/// definition, and the KJV's usage line (the words the KJV renders this number with).
private struct SingleWordEntry: View {
    let number: String
    let entry: LexiconEntry?

    var body: some View {
        if let entry {
            VStack(alignment: .leading, spacing: 5) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.lemma).font(STFont.original(16, weight: .semibold))
                    Text(entry.translit).font(.system(size: 12, design: .rounded)).foregroundStyle(STColor.secondary)
                    if !entry.pronunciation.isEmpty {
                        Text("[\(entry.pronunciation)]").font(.system(size: 11, design: .rounded)).foregroundStyle(STColor.secondary)
                    }
                    Spacer(minLength: 0)
                    Text(number).font(STFont.lcd(9)).foregroundStyle(STColor.secondary)
                }
                Text(entry.definition)
                    .font(STFont.reading(12.5)).lineSpacing(2).textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                if let usage = entry.kjvUsage, !usage.isEmpty {
                    Text("KJV USAGE").font(STFont.legend(9)).tracking(0.6).foregroundStyle(STColor.secondary).padding(.top, 2)
                    Text(usage).font(STFont.reading(12)).foregroundStyle(STColor.ink).textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(STColor.tileTop.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
        }
    }
}

/// Shown above the full list while a word is still focused there: which word, and the two ways out.
struct WordFocusBar: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var selection = InterlinearSelection.shared
    let passage: String

    private var summary: String {
        if let studied = selection.studied(for: passage) {
            return "\u{201C}\(studied.word)\u{201D} \u{00B7} \(studied.result.match == nil ? "no single original word" : "highlighted below")"
        }
        return "Word highlighted below"
    }

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "scope").font(.system(size: 10, weight: .semibold)).accessibilityHidden(true)
            Text(summary).font(.system(size: 11.5, weight: .medium, design: .rounded)).lineLimit(1)
            Spacer(minLength: 4)
            Button { selection.showSingle() } label: {
                Text("SHOW ONLY THIS WORD").font(STFont.legend(9)).tracking(0.6)
            }
            .buttonStyle(.plain)
            .accessibilityHint("Returns to the single-word study")
            Button { selection.clear() } label: { Image(systemName: "xmark").font(.system(size: 9, weight: .bold)) }
                .buttonStyle(.plain)
                .help("Clear the chosen word")
                .accessibilityLabel("Clear word")
        }
        .foregroundStyle(STColor.ink)
        .padding(.horizontal, 12).padding(.vertical, 7)
        .background(STColor.tileWell)
        .overlay(alignment: .bottom) { Rectangle().fill(STColor.hairline).frame(height: 1) }
    }
}
