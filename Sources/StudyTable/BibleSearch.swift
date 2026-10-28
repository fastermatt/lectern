import Foundation
import StudyTableCore

/// A snapshot of an installed pack's location. It never exposes the reader's main-actor cache
/// or online provider caches. A new revision on rescan invalidates the disposable search index.
struct BibleSearchSource: Hashable, Sendable {
    let translationID: String
    let directory: URL
    let bookCodes: [String]
    let revision: UUID
}

enum BibleSearchScope: Hashable, Sendable {
    case bible, oldTestament, newTestament, book(String), passage(Anchor)

    func includes(_ hit: ScriptureSearchHit) -> Bool {
        switch self {
        case .bible: true
        case .oldTestament: (Canon.order[hit.bookCode] ?? 66) < 39
        case .newTestament: (Canon.order[hit.bookCode] ?? -1) >= 39
        case .book(let code): hit.bookCode == code
        case .passage(let anchor): hit.bookCode == anchor.book && anchor.contains(chapter: hit.chapter, verse: hit.verse)
        }
    }
}

struct BibleSearchPage: Sendable {
    let translationID: String
    let total: Int
    let offset: Int
    let hits: [ScriptureSearchHit]
}

enum BibleSearchError: Error, LocalizedError, Equatable {
    case syntax(String), unavailable, damagedPack(String), invalidPassage
    var errorDescription: String? {
        switch self {
        case .syntax(let reason): reason
        case .unavailable: "This translation has no installed local pack. Choose an offline translation. Online publisher caches are not searched."
        case .damagedPack(let code): "The local pack could not be read (\(code)). Reinstall the translation and try again."
        case .invalidPassage: "The passage endpoints do not exist in this translation. Check the book, chapter and verse numbers."
        }
    }
}

/// Word and phrase matching is case/diacritic insensitive; punctuation separates words.
/// Operators are uppercase so ordinary words such as “and” remain searchable.
indirect enum BibleSearchExpression: Equatable, Sendable {
    case term(String), prefix(String), phrase([String])
    case and(BibleSearchExpression, BibleSearchExpression)
    case or(BibleSearchExpression, BibleSearchExpression)
    case not(BibleSearchExpression)
}

struct BibleSearchParser {
    private enum Token: Equatable { case atom(BibleSearchExpression), and, or, not, left, right }
    private var tokens: [Token]
    private var position = 0

    static func words(_ text: String) -> [String] {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
    }

    static func parse(_ query: String) throws -> BibleSearchExpression {
        guard query.count <= 4096 else { throw BibleSearchError.syntax("Use a query of at most 4,096 characters.") }
        var tokens: [Token] = []
        let chars = Array(query)
        var i = 0
        while i < chars.count {
            if chars[i].isWhitespace { i += 1; continue }
            switch chars[i] {
            case "(": tokens.append(.left); i += 1
            case ")": tokens.append(.right); i += 1
            case "\"":
                i += 1
                let start = i
                while i < chars.count && chars[i] != "\"" { i += 1 }
                guard i < chars.count else { throw BibleSearchError.syntax("Close the quoted phrase with a double quote (\").") }
                let raw = String(chars[start..<i])
                guard !raw.contains("*") else { throw BibleSearchError.syntax("Use a trailing * on a word outside quotes, such as lov*.") }
                let words = words(raw)
                guard !words.isEmpty else { throw BibleSearchError.syntax("Put at least one word inside the quotation marks.") }
                tokens.append(.atom(.phrase(words))); i += 1
            default:
                let start = i
                while i < chars.count && !chars[i].isWhitespace && !["(", ")", "\""].contains(chars[i]) { i += 1 }
                let raw = String(chars[start..<i])
                if raw.contains(":") {
                    throw BibleSearchError.syntax("Field queries such as lemma:G26 are not supported. Search Bible words, or use Custom passage for a reference.")
                }
                if raw.contains("?") {
                    throw BibleSearchError.syntax("The ? wildcard is not supported. Use a single trailing * for a word prefix, such as lov*.")
                }
                let operatorName = raw.split(separator: "/").first.map(String.init) ?? raw
                if ["NEAR", "WITHIN", "BEFORE", "AFTER"].contains(operatorName) {
                    throw BibleSearchError.syntax("\(operatorName) proximity searches are not supported. Use AND, OR, NOT, or a quoted phrase; quote a literal word such as \"before\".")
                }
                switch raw {
                case "AND": tokens.append(.and)
                case "OR": tokens.append(.or)
                case "NOT": tokens.append(.not)
                default:
                    let prefix = raw.hasSuffix("*")
                    let base = prefix ? String(raw.dropLast()) : raw
                    guard !base.contains("*"), !base.isEmpty else { throw BibleSearchError.syntax("A wildcard must follow a word, for example lov*. Only a single trailing * is supported.") }
                    let terms = words(base)
                    guard !terms.isEmpty, !prefix || terms.count == 1 else { throw BibleSearchError.syntax("Enter a word, a quoted phrase, or a trailing-prefix word such as lov*.") }
                    for term in terms { tokens.append(.atom(prefix ? .prefix(term) : .term(term))) }
                }
            }
            guard tokens.count <= 256 else { throw BibleSearchError.syntax("Use at most 256 search terms and operators.") }
        }
        guard !tokens.isEmpty else { throw BibleSearchError.syntax("Enter a word or phrase to search the Bible.") }
        var parser = Self(tokens: tokens)
        let expression = try parser.parseOr(depth: 0)
        guard parser.position == tokens.count else { throw BibleSearchError.syntax("Unexpected closing parenthesis. Remove it or add a matching opening parenthesis.") }
        return expression
    }

