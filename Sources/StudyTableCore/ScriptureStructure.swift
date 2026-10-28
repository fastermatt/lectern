import Foundation

// MARK: - Structure carried by a Scripture pack (schema 2)
//
// USFM carries more than verse text: editorial section headings (`\s1`, `\s2`, `\ms1`, `\qa`),
// the parallel / quotation reference line that follows a heading (`\r`), and paragraph
// boundaries (`\p`, `\m`, `\b`, ...). Schema 2 keeps all three, keyed to the verse they precede.
// Verse text itself is never touched by any of this.

/// One reference from a heading's parallel line, e.g. "Matthew 8:23–27" in
/// `\r (Psalms 107:1–43; Matthew 8:23–27; Luke 8:22–25)`.
///
/// `chapter`/`verse` start the span, `endChapter`/`endVerse` finish it. `verse == 0` means "the
/// whole chapter" (start at its first verse); `endVerse == 0` means "through the last verse of
/// `endChapter`". `book` is nil when the source's book name could not be resolved (the `label`
/// is then all there is; the app shows it as inert text).
public struct ParallelReference: Codable, Sendable, Equatable, Hashable {
    /// The reference exactly as the source prints it ("Psalms 107:1–43").
    public let label: String
    /// USFM book code ("PSA"), or nil when unresolved.
    public let book: String?
    public let chapter: Int
    public let verse: Int
    public let endChapter: Int
    public let endVerse: Int

    public init(label: String, book: String?, chapter: Int, verse: Int, endChapter: Int, endVerse: Int) {
        self.label = label
        self.book = book
        self.chapter = chapter
        self.verse = verse
        self.endChapter = endChapter
        self.endVerse = endVerse
    }

    enum CodingKeys: String, CodingKey {
        case label = "l", book = "b", chapter = "c", verse = "v", endChapter = "ec", endVerse = "ev"
    }

    /// True when the reference points at real Scripture the reader can navigate to.
    public var isNavigable: Bool { book != nil && chapter > 0 }
}

/// An editorial section heading. `level`: 0 = major division (`\ms`, e.g. "BOOK I" over Psalms),
/// 1 = section (`\s`/`\s1`), 2 = subsection (`\s2`), 3 = acrostic stanza letter (`\qa`, Psalm 119)
/// and any deeper `\s3`+.
public struct SectionHeading: Codable, Sendable, Equatable, Hashable {
    /// The verse this heading precedes. 0 means it sits above the unnumbered superscription.
    public let verse: Int
    public let level: Int
    public let title: String
    /// A secondary line the source attaches to the heading (`\mr`, e.g. "Psalms 1—41").
    public let subtitle: String?
    /// The parallel / quotation references printed under the heading (`\r`).
    public let parallels: [ParallelReference]?

    public init(verse: Int, level: Int, title: String, subtitle: String? = nil, parallels: [ParallelReference]? = nil) {
        self.verse = verse
        self.level = level
        self.title = title
        self.subtitle = subtitle
        self.parallels = parallels
    }

    enum CodingKeys: String, CodingKey {
        case verse = "v", level = "l", title = "t", subtitle = "sub", parallels = "r"
    }
}

/// Counts reported by the pack builder so a rebuild can be checked against the source.
public struct StructureStats: Sendable, Equatable {
    public var headings = 0
    public var headingsByLevel: [Int: Int] = [:]
    public var parallelLines = 0
    public var parallelReferences = 0
    public var unresolvedReferences: [String] = []
    public var paragraphStarts = 0
    /// Headings the source places where no verse follows in the chapter, or in the middle of a
    /// verse. They are not kept (a heading must never point at the wrong verse).
    public var droppedHeadings: [String] = []
    public init() {}
}

// MARK: - Parallel reference parsing

