import Foundation
import StudyTableCore

// MARK: - Book table (versification-free facts about the 66-book canon)

/// One canonical book: display name, OSIS id, chapter count, and every spelling the parser accepts.
struct BookInfo: Sendable {
    let code: String            // USFM code, same as `Canon.bookCodes` ("ROM", "1CO", "SNG")
    let name: String            // display name ("Romans", "1 Corinthians", "Song of Solomon")
    let osis: String            // OSIS book id ("Rom", "1Cor", "Song")
    let chapters: Int
    let index: Int              // canonical position, 0-based
    var isSingleChapter: Bool { chapters == 1 }
}

enum BookTable {
    /// (code, base name, OSIS, chapters, base aliases). For numbered books (`1SA`…) the number
    /// prefix is added to the display name and every alias ("1 cor", "1cor", "i cor", "first cor").
    private static let rows: [(String, String, String, Int, String)] = [
        ("GEN", "Genesis", "Gen", 50, "gen|ge|gn"),
        ("EXO", "Exodus", "Exod", 40, "exod|ex|exo"),
        ("LEV", "Leviticus", "Lev", 27, "lev|le|lv"),
        ("NUM", "Numbers", "Num", 36, "num|nu|nm|nb"),
        ("DEU", "Deuteronomy", "Deut", 34, "deut|dt|de|deu"),
        ("JOS", "Joshua", "Josh", 24, "josh|jos|jsh"),
        ("JDG", "Judges", "Judg", 21, "judg|jdg|jg|jdgs"),
        ("RUT", "Ruth", "Ruth", 4, "rut|ru"),
        ("1SA", "Samuel", "1Sam", 31, "sam|sa|sm"),
        ("2SA", "Samuel", "2Sam", 24, "sam|sa|sm"),
        ("1KI", "Kings", "1Kgs", 22, "kgs|ki|kin"),
        ("2KI", "Kings", "2Kgs", 25, "kgs|ki|kin"),
        ("1CH", "Chronicles", "1Chr", 29, "chron|chr|ch"),
        ("2CH", "Chronicles", "2Chr", 36, "chron|chr|ch"),
        ("EZR", "Ezra", "Ezra", 10, "ezr"),
        ("NEH", "Nehemiah", "Neh", 13, "neh|ne"),
        ("EST", "Esther", "Esth", 10, "esth|est|es"),
        ("JOB", "Job", "Job", 42, "jb"),
        ("PSA", "Psalms", "Ps", 150, "psalm|ps|psa|pss|psm|pslm"),
        ("PRO", "Proverbs", "Prov", 31, "prov|pro|prv|pr"),
        ("ECC", "Ecclesiastes", "Eccl", 12, "eccl|ecc|eccles|qoh|ec"),
        ("SNG", "Song of Solomon", "Song", 8, "song|song of songs|songs|sos|ss|sg|canticles|song of sol"),
        ("ISA", "Isaiah", "Isa", 66, "isa|is"),
        ("JER", "Jeremiah", "Jer", 52, "jer|je"),
        ("LAM", "Lamentations", "Lam", 5, "lam|la"),
        ("EZK", "Ezekiel", "Ezek", 48, "ezek|eze|ezk"),
        ("DAN", "Daniel", "Dan", 12, "dan|da|dn"),
        ("HOS", "Hosea", "Hos", 14, "hos|ho"),
        ("JOL", "Joel", "Joel", 3, "joe|jl"),
        ("AMO", "Amos", "Amos", 9, "am"),
        ("OBA", "Obadiah", "Obad", 1, "obad|oba|ob"),
        ("JON", "Jonah", "Jonah", 4, "jon|jnh"),
        ("MIC", "Micah", "Mic", 7, "mic|mc"),
        ("NAM", "Nahum", "Nah", 3, "nah|na|nam"),
        ("HAB", "Habakkuk", "Hab", 3, "hab|hb"),
        ("ZEP", "Zephaniah", "Zeph", 3, "zeph|zep|zp"),
        ("HAG", "Haggai", "Hag", 2, "hag|hg"),
        ("ZEC", "Zechariah", "Zech", 14, "zech|zec|zc"),
        ("MAL", "Malachi", "Mal", 4, "mal|ml"),
        ("MAT", "Matthew", "Matt", 28, "matt|mat|mt"),
        ("MRK", "Mark", "Mark", 16, "mrk|mk|mr"),
        ("LUK", "Luke", "Luke", 24, "luk|lk"),
        ("JHN", "John", "John", 21, "jhn|jn"),
        ("ACT", "Acts", "Acts", 28, "act|ac"),
        ("ROM", "Romans", "Rom", 16, "rom|ro|rm"),
        ("1CO", "Corinthians", "1Cor", 16, "cor|co"),
        ("2CO", "Corinthians", "2Cor", 13, "cor|co"),
        ("GAL", "Galatians", "Gal", 6, "gal|ga"),
        ("EPH", "Ephesians", "Eph", 6, "eph|ephes"),
        ("PHP", "Philippians", "Phil", 4, "phil|php|pp|philip"),
        ("COL", "Colossians", "Col", 4, "col"),
        ("1TH", "Thessalonians", "1Thess", 5, "thess|thes|th"),
        ("2TH", "Thessalonians", "2Thess", 3, "thess|thes|th"),
        ("1TI", "Timothy", "1Tim", 6, "tim|ti"),
        ("2TI", "Timothy", "2Tim", 4, "tim|ti"),
        ("TIT", "Titus", "Titus", 3, "tit"),
        ("PHM", "Philemon", "Phlm", 1, "phlm|phm|philem"),
        ("HEB", "Hebrews", "Heb", 13, "heb"),
        ("JAS", "James", "Jas", 5, "jas|jm"),
        ("1PE", "Peter", "1Pet", 5, "pet|pe|pt"),
        ("2PE", "Peter", "2Pet", 3, "pet|pe|pt"),
        ("1JN", "John", "1John", 5, "jn|jhn"),
        ("2JN", "John", "2John", 1, "jn|jhn"),
        ("3JN", "John", "3John", 1, "jn|jhn"),
        ("JUD", "Jude", "Jude", 1, "jud|jd"),
        ("REV", "Revelation", "Rev", 22, "re|revelations|the revelation|apocalypse")
    ]

