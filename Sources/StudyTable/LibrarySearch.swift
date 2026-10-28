import Foundation
import SwiftUI

struct LibraryTextHit: Identifiable, Sendable {
    var id: String
    var title: String
    var collection: String
    var body: String
    var anchor: Anchor?
    var source: URL?
    var attribution: String
}
struct LibraryTextPage: Sendable { var hits: [LibraryTextHit]; var total: Int; var unreadable: Int }
enum LibraryTextScope: String, CaseIterable, Identifiable, Sendable {
    case all = "All texts", commentary = "Commentaries", books = "My books", notes = "My notes"
    var id: String { rawValue }
}

/// Scans one chapter at a time off the UI thread. Source files remain the authority, and
/// results never include hidden disputed sources. No persistent copy of private notes is made.
enum LibraryTextSearch {
    private struct Chapter: Decodable { let code: String; let schema: Int; let entries: [StudySource] }
    static func search(query: String, scope: LibraryTextScope, offset: Int, studyRoot: URL?,
                       books: [ResourceBook], notes: [Note], historicRoot: URL?, includeResearch: Bool) throws -> LibraryTextPage {
        let terms = query.lowercased().split(whereSeparator: \.isWhitespace).map(String.init)
        guard !terms.isEmpty else { return .init(hits: [], total: 0, unreadable: 0) }
        var result = LibraryTextPage(hits: [], total: 0, unreadable: 0)
        func consider(_ hit: LibraryTextHit) {
            let text = (hit.title + " " + hit.body + " " + hit.collection).lowercased()
            guard terms.allSatisfy({ text.contains($0) }) else { return }
            if result.total >= offset, result.hits.count < 40 { result.hits.append(hit) }
            result.total += 1
        }
        if scope == .all || scope == .notes {
            for note in notes {
                try Task.checkCancellation()
                consider(.init(id: "note:" + note.id.uuidString, title: note.title.isEmpty ? "Untitled note" : note.title,
                    collection: "My notes", body: ([note.body] + note.sections.map(\.text) + note.tags).joined(separator: "\n\n"), anchor: note.anchors.first, source: nil, attribution: "Your private note · stored on this Mac"))
            }
        }
        if scope == .all || scope == .books {
            for book in books.sorted(by: { $0.title < $1.title }) {
                for article in book.articles {
                    try Task.checkCancellation()
                    consider(.init(id: book.id + ":" + article.id, title: article.title, collection: book.title,
                        body: article.body, anchor: article.anchor, source: book.source.flatMap(URL.init(string:)), attribution: book.attribution))
                }
            }
            if let root = historicRoot, let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey]) {
                for file in files.filter({ $0.pathExtension == "xml" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
                    try Task.checkCancellation()
                    let values = try? file.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
                    guard values?.isSymbolicLink != true, (values?.fileSize ?? Int.max) <= 30 * 1024 * 1024,
                          let data = try? Data(contentsOf: file), let work = TEIParser.parse(data) else { result.unreadable += 1; continue }
                    for (index, section) in work.sections.enumerated() {
                        consider(.init(id: "tcp:" + file.lastPathComponent + ":\(index)", title: section.heading, collection: work.title,
                            body: section.body, anchor: nil, source: URL(string: "https://textcreationpartnership.org/"), attribution: "EEBO-TCP public text edition · \(file.deletingPathExtension().lastPathComponent) · \(work.author)"))
                    }
                }
            }
        }
        if scope == .all || scope == .commentary, let root = studyRoot {
            for book in BookTable.all {
                for chapter in 1...book.chapters {
                    try Task.checkCancellation()
                    let file = root.appendingPathComponent(book.code).appendingPathComponent("\(chapter).json")
                    guard FileManager.default.fileExists(atPath: file.path) else { continue }
                    guard let data = try? Data(contentsOf: file), let content = try? JSONDecoder().decode(Chapter.self, from: data), content.schema == 3 else { result.unreadable += 1; continue }
                    var seen = Set<String>()
                    for entry in content.entries where !entry.excerpt.isEmpty && (includeResearch || entry.tier != .tier3ResearchOnly) && seen.insert(entry.id).inserted {
                        consider(.init(id: "commentary:" + entry.id, title: entry.work, collection: entry.author,
                            body: entry.excerpt, anchor: Anchor(book: book.code, chapter: entry.chapter, verses: entry.startVerse, to: entry.endVerse),
                            source: entry.sourceURL, attribution: "\(entry.isExactQuote ? "Source quotation" : "Editorial summary") · \(entry.tradition.rawValue) · \(entry.source)"))
                    }
                }
            }
        }
        return result
    }
}