public enum ParallelReferenceParser {
    /// English book names and common alternates → USFM codes.
    static let bookCodes: [String: String] = {
        let names: [(String, String)] = [
            ("Genesis", "GEN"), ("Exodus", "EXO"), ("Leviticus", "LEV"), ("Numbers", "NUM"), ("Deuteronomy", "DEU"),
            ("Joshua", "JOS"), ("Judges", "JDG"), ("Ruth", "RUT"), ("1 Samuel", "1SA"), ("2 Samuel", "2SA"),
            ("1 Kings", "1KI"), ("2 Kings", "2KI"), ("1 Chronicles", "1CH"), ("2 Chronicles", "2CH"),
            ("Ezra", "EZR"), ("Nehemiah", "NEH"), ("Esther", "EST"), ("Job", "JOB"), ("Psalms", "PSA"),
            ("Psalm", "PSA"), ("Proverbs", "PRO"), ("Ecclesiastes", "ECC"), ("Song of Solomon", "SNG"),
            ("Song of Songs", "SNG"), ("Song", "SNG"), ("Isaiah", "ISA"), ("Jeremiah", "JER"),
            ("Lamentations", "LAM"), ("Ezekiel", "EZK"), ("Daniel", "DAN"), ("Hosea", "HOS"), ("Joel", "JOL"),
            ("Amos", "AMO"), ("Obadiah", "OBA"), ("Jonah", "JON"), ("Micah", "MIC"), ("Nahum", "NAM"),
            ("Habakkuk", "HAB"), ("Zephaniah", "ZEP"), ("Haggai", "HAG"), ("Zechariah", "ZEC"), ("Malachi", "MAL"),
            ("Matthew", "MAT"), ("Mark", "MRK"), ("Luke", "LUK"), ("John", "JHN"), ("Acts", "ACT"),
            ("Romans", "ROM"), ("1 Corinthians", "1CO"), ("2 Corinthians", "2CO"), ("Galatians", "GAL"),
            ("Ephesians", "EPH"), ("Philippians", "PHP"), ("Colossians", "COL"), ("1 Thessalonians", "1TH"),
            ("2 Thessalonians", "2TH"), ("1 Timothy", "1TI"), ("2 Timothy", "2TI"), ("Titus", "TIT"),
            ("Philemon", "PHM"), ("Hebrews", "HEB"), ("James", "JAS"), ("1 Peter", "1PE"), ("2 Peter", "2PE"),
            ("1 John", "1JN"), ("2 John", "2JN"), ("3 John", "3JN"), ("Jude", "JUD"), ("Revelation", "REV")
        ]
        return Dictionary(names.map { ($0.0.lowercased(), $0.1) }, uniquingKeysWith: { first, _ in first })
    }()

    /// Books with a single chapter: a bare number after the name is a verse ("Jude 5–7").
    static let singleChapter: Set<String> = ["OBA", "PHM", "2JN", "3JN", "JUD"]

    /// Parses a `\r` line ("(Isaiah 40:1–5; Matthew 3:1–17)") into structured references.
    /// Every part is returned; parts whose book or numbers are not understood come back with
    /// `book == nil` so the label is still shown.
    public static func parse(_ line: String) -> [ParallelReference] {
        var text = line.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("("), text.hasSuffix(")") { text = String(text.dropFirst().dropLast()) }
        return text.split(separator: ";", omittingEmptySubsequences: true).compactMap { part in
            var item = part.trimmingCharacters(in: .whitespaces)
            if item.lowercased().hasPrefix("cf. ") { item = String(item.dropFirst(4)) }
            item = item.trimmingCharacters(in: CharacterSet(charactersIn: ". ").union(.whitespaces))
            return item.isEmpty ? nil : parseOne(item)
        }
    }

    public static func parseOne(_ item: String) -> ParallelReference {
        let unresolved = ParallelReference(label: item, book: nil, chapter: 0, verse: 0, endChapter: 0, endVerse: 0)
        // Split "1 Corinthians 15:3–8" at the last space: name = everything before, spec = after.
        guard let split = item.lastIndex(of: " ") else { return unresolved }
        let name = item[..<split].trimmingCharacters(in: .whitespaces).lowercased()
        let spec = String(item[item.index(after: split)...])
        guard let code = bookCodes[name] else { return unresolved }

        func number(_ value: Substring) -> Int? { Int(value.trimmingCharacters(in: .whitespaces)) }
        func rangeSplit(_ value: String) -> [Substring] {
            value.split(omittingEmptySubsequences: false, whereSeparator: { "\u{2013}\u{2014}-".contains($0) })
        }
        func ref(_ c: Int, _ v: Int, _ ec: Int, _ ev: Int) -> ParallelReference {
            ParallelReference(label: item, book: code, chapter: c, verse: v, endChapter: ec, endVerse: ev)
        }
        let halves = rangeSplit(spec)
        guard (1...2).contains(halves.count) else { return unresolved }

        // Chapter:verse forms.
        let firstParts = halves[0].split(separator: ":", omittingEmptySubsequences: false)
        if firstParts.count == 2, let c = number(firstParts[0]), let v = number(firstParts[1]) {
            if halves.count == 1 { return ref(c, v, c, v) }
            let second = halves[1].split(separator: ":", omittingEmptySubsequences: false)
            if second.count == 1, let ev = number(second[0]) { return ref(c, v, c, ev) }
            if second.count == 2, let ec = number(second[0]), let ev = number(second[1]) { return ref(c, v, ec, ev) }
            return unresolved
        }
        // Bare numbers: verses for a one-chapter book, otherwise whole chapters.
        guard firstParts.count == 1, let first = number(firstParts[0]) else { return unresolved }
        let last: Int
        if halves.count == 2 {
            guard let value = number(halves[1]) else { return unresolved }
            last = value
        } else { last = first }
        if singleChapter.contains(code) { return ref(1, first, 1, last) }
        return ref(first, 0, last, 0)
    }
}