    static let all: [BookInfo] = rows.enumerated().map { index, row in
        let prefix = row.0.first.flatMap { $0.isNumber ? String($0) : nil }
        let name = prefix.map { "\($0) \(row.1)" } ?? row.1
        return BookInfo(code: row.0, name: name, osis: row.2, chapters: row.3, index: index)
    }
    static let byCode: [String: BookInfo] = Dictionary(uniqueKeysWithValues: all.map { ($0.code, $0) })
    private static let byOSIS: [String: BookInfo] = Dictionary(uniqueKeysWithValues: all.map { ($0.osis.lowercased(), $0) })

    /// Aliases claimed by two different books (must stay empty; a test asserts it).
    static var aliasCollisions: [String] { aliasBuild.collisions }
    private static var aliasList: [(alias: String, book: BookInfo)] { aliasBuild.list }

    /// alias (lowercased, no periods, single spaces) → book, longest alias first for prefix matching.
    private static let aliasBuild: (list: [(alias: String, book: BookInfo)], collisions: [String]) = {
        var pairs: [String: BookInfo] = [:]
        var collisions: [String] = []
        func claim(_ alias: String, _ info: BookInfo) {
            if let existing = pairs[alias], existing.code != info.code { collisions.append(alias) }
            pairs[alias] = info
        }
        let romans = ["1": "i", "2": "ii", "3": "iii"], ordinals = ["1": "first", "2": "second", "3": "third"]
        let suffixes = ["1": "1st", "2": "2nd", "3": "3rd"]
        for (info, row) in zip(all, rows) {
            var bases = row.4.split(separator: "|").map(String.init) + [row.1.lowercased()]
            if info.code == "PSA" { bases.append("psalms") }
            if let n = row.0.first.flatMap({ $0.isNumber ? String($0) : nil }) {
                for base in bases {
                    for prefix in [n, romans[n]!, ordinals[n]!, suffixes[n]!] {
                        claim("\(prefix) \(base)", info)
                        if prefix == n || prefix == suffixes[n]! { claim("\(prefix)\(base)", info) }
                    }
                }
            } else {
                for base in bases { claim(base, info) }
            }
            claim(info.name.lowercased(), info)
            claim(info.osis.lowercased(), info)
        }
        return (pairs.map { ($0.key, $0.value) }.sorted { $0.0.count > $1.0.count }, collisions)
    }()

    static func info(code: String) -> BookInfo? { byCode[code] }
    static func info(osis: String) -> BookInfo? { byOSIS[osis.lowercased()] }

    /// Splits "1 Cor 13:4–7" into the book and the remainder ("13:4-7"); nil when no book leads.
    static func splitReference(_ text: String) -> (book: BookInfo, remainder: String)? {
        let s = normalizeReference(text)
        for (alias, book) in aliasList {
            guard s.hasPrefix(alias) else { continue }
            let rest = s.dropFirst(alias.count)
            if rest.isEmpty { return (book, "") }
            if let first = rest.first, first == " " || first.isNumber { return (book, String(rest).trimmingCharacters(in: .whitespaces)) }
        }
        return nil
    }

