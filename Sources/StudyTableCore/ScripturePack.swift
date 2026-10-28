import Foundation

/// The canonical 66-book Protestant order, as USFM book identifiers.
public enum Canon {
    public static let bookCodes: [String] = [
        "GEN", "EXO", "LEV", "NUM", "DEU", "JOS", "JDG", "RUT", "1SA", "2SA", "1KI", "2KI",
        "1CH", "2CH", "EZR", "NEH", "EST", "JOB", "PSA", "PRO", "ECC", "SNG", "ISA", "JER",
        "LAM", "EZK", "DAN", "HOS", "JOL", "AMO", "OBA", "JON", "MIC", "NAM", "HAB", "ZEP",
        "HAG", "ZEC", "MAL", "MAT", "MRK", "LUK", "JHN", "ACT", "ROM", "1CO", "2CO", "GAL",
        "EPH", "PHP", "COL", "1TH", "2TH", "1TI", "2TI", "TIT", "PHM", "HEB", "JAS", "1PE",
        "2PE", "1JN", "2JN", "3JN", "JUD", "REV"
    ]
    public static let order: [String: Int] = Dictionary(
        uniqueKeysWithValues: bookCodes.enumerated().map { ($1, $0) }
    )
}

public struct PackLicense: Codable, Sendable, Equatable {
    public let summary: String
    public let url: String?
    public let attribution: String
    public init(summary: String, url: String?, attribution: String) {
        self.summary = summary
        self.url = url
        self.attribution = attribution
    }
}

/// Hand-written metadata that sits next to the USFM files (`translation.json`).
public struct PackSourceMeta: Codable, Sendable, Equatable {
    public let id: String
    public let abbreviation: String
    public let name: String
    public let language: String
    public let license: PackLicense
    public let sourceURL: String?
}

public struct ManifestBook: Codable, Sendable, Equatable {
    public let code: String
    public let name: String
    /// Number of verses (excluding the unnumbered superscription) for chapters 1...n.
    public let verses: [Int]
    public var chapterCount: Int { verses.count }
}

public struct TranslationManifest: Codable, Sendable, Equatable {
    public let schema: Int
    public let id: String
    public let abbreviation: String
    public let name: String
    public let language: String
    public let license: PackLicense
    public let sourceURL: String?
    public let books: [ManifestBook]
}

public struct ChapterPack: Codable, Sendable, Equatable {
    public let n: Int
    /// Verse numbers; a leading 0 is the unnumbered superscription.
    public let v: [Int]
    public let t: [String]
    /// Section headings (schema 2), each keyed to the verse it precedes. Absent when the
    /// source had none or the pack was built without structure.
    public let s: [SectionHeading]?
    /// Verses that begin a paragraph (schema 2). Absent when the source has no paragraph marks.
    public let p: [Int]?

    public init(n: Int, v: [Int], t: [String], s: [SectionHeading]? = nil, p: [Int]? = nil) {
        self.n = n
        self.v = v
        self.t = t
        self.s = s
        self.p = p
    }
}

public struct BookPack: Codable, Sendable, Equatable {
    public let code: String
    public let name: String
    public let chapters: [ChapterPack]

    public init(code: String, name: String, chapters: [ChapterPack]) {
        self.code = code
        self.name = name
        self.chapters = chapters
    }
}

public struct BuiltPack: Sendable {
    public let manifest: TranslationManifest
    public let books: [BookPack]
    /// Section-heading / parallel-reference / paragraph counts gathered while parsing.
    public let stats: StructureStats
}

public enum ScripturePackError: Error, CustomStringConvertible {
    case missingMetadata(String)
    case missingBooks([String])

    public var description: String {
        switch self {
        case .missingMetadata(let path): "Missing translation.json in \(path)"
        case .missingBooks(let codes): "Source is missing books: \(codes.joined(separator: ", "))"
        }
    }
}

