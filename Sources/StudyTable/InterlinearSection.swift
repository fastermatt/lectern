import SwiftUI

/// Passage-scoped word focus shared by the LCD, the Scripture reader and the Study Desk. The
/// request token also handles repeat clicks; passage identity prevents an old word from
/// highlighting or opening in another verse.
///
/// Two ways in, one destination:
/// - the LCD's original-language words (and rows of the full list) focus an *original* word by index;
/// - double-clicking (or menu-choosing) an *English* word in Scripture records that word, how it was
///   aligned (`WordAlignmentResult`), and — when there is a match — the original word's index.
/// `mode` says whether the desk shows just that word (`.single`, with a way back) or the full list.
@MainActor
final class InterlinearSelection: ObservableObject {
    static let shared = InterlinearSelection()

    enum Mode: Equatable, Sendable { case single, all }

    /// The English word the reader chose in Scripture, and how it was tied to the original text.
    struct StudiedWord: Equatable {
        let word: String
        let key: String
        let occurrence: Int
        /// UTF-16 range in the verse text as displayed (drives the reader's highlight).
        let range: NSRange
        /// Highlight and re-resolution only apply while this translation is on screen.
        let translationID: String
        let result: WordAlignmentResult
    }

    private(set) var focusedWordIndex: Int?
    private(set) var passageID: String?
    private(set) var studiedWord: StudiedWord?
    private(set) var mode: Mode = .single

    static func passageID(book: String, chapter: Int, verse: Int?) -> String {
        "\(book).\(chapter).\(verse ?? 0)"
    }
    static func rowID(passage: String, index: Int) -> String { "original.\(passage).\(index)" }
    static func cardID(passage: String) -> String { "original.card.\(passage)" }

    func focusedIndex(for passage: String) -> Int? {
        passageID == passage ? focusedWordIndex : nil
    }
    /// Any word focus (an original word, or a studied English word with or without a match).
    func hasFocus(for passage: String) -> Bool {
        passageID == passage && (focusedWordIndex != nil || studiedWord != nil)
    }
    func studied(for passage: String) -> StudiedWord? {
        passageID == passage ? studiedWord : nil
    }
    func mode(for passage: String) -> Mode { passageID == passage ? mode : .all }
    /// The range to highlight in this verse's text: only for the passage *and* translation studied.
    func highlightRange(passage: String, translationID: String) -> NSRange? {
        guard passageID == passage, let studiedWord, studiedWord.translationID == translationID else { return nil }
        return studiedWord.range
    }

    /// Bumped on every LCD word click, even a re-click of the already-focused word — a view
    /// watching this via `.onChange` always sees a change to react to, unlike a boolean that
    /// could already equal the value being set.
    @Published private(set) var requestToken: Int = 0

    /// Focus one original word (LCD strip): single-word view.
    func focus(wordIndex: Int, passage: String? = nil) {
        objectWillChange.send()
        focusedWordIndex = wordIndex
        passageID = passage
        studiedWord = nil
        mode = .single
        requestToken += 1
    }

    /// Focus an English word studied in Scripture.
    func focus(studied word: StudiedWord, passage: String) {
        objectWillChange.send()
        focusedWordIndex = word.result.match?.wordIndex
        passageID = passage
        studiedWord = word
        mode = .single
        requestToken += 1
    }

    /// A row of the full list was chosen: highlight it there without changing the view mode or
    /// asking the desk to scroll.
    func select(wordIndex: Int, passage: String) {
        objectWillChange.send()
        focusedWordIndex = wordIndex
        passageID = passage
        studiedWord = nil
    }

    /// Switching view also bumps the token so the desk scrolls to the word in its new place.
    func showAll() { objectWillChange.send(); mode = .all; requestToken += 1 }
    func showSingle() { objectWillChange.send(); mode = .single; requestToken += 1 }

    func clear() {
        objectWillChange.send()
        focusedWordIndex = nil
        passageID = nil
        studiedWord = nil
        mode = .single
    }

    /// Drops a focus that belongs to some other passage (called when the selected verse changes).
    func clear(unlessPassage passage: String) {
        if passageID != nil, passageID != passage { clear() }
    }

    func reveal(wordIndex: Int, state: AppState) {
        state.focusMode = false
        state.showStudyDesk = true
        state.setDeskSectionVisible(.originalLanguage, true)
        focus(wordIndex: wordIndex, passage: Self.passageID(book: state.selectedBookCode,
              chapter: state.selectedChapter, verse: state.selectedVerse))
    }