    /// Lowercase, en/em dashes → "-", periods dropped, whitespace collapsed.
    static func normalizeReference(_ text: String) -> String {
        var s = text.lowercased()
        for dash in ["\u{2013}", "\u{2014}", "\u{2012}", "\u{2212}", "\u{2011}"] { s = s.replacingOccurrences(of: dash, with: "-") }
        s = s.replacingOccurrences(of: ".", with: "")
        return s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }
}

// MARK: - Anchor

/// A word inside an anchored verse (for word-study notes): position in the interlinear plus Strong's.
struct WordRef: Codable, Hashable, Sendable {
    var index: Int
    var strong: String?
}

/// A place in Scripture, in **BSB versification**, stored as references — never Scripture text.
///
/// Positions are `(chapter, verse)` pairs. Verse `0` is the unnumbered superscription; verse
/// `Anchor.endOfChapter` (999) means "to the end of the chapter", so a whole chapter is
/// `(c, 0)…(c, 999)` and a whole book is `(1, 0)…(lastChapter, 999)`. Because everything is one
/// comparable position range, overlap/containment need no special cases.
struct Anchor: Codable, Hashable, Sendable, Comparable {
    static let endOfChapter = 999

    var book: String            // USFM code, e.g. "ROM"
    var chapterStart: Int
    var verseStart: Int
    var chapterEnd: Int
    var verseEnd: Int
    var word: WordRef?

    init(book: String, chapterStart: Int, verseStart: Int, chapterEnd: Int, verseEnd: Int, word: WordRef? = nil) {
        self.book = book
        self.chapterStart = chapterStart; self.verseStart = verseStart
        self.chapterEnd = chapterEnd; self.verseEnd = verseEnd
        self.word = word
        normalizeOrder()
    }

    /// A single verse.
    init(book: String, chapter: Int, verse: Int, word: WordRef? = nil) {
        self.init(book: book, chapterStart: chapter, verseStart: verse, chapterEnd: chapter, verseEnd: verse, word: word)
    }

    /// Verses `from...to` inside one chapter.
    init(book: String, chapter: Int, verses from: Int, to: Int) {
        self.init(book: book, chapterStart: chapter, verseStart: from, chapterEnd: chapter, verseEnd: to)
    }

    /// One or more whole chapters.
    init(book: String, chapter: Int, throughChapter last: Int? = nil) {
        self.init(book: book, chapterStart: chapter, verseStart: 0, chapterEnd: last ?? chapter, verseEnd: Anchor.endOfChapter)
    }

    /// The whole book.
    static func wholeBook(_ code: String) -> Anchor {
        Anchor(book: code, chapter: 1, throughChapter: BookTable.info(code: code)?.chapters ?? 1)
    }

