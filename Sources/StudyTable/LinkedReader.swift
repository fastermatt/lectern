import SwiftUI

/// Internal links from a reader paragraph to a Bible passage. Never leaves the app.
enum PassageLink {
    static func url(_ anchor: Anchor) -> URL {
        URL(string: "thruline://passage/\(anchor.book)/\(anchor.chapterStart)/\(anchor.verseStart)/\(anchor.verseEnd)")!
    }
    static func anchor(_ url: URL) -> Anchor? {
        guard url.scheme == "thruline", url.host == "passage" else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        guard parts.count == 4, let book = BookTable.info(code: parts[0]),
              let chapter = Int(parts[1]), let start = Int(parts[2]), let end = Int(parts[3]),
              (1...book.chapters).contains(chapter), start >= 0, end >= start else { return nil }
        return Anchor(book: book.code, chapter: chapter, verses: start, to: end)
    }
}

/// Word-start matching ("rapture" finds "raptures", not "enraptured"); quoted phrases stay together.
enum TextMatch {
    static func terms(_ query: String) -> [String] {
        var terms: [String] = [], current = "", quoted = false
        for character in query.lowercased() {
            if character == "\"" || character == "“" || character == "”" {
                if quoted, !current.isEmpty { terms.append(current.trimmingCharacters(in: .whitespaces)) }
                else { terms += current.split(whereSeparator: \.isWhitespace).map(String.init) }
                current = ""; quoted.toggle()
            } else { current.append(character) }
        }
        terms += quoted ? [current.trimmingCharacters(in: .whitespaces)] : current.split(whereSeparator: \.isWhitespace).map(String.init)
        return terms.filter { $0.count > 1 }
    }
    /// Range of `term` starting at a word boundary.
    static func range(of term: String, in text: String, from start: String.Index? = nil) -> Range<String.Index>? {
        var cursor = start ?? text.startIndex
        while let found = text.range(of: term, options: [.caseInsensitive, .diacriticInsensitive], range: cursor..<text.endIndex) {
            if found.lowerBound == text.startIndex || !(text[text.index(before: found.lowerBound)].isLetter || text[text.index(before: found.lowerBound)].isNumber) { return found }
            cursor = found.upperBound
        }
        return nil
    }
    static func matchesAll(_ terms: [String], in text: String) -> Bool { terms.allSatisfy { range(of: $0, in: text) != nil } }
}

enum ReaderText {
    static func terms(_ query: String) -> [String] { TextMatch.terms(query) }
    /// Scripture references become links; search terms are highlighted. Text is otherwise unchanged.
    static func attributed(_ text: String, terms: [String], linkReferences: Bool = true, linkNotes: Bool = false) -> AttributedString {
        var out = AttributedString(text)
        if linkNotes {
            let ns = text as NSString
            FootnoteMap.marker.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
                guard let match, let stringRange = Range(match.range, in: text),
                      let range = Range<AttributedString.Index>(stringRange, in: out) else { return }
                let number = ns.substring(with: match.range(at: 1))
                // A note's own leading number returns to the text; other markers open the note.
                out[range].link = URL(string: "thruline://\(match.range.location == 0 ? "noteref" : "note")/\(number)")
                out[range].foregroundColor = STColor.navy
            }
        }
        if linkReferences {
            for citation in ScriptureReferenceScanner.citations(in: text) {
                guard let stringRange = Range(citation.range, in: text),
                      let range = Range<AttributedString.Index>(stringRange, in: out) else { continue }
                out[range].link = PassageLink.url(citation.anchor)
                out[range].foregroundColor = STColor.navy
                out[range].underlineStyle = .single
            }
        }
        for term in terms {
            var cursor = text.startIndex
            while cursor < text.endIndex, let found = TextMatch.range(of: term, in: text, from: cursor) {
                if let range = Range<AttributedString.Index>(found, in: out) { out[range].backgroundColor = STColor.navy.opacity(0.22) }
                cursor = found.upperBound
            }
        }
        return out
    }
    /// About `length` characters around the first search term, for result lists.
    static func snippet(_ text: String, terms: [String], length: Int = 260) -> String {
        let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard let first = terms.lazy.compactMap({ TextMatch.range(of: $0, in: flat) ?? flat.range(of: $0, options: [.caseInsensitive]) }).first else {
            return String(flat.prefix(length))
        }
        let start = flat.index(first.lowerBound, offsetBy: -length / 3, limitedBy: flat.startIndex) ?? flat.startIndex
        let end = flat.index(start, offsetBy: length, limitedBy: flat.endIndex) ?? flat.endIndex
        return (start > flat.startIndex ? "…" : "") + flat[start..<end] + (end < flat.endIndex ? "…" : "")
    }
}