    private var peek: Token? { position < tokens.count ? tokens[position] : nil }
    private mutating func parseOr(depth: Int) throws -> BibleSearchExpression {
        var result = try parseAnd(depth: depth)
        while peek == .or { position += 1; result = .or(result, try parseAnd(depth: depth)) }
        return result
    }
    private mutating func parseAnd(depth: Int) throws -> BibleSearchExpression {
        var result = try parseUnary(depth: depth)
        while let next = peek, next != .or, next != .right {
            if next == .and { position += 1 }
            result = .and(result, try parseUnary(depth: depth))
        }
        return result
    }
    private mutating func parseUnary(depth: Int) throws -> BibleSearchExpression {
        guard depth < 32 else { throw BibleSearchError.syntax("Use fewer than 32 nested groups or NOT operators.") }
        guard let next = peek else { throw BibleSearchError.syntax("An operator needs a word or phrase after it.") }
        position += 1
        switch next {
        case .atom(let expression): return expression
        case .not: return .not(try parseUnary(depth: depth + 1))
        case .left:
            let result = try parseOr(depth: depth + 1)
            guard peek == .right else { throw BibleSearchError.syntax("Close the group with a matching parenthesis.") }
            position += 1; return result
        default: throw BibleSearchError.syntax("Expected a word, quoted phrase, or group. Check consecutive operators and empty parentheses.")
        }
    }
}