    /// The single entry point for "study this English word": selects the verse, aligns the word to
    /// the original text, and reveals the desk on that word. Used by double-click, the context menu
    /// and the VoiceOver word list, so all three behave identically.
    func studyWord(_ hit: WordHit, in verse: BibleVerse, state: AppState,
                   interlinear: InterlinearStore = .shared, lexicon: LexiconStore = .shared) {
        if state.selectedVerse != verse.number {
            state.suppressScrollForVerse = verse.number
            state.selectedVerse = verse.number
        }
        let words = interlinear.words(bookCode: state.selectedBookCode, chapter: state.selectedChapter, verse: verse.number)
        let tags = lexicon.tags(bookCode: state.selectedBookCode, chapter: state.selectedChapter, verse: verse.number)
        let result = WordAlignment.align(hit: hit, verseText: verse.text, tags: tags, words: words)
        state.focusMode = false
        state.showStudyDesk = true
        state.setDeskSectionVisible(.originalLanguage, true)
        focus(studied: StudiedWord(word: hit.word, key: hit.key, occurrence: hit.occurrence, range: hit.range,
                                   translationID: state.translationID, result: result),
              passage: Self.passageID(book: state.selectedBookCode, chapter: state.selectedChapter, verse: verse.number))
    }

    /// After a translation change: keep the studied word only if the same word can be found in the
    /// new text *and* still resolves to the same original word (or still to none); otherwise clear,
    /// so the desk never silently swaps to a different original word.
    func reconcile(with content: ChapterContent, state: AppState,
                   interlinear: InterlinearStore = .shared, lexicon: LexiconStore = .shared) {
        guard let studied = studiedWord, let verseNumber = state.selectedVerse,
              passageID == Self.passageID(book: state.selectedBookCode, chapter: state.selectedChapter, verse: verseNumber),
              studied.translationID != state.translationID else { return }
        guard let verse = content.verses.first(where: { $0.number == verseNumber }) else { clear(); return }
        let tokens = WordTokenizer.tokens(in: verse.text)
        // The same word, or (for content words) the same stem: believes -> believeth.
        let stem = WordStem.stem(studied.key)
        let sameStem = WordClass.weight(of: studied.key) == .content
            ? tokens.filter { WordStem.stem($0.key) == stem } : []
        guard let token = tokens.first(where: { $0.key == studied.key && $0.occurrence == studied.occurrence })
                ?? tokens.first(where: { $0.key == studied.key })
                ?? (sameStem.count == 1 ? sameStem.first : nil) else { clear(); return }
        let hit = WordHit(word: token.text, range: token.range, occurrence: token.occurrence, tokenIndex: token.index, key: token.key)
        let words = interlinear.words(bookCode: state.selectedBookCode, chapter: state.selectedChapter, verse: verseNumber)
        let tags = lexicon.tags(bookCode: state.selectedBookCode, chapter: state.selectedChapter, verse: verseNumber)
        let result = WordAlignment.align(hit: hit, verseText: verse.text, tags: tags, words: words)
        guard result.match?.wordIndex == studied.result.match?.wordIndex else { clear(); return }
        objectWillChange.send()
        studiedWord = StudiedWord(word: token.text, key: token.key, occurrence: token.occurrence, range: token.range,
                                  translationID: state.translationID, result: result)
    }
}

/// Original-language word study for the selected verse: STEPBible-Data's Hebrew/Aramaic (TAHOT)
/// and Greek (TAGNT) tagging, word-by-word, with plain-English decoded parsing and — reusing
/// `LexiconStore`'s already-shipped dictionaries wherever the Strong's numbering lines up — a
/// lexicon-entry expansion and lemma concordance per word.
///
/// This is the desk's single word-study surface, replacing the overlapping KJV Word Study UI.
struct OriginalLanguageSection: View {
    @EnvironmentObject private var state: AppState
    var store: InterlinearStore = .shared
    var lexicon: LexiconStore = .shared
    /// Collapsed by default, same rationale as Word Study (0.7): a verse can carry 30+ words,
    /// which would push the commentary banks below the fold.
    @AppStorage("desk.originalLanguageExpanded") private var sectionExpanded = false
    @ObservedObject private var selection = InterlinearSelection.shared