private struct ReaderScroll: Equatable { var paragraph: Int; var token = UUID() }

/// Reads one installed book: full-text search with highlighted matches, linked Bible references,
/// and opening at a requested section and paragraph.
struct ResourceBookReader: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow
    let book: ResourceBook
    var focus: LibraryFocus? = nil
    let back: () -> Void
    @State private var query = ""
    @State private var matches: [ResourceArticle] = []
    @State private var selected: String?
    @State private var limit = 100
    @State private var paragraphs: [String] = []
    @State private var linkedCount = 0
    @State private var focusedParagraph: Int?
    @State private var scroll: ReaderScroll?
    @State private var pendingFocus: LibraryFocus?
    @State private var notes = FootnoteMap()
    @State private var searching = false
    private var article: ResourceArticle? { book.articles.first { $0.id == selected } }
    private var terms: [String] { ReaderText.terms(query) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack { Button("Back to library", action: back); Spacer(); Text(book.author).font(.caption).foregroundStyle(.secondary) }
            Text(book.title).font(.title2)
            TextField("Search this book’s full text", text: $query).textFieldStyle(.roundedBorder)
            HSplitView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(searching ? "Searching…" : query.isEmpty ? "\(matches.count.formatted()) sections" : "\(matches.count.formatted()) of \(book.articles.count.formatted()) sections match")
                        .font(.caption).foregroundStyle(.secondary)
                    List(selection: $selected) {
                        ForEach(matches.prefix(limit)) { entry in Text(entry.displayTitle).lineLimit(3).tag(entry.id) }
                    }.listStyle(.plain)
                    if matches.count > limit { Button("Show 100 more") { limit += 100 } }
                }.frame(minWidth: 160, idealWidth: 190, maxWidth: 260)
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            if let article {
                                Text(article.displayTitle).font(state.studyTypeface.font(size: 24, weight: .semibold))
                                    .padding(.top, 10).id(-1)
                                if let anchor = article.anchor {
                                    Button(anchor.displayString) { open(anchor) }.buttonStyle(.link).font(.callout)
                                }
                                if linkedCount > 0 {
                                    Label("\(linkedCount) Bible references linked — click one to open the passage", systemImage: "link")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                ForEach(Array(paragraphs.enumerated()), id: \.offset) { index, paragraph in
                                    Text(ReaderText.attributed(paragraph, terms: terms, linkNotes: !notes.isEmpty))
                                        .font(state.studyTypeface.font(size: 17)).lineSpacing(6).textSelection(.enabled)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .padding(.vertical, 4).padding(.horizontal, 6)
                                        .background(index == focusedParagraph ? STColor.tileWell : .clear, in: RoundedRectangle(cornerRadius: 4))
                                        .id(index)
                                }
                            } else { Text("Choose a section to read.").foregroundStyle(.secondary) }
                        }
                        // A book's column, not a full-window line: about 70 characters at reading size.
                        .frame(maxWidth: 640, alignment: .leading).padding(.horizontal, 28).padding(.bottom, 40)
                        .frame(maxWidth: .infinity)
                    }
                    .onChange(of: scroll) { _, request in
                        guard let request else { return }
                        DispatchQueue.main.async { proxy.scrollTo(request.paragraph, anchor: .top) }
                    }
                }.frame(minWidth: 260)
            }
            DisclosureGroup("Attribution & edition details") {
                Text(book.attribution).font(.caption).textSelection(.enabled)
                Text("Bible references are detected automatically and open in the workspace. Older editions can number Psalms and some chapters differently (for example Latin or Greek Psalm numbering), so check the passage you land on.")
                    .font(.caption).foregroundStyle(.secondary)
                if let source = book.source, let url = URL(string: source), url.scheme == "https" { Link("Original publisher resource", destination: url) }
            }.font(.caption)
        }.padding(20).foregroundStyle(STColor.ink).background(STColor.paper)
        .environment(\.openURL, OpenURLAction { url in
            if url.scheme == "thruline", ["note", "noteref"].contains(url.host ?? "") {
                followNote(url.lastPathComponent, toNote: url.host == "note"); return .handled
            }
            guard let anchor = PassageLink.anchor(url) else { return .systemAction }
            open(anchor); return .handled
        })
        .task(id: book.id) {
            let articles = book.articles
            notes = await Task.detached(priority: .utility) { FootnoteMap.build(articles.map(\.paragraphs)) }.value
        }
        .onAppear {
            guard let focus, focus.bookID == book.id else { return }
            pendingFocus = focus
            query = focus.terms.joined(separator: " ")
            selected = focus.articleID
        }
        .task(id: query) {
            let text = query.trimmingCharacters(in: .whitespacesAndNewlines), articles = book.articles
            let words = ReaderText.terms(text)
            searching = !words.isEmpty
            let worker = Task.detached {
                articles.filter { article in words.isEmpty || TextMatch.matchesAll(words, in: article.title + " " + article.body) }
            }
            let found = await worker.value
            searching = false
            guard !Task.isCancelled else { return }
            matches = found; limit = 100
            if !found.contains(where: { $0.id == selected }) { selected = found.first?.id }
            else { loadSelected() }
        }
        .onChange(of: selected) { _, _ in loadSelected() }
    }

    private func loadSelected() {
        guard let article else { paragraphs = []; linkedCount = 0; return }
        paragraphs = article.paragraphs
        linkedCount = paragraphs.reduce(0) { $0 + ScriptureReferenceScanner.citations(in: $1).count }
        if let focus = pendingFocus, focus.articleID == article.id, let paragraph = focus.paragraph, paragraph < paragraphs.count {
            focusedParagraph = paragraph
            scroll = ReaderScroll(paragraph: paragraph)
            pendingFocus = nil
            return
        }
        focusedParagraph = nil
        let words = terms
        if !words.isEmpty, let first = paragraphs.firstIndex(where: { TextMatch.matchesAll(words, in: $0) })
            ?? paragraphs.firstIndex(where: { p in words.contains { TextMatch.matchesAll([$0], in: p) } }) {
            scroll = ReaderScroll(paragraph: first)
        } else {
            scroll = ReaderScroll(paragraph: -1)
        }
    }

    private func open(_ anchor: Anchor) {
        state.openPassage(anchor)
        openWindow(id: "workspace")
    }

    /// Footnote markers jump to the note; a note's own number jumps back to the text.
    private func followNote(_ number: String, toNote: Bool) {
        guard let current = book.articles.firstIndex(where: { $0.id == selected }) else { return }
        let here = FootnoteMap.Location(article: current, paragraph: focusedParagraph ?? 0)
        guard let target = toNote ? notes.noteLocation(number) : notes.bodyLocation(number, near: here),
              book.articles.indices.contains(target.article) else { return }
        let articleID = book.articles[target.article].id
        if !matches.contains(where: { $0.id == articleID }) { query = "" }
        pendingFocus = LibraryFocus(bookID: book.id, articleID: articleID, paragraph: target.paragraph)
        if selected == articleID { loadSelected() } else { selected = articleID }
    }
}

