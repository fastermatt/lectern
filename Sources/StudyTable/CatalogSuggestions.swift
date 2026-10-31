import SwiftUI

/// Where each optional historic work cites Scripture, shipped with the app so Thruline can
/// suggest books before they are downloaded. Reference metadata and section titles only — no
/// text from the works. Generated from the catalogue's own editions by
/// `STUDYTABLE_WRITE_CITATION_INDEX=… swift test --filter CatalogSuggestionTests/testWriteIndex`.
struct CatalogCitationIndex: Decodable, Sendable {
    struct Work: Decodable, Sendable {
        let sections: [String]
        /// [book index in BookTable.all, chapter, first verse, last verse, section index]
        let refs: [[Int]]
    }
    let schema: Int
    let generated: String
    let works: [String: Work]

    static let shared: CatalogCitationIndex? = {
        guard let url = AppResources.url("Reference/historic-citations.json"), let data = try? Data(contentsOf: url),
              let index = try? JSONDecoder().decode(CatalogCitationIndex.self, from: data), index.schema == 1 else { return nil }
        return index
    }()

    struct Suggestion: Identifiable, Sendable {
        let work: HistoricWork
        let places: Int
        let sections: [String]
        var id: String { work.id }
    }

    /// Works that discuss `anchor`, most places first, one work per author before a second from the same author,
    /// so a reader meets voices they would not usually open.
    func suggestions(for anchor: Anchor, excluding installed: Set<String>, limit: Int = 6) -> [Suggestion] {
        guard let bookIndex = BookTable.all.firstIndex(where: { $0.code == anchor.book }) else { return [] }
        var found: [Suggestion] = []
        for work in HistoricWork.catalog where !installed.contains(work.id) {
            guard let entry = works[work.id] else { continue }
            let hits = entry.refs.filter { ref in
                ref.count == 5 && ref[0] == bookIndex &&
                Anchor(book: anchor.book, chapter: ref[1], verses: ref[2], to: ref[3]).overlaps(anchor)
            }
            guard !hits.isEmpty else { continue }
            var titles: [String] = []
            for ref in hits { if let title = entry.sections[safe: ref[4]], !titles.contains(title) { titles.append(title) } }
            found.append(Suggestion(work: work, places: hits.count, sections: Array(titles.prefix(3))))
        }
        found.sort { $0.places > $1.places }
        var authors = Set<String>(), first: [Suggestion] = [], rest: [Suggestion] = []
        for item in found { if authors.insert(item.work.author).inserted { first.append(item) } else { rest.append(item) } }
        return Array((first + rest).prefix(limit))
    }

    static func build(_ books: [ResourceBook]) throws -> [String: Any] {
        var works: [String: Any] = [:]
        for book in books {
            let index = try LibraryCitationIndex.build([book])
            let order = book.articles.map(\.id)
            var refs: [[Int]] = []
            for list in index.byBibleBook.values {
                for hit in list {
                    guard let bookIndex = BookTable.all.firstIndex(where: { $0.code == hit.anchor.book }),
                          let section = order.firstIndex(of: hit.articleID) else { continue }
                    refs.append([bookIndex, hit.anchor.chapterStart, hit.anchor.verseStart, hit.anchor.verseEnd, section])
                }
            }
            refs.sort { $0.lexicographicallyPrecedes($1) }
            works[book.id] = ["sections": book.articles.map(\.displayTitle), "refs": refs]
        }
        return works
    }
}

/// "Worth adding for this passage": works not yet downloaded that discuss it.
struct CatalogSuggestionsPanel: View {
    @ObservedObject var books: ResourceBookLibrary
    let anchor: Anchor?
    @State private var expanded = false

