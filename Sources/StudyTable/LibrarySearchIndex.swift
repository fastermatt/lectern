import Foundation
import SQLite3

/// On-device full-text index over installed books, the included Apostolic Fathers, bundled
/// commentaries and downloaded historic works. Uses macOS's own SQLite FTS5 (no added
/// dependency) with English stemming and diacritic folding, ranked by BM25.
///
/// The index is contentless: it stores search terms and locations, never a second copy of
/// the texts, so it stays small and source files remain the authority. Results are rebuilt
/// from the books in memory or the commentary files. It holds no private notes.
actor LibrarySearchIndex {
    enum Kind: String, Sendable { case book, commentary, historic }

    /// Where a matching paragraph or entry lives.
    struct Location: Codable, Sendable, Hashable {
        var kind: String
        var source: String          // "book:<id>", "commentary", "tcp:<file>"
        var bookID: String?
        var articleID: String?
        var paragraph: Int?
        var title: String
        var collection: String
        var entryID: String?        // commentary entry
        var bibleBook: String?
        var chapter: Int?
        var verseStart: Int?
        var verseEnd: Int?
        var file: String?           // commentary chapter file or TCP file
        var section: Int?           // TCP section index
        // Short keys: one location is stored per indexed paragraph or entry.
        enum CodingKeys: String, CodingKey {
            case kind = "k", source = "s", bookID = "b", articleID = "a", paragraph = "p", title = "t", collection = "c"
            case entryID = "e", bibleBook = "bb", chapter = "ch", verseStart = "vs", verseEnd = "ve", file = "f", section = "sc"
        }
    }

    struct Hit: Sendable { let location: Location; let rank: Double }

    static let schemaVersion: Int32 = 3
    /// Owns the SQLite connection; closes it when the index goes away.
    private final class Handle: @unchecked Sendable {
        var pointer: OpaquePointer?
        deinit { if let pointer { sqlite3_close(pointer) } }
    }
    private let handle = Handle()
    private var db: OpaquePointer? {
        get { handle.pointer }
        set { handle.pointer = newValue }
    }
    private let url: URL
    private(set) var isReady = false

    init(url: URL = AppResources.supportDirectory.appendingPathComponent("SearchIndex.sqlite")) {
        self.url = url
    }


    // MARK: Opening

    private func open() throws -> OpaquePointer {
        if let db { return db }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        var handle: OpaquePointer?
        guard sqlite3_open_v2(url.path, &handle, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_NOMUTEX, nil) == SQLITE_OK, let handle else {
            throw IndexError.message("The search index could not be opened.")
        }
        db = handle
        if try scalarInt("PRAGMA user_version") != Int(Self.schemaVersion) {
            try exec("DROP TABLE IF EXISTS passages; DROP TABLE IF EXISTS docs; DROP TABLE IF EXISTS sources;")
            try exec("""
                CREATE VIRTUAL TABLE passages USING fts5(title, body, content='', contentless_delete=1,
                    tokenize='porter unicode61 remove_diacritics 2');
                CREATE TABLE docs(rowid INTEGER PRIMARY KEY, source TEXT NOT NULL, kind TEXT NOT NULL, research INTEGER NOT NULL, location TEXT NOT NULL);
                CREATE INDEX docs_source ON docs(source);
                CREATE TABLE sources(id TEXT PRIMARY KEY, fingerprint TEXT NOT NULL);
                PRAGMA user_version = \(Self.schemaVersion);
                """)
        }
        try exec("PRAGMA journal_mode = WAL; PRAGMA synchronous = NORMAL;")
        return handle
    }

    enum IndexError: LocalizedError {
        case message(String)
        var errorDescription: String? { if case .message(let text) = self { return text }; return nil }
    }

    private func exec(_ sql: String) throws {
        var error: UnsafeMutablePointer<CChar>?
        guard sqlite3_exec(db, sql, nil, nil, &error) == SQLITE_OK else {
            let text = error.map { String(cString: $0) } ?? "unknown"; sqlite3_free(error)
            throw IndexError.message("Search index error: \(text)")
        }
    }
    private func prepare(_ sql: String) throws -> OpaquePointer {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            throw IndexError.message("Search index error: \(String(cString: sqlite3_errmsg(db)))")
        }
        return statement
    }
    private func scalarInt(_ sql: String) throws -> Int {
        let s = try prepare(sql); defer { sqlite3_finalize(s) }
        return sqlite3_step(s) == SQLITE_ROW ? Int(sqlite3_column_int64(s, 0)) : 0
    }
    private static let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    private func bind(_ s: OpaquePointer, _ index: Int32, _ text: String) { sqlite3_bind_text(s, index, text, -1, Self.transient) }

    // MARK: Syncing

    struct Document { let title: String; let body: String; let research: Bool; let location: Location }

    /// Brings the index in line with the given sources: new or changed sources are (re)indexed,
    /// sources that no longer exist are removed. Returns how many sources were indexed.
    @discardableResult
    func sync(sources: [(id: String, fingerprint: String, documents: () throws -> [Document])]) throws -> Int {
        _ = try open()
        var known: [String: String] = [:]
        let read = try prepare("SELECT id, fingerprint FROM sources"); defer { sqlite3_finalize(read) }
        while sqlite3_step(read) == SQLITE_ROW { known[String(cString: sqlite3_column_text(read, 0))] = String(cString: sqlite3_column_text(read, 1)) }
        var indexed = 0
        let wanted = Set(sources.map(\.id))
        for stale in known.keys where !wanted.contains(stale) { try remove(source: stale) }
        for source in sources where known[source.id] != source.fingerprint {
            try Task.checkCancellation()
            try exec("BEGIN IMMEDIATE")
            do {
                try deleteRows(source: source.id)
                let insertDoc = try prepare("INSERT INTO docs(source, kind, research, location) VALUES (?, ?, ?, ?)")
                let insertText = try prepare("INSERT INTO passages(rowid, title, body) VALUES (?, ?, ?)")
                defer { sqlite3_finalize(insertDoc); sqlite3_finalize(insertText) }
                let encoder = JSONEncoder()
                for document in try source.documents() {
                    try Task.checkCancellation()
                    sqlite3_reset(insertDoc); sqlite3_reset(insertText)
                    bind(insertDoc, 1, source.id); bind(insertDoc, 2, document.location.kind)
                    sqlite3_bind_int(insertDoc, 3, document.research ? 1 : 0)
                    bind(insertDoc, 4, String(decoding: try encoder.encode(document.location), as: UTF8.self))
                    guard sqlite3_step(insertDoc) == SQLITE_DONE else { throw IndexError.message("Could not index \(source.id).") }
                    sqlite3_bind_int64(insertText, 1, sqlite3_last_insert_rowid(db))
                    bind(insertText, 2, document.title); bind(insertText, 3, document.body)
                    guard sqlite3_step(insertText) == SQLITE_DONE else { throw IndexError.message("Could not index \(source.id).") }
                }
                let mark = try prepare("INSERT OR REPLACE INTO sources(id, fingerprint) VALUES (?, ?)"); defer { sqlite3_finalize(mark) }
                bind(mark, 1, source.id); bind(mark, 2, source.fingerprint)
                guard sqlite3_step(mark) == SQLITE_DONE else { throw IndexError.message("Could not record \(source.id).") }
                try exec("COMMIT")
                indexed += 1
            } catch { try? exec("ROLLBACK"); throw error }
        }
        if indexed > 0 {
            // Merge index segments and fold the write-ahead log back in, keeping the file compact.
            try exec("INSERT INTO passages(passages) VALUES('optimize'); PRAGMA wal_checkpoint(TRUNCATE);")
        }
        isReady = true
        return indexed
    }

    private func deleteRows(source: String) throws {
        let s = try prepare("DELETE FROM passages WHERE rowid IN (SELECT rowid FROM docs WHERE source = ?)"); defer { sqlite3_finalize(s) }
        bind(s, 1, source); _ = sqlite3_step(s)
        let d = try prepare("DELETE FROM docs WHERE source = ?"); defer { sqlite3_finalize(d) }
        bind(d, 1, source); _ = sqlite3_step(d)
    }
    private func remove(source: String) throws {
        try exec("BEGIN IMMEDIATE")
        do {
            try deleteRows(source: source)
            let s = try prepare("DELETE FROM sources WHERE id = ?"); defer { sqlite3_finalize(s) }
            bind(s, 1, source); _ = sqlite3_step(s)
            try exec("COMMIT")
        } catch { try? exec("ROLLBACK"); throw error }
    }

    // MARK: Searching

    /// Ranked matches for an FTS5 expression. Title matches weigh three times body matches.
    func search(_ expression: String, kinds: Set<Kind>, includeResearch: Bool, limit: Int) throws -> (hits: [Hit], total: Int) {
        _ = try open()
        guard !kinds.isEmpty else { return ([], 0) }
        let kindList = kinds.map { "'\($0.rawValue)'" }.sorted().joined(separator: ",")
        let filter = "d.kind IN (\(kindList))" + (includeResearch ? "" : " AND d.research = 0")
        let count = try prepare("SELECT count(*) FROM passages p JOIN docs d ON d.rowid = p.rowid WHERE passages MATCH ? AND \(filter)")
        defer { sqlite3_finalize(count) }
        bind(count, 1, expression)
        guard sqlite3_step(count) == SQLITE_ROW else { throw IndexError.message("That search could not be understood. Try fewer symbols.") }
        let total = Int(sqlite3_column_int64(count, 0))
        let query = try prepare("""
            SELECT d.location, bm25(passages, 3.0, 1.0) AS rank FROM passages p JOIN docs d ON d.rowid = p.rowid
            WHERE passages MATCH ? AND \(filter) ORDER BY rank LIMIT ?
            """)
        defer { sqlite3_finalize(query) }
        bind(query, 1, expression); sqlite3_bind_int(query, 2, Int32(limit))
        var hits: [Hit] = []
        let decoder = JSONDecoder()
        while sqlite3_step(query) == SQLITE_ROW {
            guard let text = sqlite3_column_text(query, 0),
                  let location = try? decoder.decode(Location.self, from: Data(String(cString: text).utf8)) else { continue }
            hits.append(Hit(location: location, rank: sqlite3_column_double(query, 1)))
        }
        return (hits, total)
    }

    func documentCount() throws -> Int { _ = try open(); return try scalarInt("SELECT count(*) FROM docs") }
}