    // Tolerant decoding: never throws on a wrong-typed or missing field (an unknown book decodes
    // as an invalid anchor that queries ignore rather than dropping the note that carries it).
    private enum CodingKeys: String, CodingKey { case book, chapterStart, verseStart, chapterEnd, verseEnd, word }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        book = c.lenient(String.self, .book) ?? ""
        chapterStart = c.lenient(Int.self, .chapterStart) ?? 1
        verseStart = c.lenient(Int.self, .verseStart) ?? 0
        chapterEnd = c.lenient(Int.self, .chapterEnd) ?? chapterStart
        verseEnd = c.lenient(Int.self, .verseEnd) ?? (c.lenient(Int.self, .verseStart) ?? Anchor.endOfChapter)
        word = c.lenient(WordRef.self, .word)
        normalizeOrder()
    }

    private mutating func normalizeOrder() {
        if startKey > endKey { swap(&chapterStart, &chapterEnd); swap(&verseStart, &verseEnd) }
    }

    // MARK: Position arithmetic

    var startKey: Int { chapterStart * 1000 + verseStart }
    var endKey: Int { chapterEnd * 1000 + verseEnd }
    var bookInfo: BookInfo? { BookTable.info(code: book) }
    var isValid: Bool { bookInfo != nil && chapterStart >= 1 && verseStart >= 0 && verseEnd <= Anchor.endOfChapter }

    var isSingleVerse: Bool { chapterStart == chapterEnd && verseStart == verseEnd && verseStart != Anchor.endOfChapter }
    var isWholeChapters: Bool { verseStart == 0 && verseEnd == Anchor.endOfChapter }
    var isWholeBook: Bool { isWholeChapters && chapterStart == 1 && chapterEnd == (bookInfo?.chapters ?? -1) }
    var spansChapters: Bool { chapterStart != chapterEnd }

    /// The first verse (or first verse of the first chapter for a whole-chapter anchor) — the
    /// navigation target. A superscription start (verse 0) lands on verse 1.
    var startVerse: (chapter: Int, verse: Int) { (chapterStart, max(verseStart, 1)) }

    /// Same passage, ignoring any word reference.
    func sameSpan(as other: Anchor) -> Bool {
        book == other.book && startKey == other.startKey && endKey == other.endKey
    }

    func overlaps(_ other: Anchor) -> Bool {
        book == other.book && isValid && other.isValid && startKey <= other.endKey && other.startKey <= endKey
    }

    func contains(_ other: Anchor) -> Bool {
        book == other.book && startKey <= other.startKey && other.endKey <= endKey
    }

    func contains(chapter: Int, verse: Int) -> Bool {
        let key = chapter * 1000 + verse
        return startKey <= key && key <= endKey
    }

    static func < (lhs: Anchor, rhs: Anchor) -> Bool {
        let l = lhs.bookInfo?.index ?? Int.max, r = rhs.bookInfo?.index ?? Int.max
        if l != r { return l < r }
        if lhs.startKey != rhs.startKey { return lhs.startKey < rhs.startKey }
        return lhs.endKey < rhs.endKey
    }

    // MARK: Display

    /// "Romans 8:28", "Romans 8:28–39", "Romans 8:39–9:5", "Romans 8", "Romans 8–9", "Romans",
    /// "Psalm 23", "Song of Solomon 2:1" (en dash; "Psalm" singular for one chapter).
    var displayString: String {
        guard let info = bookInfo else { return book.isEmpty ? "Unknown passage" : book }
        var name = info.name
        if info.code == "PSA" && !(isWholeBook || spansChapters) { name = "Psalm" }
        if isWholeBook { return name }
        let dash = "\u{2013}"
        if isWholeChapters {
            return chapterStart == chapterEnd ? "\(name) \(chapterStart)" : "\(name) \(chapterStart)\(dash)\(chapterEnd)"
        }
        if chapterStart == chapterEnd {
            return verseStart == verseEnd ? "\(name) \(chapterStart):\(verseStart)" : "\(name) \(chapterStart):\(verseStart)\(dash)\(verseEnd)"
        }
        return "\(name) \(chapterStart):\(verseStart)\(dash)\(chapterEnd):\(verseEnd)"
    }

    /// OSIS reference: "Rom.8.28", "Rom.8.28-Rom.8.39", "Rom.8", "Rom.8-Rom.9", "Rom".
    var osis: String {
        guard let info = bookInfo else { return book }
        if isWholeBook { return info.osis }
        func point(_ c: Int, _ v: Int?) -> String { v.map { "\(info.osis).\(c).\($0)" } ?? "\(info.osis).\(c)" }
        if isWholeChapters { return chapterStart == chapterEnd ? point(chapterStart, nil) : "\(point(chapterStart, nil))-\(point(chapterEnd, nil))" }
        return startKey == endKey ? point(chapterStart, verseStart) : "\(point(chapterStart, verseStart))-\(point(chapterEnd, verseEnd))"
    }

    // MARK: Parsing

    /// Parses a display string ("Romans 8:28–39", "1 Cor 13", "Psalm 23", "Song 2:1",
    /// "Romans 8:39–9:5"). Returns nil for anything that is not exactly one contiguous passage.
    static func parse(_ text: String) -> Anchor? {
        guard let (book, remainder) = BookTable.splitReference(text) else { return nil }
        if remainder.isEmpty { return .wholeBook(book.code) }
        let rem = remainder.filter { !$0.isWhitespace }
        guard rem.allSatisfy({ $0.isNumber && $0.isASCII || $0 == ":" || $0 == "-" }) else { return nil }
        let halves = rem.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard halves.count <= 2, halves.allSatisfy({ !$0.isEmpty }) else { return nil }
        // A reversed range is a typo, not a request to swap silently.
        func pair(_ s: String) -> (Int, Int)? {
            let parts = s.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
            guard parts.count == 2, let c = Int(parts[0]), let v = Int(parts[1]) else { return nil }
            return (c, v)
        }
        func chapterOK(_ c: Int) -> Bool { c >= 1 && c <= book.chapters }
        func verseOK(_ v: Int) -> Bool { v >= 0 && v < Anchor.endOfChapter }

        let anchor: Anchor
        if !rem.contains(":") {
            // Bare numbers: chapters ("8", "8-9") — or verses when the book has a single chapter.
            guard let a = Int(halves[0]), halves.count == 1 || Int(halves[1]) != nil else { return nil }
            let b = halves.count == 2 ? Int(halves[1])! : a
            guard a <= b else { return nil }
            if book.isSingleChapter {
                anchor = Anchor(book: book.code, chapter: 1, verses: a, to: b)
                guard verseOK(a), verseOK(b) else { return nil }
            } else {
                guard chapterOK(a), chapterOK(b) else { return nil }
                anchor = Anchor(book: book.code, chapter: a, throughChapter: b)
            }
        } else {
            guard let (c1, v1) = pair(halves[0]) else { return nil }
            var c2 = c1, v2 = v1
            if halves.count == 2 {
                if let (c, v) = pair(halves[1]) { c2 = c; v2 = v }
                else if let v = Int(halves[1]) { v2 = v }
                else { return nil }
            }
            guard chapterOK(c1), chapterOK(c2), verseOK(v1), verseOK(v2), c1 * 1000 + v1 <= c2 * 1000 + v2 else { return nil }
            anchor = Anchor(book: book.code, chapterStart: c1, verseStart: v1, chapterEnd: c2, verseEnd: v2)
        }
        return anchor
    }

    /// Parses an OSIS reference ("Rom.8.28", "Rom.8.28-Rom.8.39", "Rom.8", "Rom").
    init?(osis text: String) {
        let halves = text.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
        guard (1...2).contains(halves.count) else { return nil }
        func parts(_ s: String) -> (BookInfo?, [Int])? {
            let comps = s.split(separator: ".", omittingEmptySubsequences: false).map(String.init)
            var book: BookInfo?
            var numbers: [Int] = []
            for (i, comp) in comps.enumerated() {
                if i == 0, Int(comp) == nil { guard let b = BookTable.info(osis: comp) else { return nil }; book = b }
                else { guard let n = Int(comp) else { return nil }; numbers.append(n) }
            }
            return (book, numbers)
        }
        guard let first = parts(halves[0]), let book = first.0, first.1.count <= 2 else { return nil }
        let startNums = first.1
        var endBook = book
        var endNums = startNums
        if halves.count == 2 {
            guard let second = parts(halves[1]) else { return nil }
            if let b = second.0 { endBook = b }
            endNums = second.1
            if second.0 == nil, endNums.count == 1, startNums.count == 2 { endNums = [startNums[0], endNums[0]] }  // Rom.8.28-39
        }
        guard endBook.code == book.code else { return nil }
        func position(_ nums: [Int], isEnd: Bool) -> (Int, Int)? {
            switch nums.count {
            case 0: return isEnd ? (book.chapters, Anchor.endOfChapter) : (1, 0)
            case 1: return (nums[0], isEnd ? Anchor.endOfChapter : 0)
            default: return (nums[0], nums[1])
            }
        }
        guard let s = position(startNums, isEnd: false), let e = position(endNums, isEnd: true) else { return nil }
        guard s.0 >= 1, e.0 <= book.chapters, s.0 * 1000 + s.1 <= e.0 * 1000 + e.1 else { return nil }
        self.init(book: book.code, chapterStart: s.0, verseStart: s.1, chapterEnd: e.0, verseEnd: e.1)
    }
}

