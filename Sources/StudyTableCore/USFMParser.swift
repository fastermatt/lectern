import Foundation

/// One verse of Scripture. `number == 0` is the unnumbered superscription
/// (`\d`, e.g. a Psalm title) that precedes verse 1 of a chapter.
public struct ParsedVerse: Sendable, Equatable {
    public let number: Int
    public let text: String
    public init(number: Int, text: String) {
        self.number = number
        self.text = text
    }
}

public struct ParsedBook: Sendable, Equatable {
    public let code: String
    public let name: String
    /// Verses per chapter, in source order.
    public let chapters: [Int: [ParsedVerse]]
    /// Section headings per chapter, in source order, each keyed to the verse it precedes.
    public let headings: [Int: [SectionHeading]]
    /// Per chapter, the verses that begin a paragraph (the chapter's first verse always does).
    public let paragraphStarts: [Int: [Int]]
    public let stats: StructureStats
    public init(code: String, name: String, chapters: [Int: [ParsedVerse]],
                headings: [Int: [SectionHeading]] = [:], paragraphStarts: [Int: [Int]] = [:],
                stats: StructureStats = StructureStats()) {
        self.code = code
        self.name = name
        self.chapters = chapters
        self.headings = headings
        self.paragraphStarts = paragraphStarts
        self.stats = stats
    }
}

/// Minimal, dependency-free USFM reader for eBible.org style files.
public enum USFMParser {
    /// Markers that start a new paragraph or stanza block. (`\nb` cancels a pending break.)
    private static let breakMarkers: Set<String> = [
        "p", "pm", "pmo", "pmc", "pmr", "pi", "pi1", "pi2", "pi3", "pc", "pr", "po", "ph", "ph1", "ph2", "ph3",
        "m", "mi", "b"
    ]

    private struct PendingHeading {
        var level: Int
        var title: String
        var subtitle: String?
        var parallels: [ParallelReference]?
    }

    /// The marker at the start of a USFM line ("s1" for `\s1 Title`), or nil.
    private static func marker(of line: String) -> String? {
        guard line.hasPrefix("\\") else { return nil }
        let name = line.dropFirst().prefix { $0.isLetter || $0.isNumber }
        return name.isEmpty ? nil : String(name)
    }

    /// Heading level for a section-heading marker, or nil when the marker is not one.
    private static func headingLevel(_ marker: String) -> Int? {
        switch marker {
        case "ms", "ms1", "ms2", "ms3": return 0
        case "s", "s1": return 1
        case "s2": return 2
        case "s3", "s4": return 3
        case "qa": return 3   // acrostic stanza letter (Psalm 119)
        default: return nil
        }
    }