public enum ScripturePackBuilder {
    /// 2 adds per-chapter section headings (`s`), parallel references (inside headings) and
    /// paragraph starts (`p`). Schema 1 packs (older user-installed packs) stay readable.
    public static let schema = 2
    public static let supportedSchemas = 1...2

    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }

    /// Parses every canonical book found in `sourceDirectory` (any `.usfm`/`.sfm`
    /// file whose `\id` is one of the 66 canonical codes) into compact packs.
    /// `includeStructure: false` leaves headings, parallels and paragraph marks out (the app builds
    /// downloaded Bibles this way: only vetted bundled sources carry editorial structure).
    public static func build(sourceDirectory: URL, includeStructure: Bool = true) throws -> BuiltPack {
        let metaURL = sourceDirectory.appendingPathComponent("translation.json")
        guard let metaData = try? Data(contentsOf: metaURL) else {
            throw ScripturePackError.missingMetadata(sourceDirectory.path)
        }
        let meta = try JSONDecoder().decode(PackSourceMeta.self, from: metaData)

        let files = try FileManager.default.contentsOfDirectory(at: sourceDirectory, includingPropertiesForKeys: nil)
            .filter { ["usfm", "sfm"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        var parsed: [String: ParsedBook] = [:]
        for file in files {
            guard let raw = try? String(contentsOf: file, encoding: .utf8),
                  let book = USFMParser.parseBook(raw),
                  Canon.order[book.code] != nil else { continue }
            parsed[book.code] = book
        }
        let missing = Canon.bookCodes.filter { parsed[$0] == nil }
        guard missing.isEmpty else { throw ScripturePackError.missingBooks(missing) }

        var manifestBooks: [ManifestBook] = []
        var packs: [BookPack] = []
        var stats = StructureStats()
        for code in Canon.bookCodes {
            let book = parsed[code]!
            let chapterNumbers = book.chapters.keys.sorted()
            let chapters = chapterNumbers.map { number -> ChapterPack in
                let verses = book.chapters[number]!.sorted { $0.number < $1.number }
                guard includeStructure else { return ChapterPack(n: number, v: verses.map(\.number), t: verses.map(\.text)) }
                let headings = book.headings[number] ?? []
                let starts = book.paragraphStarts[number] ?? []
                return ChapterPack(n: number, v: verses.map(\.number), t: verses.map(\.text),
                                   s: headings.isEmpty ? nil : headings, p: starts.isEmpty ? nil : starts)
            }
            if includeStructure {
                stats.headings += book.stats.headings
                for (level, count) in book.stats.headingsByLevel { stats.headingsByLevel[level, default: 0] += count }
                stats.parallelLines += book.stats.parallelLines
                stats.parallelReferences += book.stats.parallelReferences
                stats.unresolvedReferences += book.stats.unresolvedReferences
                stats.paragraphStarts += book.stats.paragraphStarts
                stats.droppedHeadings += book.stats.droppedHeadings
            }
            let counts = chapters.map { $0.v.filter { $0 > 0 }.count }
            manifestBooks.append(ManifestBook(code: code, name: book.name, verses: counts))
            packs.append(BookPack(code: code, name: book.name, chapters: chapters))
        }
        let manifest = TranslationManifest(
            schema: schema, id: meta.id, abbreviation: meta.abbreviation, name: meta.name,
            language: meta.language, license: meta.license, sourceURL: meta.sourceURL,
            books: manifestBooks
        )
        return BuiltPack(manifest: manifest, books: packs, stats: stats)
    }

    /// Writes `manifest.json` plus one `<CODE>.json` per book into `directory`.
    public static func write(_ pack: BuiltPack, to directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let encoder = encoder()
        try encoder.encode(pack.manifest).write(to: directory.appendingPathComponent("manifest.json"), options: .atomic)
        for book in pack.books {
            try encoder.encode(book).write(to: directory.appendingPathComponent("\(book.code).json"), options: .atomic)
        }
    }

    /// Returns the relative file names whose on-disk bytes differ from a fresh build.
    public static func drift(of pack: BuiltPack, in directory: URL) -> [String] {
        let encoder = encoder()
        var stale: [String] = []
        func check(_ name: String, _ data: Data) {
            let existing = try? Data(contentsOf: directory.appendingPathComponent(name))
            if existing != data { stale.append(name) }
        }
        if let data = try? encoder.encode(pack.manifest) { check("manifest.json", data) }
        for book in pack.books {
            if let data = try? encoder.encode(book) { check("\(book.code).json", data) }
        }
        return stale
    }
}