    var body: some View {
        if let anchor, let index = CatalogCitationIndex.shared {
            let items = index.suggestions(for: anchor, excluding: Set(books.books.map(\.id)))
            if !items.isEmpty {
                DisclosureGroup("Worth adding for this passage · \(items.count) \(items.count == 1 ? "book" : "books")", isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Free historic books you have not downloaded that discuss this passage, found from where each one cites Scripture. Add one to read the passage in context.")
                            .font(.caption).foregroundStyle(STColor.secondary)
                        ForEach(items) { item in
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(alignment: .firstTextBaseline, spacing: 8) {
                                    Text(item.work.title).font(.system(size: 13, weight: .semibold))
                                    if let labels = WorkLabels.of(item.work.id) { WorkBadge(text: labels.badge) }
                                }
                                Text("\(item.work.author) · cites this passage in \(item.places) \(item.places == 1 ? "place" : "places")" + (item.sections.isEmpty ? "" : " · " + item.sections.joined(separator: "; ")))
                                    .font(.caption).foregroundStyle(STColor.secondary).lineLimit(2)
                                if let why = WorkLabels.of(item.work.id)?.whyRead { Text(why).font(.callout) }
                                if books.activeID == item.work.id {
                                    HStack { ProgressView().controlSize(.small); Text("Downloading & preparing…").font(.callout); Button("Cancel") { books.cancel() } }
                                } else {
                                    Button("Add to library") { books.install(item.work) }.disabled(books.activeID != nil)
                                        .help("Download once from Project Gutenberg; its references to this passage then appear above, linked")
                                        .accessibilityLabel("Add \(item.work.title) to library")
                                }
                                Divider()
                            }.font(.callout)
                        }
                    }.padding(.top, 8)
                }.font(.headline).padding(14)
            }
        }
    }
}

extension AIContextBuilder {
    /// Titles and locations of not-yet-downloaded works that discuss a passage — no text — so a model can recommend them.
    static func suggestions(for anchor: Anchor, installed: Set<String>, budget: Int) -> String {
        guard let index = CatalogCitationIndex.shared else { return "" }
        let items = index.suggestions(for: anchor, excluding: installed, limit: 8)
        guard !items.isEmpty else { return "" }
        var out = "\nOther free books available in Thruline but NOT downloaded (titles and locations only; their text is not attached — recommend, do not quote):\n"
        for item in items {
            let labels = WorkLabels.of(item.work.id)
            let line = "- \(item.work.title), \(item.work.author) (\(item.work.edition)); \(labels.map { "\($0.badge); \($0.era); " } ?? "")cites \(anchor.displayString) in \(item.places) place(s): \(item.sections.joined(separator: "; "))\(labels?.lastThings.map { ". Note: " + $0 } ?? "")\n"
            guard out.utf8.count + line.utf8.count <= budget else { break }
            out += line
        }
        return out
    }
}

extension NotebookSession {
    /// The open note as plain text: title, body, template fields and tags. Never sent anywhere automatically.
    var plainText: String {
        ([title, body] + fieldTexts.keys.sorted().compactMap { fieldTexts[$0] } + (tags.isEmpty ? [] : ["Tags: " + tags.joined(separator: ", ")]))
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }
}

/// Distinctive words in a note, for finding the same ideas in other texts.
enum NoteIdeas {
    private static let common: Set<String> = Set("""
    the and that this with from have will what when where which their there they them then than been were would could should about into your yours ours ourselves our upon also very much many more most some such only other over under after before because while these those being does did done just like even still each every both either neither shall unto thee thou thy hath doth said says saith verse verses chapter passage passages note notes read reading lord god jesus christ church people things thing make made time times first second third today well
    """.split(whereSeparator: \.isWhitespace).map(String.init))
    static func keywords(_ text: String, limit: Int = 6) -> [String] {
        var counts: [String: Int] = [:]
        for raw in text.lowercased().split(whereSeparator: { !$0.isLetter }) {
            let word = String(raw)
            guard word.count >= 5, !common.contains(word) else { continue }
            counts[word, default: 0] += 1
        }
        return counts.sorted { $0.value != $1.value ? $0.value > $1.value : $0.key < $1.key }.prefix(limit).map(\.key)
    }
}