    public static func parseBook(_ raw: String) -> ParsedBook? {
        var code = ""
        var name = ""
        var chapter = 0
        var currentVerse: Int?
        var chapters: [Int: [ParsedVerse]] = [:]
        var headings: [Int: [SectionHeading]] = [:]
        var paragraphStarts: [Int: Set<Int>] = [:]
        var pending: [PendingHeading] = []
        var pendingBreak = false
        var stats = StructureStats()

        func append(_ text: String, verse: Int) {
            let cleaned = cleanUSFM(text)
            guard !cleaned.isEmpty else { return }
            var list = chapters[chapter, default: []]
            if let index = list.firstIndex(where: { $0.number == verse }) {
                list[index] = ParsedVerse(number: verse, text: list[index].text + " " + cleaned)
            } else {
                list.append(ParsedVerse(number: verse, text: cleaned))
            }
            chapters[chapter] = list
        }

        /// A verse (or the superscription, verse 0) begins here: headings and paragraph breaks that
        /// were waiting for it attach to it.
        func beginRow(_ verse: Int) {
            let firstRow = chapters[chapter, default: []].isEmpty
            let alreadyHasRow = chapters[chapter, default: []].contains { $0.number == verse }
            if !alreadyHasRow {
                for item in pending {
                    headings[chapter, default: []].append(SectionHeading(
                        verse: verse, level: item.level, title: item.title, subtitle: item.subtitle, parallels: item.parallels))
                }
                if pendingBreak || !pending.isEmpty || firstRow { paragraphStarts[chapter, default: []].insert(verse) }
                pending.removeAll()
            }
            pendingBreak = false
        }

        /// Text that continues the current verse arrived: any heading still waiting sat in the
        /// middle of that verse and is dropped; a break before it belongs to the verse's inside.
        func continuationText() {
            for item in pending { stats.droppedHeadings.append("\(code) \(chapter) (mid-verse): \(item.title)") }
            pending.removeAll()
            pendingBreak = false
        }

        for line in raw.components(separatedBy: .newlines) {
            let marker = marker(of: line)
            if let marker, breakMarkers.contains(marker) { pendingBreak = true } else if marker == "nb" { pendingBreak = false }

            if line.hasPrefix("\\id ") {
                code = line.dropFirst(4).split(separator: " ").first.map(String.init) ?? ""
            } else if line.hasPrefix("\\toc1 ") {
                name = String(line.dropFirst(6)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("\\h "), name.isEmpty {
                name = String(line.dropFirst(3)).trimmingCharacters(in: .whitespaces)
            } else if line.hasPrefix("\\c ") {
                chapter = Int(line.dropFirst(3).trimmingCharacters(in: .whitespaces)) ?? chapter
                currentVerse = nil
                pendingBreak = false
            } else if let marker, let level = headingLevel(marker), chapter > 0 {
                let title = cleanUSFM(String(line.dropFirst(marker.count + 1)))
                if !title.isEmpty { pending.append(PendingHeading(level: level, title: title)) }
            } else if marker == "mr", chapter > 0 {
                // A major-section reference line belongs to the heading above it; never verse text.
                let text = cleanUSFM(String(line.dropFirst(3)))
                if !text.isEmpty, !pending.isEmpty { pending[pending.count - 1].subtitle = text }
            } else if marker == "r", chapter > 0 {
                let references = ParallelReferenceParser.parse(cleanUSFM(String(line.dropFirst(2))))
                if !pending.isEmpty {
                    stats.parallelLines += 1
                    pending[pending.count - 1].parallels = (pending[pending.count - 1].parallels ?? []) + references
                }
            } else if line.hasPrefix("\\d ") || line == "\\d", chapter > 0 {
                // Psalm superscriptions are Scripture, not editorial headings.
                let text = String(line.dropFirst(2))
                if !cleanUSFM(text).isEmpty { beginRow(0) }
                append(text, verse: 0)
            } else if line.hasPrefix("\\v ") {
                let remainder = String(line.dropFirst(3))
                let parts = remainder.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: true)
                guard let token = parts.first else { continue }
                guard let verse = Int(token.prefix { $0.isNumber }), chapter > 0 else { continue }
                currentVerse = verse
                beginRow(verse)
                append(parts.count > 1 ? String(parts[1]) : "", verse: verse)
            } else if let verse = currentVerse,
                      line.hasPrefix("\\q") || line.hasPrefix("\\m") || line.hasPrefix("\\p") {
                if !cleanUSFM(line).isEmpty { continuationText() }
                append(line, verse: verse)
            }
        }
        for item in pending { stats.droppedHeadings.append("\(code) \(chapter) (no verse follows): \(item.title)") }
        guard !code.isEmpty, !name.isEmpty, !chapters.isEmpty else { return nil }

        // A heading must point at a verse that exists; the source sometimes puts a heading before a
        // verse marker whose text arrives on a later line, so this is a check, not a rewrite.
        var kept: [Int: [SectionHeading]] = [:]
        for number in headings.keys.sorted() {
            let list = headings[number] ?? []
            let numbers = Set(chapters[number, default: []].map(\.number))
            for heading in list {
                if numbers.contains(heading.verse) { kept[number, default: []].append(heading) } else {
                    stats.droppedHeadings.append("\(code) \(number):\(heading.verse) (verse missing): \(heading.title)")
                }
            }
        }
        for number in kept.keys.sorted() {
            for heading in kept[number] ?? [] {
                stats.headings += 1
                stats.headingsByLevel[heading.level, default: 0] += 1
                stats.parallelReferences += heading.parallels?.count ?? 0
                stats.unresolvedReferences += (heading.parallels ?? []).filter { !$0.isNavigable }.map(\.label)
            }
        }
        // A paragraph break before a verse the translation omits (WEB Acts 8:37) marks nothing.
        var starts: [Int: [Int]] = [:]
        for (number, set) in paragraphStarts {
            let numbers = Set(chapters[number, default: []].map(\.number))
            let existing = set.filter { numbers.contains($0) }.sorted()
            if !existing.isEmpty { starts[number] = existing }
        }
        stats.paragraphStarts = starts.values.reduce(0) { $0 + $1.count }
        return ParsedBook(code: code, name: name, chapters: chapters, headings: kept, paragraphStarts: starts, stats: stats)
    }

    /// Strips USFM markup, footnotes, cross-references and Strong's attributes.
    public static func cleanUSFM(_ input: String) -> String {
        // Nested character markup (`\+w ... \+w*`, used inside words of Jesus) is the same
        // markup with a `+` prefix; pilcrows (¶) are paragraph marks, not text.
        var text = input.replacingOccurrences(of: "\\+", with: "\\").replacingOccurrences(of: "¶", with: " ")
        removeDelimited(from: &text, opening: "\\f ", closing: "\\f*")
        removeDelimited(from: &text, opening: "\\x ", closing: "\\x*")
        while let start = text.range(of: "\\w "),
              let end = text.range(of: "\\w*", range: start.upperBound..<text.endIndex) {
            let payload = text[start.upperBound..<end.lowerBound]
            let visible = payload.split(separator: "|", maxSplits: 1).first.map(String.init) ?? ""
            text.replaceSubrange(start.lowerBound..<end.upperBound, with: visible)
        }
        text = text.replacingOccurrences(of: "~", with: " ")
        var visible = ""
        var index = text.startIndex
        while index < text.endIndex {
            if text[index] == "\\" {
                index = text.index(after: index)
                while index < text.endIndex, text[index].isLetter || text[index].isNumber { index = text.index(after: index) }
                if index < text.endIndex, text[index] == "*" {
                    // A closing marker (`\add*`) does not own the space after it: "of\add* \w the" is "of the".
                    index = text.index(after: index)
                } else {
                    // An opening marker owns the single space that separates it from its content.
                    while index < text.endIndex, text[index].isWhitespace { index = text.index(after: index) }
                }
            } else {
                visible.append(text[index])
                index = text.index(after: index)
            }
        }
        return visible.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func removeDelimited(from value: inout String, opening: String, closing: String) {
        while let start = value.range(of: opening) {
            guard let end = value.range(of: closing, range: start.upperBound..<value.endIndex) else {
                value.removeSubrange(start.lowerBound..<value.endIndex)
                return
            }
            value.removeSubrange(start.lowerBound..<end.upperBound)
        }
    }
}
