import SwiftUI

struct MorphologyQuery: Equatable, Sendable {
    var lemma = ""
    var morphology = ""
    var language = ""
    var hasFilter: Bool { !lemma.trimmingCharacters(in: .whitespaces).isEmpty || !morphology.trimmingCharacters(in: .whitespaces).isEmpty }
    func matches(_ word: InterlinearWord) -> Bool {
        guard language.isEmpty || word.language.rawValue == language else { return false }
        let lemma = lemma.trimmingCharacters(in: .whitespacesAndNewlines)
        let morph = morphology.trimmingCharacters(in: .whitespacesAndNewlines)
        let lexical = lemma.isEmpty || word.strongs.contains(where: { let target = InterlinearStore.baseStrong(lemma.uppercased()); return target != nil && InterlinearStore.baseStrong($0) == target }) || word.lemma == lemma
        let grammar = morph.isEmpty || word.morphCode.localizedCaseInsensitiveContains(morph) || morph.split(whereSeparator: \.isWhitespace).allSatisfy { word.morphDescription.localizedCaseInsensitiveContains(String($0)) }
        return lexical && grammar
    }
}
struct MorphologyHit: Identifiable, Sendable {
    var id: String
    var anchor: Anchor
    var word: InterlinearWord
}
struct MorphologyPage: Sendable { var hits: [MorphologyHit]; var total: Int; var unreadable: Int }
enum MorphologySearch {
    private struct Chapter: Decodable { let verses: [String: [InterlinearWord]] }
    static func search(_ query: MorphologyQuery, root: URL, offset: Int) throws -> MorphologyPage {
        var result = MorphologyPage(hits: [], total: 0, unreadable: 0)
        guard query.hasFilter else { return result }
        for book in BookTable.all {
            for chapter in 1...book.chapters {
                try Task.checkCancellation()
                let file = root.appendingPathComponent(book.code).appendingPathComponent("\(chapter).json")
                guard FileManager.default.fileExists(atPath: file.path) else { continue }
                guard let data = try? Data(contentsOf: file), let content = try? JSONDecoder().decode(Chapter.self, from: data) else { result.unreadable += 1; continue }
                for verse in content.verses.keys.compactMap(Int.init).sorted() {
                    for (position, word) in (content.verses[String(verse)] ?? []).enumerated() where query.matches(word) {
                        if result.total >= offset, result.hits.count < 40 {
                            result.hits.append(.init(id: "\(book.code).\(chapter).\(verse).\(position)", anchor: Anchor(book: book.code, chapter: chapter, verse: verse), word: word))
                        }
                        result.total += 1
                    }
                }
            }
        }
        return result
    }
}

struct MorphologySearchView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var query = MorphologyQuery()
    @State private var submitted = MorphologyQuery()
    @State private var revision = UUID()
    @State private var offset = 0
    @State private var page: MorphologyPage?
    @State private var busy = false
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("Original-language search").font(.title2); Spacer(); Button("Done") { dismiss() } }
            HStack {
                TextField("Strong’s number or exact lemma (G26, ἀγάπη)", text: $query.lemma).textFieldStyle(.roundedBorder)
                Picker("Language", selection: $query.language) {
                    Text("All languages").tag(""); Text("Greek").tag("G"); Text("Hebrew").tag("H"); Text("Aramaic").tag("A")
                }.frame(width: 190)
            }
            HStack {
                TextField("Grammar words or code (aorist active, V-AAI)", text: $query.morphology).textFieldStyle(.roundedBorder).onSubmit(run)
                Button("Search", action: run).disabled(!query.hasFilter)
            }
            Text("Search tagged Hebrew, Aramaic and Greek words. Grammar words must all match the word’s description. Edition variants remain separate occurrences.")
                .font(.caption).foregroundStyle(.secondary)
            if busy { ProgressView("Searching tagged words…").frame(maxWidth: .infinity, maxHeight: .infinity) }
            else if let error { Text(error).foregroundStyle(.secondary); Spacer() }
            else if let page {
                List(page.hits) { hit in
                    Button {
                        state.navigate(bookCode: hit.anchor.book, chapter: hit.anchor.chapterStart, verse: hit.anchor.verseStart)
                        state.focusMode = false; state.showStudyDesk = true; state.setDeskSectionVisible(.originalLanguage, true)
                        state.requestedStudyTool = .originalLanguage; state.deskMode = .tools; dismiss()
                    } label: {
                        VStack(alignment: .leading, spacing: 5) {
                            HStack { Text(hit.word.surface).font(.title3); Text(hit.word.gloss); Spacer(); Text(hit.anchor.displayString).font(.callout) }
                            Text(hit.word.morphDescription).font(.callout)
                            Text("\(hit.word.strongs.joined(separator: ", ")) · \(hit.word.morphCode)" + (hit.word.variant == nil ? "" : " · Edition/variant flag")).font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6).contentShape(Rectangle())
                    }.buttonStyle(.plain)
                }.listStyle(.plain)
                HStack {
                    Text("\(page.total.formatted()) tagged occurrences").font(.callout)
                    if page.unreadable > 0 { Text("\(page.unreadable) files unreadable").font(.caption) }
                    Spacer()
                    Button("Previous") { offset = max(0, offset - 40); revision = UUID() }.disabled(offset == 0)
                    Button("Next") { offset += 40; revision = UUID() }.disabled(offset + page.hits.count >= page.total)
                }
            } else { ContentUnavailableView("Explore how a word is used", systemImage: "character.book.closed", description: Text("Enter a Strong’s number, lemma, or grammatical form.")) }
            Text("STEPBible TAHOT / TAGNT and TEHMC / TEGMC · Tyndale House Cambridge · CC BY 4.0. Tagged-source versification can differ from your English Bible.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(16)
        .task(id: revision) {
            guard submitted.hasFilter, let root = AppResources.url("Interlinear") else { return }
            busy = true; error = nil
            let query = submitted, offset = offset
            let worker = Task.detached { try MorphologySearch.search(query, root: root, offset: offset) }
            do {
                let found = try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                guard !Task.isCancelled else { return }; page = found
            } catch { guard !Task.isCancelled else { return }; self.error = "Search could not finish. Try again." }
            busy = false
        }
    }
    private func run() { submitted = query; offset = 0; revision = UUID() }
}