// MARK: - Sources

enum LibrarySearchSources {
    static func fingerprint(_ book: ResourceBook) -> String {
        "v1:\(book.articles.count):\(book.articles.reduce(0) { $0 + $1.body.utf8.count }):\(book.articles.first?.id ?? ""):\(book.articles.last?.id ?? "")"
    }

    static func book(_ book: ResourceBook) -> (id: String, fingerprint: String, documents: () throws -> [LibrarySearchIndex.Document]) {
        (id: "book:" + book.id, fingerprint: fingerprint(book), documents: {
            var out: [LibrarySearchIndex.Document] = []
            for article in book.articles {
                let title = article.displayTitle
                for (number, paragraph) in article.paragraphs.enumerated() {
                    out.append(.init(title: title, body: paragraph, research: false, location: .init(kind: LibrarySearchIndex.Kind.book.rawValue,
                        source: "book:" + book.id, bookID: book.id, articleID: article.id, paragraph: number, title: title, collection: book.title)))
                }
            }
            return out
        })
    }

    private struct Chapter: Decodable { let code: String; let schema: Int; let entries: [StudySource] }

    /// Bundled commentaries, once per entry (entries repeat across chapters they cover).
    static func commentary(root: URL) -> (id: String, fingerprint: String, documents: () throws -> [LibrarySearchIndex.Document])? {
        let files = BookTable.all.flatMap { book in (1...book.chapters).map { root.appendingPathComponent(book.code).appendingPathComponent("\($0).json") } }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
        guard !files.isEmpty else { return nil }
        let bytes = files.reduce(0) { $0 + ((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return (id: "commentary", fingerprint: "v1:\(files.count):\(bytes)", documents: {
            var out: [LibrarySearchIndex.Document] = [], seen = Set<String>()
            for file in files {
                try Task.checkCancellation()
                guard let data = try? Data(contentsOf: file), let content = try? JSONDecoder().decode(Chapter.self, from: data), content.schema == 3 else { continue }
                let relative = file.deletingLastPathComponent().lastPathComponent + "/" + file.lastPathComponent
                for entry in content.entries where !entry.excerpt.isEmpty && seen.insert(entry.id).inserted {
                    out.append(.init(title: entry.work + " — " + entry.author, body: entry.excerpt, research: entry.tier == .tier3ResearchOnly,
                        location: .init(kind: LibrarySearchIndex.Kind.commentary.rawValue, source: "commentary", title: "", collection: "",
                                        entryID: entry.id, bibleBook: content.code, chapter: entry.chapter, verseStart: entry.startVerse,
                                        verseEnd: entry.endVerse, file: relative)))
                }
            }
            return out
        })
    }

    /// Downloaded EEBO-TCP works (TEI XML), one document per section.
    static func historic(root: URL) -> [(id: String, fingerprint: String, documents: () throws -> [LibrarySearchIndex.Document])] {
        guard let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey]) else { return [] }
        return files.filter { $0.pathExtension == "xml" }.compactMap { file in
            guard let values = try? file.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .isSymbolicLinkKey]),
                  values.isSymbolicLink != true, let size = values.fileSize, size <= 30 * 1024 * 1024 else { return nil }
            let stamp = values.contentModificationDate?.timeIntervalSince1970 ?? 0
            return (id: "tcp:" + file.lastPathComponent, fingerprint: "v1:\(size):\(Int(stamp))", documents: {
                guard let work = TEIParser.parse(try Data(contentsOf: file)) else { return [] }
                return work.sections.enumerated().map { index, section in
                    .init(title: section.heading, body: section.body, research: false,
                          location: .init(kind: LibrarySearchIndex.Kind.historic.rawValue, source: "tcp:" + file.lastPathComponent,
                                          title: section.heading, collection: work.title, file: file.lastPathComponent, section: index))
                }
            })
        }
    }
}