// MARK: - Lenient decoding helpers

/// Advances an unkeyed container past an element of any shape.
private struct Skip: Decodable { init(from decoder: Decoder) throws {} }

extension KeyedDecodingContainer {
    /// Decodes `key` as `T`, or returns nil when absent **or of the wrong type** — a damaged
    /// field must never fail the whole record (PASTOR-QA defect 1).
    func lenient<T: Decodable>(_ type: T.Type, _ key: Key) -> T? {
        (try? decodeIfPresent(type, forKey: key)) ?? nil
    }

    /// Accepts Foundation's default numeric `Date` (v1 files), or an ISO-8601 string.
    func lenientDate(_ key: Key) -> Date? {
        if let seconds = (try? decodeIfPresent(Double.self, forKey: key)) ?? nil { return Date(timeIntervalSinceReferenceDate: seconds) }
        if let text = (try? decodeIfPresent(String.self, forKey: key)) ?? nil {
            return (try? Date(text, strategy: Date.ISO8601FormatStyle(includingFractionalSeconds: true)))
                ?? (try? Date(text, strategy: .iso8601))
        }
        return nil
    }

    /// Decodes an array element by element; elements that fail to decode are skipped and counted.
    func lossyArray<T: Decodable>(_ type: T.Type, _ key: Key, skipped: inout Int) -> [T] {
        guard var list = try? nestedUnkeyedContainer(forKey: key) else { return [] }
        var result: [T] = []
        while !list.isAtEnd {
            if let item = try? list.decode(T.self) { result.append(item) }
            else { skipped += 1; _ = try? list.decode(Skip.self) }
        }
        return result
    }

    func lossyArray<T: Decodable>(_ type: T.Type, _ key: Key) -> [T] {
        var ignored = 0
        return lossyArray(type, key, skipped: &ignored)
    }
}

extension CodingUserInfoKey {
    /// `Date` used when a record carries no usable timestamp at all (the store injects its clock).
    static let studyFallbackDate = CodingUserInfoKey(rawValue: "studyFallbackDate")!
}

