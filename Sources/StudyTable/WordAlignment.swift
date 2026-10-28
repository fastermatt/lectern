import Foundation

// MARK: - Result types

/// How an English word in the verse the reader clicked was tied to one original-language word.
///
/// This is a *heuristic* alignment. No bundled data links an arbitrary translation word to a
/// Greek/Hebrew word (the interlinear is a separate text, and translations combine, drop, add and
/// reorder words), so every result says how it was reached and how sure that route is, and the
/// interface must say so too. Nothing here is ever a silent guess: no match is a first-class result.
struct AlignmentMatch: Equatable, Sendable {
    enum Method: String, Sendable {
        /// Through the KJV's Strong's-number tagging (the displayed text is the KJV, or wording matches it).
        case kjvTag
        /// Same, but the English word form differs from the KJV's (believes / believeth).
        case kjvTagStem
        /// The clicked word is a word of the interlinear's English gloss.
        case glossExact
        /// The clicked word shares a stem with a word of the interlinear's English gloss.
        case glossStem
    }

    enum Confidence: Int, Comparable, Sendable {
        case low = 0, medium, high
        static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    }

    /// Index into `InterlinearStore.words(...)` for the verse.
    let wordIndex: Int
    let method: Method
    let confidence: Confidence
    /// Other original words that fit as well as the chosen one did (empty when the choice was unique).
    let candidates: [Int]
}

/// Why there is no single original word for the clicked English word.
enum AlignmentGap: Equatable, Sendable {
    /// "the", "a", "an": Greek and Hebrew articles do not line up with English ones one for one.
    case article
    /// Prepositions, auxiliaries, pronouns and connectives that translations add or fold into a neighbour.
    case functionWord
    /// The word simply has no counterpart the data can identify (a translator's wording).
    case noCounterpart
    /// There is no original-language tagging for this verse at all.
    case noOriginalData
}

struct WordAlignmentResult: Equatable, Sendable {
    /// The word as displayed (punctuation removed).
    let word: String
    let key: String
    /// 0-based occurrence among the verse's words with the same key.
    let occurrence: Int
    let match: AlignmentMatch?
    /// The nearest plausible original words: alternatives when there is a match, the best 1-3
    /// candidates when there is none.
    let candidates: [Int]
    let gap: AlignmentGap?

    /// The one line that tells the reader how this word was tied to the original-language word.
    var provenanceLine: String {
        guard let match else {
            switch gap {
            case .noOriginalData: return "No original-language data for this verse."
            case .article, .functionWord: return "\u{201C}\(word)\u{201D} has no single original word of its own."
            default: return "No single original word matches \u{201C}\(word)\u{201D}."
            }
        }
        switch (match.method, match.confidence) {
        case (.kjvTag, .high): return "Matched through the KJV's Strong's numbers."
        case (.kjvTag, _): return "Probable match through the KJV's Strong's numbers; the wording or position differs."
        case (.kjvTagStem, _): return "Probable match through the KJV's Strong's numbers; the English word form differs."
        case (.glossExact, _): return "Best guess from the English gloss."
        case (.glossStem, _): return "Loose guess from the English gloss."
        }
    }

    /// Why there is no match, for the card's second paragraph (nil when there is one or no data).
    var gapExplanation: String? {
        switch gap {
        case .article: return "English articles are added, dropped or merged by translators; Greek and Hebrew articles do not line up with them one for one."
        case .functionWord: return "Small words like this are often supplied by the translation or folded into a neighbouring word, so they rarely have a word of their own."
        case .noCounterpart: return "Translations combine, reorder and add words, so a word like \u{201C}\(word)\u{201D} does not always have its own Hebrew or Greek word."
        default: return nil
        }
    }

    /// True when the reader should be told this is an approximation, not a firm match.
    var isHeuristic: Bool { match.map { !($0.method == .kjvTag && $0.confidence == .high) } ?? false }
}

// MARK: - Word lists and stemming

enum WordWeight: Sendable { case article, function, content }