/// Paragraphs from your installed books that cite the current passage.
struct LibraryCitationsPanel: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var books: ResourceBookLibrary
    let anchor: Anchor?
    var startsExpanded = false
    @State private var expanded = false
    @State private var limit = 12

    var body: some View {
        if let anchor {
            let hits = books.citations.citing(anchor)
            if !hits.isEmpty {
                DisclosureGroup("From your library · \(hits.count) \(hits.count == 1 ? "citation" : "citations")", isExpanded: $expanded) {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Quotations from installed books whose text cites this passage. References are detected automatically; inclusion is not doctrinal endorsement.")
                            .font(.caption).foregroundStyle(STColor.secondary)
                        ForEach(hits.prefix(limit)) { hit in row(hit) }
                        if hits.count > limit { Button("Show \(min(12, hits.count - limit)) more") { limit += 12 } .font(.callout) }
                    }.padding(.top, 8)
                }.font(.headline).padding(14)
                .onAppear { if startsExpanded { expanded = true } }
                .onChange(of: anchor) { _, _ in limit = 12 }
            }
        }
    }

    @ViewBuilder private func row(_ hit: LibraryCitation) -> some View {
        let paragraph = books.book(id: hit.bookID)?.articles.first { $0.id == hit.articleID }?.paragraphs[safe: hit.paragraph] ?? ""
        VStack(alignment: .leading, spacing: 5) {
            Text("\(hit.author) · \(hit.bookTitle)").font(.system(size: 12, weight: .semibold))
            Text("\(ResourceArticle.tidy(hit.articleTitle)) · cites \(hit.reference.split(whereSeparator: \.isWhitespace).joined(separator: " "))" + (hit.footnote.map { " in note \($0)" } ?? ""))
                .font(.caption).foregroundStyle(STColor.secondary).lineLimit(2)
            Text(ReaderText.attributed(ReaderText.snippet(paragraph, terms: [hit.footnote.map { "[\($0)]" } ?? hit.reference.split(whereSeparator: \.isWhitespace).joined(separator: " ")], length: 340), terms: [], linkReferences: false))
                .font(.system(size: 14, design: .serif)).lineSpacing(3).textSelection(.enabled)
            Button("Read in context") {
                state.libraryRequest = LibraryFocus(bookID: hit.bookID, articleID: hit.articleID, paragraph: hit.paragraph)
                openWindow(id: "resource-library")
            }.buttonStyle(.link).font(.callout)
            .accessibilityLabel("Read \(hit.bookTitle), \(hit.articleTitle), in context")
            Divider()
        }.font(.callout)
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}