struct SearchWorkspace: View {
    @ObservedObject var session: BibleSearchSession
    @State private var selected = 0
    private let titles = ["Bible", "Library & notes", "Original languages"]
    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(titles.indices, id: \.self) { index in
                    Button { selected = index } label: {
                        HStack(spacing: 6) {
                            if selected == index { Image(systemName: "checkmark") }
                            Text(titles[index])
                        }
                        .font(.system(size: 13, weight: .medium))
                        .frame(maxWidth: .infinity).frame(height: 32)
                        .foregroundStyle(selected == index ? STColor.lcdInk : STColor.ink)
                        .background(selected == index ? STColor.lcd : STColor.keyTop, in: RoundedRectangle(cornerRadius: 5))
                    }.buttonStyle(.plain).accessibilityAddTraits(selected == index ? .isSelected : [])
                }
            }
            Group {
                if selected == 0 { BibleSearchView(session: session) }
                else if selected == 1 { LibraryTextSearchView() }
                else { MorphologySearchView() }
            }.frame(width: 760, height: 620)
        }.padding(12).frame(width: 790, height: 690).background(STColor.paper)
    }
}

private struct LibraryTextSearchView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var submitted = ""
    @State private var scope = LibraryTextScope.all
    @State private var offset = 0
    @State private var revision = UUID()
    @State private var page: LibraryTextPage?
    @State private var busy = false
    @State private var error: String?
    @State private var detail: LibraryTextHit?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Search your library").font(.title2); Spacer(); Button("Done") { dismiss() } }
            HStack {
                TextField("Words to find in every text", text: $query).textFieldStyle(.roundedBorder).onSubmit(run)
                Button("Search", action: run)
            }
            Picker("Look in", selection: $scope) { ForEach(LibraryTextScope.allCases) { Text($0.rawValue).tag($0) } }.pickerStyle(.segmented)
                .onChange(of: scope) { _, _ in run() }
            Text("Matches all entered words. Searches commentary text, installed books and notes. Bible text and Boolean queries use the Bible tab.")
                .font(.caption).foregroundStyle(.secondary)
            if busy { ProgressView("Searching local texts…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let error { ContentUnavailableView(error, systemImage: "exclamationmark.triangle") }
            else if let page {
                List(page.hits) { hit in
                    Button { detail = hit } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            Text(hit.title).font(.headline)
                            Text(hit.collection + (hit.anchor.map { " · " + $0.displayString } ?? "")).font(.caption).foregroundStyle(.secondary)
                            Text(hit.body.prefix(240)).font(.callout).lineLimit(3)
                        }.padding(.vertical, 7).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }.listStyle(.plain)
                if page.total == 0 { Text("No matching texts. Try fewer words or another library scope.").foregroundStyle(.secondary) }
                HStack {
                    Text(page.total == 0 ? "0 results" : "\(offset + 1)–\(offset + page.hits.count) of \(page.total.formatted()) results").font(.callout)
                    if page.unreadable > 0 { Text("\(page.unreadable) files could not be read").font(.caption) }
                    Spacer()
                    Button("Previous") { offset = max(0, offset - 40); revision = UUID() }.disabled(offset == 0)
                    Button("Next") { offset += 40; revision = UUID() }.disabled(offset + page.hits.count >= page.total)
                }
            } else { ContentUnavailableView("Find ideas across your books", systemImage: "text.magnifyingglass", description: Text("Search a topic, author, or phrase. Nothing leaves your Mac.")) }
        }.padding(16)
        .task(id: revision) {
            guard !submitted.isEmpty else { page = nil; return }
            busy = true; error = nil
            let query = submitted, scope = scope, offset = offset, root = state.studyResources.searchDirectory
            let books = state.resourceBooks.books, notes = state.study.allNotes, research = state.showResearchTier
            let historic = AppResources.supportDirectory.appendingPathComponent("PuritanLibrary")
            let worker = Task.detached {
                try LibraryTextSearch.search(query: query, scope: scope, offset: offset, studyRoot: root, books: books, notes: notes, historicRoot: historic, includeResearch: research)
            }
            do {
                let value = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled else { return }; page = value
            } catch { guard !Task.isCancelled else { return }; self.error = "Search could not finish. Please try again." }
            busy = false
        }
        .sheet(item: $detail) { hit in
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text(hit.title).font(.headline); Spacer(); Button("Done") { detail = nil } }
                Text(hit.collection).foregroundStyle(.secondary)
                if let anchor = hit.anchor {
                    Button("Read \(anchor.displayString) in workspace") { state.navigate(bookCode: anchor.book, chapter: anchor.chapterStart, verse: max(1, anchor.verseStart)); detail = nil; dismiss() }
                }
                ScrollView { Text(hit.body).font(.system(size: 16, design: .serif)).lineSpacing(5).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                Text(hit.attribution).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                if let url = hit.source, url.scheme == "https" || url.scheme == "http" { Link("Original source", destination: url) }
            }.padding(22).frame(width: 650, height: 560)
        }
    }
    private func run() { submitted = query.trimmingCharacters(in: .whitespacesAndNewlines); offset = 0; revision = UUID() }
}