enum WordClass {
    private static let articles: Set<String> = ["the", "a", "an"]
    private static let function: Set<String> = [
        "of", "to", "in", "on", "at", "by", "with", "for", "from", "into", "unto", "upon", "and", "or",
        "but", "nor", "that", "as", "so", "than", "then", "if", "is", "am", "are", "was", "were", "be",
        "been", "being", "do", "does", "did", "will", "would", "shall", "should", "may", "might", "must",
        "can", "could", "he", "she", "it", "they", "we", "you", "ye", "thou", "thee", "thy", "thine", "i",
        "me", "my", "him", "her", "his", "its", "their", "them", "us", "our", "your", "who", "whom",
        "whose", "which", "what", "this", "these", "those", "there", "hath", "hast", "art", "wilt", "shalt",
        "have", "has", "had", "having"
    ]

    static func weight(of key: String) -> WordWeight {
        if articles.contains(key) { return .article }
        if function.contains(key) { return .function }
        return .content
    }
}

/// A deliberately conservative English stemmer: enough to relate loved/love/loves/loveth and
/// world/worlds/world's, not a linguistic analysis. Stem matches are always reported as weaker
/// than exact matches. Words of three letters or fewer are never stemmed.
enum WordStem {
    private static let irregular: [String: String] = [
        "gave": "give", "given": "give", "took": "take", "taken": "take", "came": "come", "went": "go",
        "gone": "go", "saw": "see", "seen": "see", "said": "say", "spoke": "speak", "spoken": "speak",
        "knew": "know", "known": "know", "begat": "beget", "begotten": "beget", "sent": "send",
        "made": "make", "told": "tell", "wrote": "write", "written": "write", "rose": "rise",
        "risen": "rise", "fell": "fall", "fallen": "fall", "ate": "eat", "eaten": "eat", "bore": "bear",
        "born": "bear", "borne": "bear", "brought": "bring", "thought": "think", "stood": "stand",
        "held": "hold", "found": "find", "heard": "hear", "kept": "keep", "left": "leave",
        "sat": "sit", "slept": "sleep", "led": "lead", "lost": "lose", "died": "die", "lay": "lie",
        "laid": "lay", "set": "set", "ran": "run", "drank": "drink", "drunk": "drink", "sang": "sing",
        "sung": "sing", "children": "child", "men": "man", "women": "woman", "feet": "foot",
        "people": "people", "sons": "son", "daughters": "daughter", "brethren": "brother"
    ]

    /// Suffixes tried in order; the remainder must keep at least `minimum` letters.
    private static let suffixes: [(String, Int)] = [("ing", 3), ("eth", 3), ("est", 4), ("ed", 3), ("es", 3), ("s", 3)]

    static func stem(_ key: String) -> String {
        if let base = irregular[key], base != key { return stem(base) }
        var s = key
        guard s.count > 3, !s.contains("'") else { return s }
        for (suffix, minimum) in suffixes where s.hasSuffix(suffix) && s.count - suffix.count >= minimum {
            s.removeLast(suffix.count)
            break
        }
        if s.count > 3, s.hasSuffix("e") { s.removeLast() }
        if s.count > 3, s.hasSuffix("y") { s.removeLast(); s.append("i") }
        if s.count > 3, let last = s.last, s.dropLast().last == last, !"lsf".contains(last), last.isLetter { s.removeLast() }
        return s
    }
}

// MARK: - Alignment

enum WordAlignment {
    /// Fraction of KJV tag phrases that must line up, in order, with the displayed text before its
    /// wording is trusted to follow the KJV's tagging (the KJV itself is ~100%).
    static let kjvLikeCoverage = 0.9