private func fallbackDate(_ decoder: Decoder) -> Date {
    (decoder.userInfo[.studyFallbackDate] as? Date) ?? Date(timeIntervalSinceReferenceDate: 0)
}

// MARK: - Notes

enum NoteKind: String, Codable, CaseIterable, Sendable {
    case free, oia, wordStudy, sermonIdea
}

struct NoteSection: Codable, Hashable, Sendable {
    var key: String             // template slot, e.g. "observation", "interpretation", "application"
    var text: String

    init(key: String, text: String) { self.key = key; self.text = text }
    private enum CodingKeys: String, CodingKey { case key, text }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = c.lenient(String.self, .key) ?? ""
        text = c.lenient(String.self, .text) ?? ""
    }
}

/// A study note. `modifiedAt` changes only when content changes (the store enforces this).
struct Note: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var anchors: [Anchor]
    /// Verbatim v1 `passage` string that could not be parsed into an `Anchor` (kept, never dropped).
    var legacyPassage: String?
    var title: String
    var kind: NoteKind
    var sections: [NoteSection]
    /// Free-text body — the whole note for `.free`/legacy notes.
    var body: String
    var clipIDs: [UUID]
    var tags: [String]
    var createdAt: Date
    var modifiedAt: Date
    var deletedAt: Date?

    init(id: UUID = UUID(), anchors: [Anchor] = [], legacyPassage: String? = nil, title: String = "",
         kind: NoteKind = .free, sections: [NoteSection] = [], body: String = "", clipIDs: [UUID] = [],
         tags: [String] = [], createdAt: Date, modifiedAt: Date? = nil, deletedAt: Date? = nil) {
        self.id = id; self.anchors = anchors; self.legacyPassage = legacyPassage; self.title = title
        self.kind = kind; self.sections = sections; self.body = body; self.clipIDs = clipIDs
        self.tags = StudyTag.normalized(tags); self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt; self.deletedAt = deletedAt
    }

    private enum CodingKeys: String, CodingKey {
        case id, anchors, legacyPassage, title, kind, sections, body, clipIDs, tags, createdAt, modifiedAt, deletedAt
    }
    private enum V1Keys: String, CodingKey { case passage }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(UUID.self, .id) ?? UUID()
        anchors = c.lossyArray(Anchor.self, .anchors)
        legacyPassage = c.lenient(String.self, .legacyPassage)
        title = c.lenient(String.self, .title) ?? ""
        kind = c.lenient(NoteKind.self, .kind) ?? .free
        sections = c.lossyArray(NoteSection.self, .sections)
        body = c.lenient(String.self, .body) ?? ""
        clipIDs = c.lossyArray(UUID.self, .clipIDs)
        tags = StudyTag.normalized(c.lossyArray(String.self, .tags))
        let created = c.lenientDate(.createdAt), modified = c.lenientDate(.modifiedAt)
        let fallback = fallbackDate(decoder)
        createdAt = created ?? modified ?? fallback
        modifiedAt = modified ?? created ?? fallback
        deletedAt = c.lenientDate(.deletedAt)
        // A hand-edited or v1-shaped record may still carry `passage`; keep it rather than lose it.
        if anchors.isEmpty, legacyPassage == nil,
           let passage = (try? decoder.container(keyedBy: V1Keys.self))?.lenient(String.self, .passage) {
            if let parsed = Anchor.parse(passage) { anchors = [parsed] } else { legacyPassage = passage }
        }
    }

    /// All of the note's text, for search and emptiness checks.
    var plainText: String { ([body] + sections.map(\.text)).joined(separator: "\n") }
    var hasContent: Bool { !plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !clipIDs.isEmpty }
    var isDeleted: Bool { deletedAt != nil }

    /// "Romans 8:28" / "Romans 8:28; John 3:16" / the verbatim legacy string / "".
    var referenceLabel: String {
        if !anchors.isEmpty { return anchors.map(\.displayString).joined(separator: "; ") }
        return legacyPassage ?? ""
    }
}

// MARK: - Saved passages, collections, clips, projects

enum HighlightColor: String, Codable, CaseIterable, Sendable {
    case yellow, green, blue, pink, orange, purple
}