    private var words: [InterlinearWord] {
        guard let verse = state.selectedVerse, verse > 0 else { return [] }
        return store.words(bookCode: state.selectedBookCode, chapter: state.selectedChapter, verse: verse)
    }

    /// Preserve the original script and source word order in the compact preview.
    private var collapsedSummary: String { words.map(\.surface).joined(separator: " ") }
    private var passageID: String {
        InterlinearSelection.passageID(book: state.selectedBookCode, chapter: state.selectedChapter, verse: state.selectedVerse)
    }

    private var hasFocus: Bool { selection.hasFocus(for: passageID) }
    private var isSingle: Bool { hasFocus && selection.mode(for: passageID) == .single }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            OriginalLanguageHeader(count: words.count, expanded: $sectionExpanded)
            if !sectionExpanded {
                if !words.isEmpty {
                    DeskCollapsedSummary(section: "Original Language", text: collapsedSummary) { sectionExpanded = true }
                }
            } else if isSingle {
                // One word, studied on its own; "Show all" returns to the list below.
                SingleWordCard(words: words, passage: passageID, store: store, lexicon: lexicon) { hit in
                    state.navigate(bookCode: hit.bookCode, chapter: hit.chapter, verse: hit.verse)
                }
                .id(InterlinearSelection.cardID(passage: passageID))
            } else if words.isEmpty {
                emptyState
            } else {
                if hasFocus {
                    WordFocusBar(passage: passageID)
                }
                ForEach(Array(words.enumerated()), id: \.offset) { index, word in
                    OriginalWordRow(word: word, index: index, lexicon: lexicon, interlinear: store,
                                    isFocused: selection.focusedIndex(for: passageID) == index,
                                    startExpanded: selection.focusedIndex(for: passageID) == index,
                                    focusRequest: selection.requestToken,
                                    onSelect: { selection.select(wordIndex: index, passage: passageID) },
                                    onFocusAlone: { selection.focus(wordIndex: index, passage: passageID) },
                                    onClear: { selection.clear() }) { hit in
                        state.navigate(bookCode: hit.bookCode, chapter: hit.chapter, verse: hit.verse)
                    }
                    .id(InterlinearSelection.rowID(passage: passageID, index: index))
                    if index < words.count - 1 {
                        Rectangle().fill(STColor.hairline).frame(height: 1)
                    }
                }
            }
        }
        .onAppear { if hasFocus { sectionExpanded = true } }
        // Initial mount covers a word click that first reveals a hidden desk; onChange handles
        // later clicks while it is already present. Both require the same passage identity.
        .onChange(of: selection.requestToken) { _, _ in
            guard hasFocus else { return }
            sectionExpanded = true
        }
    }

    private var emptyState: some View {
        let reason = state.selectedVerse == nil || state.selectedVerse == 0
            ? "Select a verse to see its original-language words."
            : store.hasData(bookCode: state.selectedBookCode)
                ? "No original-language tagging for \(state.passage) in this build."
                : "\(state.bookName) has no original-language data in this build."
        return Text(reason)
            .font(.system(size: 11, design: .rounded))
            .foregroundStyle(STColor.secondary)
            .padding(.horizontal, 12).padding(.vertical, 14)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Restyled onto `DeskSectionHeader` exactly like Word Study — its own quiet identity
/// (`navyOnBlack`, the same fixed on-black token Word Study uses) since neither is a source-bank
/// tradition with its own tactile key.
struct OriginalLanguageHeader: View {
    var count: Int = 0
    var expanded: Binding<Bool>? = nil

    var body: some View {
        DeskSectionHeader(
            title: "Original Language", color: STColor.navyOnBlack, count: count,
            disclaimer: "Hebrew/Aramaic Old Testament and Greek New Testament word tagging from STEPBible-Data (Tyndale House Cambridge), used under CC BY 4.0.",
            expanded: expanded)
    }
}

/// One original-language word: the source-script surface form (right-to-left for Hebrew/Aramaic),
/// transliteration, English gloss and — on request — the plain-English decoded parsing, the full
/// lexicon entry for each Strong's number, and a lemma concordance across the tagged corpus.
struct OriginalWordRow: View {
    let word: InterlinearWord
    let index: Int
    let lexicon: LexiconStore
    let interlinear: InterlinearStore
    var isFocused: Bool = false
    var focusRequest: Int = 0
    /// Choosing a row highlights it in the list (without leaving the list).
    var onSelect: () -> Void = {}
    /// "Show only this word": the single-word study for this row.
    var onFocusAlone: (() -> Void)?
    var onClear: (() -> Void)?
    var onNavigate: (InterlinearOccurrence) -> Void = { _ in }

    @State private var expanded: Bool

    init(word: InterlinearWord, index: Int, lexicon: LexiconStore, interlinear: InterlinearStore,
         isFocused: Bool = false, startExpanded: Bool = false, focusRequest: Int = 0,
         onSelect: @escaping () -> Void = {}, onFocusAlone: (() -> Void)? = nil, onClear: (() -> Void)? = nil,
         onNavigate: @escaping (InterlinearOccurrence) -> Void = { _ in }) {
        self.word = word
        self.index = index
        self.lexicon = lexicon
        self.interlinear = interlinear
        self.isFocused = isFocused
        self.focusRequest = focusRequest
        self.onSelect = onSelect
        self.onFocusAlone = onFocusAlone
        self.onClear = onClear
        self.onNavigate = onNavigate
        _expanded = State(initialValue: startExpanded)
    }

    private var isRightToLeft: Bool { word.language != .greek }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            summaryRow
            if expanded {
                Text(word.morphDescription)
                    .font(.system(size: 11.5, weight: .medium, design: .rounded))
                    .foregroundStyle(STColor.secondary)
                if let explanation = interlinear.explanation(for: word) {
                    VariantDetail(explanation: explanation)
                }
                ForEach(word.strongs, id: \.self) { number in
                    OriginalEntryDetail(number: number, entry: lexicon.entry(for: InterlinearStore.baseStrong(number) ?? number))
                }
                OriginalConcordanceDisclosure(strong: word.strongs.first ?? "", lemma: word.lemma, store: interlinear, onNavigate: onNavigate)
                if onFocusAlone != nil || (isFocused && onClear != nil) {
                    HStack(spacing: 14) {
                        if let onFocusAlone {
                            Button(action: onFocusAlone) {
                                HStack(spacing: 5) { Image(systemName: "scope"); Text("SHOW ONLY THIS WORD") }
                            }
                            .accessibilityHint("Opens this word's full study on its own")
                        }
                        if isFocused, let onClear {
                            Button(action: onClear) {
                                HStack(spacing: 5) { Image(systemName: "xmark"); Text("CLEAR WORD") }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .font(STFont.legend(9)).tracking(0.6).foregroundStyle(STColor.ink)
                }
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
        .background(isFocused ? STColor.tileWell : Color.clear)
        .overlay(alignment: .leading) {
            if isFocused { Rectangle().fill(STColor.orange).frame(width: 2) }
        }
        .onChange(of: isFocused) { _, focused in if focused { expanded = true } }
        .onChange(of: focusRequest) { _, _ in if isFocused { expanded = true } }
    }

    private var summaryRow: some View {
        Button { expanded.toggle(); onSelect() } label: {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: isRightToLeft ? .trailing : .leading, spacing: 2) {
                    Text(word.surface)
                        .font(STFont.original(17, weight: isFocused ? .bold : .medium))
                        .foregroundStyle(STColor.ink)
                        .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
                    Text(word.transliteration)
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(STColor.secondary)
                    Text(word.gloss)
                        .font(.system(size: 11.5, weight: .medium, design: .rounded))
                        .foregroundStyle(STColor.ink)
                    if let variant = word.variant {
                        VariantChip(variant: variant).padding(.top, 2)
                    }
                }
                .frame(maxWidth: .infinity, alignment: isRightToLeft ? .trailing : .leading)
                Spacer(minLength: 6)
                HStack(spacing: 4) {
                    ForEach(word.strongs, id: \.self) { OriginalStrongChip(number: $0) }
                }
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(STColor.secondary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(word.surface), \(word.transliteration), \(word.gloss)"
                            + (word.variant.map { $0.isSignificant ? ", textual variant" : ", minor textual variant" } ?? ""))
        .accessibilityHint(word.morphDescription)
    }
}

// MARK: Textual variants (0.10)

/// The compact marker on a word the source flags as a textual variant. A solid chip means the
/// source rates the difference as significant, a dashed outline means minor: the distinction is in
/// the shape and the words, never colour alone. Not a button (it sits inside the row's own button);
/// the row's expansion carries the explanation.
struct VariantChip: View {
    let variant: WordVariant

    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "arrow.triangle.branch").font(.system(size: 8, weight: .bold)).accessibilityHidden(true)
            Text(variant.chipLabel).font(STFont.legend(8.5)).tracking(0.6)
        }
        .foregroundStyle(variant.isSignificant ? STColor.ink : STColor.secondary)
        .padding(.horizontal, 5).padding(.vertical, 2)
        .background(variant.isSignificant ? STColor.tileTop : Color.clear, in: RoundedRectangle(cornerRadius: 2))
        .overlay(
            RoundedRectangle(cornerRadius: 2)
                .strokeBorder(variant.isSignificant ? STColor.ink.opacity(0.6) : STColor.secondary,
                              style: StrokeStyle(lineWidth: 1, dash: variant.isSignificant ? [] : [2, 2])))
        .fixedSize()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(variant.isSignificant ? "Textual variant" : "Minor textual variant")
    }
}

/// The plain-English explanation of one variant flag: what the source says, which editions or
/// manuscripts carry which reading, and the source's own legend for every code used. Everything
/// comes from `VariantExplanation`, which is built only from the word's data and the source legend.
struct VariantDetail: View {
    let explanation: VariantExplanation

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 5) {
                Image(systemName: "arrow.triangle.branch").font(.system(size: 9, weight: .bold)).accessibilityHidden(true)
                Text(explanation.title).font(STFont.legend(9)).tracking(0.9)
            }
            .foregroundStyle(STColor.ink)

            Text(explanation.headline)
                .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(STColor.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let kind = explanation.noteKind {
                Text(kind).font(.system(size: 11, design: .rounded)).foregroundStyle(STColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let note = explanation.sourceNote {
                VStack(alignment: .leading, spacing: 2) {
                    Text("SOURCE NOTE").font(STFont.legend(9)).tracking(0.6).foregroundStyle(STColor.secondary)
                    Text(note).font(STFont.reading(12)).foregroundStyle(STColor.ink)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(explanation.readings) { reading in
                VariantReadingRow(reading: reading)
            }
            ForEach(Array(explanation.editionLines.enumerated()), id: \.offset) { _, line in
                Text(line).font(.system(size: 11, design: .rounded)).foregroundStyle(STColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(explanation.significance).font(.system(size: 10.5, design: .rounded)).foregroundStyle(STColor.secondary)
                .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 2) {
                Text("SOURCE LEGEND").font(STFont.legend(9)).tracking(0.6).foregroundStyle(STColor.secondary)
                Text(explanation.codeLine).font(.system(size: 10.5, design: .rounded)).foregroundStyle(STColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(Array(explanation.legendLines.enumerated()), id: \.offset) { _, line in
                    Text(line).font(STFont.lcd(9.5)).foregroundStyle(STColor.secondary).fixedSize(horizontal: false, vertical: true)
                }
                Text("STEPBible-Data (Tyndale House Cambridge), CC BY 4.0.")
                    .font(.system(size: 10, design: .rounded)).foregroundStyle(STColor.secondary)
            }
            if let caveat = explanation.caveat {
                Text(caveat).font(.system(size: 10, design: .rounded)).foregroundStyle(STColor.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(9)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(STColor.tileTop.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(STColor.hairline, lineWidth: 1))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(explanation.plainText)
    }
}

/// One alternate reading the source records for a word.
struct VariantReadingRow: View {
    let reading: VariantExplanation.ReadingLine

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text("OTHER READING").font(STFont.legend(9)).tracking(0.6).foregroundStyle(STColor.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(reading.text).font(STFont.original(16, weight: .medium)).foregroundStyle(STColor.ink)
                    .environment(\.layoutDirection, reading.isRightToLeft ? .rightToLeft : .leftToRight)
                    .textSelection(.enabled)
                if !reading.transliteration.isEmpty {
                    Text(reading.transliteration).font(.system(size: 11, design: .rounded)).foregroundStyle(STColor.secondary)
                }
                if !reading.gloss.isEmpty {
                    Text("\u{201C}\(reading.gloss)\u{201D}").font(.system(size: 11.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(STColor.ink)
                }
                Spacer(minLength: 0)
            }
            if !reading.carriedBy.isEmpty {
                Text("Read by \(reading.carriedBy).").font(.system(size: 11, design: .rounded)).foregroundStyle(STColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !reading.morphDescription.isEmpty || !reading.strongs.isEmpty {
                HStack(spacing: 4) {
                    ForEach(reading.strongs, id: \.self) { OriginalStrongChip(number: $0) }
                    if !reading.morphDescription.isEmpty {
                        Text(reading.morphDescription).font(.system(size: 10.5, design: .rounded)).foregroundStyle(STColor.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
        .padding(.leading, 8)
        .overlay(alignment: .leading) { Rectangle().fill(STColor.hairline).frame(width: 2) }
    }
}

struct OriginalStrongChip: View {
    let number: String
    private var isGreek: Bool { number.hasPrefix("G") }

    var body: some View {
        Text(number)
            .font(STFont.lcd(10, weight: .medium)).monospacedDigit()
            .foregroundStyle(STColor.lcdInk)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(STColor.lcd, in: RoundedRectangle(cornerRadius: 2))
            .accessibilityLabel("Strong's number \(number)")
    }
}

/// Full dictionary entry for one Strong's number, reusing `LexiconStore`'s already-verified
/// public-domain Strong's Hebrew/Greek text — the same data `WordStudySection`'s `EntryDetail`
/// shows, just looked up by this word's own tag instead of the KJV's.
struct OriginalEntryDetail: View {
    let number: String
    let entry: LexiconEntry?

    var body: some View {
        if let entry {
            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(entry.lemma).font(STFont.original(15, weight: .semibold))
                    Text(entry.translit).font(.system(size: 12, design: .rounded)).foregroundStyle(STColor.secondary)
                    if !entry.pronunciation.isEmpty {
                        Text("[\(entry.pronunciation)]").font(.system(size: 11, design: .rounded)).foregroundStyle(STColor.secondary)
                    }
                }
                Text(entry.definition)
                    .font(STFont.reading(12.5))
                    .lineSpacing(2)
                    .textSelection(.enabled)
            }
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(STColor.tileWell, in: RoundedRectangle(cornerRadius: 3))
        } else {
            Text("\(number) is outside classical Strong's numbering (a STEPBible grammatical-formative extension — an article, preposition or conjunction was never assigned its own Strong's number).")
                .font(.system(size: 10.5, design: .rounded))
                .foregroundStyle(STColor.secondary)
                .padding(8)
        }
    }
}

/// Reveals every other tagged occurrence of this word's lemma (by base Strong's number) on
/// request — precomputed at build time (`InterlinearStore.occurrences`), so this is a fast lookup,
/// not a corpus scan, but still gated behind a tap since a common lemma can have hundreds of hits.
struct OriginalConcordanceDisclosure: View {
    let strong: String
    let lemma: String
    let store: InterlinearStore
    /// The single-word card states the occurrence count without a tap; the list itself stays behind one.
    var showsCountUpfront = false
    var onNavigate: (InterlinearOccurrence) -> Void = { _ in }

    @State private var showList = false
    @State private var hits: [InterlinearOccurrence]?
    @State private var visibleLimit = 60

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                if hits == nil { hits = store.occurrences(strong: strong) }
                showList.toggle()
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "list.bullet.rectangle")
                    Text(hits.map { "\($0.count) OCCURRENCES · \(lemma)" } ?? "CONCORDANCE · \(lemma)")
                }
                .font(STFont.legend(9)).tracking(0.6)
                .foregroundStyle(STColor.ink)
            }
            .buttonStyle(.plain)
            .disabled(strong.isEmpty)

            if showList, let hits {
                FlowLayout(spacing: 5) {
                    ForEach(Array(hits.prefix(visibleLimit).enumerated()), id: \.offset) { _, hit in
                        Button { onNavigate(hit) } label: {
                            Text("\(hit.bookCode) \(hit.chapter):\(hit.verse)")
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(STColor.tileWell, in: RoundedRectangle(cornerRadius: 4))
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(STColor.keyRim, lineWidth: 1))
                        .help("Go to \(hit.bookCode) \(hit.chapter):\(hit.verse) (\"\(hit.surface)\" — \(hit.gloss))")
                    }
                }
                if hits.count > visibleLimit {
                    Button("Show next \(min(60, hits.count - visibleLimit)) occurrences") { visibleLimit += 60 }
                        .font(.system(size: 11, weight: .medium))
                }
            }
        }
        .onAppear { if showsCountUpfront, hits == nil, !strong.isEmpty { hits = store.occurrences(strong: strong) } }
        .onChange(of: strong) { _, _ in
            hits = nil
            showList = false
            visibleLimit = 60
            if showsCountUpfront, !strong.isEmpty { hits = store.occurrences(strong: strong) }
        }
    }
}