    /// Align the clicked word to an original-language word of the same verse.
    /// - Parameters:
    ///   - hit: the clicked word (from `wordHit` / the word menu).
    ///   - verseText: the verse as displayed, in the selected translation.
    ///   - tags: the KJV's Strong's-tagged phrases for this verse (`LexiconStore.tags`).
    ///   - words: the verse's original-language words (`InterlinearStore.words`).
    static func align(hit: WordHit, verseText: String, tags: [WordTag], words: [InterlinearWord]) -> WordAlignmentResult {
        let tokens = WordTokenizer.tokens(in: verseText)
        // Resolve the clicked token; prefer the exact range, else key + occurrence.
        let clicked = tokens.first { $0.range == hit.range }
            ?? tokens.first { $0.key == hit.key && $0.occurrence == hit.occurrence }
        guard let clicked else {
            return WordAlignmentResult(word: hit.word, key: hit.key, occurrence: hit.occurrence,
                                       match: nil, candidates: [], gap: .noCounterpart)
        }
        let base = { (gap: AlignmentGap, candidates: [Int]) in
            WordAlignmentResult(word: clicked.text, key: clicked.key, occurrence: clicked.occurrence,
                                match: nil, candidates: candidates, gap: gap)
        }
        guard !words.isEmpty else { return base(.noOriginalData, []) }

        let weight = WordClass.weight(of: clicked.key)
        let context = Context(tokens: tokens, clicked: clicked, tags: tags, words: words)

        // 1. KJV Strong's tagging.
        if weight != .article, let found = context.kjvTagMatch(weight: weight) {
            return WordAlignmentResult(word: clicked.text, key: clicked.key, occurrence: clicked.occurrence,
                                       match: found, candidates: found.candidates, gap: nil)
        }
        // 2. The interlinear's own English gloss.
        if weight != .article, let found = context.glossMatch(weight: weight) {
            return WordAlignmentResult(word: clicked.text, key: clicked.key, occurrence: clicked.occurrence,
                                       match: found, candidates: found.candidates, gap: nil)
        }
        // 3. Honest "no single original word".
        let gap: AlignmentGap = weight == .article ? .article : (weight == .function ? .functionWord : .noCounterpart)
        return base(gap, context.nearestCandidates())
    }

    // MARK: Internals

    /// One KJV tag phrase, e.g. "the world" (G2889).
    struct TagUnit {
        let tagIndex: Int
        let keys: [String]
        let bases: [String]
    }

    struct GlossWord {
        let index: Int
        let keys: [String]        // gloss words, punctuation and <marker> brackets removed
    }

    private struct Context {
        let tokens: [WordToken]
        let clicked: WordToken
        let units: [TagUnit]
        let words: [InterlinearWord]
        let glosses: [GlossWord]
        let unitCount: Int
        let tokenPosition: Double
        /// Verse-token index -> (unit index, position inside the unit) for the in-order alignment.
        let sequence: [Int: (unit: Int, position: Int)]
        let sequenceCoverage: Double

        init(tokens: [WordToken], clicked: WordToken, tags: [WordTag], words: [InterlinearWord]) {
            self.tokens = tokens
            self.clicked = clicked
            self.words = words
            units = tags.enumerated().map { index, tag in
                TagUnit(tagIndex: index,
                        keys: WordTokenizer.tokens(in: tag.word).map(\.key),
                        bases: tag.strongs.compactMap(InterlinearStore.baseStrong))
            }
            unitCount = units.count
            glosses = words.enumerated().map { index, word in
                GlossWord(index: index, keys: Self.glossKeys(word.gloss))
            }
            tokenPosition = tokens.isEmpty ? 0 : (Double(clicked.index) + 0.5) / Double(tokens.count)
            var assigned: [Int: (unit: Int, position: Int)] = [:]
            var pointer = 0
            var matchedUnits = 0
            let keys = tokens.map(\.key)
            for (unitIndex, unit) in units.enumerated() where !unit.keys.isEmpty {
                guard let start = Self.find(unit.keys, in: keys, from: pointer) else { continue }
                for offset in unit.keys.indices { assigned[start + offset] = (unitIndex, offset) }
                pointer = start + unit.keys.count
                matchedUnits += 1
            }
            sequence = assigned
            sequenceCoverage = units.isEmpty ? 0 : Double(matchedUnits) / Double(units.count)
        }

        static func find(_ phrase: [String], in keys: [String], from start: Int) -> Int? {
            guard !phrase.isEmpty, keys.count >= phrase.count else { return nil }
            var i = start
            while i + phrase.count <= keys.count {
                if Array(keys[i..<(i + phrase.count)]) == phrase { return i }
                i += 1
            }
            return nil
        }