// MARK: - Indexed library search

struct IndexedSearchResult: Sendable {
    var page: LibraryTextPage
    var concepts: [ConceptVocabulary.Group]
    var seconds: Double
}

extension LibraryTextSearch {
    private struct Chapter: Decodable { let code: String; let schema: Int; let entries: [StudySource] }

    /// Ranked search through the on-device index, with concept expansion, exact phrases first,
    /// texts citing a searched reference first, and the reader's notes searched in memory.
    static func indexed(query: String, scope: LibraryTextScope, offset: Int, concepts: Bool, index: LibrarySearchIndex,
                        studyRoot: URL?, historicRoot: URL?, books: [ResourceBook], notes: [Note], includeResearch: Bool,
                        citing: [LibraryCitation]) async throws -> IndexedSearchResult {
        let start = Date()
        guard let plan = SearchPlan.make(query, concepts: concepts) else { return .init(page: .init(hits: [], total: 0, unreadable: 0), concepts: [], seconds: 0) }
        var leading: [LibraryTextHit] = []
        let lookup = Dictionary(books.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        if scope == .all || scope == .books {
            for citation in citing {
                guard let book = lookup[citation.bookID], let article = book.articles.first(where: { $0.id == citation.articleID }),
                      let paragraph = article.paragraphs[safe: citation.paragraph] else { continue }
                leading.append(.init(id: "cites:" + citation.id, title: article.displayTitle,
                    collection: book.title + " · cites " + citation.reference.split(whereSeparator: \.isWhitespace).joined(separator: " "),
                    body: paragraph, anchor: citation.anchor, source: book.source.flatMap(URL.init(string:)), attribution: book.attribution,
                    focus: LibraryFocus(bookID: book.id, articleID: article.id, paragraph: citation.paragraph)))
            }
        }
        if scope == .all || scope == .notes {
            for note in notes {
                let text = ([note.title, note.body] + note.sections.map(\.text) + note.tags).joined(separator: "\n\n")
                guard plan.terms.allSatisfy({ term in ([term] + (ConceptVocabulary.group(for: term)?.terms ?? [])).contains { TextMatch.range(of: $0, in: text) != nil } }) else { continue }
                leading.append(.init(id: "note:" + note.id.uuidString, title: note.title.isEmpty ? "Untitled note" : note.title, collection: "My notes",
                    body: text, anchor: note.anchors.first, source: nil, attribution: "Your private note · stored on this Mac", noteID: note.id))
            }
        }
        let kinds: Set<LibrarySearchIndex.Kind> = switch scope {
        case .all: [.book, .commentary, .historic]
        case .books: [.book, .historic]
        case .commentary: [.commentary]
        case .notes: []
        }
        // A reference query lists citing paragraphs instead of loose word matches in books.
        let referenceSearch = referenceQuery(query) != nil
        let searchKinds = referenceSearch ? kinds.subtracting([.book]) : kinds
        var ordered: [LibrarySearchIndex.Location] = [], seen = Set<LibrarySearchIndex.Location>()
        var total = 0
        if let phrase = plan.phrase {
            for hit in try await index.search(SearchPlan.literal(phrase), kinds: searchKinds, includeResearch: includeResearch, limit: 400).hits where seen.insert(hit.location).inserted { ordered.append(hit.location) }
        }
        let general = try await index.search(plan.expression, kinds: searchKinds, includeResearch: includeResearch, limit: 1_000)
        total = general.total
        for hit in general.hits where seen.insert(hit.location).inserted { ordered.append(hit.location) }

        // Materialize only the visible page.
        let all = leading.count + max(total, ordered.count)
        var page: [LibraryTextHit] = []
        var chapters: [String: Chapter] = [:], works: [String: ParsedPuritanWork] = [:]
        var unreadable = 0
        var position = offset
        while page.count < 40, position < leading.count + ordered.count {
            defer { position += 1 }
            if position < leading.count { page.append(leading[position]); continue }
            let location = ordered[position - leading.count]
            switch LibrarySearchIndex.Kind(rawValue: location.kind) {
            case .book:
                guard let id = location.bookID, let book = lookup[id], let articleID = location.articleID,
                      let article = book.articles.first(where: { $0.id == articleID }), let number = location.paragraph,
                      let paragraph = article.paragraphs[safe: number] else { unreadable += 1; continue }
                page.append(.init(id: book.id + ":" + articleID + ":\(number)", title: article.displayTitle, collection: book.title, body: paragraph,
                    anchor: article.anchor, source: book.source.flatMap(URL.init(string:)), attribution: book.attribution,
                    focus: LibraryFocus(bookID: book.id, articleID: articleID, paragraph: number,
                                       // Only wording present here, so the reader's in-book search finds this paragraph.
                                       terms: plan.highlightTerms.filter { TextMatch.range(of: $0, in: paragraph) != nil }.prefix(2).map { $0 })))
            case .commentary:
                guard let root = studyRoot, let file = location.file, let entryID = location.entryID else { unreadable += 1; continue }
                if chapters[file] == nil, let data = try? Data(contentsOf: root.appendingPathComponent(file)) { chapters[file] = try? JSONDecoder().decode(Chapter.self, from: data) }
                guard let chapter = chapters[file], let entry = chapter.entries.first(where: { $0.id == entryID }) else { unreadable += 1; continue }
                page.append(.init(id: "commentary:" + entry.id, title: entry.work, collection: entry.author, body: entry.excerpt,
                    anchor: Anchor(book: chapter.code, chapter: entry.chapter, verses: entry.startVerse, to: entry.endVerse), source: entry.sourceURL,
                    attribution: "\(entry.isExactQuote ? "Source quotation" : "Editorial summary") · \(entry.tradition.rawValue) · \(entry.source)"))
            case .historic:
                guard let root = historicRoot, let file = location.file, let section = location.section else { unreadable += 1; continue }
                if works[file] == nil, let data = try? Data(contentsOf: root.appendingPathComponent(file)) { works[file] = TEIParser.parse(data) }
                guard let work = works[file], let body = work.sections[safe: section] else { unreadable += 1; continue }
                page.append(.init(id: "tcp:" + file + ":\(section)", title: body.heading, collection: work.title, body: body.body, anchor: nil,
                    source: URL(string: "https://textcreationpartnership.org/"), attribution: "EEBO-TCP public text edition · \(file.replacingOccurrences(of: ".xml", with: "")) · \(work.author)"))
            case nil: unreadable += 1
            }
        }
        return .init(page: .init(hits: page, total: all, unreadable: unreadable), concepts: plan.concepts, seconds: Date().timeIntervalSince(start))
    }
}