// MARK: - Pericopes

/// A heading's span of Scripture, ready for range selection.
///
/// `startVerse`/`endVerse` are always real verse numbers (>= 1). A section may run across a
/// chapter boundary (`endChapter > startChapter`) when the next chapter opens without a heading.
/// `includesSuperscription` is true when the source heading sits above a psalm's unnumbered title
/// (verse 0), which `startVerse` clamps to 1.
public struct Pericope: Sendable, Equatable, Hashable, Identifiable {
    public let bookCode: String
    public let level: Int
    public let title: String
    public let subtitle: String?
    public let startChapter: Int
    public let startVerse: Int
    public let endChapter: Int
    public let endVerse: Int
    public let includesSuperscription: Bool
    public let parallels: [ParallelReference]
    /// Position among all the book's headings; makes `id` unique when two headings share a verse.
    public let ordinal: Int
    public var id: String { "\(bookCode).\(ordinal).\(startChapter):\(startVerse)" }

    public func contains(chapter: Int, verse: Int) -> Bool {
        (chapter, verse) >= (startChapter, startVerse) && (chapter, verse) <= (endChapter, endVerse)
    }
}

public enum PericopeIndex {
    /// Every heading of one book with its computed span, in reading order.
    ///
    /// A heading of level L runs from the verse it precedes to the verse before the next heading
    /// of the same or a higher (smaller-numbered) level that starts later; the last one runs to
    /// the book's final verse. Levels 0...3 are all returned; callers normally want `level <= 2`.
    public static func pericopes(in book: BookPack) -> [Pericope] {
        struct Flat { let chapter: Int; let row: Int; let heading: SectionHeading; var effective: Int { max(row, 1) } }
        var flat: [Flat] = []
        var lastVerse: [Int: Int] = [:]
        for chapter in book.chapters.sorted(by: { $0.n < $1.n }) {
            lastVerse[chapter.n] = chapter.v.max() ?? 0
            for heading in chapter.s ?? [] { flat.append(Flat(chapter: chapter.n, row: heading.verse, heading: heading)) }
        }
        guard let finalChapter = lastVerse.keys.max() else { return [] }
        let chapters = lastVerse.keys.sorted()

        func before(chapter: Int, verse: Int) -> (Int, Int) {
            if verse > 1 { return (chapter, verse - 1) }
            // The verse before a chapter's first verse is the previous chapter's last.
            let previous = chapters.last { $0 < chapter } ?? chapter
            return (previous, lastVerse[previous] ?? 1)
        }

        var result: [Pericope] = []
        for (index, item) in flat.enumerated() {
            let next = flat[(index + 1)...].first {
                $0.heading.level <= item.heading.level
                    && ($0.chapter, $0.effective) > (item.chapter, item.effective)
            }
            let end = next.map { before(chapter: $0.chapter, verse: $0.effective) }
                ?? (finalChapter, lastVerse[finalChapter] ?? 1)
            result.append(Pericope(
                bookCode: book.code, level: item.heading.level, title: item.heading.title,
                subtitle: item.heading.subtitle, startChapter: item.chapter, startVerse: item.effective,
                endChapter: end.0, endVerse: end.1,
                includesSuperscription: item.row == 0, parallels: item.heading.parallels ?? [], ordinal: index))
        }
        return result
    }
}