        /// "<the>" -> the; "and <obj.>" -> and; "He gave," -> he gave. The "<obj.>" object marker
        /// is not English.
        static func glossKeys(_ gloss: String) -> [String] {
            WordTokenizer.tokens(in: gloss.replacingOccurrences(of: "<obj.>", with: " ")).map(\.key)
        }

        // MARK: 1. KJV tag path

        func kjvTagMatch(weight: WordWeight) -> AlignmentMatch? {
            guard !units.isEmpty else { return nil }
            // (a) The displayed text lines up with the KJV's tag phrases in order.
            if sequenceCoverage >= WordAlignment.kjvLikeCoverage, let hit = sequence[clicked.index] {
                let unit = units[hit.unit]
                if weight == .content || unit.keys.count == 1 {
                    if let match = resolve(unitIndex: hit.unit, method: .kjvTag, confidence: weight == .content ? .high : .medium, sequenced: true) {
                        return match
                    }
                }
            }
            // (b) Same English word somewhere in the KJV's tagging.
            if let match = wordFormMatch(exact: true, weight: weight) { return match }
            // (c) Same stem (believes / believeth). Function words are never stemmed.
            if weight == .content, let match = wordFormMatch(exact: false, weight: weight) { return match }
            return nil
        }

        /// KJV tag units containing the clicked word (or its stem), eligible under the function-word
        /// rule: a small word only counts where it stands alone in its tag phrase.
        private func wordFormMatch(exact: Bool, weight: WordWeight) -> AlignmentMatch? {
            let target = exact ? clicked.key : WordStem.stem(clicked.key)
            var found: [(unit: Int, position: Double)] = []
            for (unitIndex, unit) in units.enumerated() {
                if weight != .content, unit.keys.count != 1 { continue }
                let hitInUnit = unit.keys.contains { (exact ? $0 : WordStem.stem($0)) == target }
                if hitInUnit { found.append((unitIndex, (Double(unit.tagIndex) + 0.5) / Double(units.count))) }
            }
            guard !found.isEmpty else { return nil }
            // How many words of the displayed verse look like this word?
            let sameInVerse = tokens.filter { (exact ? $0.key : WordStem.stem($0.key)) == target }
            let clickedOrdinal = sameInVerse.firstIndex(where: { $0.index == clicked.index }) ?? clicked.occurrence

            let chosen: (unit: Int, position: Double)
            var confidence: AlignmentMatch.Confidence
            if found.count == sameInVerse.count {
                chosen = found[min(clickedOrdinal, found.count - 1)]
                confidence = found.count == 1 ? .high : .medium
            } else {
                // The counts disagree (a translation drops or adds this word): accept only a
                // nearby candidate, by relative position in the verse.
                guard let nearest = found.min(by: { abs($0.position - tokenPosition) < abs($1.position - tokenPosition) }),
                      abs(nearest.position - tokenPosition) <= 0.3 else { return nil }
                chosen = nearest
                confidence = .low
            }
            // Sanity: an exact single match far from where the word sits in this verse is suspect.
            if confidence == .high, abs(chosen.position - tokenPosition) > 0.45 { confidence = .medium }
            if weight != .content, confidence > .medium { confidence = .medium }
            if !exact, confidence > .medium { confidence = .medium }
            return resolve(unitIndex: chosen.unit, method: exact ? .kjvTag : .kjvTagStem, confidence: confidence)
        }

        /// True when the interlinear word's own English gloss mentions the clicked word or its stem.
        private func glossMentions(_ wordIndex: Int) -> Bool {
            let stem = WordStem.stem(clicked.key)
            return glosses[wordIndex].keys.contains { $0 == clicked.key || WordStem.stem($0) == stem }
        }

