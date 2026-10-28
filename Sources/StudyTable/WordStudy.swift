import SwiftUI

/// Common English function words (articles, pronouns, prepositions, conjunctions, auxiliary
/// verbs, KJV-specific second-person forms) that `WordStudySection`'s collapsed summary skips so
/// it leads with a word actually worth scanning ("mercy G1656 · endureth G1961" rather than "For
/// G1063 · are G1526 · that G3754" -- the function words that happen to open a lot of clauses).
/// Matched against the tagged surface form (already punctuation-free, see `kjv-tags/*.json`),
/// lowercased for a case-insensitive match since the KJV capitalizes sentence-initial words. Purely
/// a display-ordering choice for the collapsed preview -- the expanded word list is unaffected and
/// stays complete, in verse order.
let wordStudyFunctionWords: Set<String> = [
    "a", "an", "the",
    "and", "or", "but", "nor", "for", "so", "yet", "if", "then", "than", "because", "lest",
    "that", "this", "these", "those", "which", "who", "whom", "whose", "what",
    "he", "him", "his", "himself", "she", "her", "hers", "herself", "it", "its", "itself",
    "they", "them", "their", "theirs", "themselves", "we", "us", "our", "ours", "ourselves",
    "i", "me", "my", "mine", "myself", "you", "your", "yours", "yourself", "yourselves",
    "thou", "thee", "thy", "thine", "thyself", "ye",
    "is", "am", "are", "art", "was", "wast", "were", "be", "been", "being",
    "have", "hast", "has", "had", "hadst", "having", "do", "doth", "does", "did", "didst", "done", "doing",
    "will", "wilt", "would", "shall", "shalt", "should", "may", "mayest", "might", "must", "can", "canst", "could",
    "of", "in", "on", "at", "by", "to", "from", "with", "without", "unto", "into", "upon",
    "over", "under", "through", "between", "among", "about", "against", "before", "after",
    "not", "no", "as", "also", "there", "here", "where", "when", "how", "why",
    "all", "any", "each", "every", "some", "such", "own", "other", "same",
]

/// Reorders `words` (a verse's tagged words, in verse order) for the collapsed-summary preview:
/// content words first, in their original relative order, skipping `wordStudyFunctionWords`;
/// falls back to the full, unfiltered list only when a verse happens to tag no content word at
/// all (rare, but possible for a short clause like a bare "Amen."). Free function (not a computed
/// property on the view) so it's directly testable without rendering -- see
/// `LexiconTests.testWordStudyCollapsedSummary*`.
func wordStudyCollapsedOrder(_ words: [WordTag]) -> [WordTag] {
    let contentWords = words.filter { !wordStudyFunctionWords.contains($0.word.lowercased()) }
    return contentWords.isEmpty ? words : contentWords
}

/// Original-language word study for the selected verse: every Strong's-tagged word the
/// bundled KJV carries in its own USFM source, each resolving to a Hebrew/Greek dictionary
/// entry and (on request) a concordance of every other verse using that number.
///
/// // DESK SLOT: word study — Workstream A's desk-section architecture (wave 2) restyles
/// this onto `DeskSectionHeader`/`DeskCard` from `DeskComponents.swift`; until that lands,
/// this view is self-contained and usable standalone (see `LexiconTests.swift` for an
/// offscreen render). Reads `AppState` directly (selected passage, navigation) the same way
/// `SourcesPane` does; owns its own `LexiconStore` via the `.shared` default so it works
/// without an `AppState` change — wave 2 may prefer to hang the store off `AppState` instead.
struct WordStudySection: View {
    @EnvironmentObject private var state: AppState
    var store: LexiconStore = .shared
    /// Collapsed by default: a verse can carry 20+ tagged words, which would push the
    /// commentary banks below the fold (seen at Matthew 26:26). Remembered once opened.
    @AppStorage("desk.wordStudyExpanded") private var sectionExpanded = false

    private var words: [WordTag] {
        guard let verse = state.selectedVerse, verse > 0 else { return [] }
        return store.tags(bookCode: state.selectedBookCode, chapter: state.selectedChapter, verse: verse)
    }