/// Builds bounded, labelled source attachments for the AI chat.
@MainActor
enum AIContextBuilder {
    /// Room left for the question and system guidance inside the on-Mac model's 6,000-byte window.
    static let localBudget = 4_300

    /// Shortens an attachment to `budget` UTF-8 bytes at a line boundary, saying so.
    static func fit(_ text: String, budget: Int) -> String {
        guard text.utf8.count > budget else { return text }
        let note = "\n[Shortened to fit the on-Mac model. Attach a shorter passage for the rest.]"
        var out = ""
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            guard out.utf8.count + line.utf8.count + 1 + note.utf8.count <= budget else { break }
            out += line + "\n"
        }
        return out + note
    }

    /// Quotations from installed books that cite a passage, one per citing paragraph, labelled with their source.
    static func library(_ hits: [LibraryCitation], passage: String, books: ResourceBookLibrary, budget: Int) -> String {
        var out = "Quotations from the reader's installed historic books that cite \(passage). Each is exact source text from the named edition; references were detected automatically.\n"
        var used = 0
        for hit in hits {
            guard let paragraph = books.book(id: hit.bookID)?.articles.first(where: { $0.id == hit.articleID })?.paragraphs[safe: hit.paragraph] else { continue }
            let reference = hit.reference.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            let excerpt = ReaderText.snippet(paragraph, terms: [hit.footnote.map { "[\($0)]" } ?? reference], length: 520)
            let entry = "\n— \(hit.author), \(hit.bookTitle), \(hit.articleTitle.split(whereSeparator: \.isWhitespace).joined(separator: " ")) (cites \(reference)\(hit.footnote.map { " in note \($0)" } ?? "")):\n\"\(excerpt)\"\n"
            guard out.utf8.count + entry.utf8.count + 80 <= budget else { break }
            out += entry; used += 1
        }
        if used < hits.count { out += "\n[\(used) of \(hits.count) citing passages included to fit the model.]" }
        return out
    }
}