        /// KJV tag unit -> the interlinear word that carries its Strong's number.
        /// `sequenced` is true when the displayed text lined up with the KJV tag phrases in order,
        /// which is the strongest evidence; otherwise the result must be supported by position or by
        /// the interlinear word's own gloss to be called high confidence.
        private func resolve(unitIndex: Int, method: AlignmentMatch.Method, confidence: AlignmentMatch.Confidence,
                             sequenced: Bool = false) -> AlignmentMatch? {
            let unit = units[unitIndex]
            guard !unit.bases.isEmpty else { return nil }
            var carriers: [Int] = words.indices.filter { i in
                let bases = words[i].strongs.compactMap(InterlinearStore.baseStrong)
                return unit.bases.contains { bases.contains($0) }
            }
            guard !carriers.isEmpty else { return nil }
            var adjusted = confidence
            if carriers.count > 1 {
                // Several original words share this Strong's number (an article, "his"/"him" G846...).
                // Prefer the ones whose own gloss mentions the clicked word.
                let mentioning = carriers.filter(glossMentions)
                if !mentioning.isEmpty, mentioning.count < carriers.count { carriers = mentioning }
            }
            let chosen: Int
            if carriers.count == 1 {
                chosen = carriers[0]
            } else {
                let sameNumber = units.indices.filter { u in units[u].bases.contains { unit.bases.contains($0) } }
                let ordinal = sameNumber.firstIndex(of: unitIndex) ?? 0
                let position = (Double(unit.tagIndex) + 0.5) / Double(units.count)
                if sameNumber.count == carriers.count {
                    chosen = carriers[ordinal]
                } else {
                    chosen = carriers.min { abs(relative($0) - position) < abs(relative($1) - position) }!
                    adjusted = min(adjusted, .medium)
                }
            }
            // Outside the in-order alignment, a "high" needs the original word's gloss to agree.
            if !sequenced, adjusted == .high, !glossMentions(chosen) {
                let position = (Double(unit.tagIndex) + 0.5) / Double(units.count)
                if abs(relative(chosen) - position) > 0.2 || abs(position - tokenPosition) > 0.2 { adjusted = .medium }
            }
            return AlignmentMatch(wordIndex: chosen, method: method, confidence: adjusted,
                                  candidates: carriers.filter { $0 != chosen })
        }

        private func relative(_ wordIndex: Int) -> Double { (Double(wordIndex) + 0.5) / Double(words.count) }

        // MARK: 2. Gloss path

        func glossMatch(weight: WordWeight) -> AlignmentMatch? {
            for exact in [true, false] {
                if !exact, weight != .content { break }
                let target = exact ? clicked.key : WordStem.stem(clicked.key)
                let found = glosses.filter { gloss in
                    if weight != .content, gloss.keys.count != 1 { return false }
                    return gloss.keys.contains { (exact ? $0 : WordStem.stem($0)) == target }
                }
                guard !found.isEmpty else { continue }
                let sameInVerse = tokens.filter { (exact ? $0.key : WordStem.stem($0.key)) == target }
                let ordinal = sameInVerse.firstIndex(where: { $0.index == clicked.index }) ?? clicked.occurrence
                let chosen: GlossWord
                var confidence: AlignmentMatch.Confidence
                if found.count == 1 {
                    chosen = found[0]
                    confidence = .medium
                } else if found.count == sameInVerse.count {
                    chosen = found[min(ordinal, found.count - 1)]
                    confidence = .medium
                } else {
                    chosen = found.min { abs(relative($0.index) - tokenPosition) < abs(relative($1.index) - tokenPosition) }!
                    confidence = .low
                }
                if !exact { confidence = .low }
                return AlignmentMatch(wordIndex: chosen.index, method: exact ? .glossExact : .glossStem,
                                      confidence: confidence, candidates: found.map(\.index).filter { $0 != chosen.index })
            }
            return nil
        }

        // MARK: 3. Candidates when nothing matches

        /// Up to three original words worth looking at: words whose gloss mentions the clicked word
        /// (or its stem), else the content words nearest in relative position.
        func nearestCandidates() -> [Int] {
            let stem = WordStem.stem(clicked.key)
            var pool = glosses.filter { $0.keys.contains(clicked.key) || $0.keys.contains { WordStem.stem($0) == stem } }.map(\.index)
            if pool.isEmpty {
                pool = glosses.filter { gloss in
                    gloss.keys.contains { WordClass.weight(of: $0) == .content }
                }.map(\.index)
            }
            return Array(pool.sorted { abs(relative($0) - tokenPosition) < abs(relative($1) - tokenPosition) }.prefix(3))
        }
    }
}