struct SavedPassage: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var anchor: Anchor
    var highlight: HighlightColor?
    var isMemory: Bool
    var tags: [String]
    var collectionIDs: [UUID]
    var createdAt: Date
    var deletedAt: Date?

    init(id: UUID = UUID(), anchor: Anchor, highlight: HighlightColor? = nil, isMemory: Bool = false,
         tags: [String] = [], collectionIDs: [UUID] = [], createdAt: Date, deletedAt: Date? = nil) {
        self.id = id; self.anchor = anchor; self.highlight = highlight; self.isMemory = isMemory
        self.tags = StudyTag.normalized(tags); self.collectionIDs = collectionIDs
        self.createdAt = createdAt; self.deletedAt = deletedAt
    }

    private enum CodingKeys: String, CodingKey { case id, anchor, highlight, isMemory, tags, collectionIDs, createdAt, deletedAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(UUID.self, .id) ?? UUID()
        anchor = c.lenient(Anchor.self, .anchor) ?? Anchor(book: "", chapter: 1, verse: 0)
        highlight = c.lenient(HighlightColor.self, .highlight)
        isMemory = c.lenient(Bool.self, .isMemory) ?? false
        tags = StudyTag.normalized(c.lossyArray(String.self, .tags))
        collectionIDs = c.lossyArray(UUID.self, .collectionIDs)
        createdAt = c.lenientDate(.createdAt) ?? fallbackDate(decoder)
        deletedAt = c.lenientDate(.deletedAt)
    }
    var isDeleted: Bool { deletedAt != nil }
}

struct StudyCollection: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var name: String
    /// Saved-passage ids in the user's chosen order; members not listed sort after, by date.
    var order: [UUID]
    var color: String?
    var glyph: String?
    var createdAt: Date

    init(id: UUID = UUID(), name: String, order: [UUID] = [], color: String? = nil, glyph: String? = nil, createdAt: Date) {
        self.id = id; self.name = name; self.order = order; self.color = color; self.glyph = glyph; self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey { case id, name, order, color, glyph, createdAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(UUID.self, .id) ?? UUID()
        name = c.lenient(String.self, .name) ?? "Untitled collection"
        order = c.lossyArray(UUID.self, .order)
        color = c.lenient(String.self, .color)
        glyph = c.lenient(String.self, .glyph)
        createdAt = c.lenientDate(.createdAt) ?? fallbackDate(decoder)
    }
}

enum ClipKind: String, Codable, CaseIterable, Sendable {
    case commentary, wordStudy, crossReference, confession, dictionary, other
}

/// Where a clipped excerpt came from. The excerpt is stored with its citation because a
/// `sourceEntryID` can change when the corpus is rebuilt.
struct ClipCitation: Codable, Hashable, Sendable {
    var author: String
    var work: String
    var era: String?
    var sourceEntryID: String?
    var sourceURL: String?
    var licence: String?
    var scope: String?

    init(author: String = "", work: String = "", era: String? = nil, sourceEntryID: String? = nil,
         sourceURL: String? = nil, licence: String? = nil, scope: String? = nil) {
        self.author = author; self.work = work; self.era = era; self.sourceEntryID = sourceEntryID
        self.sourceURL = sourceURL; self.licence = licence; self.scope = scope
    }

    private enum CodingKeys: String, CodingKey { case author, work, era, sourceEntryID, sourceURL, licence, scope }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        author = c.lenient(String.self, .author) ?? ""
        work = c.lenient(String.self, .work) ?? ""
        era = c.lenient(String.self, .era)
        sourceEntryID = c.lenient(String.self, .sourceEntryID)
        sourceURL = c.lenient(String.self, .sourceURL)
        licence = c.lenient(String.self, .licence)
        scope = c.lenient(String.self, .scope)
    }
}

struct Clip: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var kind: ClipKind
    var excerpt: String
    var citation: ClipCitation
    var anchor: Anchor?
    var capturedAt: Date

    init(id: UUID = UUID(), kind: ClipKind = .other, excerpt: String, citation: ClipCitation = ClipCitation(),
         anchor: Anchor? = nil, capturedAt: Date) {
        self.id = id; self.kind = kind; self.excerpt = excerpt; self.citation = citation
        self.anchor = anchor; self.capturedAt = capturedAt
    }

    private enum CodingKeys: String, CodingKey { case id, kind, excerpt, citation, anchor, capturedAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(UUID.self, .id) ?? UUID()
        kind = c.lenient(ClipKind.self, .kind) ?? .other
        excerpt = c.lenient(String.self, .excerpt) ?? ""
        citation = c.lenient(ClipCitation.self, .citation) ?? ClipCitation()
        anchor = c.lenient(Anchor.self, .anchor)
        capturedAt = c.lenientDate(.capturedAt) ?? fallbackDate(decoder)
    }
}

/// One node of a project outline. `itemRefs` point at notes/saved passages/clips by id.
struct OutlineNode: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var text: String
    var children: [OutlineNode]
    var itemRefs: [UUID]

    init(id: UUID = UUID(), title: String, text: String = "", children: [OutlineNode] = [], itemRefs: [UUID] = []) {
        self.id = id; self.title = title; self.text = text; self.children = children; self.itemRefs = itemRefs
    }

    private enum CodingKeys: String, CodingKey { case id, title, text, children, itemRefs }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(UUID.self, .id) ?? UUID()
        title = c.lenient(String.self, .title) ?? ""
        text = c.lenient(String.self, .text) ?? ""
        children = c.lossyArray(OutlineNode.self, .children)
        itemRefs = c.lossyArray(UUID.self, .itemRefs)
    }
}