/// The only corpus index lives here, outside the main actor. At most one translation is held
/// in memory. It is rebuilt after pack rescans and never written to disk.
actor BibleSearchEngine {
    static let shared = BibleSearchEngine()
    private struct Corpus {
        let source: BibleSearchSource
        let hits: [ScriptureSearchHit]
        let postings: [String: Set<Int>]
        let verseIDs: Set<String>
        let chapters: Set<String>
    }
    private struct MatchKey: Equatable {
        let source: BibleSearchSource
        let query: String
        let scope: BibleSearchScope
    }
    private var corpus: Corpus?
    private var lastMatches: (key: MatchKey, indices: [Int])?

    func search(source: BibleSearchSource?, query: String, scope: BibleSearchScope = .bible,
                offset: Int = 0, pageSize: Int = 40) throws -> BibleSearchPage {
        try Task.checkCancellation()
        guard let source else { throw BibleSearchError.unavailable }
        let expression = try BibleSearchParser.parse(query)
        let loaded = try load(source)
        if case .passage(let anchor) = scope { try validate(anchor, in: loaded) }
        if case .book(let code) = scope, !source.bookCodes.contains(code) { throw BibleSearchError.invalidPassage }
        let key = MatchKey(source: source, query: query, scope: scope)
        let indices: [Int]
        if let cached = lastMatches, cached.key == key { indices = cached.indices }
        else {
            let universe = Set(loaded.hits.indices.filter { scope.includes(loaded.hits[$0]) })
            indices = try evaluate(expression, in: loaded, universe: universe).sorted()
            try Task.checkCancellation()
            lastMatches = (key, indices)
        }
        let start = min(max(0, offset), indices.count)
        let end = min(start + min(max(1, pageSize), 200), indices.count)
        return BibleSearchPage(translationID: source.translationID, total: indices.count, offset: start,
                              hits: indices[start..<end].map { loaded.hits[$0] })
    }

    private func load(_ source: BibleSearchSource) throws -> Corpus {
        if let corpus, corpus.source == source { return corpus }
        // Evict before loading so the memory bound also holds when changing translations.
        corpus = nil; lastMatches = nil
        var hits: [ScriptureSearchHit] = [], postings: [String: Set<Int>] = [:]
        var verseIDs: Set<String> = [], chapters: Set<String> = []
        for code in source.bookCodes {
            try Task.checkCancellation()
            let book: BookPack
            do {
                let data = try Data(contentsOf: source.directory.appendingPathComponent("\(code).json"))
                book = try JSONDecoder().decode(BookPack.self, from: data)
                guard book.code == code else { throw BibleSearchError.damagedPack(code) }
            } catch { throw BibleSearchError.damagedPack(code) }
            for chapter in book.chapters.sorted(by: { $0.n < $1.n }) {
                guard chapter.v.count == chapter.t.count, Set(chapter.v).count == chapter.v.count else { throw BibleSearchError.damagedPack(code) }
                chapters.insert("\(code).\(chapter.n)")
                for (number, text) in zip(chapter.v, chapter.t).sorted(by: { $0.0 < $1.0 }) where number > 0 {
                    let hit = ScriptureSearchHit(bookCode: code, bookName: book.name, chapter: chapter.n, verse: number, text: text)
                    let index = hits.count
                    guard verseIDs.insert(hit.id).inserted else { throw BibleSearchError.damagedPack(code) }
                    hits.append(hit)
                    for word in Set(BibleSearchParser.words(text)) { postings[word, default: []].insert(index) }
                    if index.isMultiple(of: 256) { try Task.checkCancellation() }
                }
            }
        }
        let result = Corpus(source: source, hits: hits, postings: postings, verseIDs: verseIDs, chapters: chapters)
        corpus = result
        return result
    }

    private func validate(_ anchor: Anchor, in corpus: Corpus) throws {
        guard anchor.isValid,
              corpus.chapters.contains("\(anchor.book).\(anchor.chapterStart)"),
              corpus.chapters.contains("\(anchor.book).\(anchor.chapterEnd)"),
              anchor.verseStart == 0 || corpus.verseIDs.contains("\(anchor.book).\(anchor.chapterStart).\(anchor.verseStart)"),
              anchor.verseEnd == Anchor.endOfChapter || corpus.verseIDs.contains("\(anchor.book).\(anchor.chapterEnd).\(anchor.verseEnd)") else {
            throw BibleSearchError.invalidPassage
        }
    }

    private func evaluate(_ expression: BibleSearchExpression, in corpus: Corpus, universe: Set<Int>) throws -> Set<Int> {
        try Task.checkCancellation()
        switch expression {
        case .term(let word): return (corpus.postings[word] ?? []).intersection(universe)
        case .prefix(let prefix):
            var result: Set<Int> = []
            for (word, matches) in corpus.postings where word.hasPrefix(prefix) {
                try Task.checkCancellation(); result.formUnion(matches)
            }
            return result.intersection(universe)
        case .phrase(let words):
            var candidates = universe
            for word in Set(words) { candidates.formIntersection(corpus.postings[word] ?? []) }
            var result: Set<Int> = []
            for index in candidates {
                try Task.checkCancellation()
                let tokens = BibleSearchParser.words(corpus.hits[index].text)
                guard tokens.count >= words.count else { continue }
                if (0...(tokens.count - words.count)).contains(where: { Array(tokens[$0..<($0 + words.count)]) == words }) {
                    result.insert(index)
                }
            }
            return result
        case .and(let lhs, let rhs): return try evaluate(lhs, in: corpus, universe: universe).intersection(evaluate(rhs, in: corpus, universe: universe))
        case .or(let lhs, let rhs): return try evaluate(lhs, in: corpus, universe: universe).union(evaluate(rhs, in: corpus, universe: universe))
        case .not(let operand): return try universe.subtracting(evaluate(operand, in: corpus, universe: universe))
        }
    }
}