    /// The collapsed summary's own word order -- content words first ("mercy G1656", not "For
    /// G1063"). Purely a *display* choice: never touches `words` itself -- the expanded list
    /// (below) stays complete and in verse order regardless of what the collapsed summary leads
    /// with.
    private var collapsedSummaryWords: [WordTag] { wordStudyCollapsedOrder(words) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            WordStudyHeader(count: words.count, expanded: $sectionExpanded)
            if !sectionExpanded {
                if !words.isEmpty {
                    DeskCollapsedSummary(section: "Word Study", text: collapsedSummaryWords.map { "\($0.word) \($0.strongs.joined(separator: "/"))" }
                        .joined(separator: "  \u{00B7}  ")) { sectionExpanded = true }
                }
            } else if words.isEmpty {
                emptyState
            } else {
                ForEach(Array(words.enumerated()), id: \.offset) { index, tag in
                    WordTagRow(tag: tag, store: store) { hit in
                        state.navigate(bookCode: hit.bookCode, chapter: hit.chapter, verse: hit.verse)
                    }
                    if index < words.count - 1 {
                        Rectangle().fill(STColor.hairline).frame(height: 1)
                    }
                }
            }
        }
    }

    private var emptyState: some View {
        let reason = state.selectedVerse == nil || state.selectedVerse == 0
            ? "Select a verse to see its tagged words."
            : store.hasTags(bookCode: state.selectedBookCode)
                ? "No Strong's-tagged words for \(state.passage) in the bundled KJV."
                : "\(state.bookName) has no Strong's tagging in this build."
        return Text(reason)
            .font(.system(size: 11, design: .rounded))
            .foregroundStyle(STColor.secondary)
            .padding(.horizontal, 12).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Restyled onto `DeskSectionHeader` (`DeskComponents.swift`, workstream A) in 0.7 wave 2 (E4) —
/// word study is not a source tradition (there's no bank toggle for it, it's its own desk
/// section), so it keeps its own quiet identity (navy, matching the Type knob) rather than
/// borrowing a bank color, but otherwise uses the exact same header chrome every other section
/// uses. Uses `STColor.navyOnBlack` (a fixed hex), not the adaptive `STColor.navy` knob-cap
/// color, since this swatch sits on the invariant-black LCD bar in both finishes (see that
/// token's doc comment -- the adaptive navy measured ~1.56:1 there in light mode). The
/// KJV-tagging disclaimer lives here, once, not per word, via the same always-visible-disclaimer
/// slot `DeskSectionHeader` already gives every section.
struct WordStudyHeader: View {
    var count: Int = 0
    var expanded: Binding<Bool>? = nil

    var body: some View {
        DeskSectionHeader(
            title: "Word Study", color: STColor.navyOnBlack, count: count,
            disclaimer: "Word tagging from the KJV (Strong's numbers) — shown alongside any translation, but the tagging follows the King James Version's own words.",
            expanded: expanded)
    }
}

/// One tagged word: the KJV surface form, its Strong's number(s), and (collapsed by default)
/// the dictionary entry plus a lazily-computed concordance.
struct WordTagRow: View {
    let tag: WordTag
    let store: LexiconStore
    var onNavigate: (ConcordanceHit) -> Void = { _ in }

    @State private var expanded: Bool
    @State private var concordance: [ConcordanceHit]?

    init(tag: WordTag, store: LexiconStore, startExpanded: Bool = false, onNavigate: @escaping (ConcordanceHit) -> Void = { _ in }) {
        self.tag = tag
        self.store = store
        self.onNavigate = onNavigate
        _expanded = State(initialValue: startExpanded)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            summaryRow
            if expanded {
                ForEach(tag.strongs, id: \.self) { number in
                    EntryDetail(number: number, entry: store.entry(for: number))
                }
                concordanceSection
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    private var summaryRow: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tag.word).font(STFont.reading(14, weight: .semibold)).foregroundStyle(STColor.ink)
                    if let first = tag.strongs.first, let entry = store.entry(for: first) {
                        Text("\(entry.lemma) · \(entry.translit)")
                            .font(.system(size: 11.5, design: .rounded))
                            .foregroundStyle(STColor.secondary)
                    }
                }
                Spacer(minLength: 6)
                HStack(spacing: 4) {
                    ForEach(tag.strongs, id: \.self) { StrongChip(number: $0) }
                }
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(STColor.secondary)
            }
        }
        .buttonStyle(.plain)
    }

    private var concordanceSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(tag.strongs, id: \.self) { number in
                ConcordanceDisclosure(number: number, store: store, cached: $concordance, onNavigate: onNavigate)
            }
        }
    }
}