/// "Sources" for the open note: the passages it cites, where your library cites the same passages,
/// and paragraphs that share the note's key ideas. Runs on this Mac; nothing is sent anywhere.
struct NoteSourcesView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var notebook: NotebookSession
    @State private var ideaHits: [LibraryTextHit] = []
    @State private var searching = true

    private var text: String { notebook.plainText }
    private var references: [Anchor] {
        var seen = Set<Anchor>()
        return (ScriptureReferenceScanner.citations(in: text).map(\.anchor) + notebook.anchors).filter { seen.insert($0).inserted }
    }
    private var keywords: [String] { NoteIdeas.keywords(text) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Sources for this note").font(.title3.weight(.semibold))
            Text("Found on this Mac from your note's passages and key words. Nothing is sent to an AI unless you attach the note in Your AI.")
                .font(.caption).foregroundStyle(STColor.secondary)
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    if references.isEmpty && keywords.isEmpty {
                        Text("Write a few lines or a Bible reference such as Rom 8:28, and sources will appear here.").foregroundStyle(STColor.secondary)
                    }
                    ForEach(references, id: \.self) { anchor in
                        let hits = state.resourceBooks.citations.citing(anchor)
                        VStack(alignment: .leading, spacing: 6) {
                            HStack {
                                Button(anchor.displayString) { state.openPassage(anchor); openWindow(id: "workspace") }.buttonStyle(.link)
                                Text(hits.isEmpty ? "· not cited in your installed books" : "· cited \(hits.count)× in your library").font(.caption).foregroundStyle(STColor.secondary)
                            }.font(.headline)
                            ForEach(hits.prefix(4)) { hit in citation(hit) }
                        }
                        Divider()
                    }
                    if !keywords.isEmpty {
                        Text("Where these ideas appear: " + keywords.joined(separator: ", ")).font(.headline)
                        if searching { ProgressView().controlSize(.small) }
                        else if ideaHits.isEmpty { Text("No paragraph in your library contains these words together.").font(.callout).foregroundStyle(STColor.secondary) }
                        ForEach(ideaHits) { hit in
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(hit.collection) · \(hit.title)").font(.caption.weight(.semibold))
                                Text(ReaderText.attributed(ReaderText.snippet(hit.body, terms: keywords), terms: keywords, linkReferences: false)).font(.callout).lineLimit(4)
                                if let focus = hit.focus {
                                    Button("Read in context") { state.libraryRequest = focus; openWindow(id: "resource-library") }.buttonStyle(.link).font(.caption)
                                }
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(18).frame(width: 460, height: 560).background(STColor.paper).foregroundStyle(STColor.ink)
        .task(id: keywords) {
            searching = true
            let words = keywords, books = state.resourceBooks.readableBooks
            // Two shared key words per paragraph: specific enough to mean something, broad enough to find echoes.
            let pairs = words.count >= 2 ? [Array(words.prefix(2))] + (words.count >= 3 ? [[words[0], words[2]], [words[1], words[2]]] : []) : [words]
            await state.resourceBooks.ensureSearchIndex()
            if state.resourceBooks.searchIndexReady {
                var all: [LibraryTextHit] = [], ids = Set<String>()
                for pair in pairs where !pair.isEmpty {
                    let result = try? await LibraryTextSearch.indexed(query: pair.joined(separator: " "), scope: .books, offset: 0, concepts: true,
                        index: state.resourceBooks.searchIndex, studyRoot: nil, historicRoot: nil, books: books, notes: [], includeResearch: false, citing: [])
                    for hit in result?.page.hits ?? [] where ids.insert(hit.id).inserted { all.append(hit) }
                }
                ideaHits = Array(all.prefix(8)); searching = false
                return
            }
            let found = await Task.detached(priority: .userInitiated) {
                var all: [LibraryTextHit] = [], ids = Set<String>()
                for pair in pairs where !pair.isEmpty {
                    let page = try? LibraryTextSearch.search(query: pair.joined(separator: " "), scope: .books, offset: 0, studyRoot: nil,
                                                            books: books, notes: [], historicRoot: nil, includeResearch: false)
                    for hit in page?.hits ?? [] where ids.insert(hit.id).inserted { all.append(hit) }
                }
                return Array(all.prefix(8))
            }.value
            ideaHits = found; searching = false
        }
    }

    private func citation(_ hit: LibraryCitation) -> some View {
        let paragraph = state.resourceBooks.book(id: hit.bookID)?.articles.first { $0.id == hit.articleID }?.paragraphs[safe: hit.paragraph] ?? ""
        return VStack(alignment: .leading, spacing: 3) {
            Text("\(hit.author) · \(hit.bookTitle)").font(.caption.weight(.semibold))
            Text(ReaderText.snippet(paragraph, terms: [hit.footnote.map { "[\($0)]" } ?? String(hit.reference.prefix(5))], length: 220)).font(.callout).lineLimit(3)
            Button("Read in context") {
                state.libraryRequest = LibraryFocus(bookID: hit.bookID, articleID: hit.articleID, paragraph: hit.paragraph)
                openWindow(id: "resource-library")
            }.buttonStyle(.link).font(.caption)
        }
    }
}