enum ProjectKind: String, Codable, CaseIterable, Sendable {
    case sermon, lesson, topical, studyGuide, other
}

enum ProjectStatus: String, Codable, CaseIterable, Sendable {
    case idea, drafting, ready, archived
}

/// Types + persistence only in 0.10 wave A; the outline UI arrives later.
struct StudyProject: Identifiable, Codable, Hashable, Sendable {
    var id: UUID
    var title: String
    var kind: ProjectKind
    var primaryAnchor: Anchor?
    var outline: [OutlineNode]
    var status: ProjectStatus
    var createdAt: Date
    var modifiedAt: Date

    init(id: UUID = UUID(), title: String, kind: ProjectKind = .sermon, primaryAnchor: Anchor? = nil,
         outline: [OutlineNode] = [], status: ProjectStatus = .idea, createdAt: Date, modifiedAt: Date? = nil) {
        self.id = id; self.title = title; self.kind = kind; self.primaryAnchor = primaryAnchor
        self.outline = outline; self.status = status; self.createdAt = createdAt; self.modifiedAt = modifiedAt ?? createdAt
    }

    private enum CodingKeys: String, CodingKey { case id, title, kind, primaryAnchor, outline, status, createdAt, modifiedAt }
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.lenient(UUID.self, .id) ?? UUID()
        title = c.lenient(String.self, .title) ?? "Untitled project"
        kind = c.lenient(ProjectKind.self, .kind) ?? .other
        primaryAnchor = c.lenient(Anchor.self, .primaryAnchor)
        outline = c.lossyArray(OutlineNode.self, .outline)
        status = c.lenient(ProjectStatus.self, .status) ?? .idea
        let created = c.lenientDate(.createdAt), modified = c.lenientDate(.modifiedAt)
        createdAt = created ?? modified ?? fallbackDate(decoder)
        modifiedAt = modified ?? created ?? fallbackDate(decoder)
    }
}

// MARK: - Tags

enum StudyTag {
    /// Trims, strips a leading "#", collapses whitespace, drops empties and case-insensitive
    /// duplicates (first spelling wins).
    static func normalize(_ tag: String) -> String {
        var s = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.hasPrefix("#") { s.removeFirst() }
        return s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    static func normalized(_ tags: [String]) -> [String] {
        var seen = Set<String>(), result: [String] = []
        for tag in tags {
            let clean = normalize(tag)
            guard !clean.isEmpty, seen.insert(clean.lowercased()).inserted else { continue }
            result.append(clean)
        }
        return result
    }
}

// MARK: - Envelope

/// The whole `study.json` document: `{schema, notes, saved, collections, projects, clips}`.
struct StudyEnvelope: Codable, Equatable, Sendable {
    static let currentSchema = 2

    var schema: Int = StudyEnvelope.currentSchema
    var notes: [Note] = []
    var saved: [SavedPassage] = []
    var collections: [StudyCollection] = []
    var projects: [StudyProject] = []
    var clips: [Clip] = []

    init() {}

    /// Result of a tolerant decode: how many array elements were unusable and skipped.
    struct Decoded { var envelope: StudyEnvelope; var skipped: Int }

    private struct Wire: Decodable {
        let decoded: Decoded
        private enum CodingKeys: String, CodingKey { case schema, notes, saved, collections, projects, clips }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            var env = StudyEnvelope()
            var skipped = 0
            env.schema = c.lenient(Int.self, .schema) ?? StudyEnvelope.currentSchema
            env.notes = c.lossyArray(Note.self, .notes, skipped: &skipped)
            env.saved = c.lossyArray(SavedPassage.self, .saved, skipped: &skipped)
            env.collections = c.lossyArray(StudyCollection.self, .collections, skipped: &skipped)
            env.projects = c.lossyArray(StudyProject.self, .projects, skipped: &skipped)
            env.clips = c.lossyArray(Clip.self, .clips, skipped: &skipped)
            decoded = Decoded(envelope: env, skipped: skipped)
        }
    }

    /// Tolerant decode: unknown keys ignored, missing/wrong-typed fields defaulted, unusable
    /// array elements skipped and counted. Throws only when `data` is not a JSON object at all.
    static func decodeTolerant(_ data: Data, fallbackDate: Date) throws -> Decoded {
        let decoder = JSONDecoder()
        decoder.userInfo[.studyFallbackDate] = fallbackDate
        return try decoder.decode(Wire.self, from: data).decoded
    }

    static func encode(_ envelope: StudyEnvelope) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(envelope)
    }
}