private struct StrongChip: View {
    let number: String

    private var isGreek: Bool { number.hasPrefix("G") }

    var body: some View {
        Text(number)
            .font(STFont.lcd(10, weight: .medium)).monospacedDigit()
            .foregroundStyle(STColor.lcdInk)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background((isGreek ? STColor.navy : STColor.orange), in: RoundedRectangle(cornerRadius: 2))
            .accessibilityLabel("Strong's number \(number)")
    }
}

/// Full dictionary entry for one Strong's number — lemma, transliteration, pronunciation,
/// definition and (when the source has one) the KJV's own rendering gloss.
private struct EntryDetail: View {
    let number: String
    let entry: LexiconEntry?

    var body: some View {
        if let entry {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.lemma).font(STFont.reading(15, weight: .semibold))
                    Text(entry.translit).font(.system(size: 12, design: .rounded)).foregroundStyle(STColor.secondary)
                    if !entry.pronunciation.isEmpty {
                        Text("[\(entry.pronunciation)]").font(.system(size: 11, design: .rounded)).foregroundStyle(STColor.secondary)
                    }
                }
                Text(entry.definition)
                    .font(STFont.reading(12.5))
                    .lineSpacing(2)
                    .textSelection(.enabled)
                if let kjvUsage = entry.kjvUsage, !kjvUsage.isEmpty {
                    Text("KJV: \(kjvUsage)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(STColor.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(STColor.tileWell, in: RoundedRectangle(cornerRadius: 3))
        } else {
            Text("No dictionary entry found for \(number).")
                .font(.system(size: 11, design: .rounded))
                .foregroundStyle(STColor.warning)
                .padding(8)
        }
    }
}

/// Reveals the concordance for one Strong's number on request — the expensive computation
/// (scanning all 66 books' tag files the first time) only ever runs when a reader asks for it.
struct ConcordanceDisclosure: View {
    let number: String
    let store: LexiconStore
    @Binding var cached: [ConcordanceHit]?
    var onNavigate: (ConcordanceHit) -> Void

    @State private var showList: Bool
    @State private var hits: [ConcordanceHit]?

    init(number: String, store: LexiconStore, cached: Binding<[ConcordanceHit]?>,
         startShown: Bool = false, onNavigate: @escaping (ConcordanceHit) -> Void = { _ in }) {
        self.number = number
        self.store = store
        _cached = cached
        self.onNavigate = onNavigate
        _showList = State(initialValue: startShown)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if hits == nil { hits = store.concordance(for: number) }
                showList.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "list.bullet.rectangle")
                    Text(hits.map { "\($0.count) OCCURRENCES · \(number)" } ?? "CONCORDANCE · \(number)")
                }
                .font(STFont.legend(9)).tracking(0.6)
                .foregroundStyle(STColor.ink)
            }
            .buttonStyle(.plain)

            if showList, let hits {
                FlowLayout(spacing: 5) {
                    ForEach(hits) { hit in
                        Button { onNavigate(hit) } label: {
                            Text("\(hit.bookCode) \(hit.chapter):\(hit.verse)")
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(STColor.tileWell, in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(STColor.keyRim, lineWidth: 1))
                        .help("Go to \(hit.bookCode) \(hit.chapter):\(hit.verse) (\"\(hit.word)\")")
                    }
                }
            }
        }
        .onAppear {
            // Supports `startShown: true` (previews/tests): a real tap always populates `hits`
            // itself before revealing the list, so this only matters when the disclosure is
            // asked to start open.
            if showList, hits == nil { hits = store.concordance(for: number) }
        }
    }
}
