import Foundation

/// Guide scope stays independent of the reader cursor when an explicit passage is entered.
/// Following is an explicit action, so opening a reference never silently replaces a pinned guide.
struct PassageGuideScope: Equatable {
    private(set) var explicitAnchor: Anchor?
    var followsSelection: Bool { explicitAnchor == nil }
    func anchor(selection: Anchor?) -> Anchor? { explicitAnchor ?? selection }
    mutating func pin(_ anchor: Anchor) { explicitAnchor = anchor }
    mutating func followSelection() { explicitAnchor = nil }
}

struct PassageGuideVerse: Hashable, Identifiable {
    let chapter: Int
    let verse: Int
    var id: String { "\(chapter):\(verse)" }
}

struct PassageGuideSource: Identifiable {
    let resolved: ResolvedSource
    var verses: [PassageGuideVerse]
    var id: String { resolved.id }
}

struct PassageGuideCrossReference: Identifiable {
    let reference: CrossReference
    var from: [PassageGuideVerse]
    var sources: [ResolvedSource] = []
    var id: String { reference.id }
}

struct PassageGuideTopic: Identifiable {
    let name: String
    var direct: [PassageGuideVerse] = []
    /// ReferenceStore's additional index mixes direct matches beyond the display cap with
    /// broader-passage citations. Membership alone does not establish citation width.
    var additional: [PassageGuideVerse] = []
    var id: String { name }
}

struct PassageGuidePerson: Identifiable {
    let id: String
    let name: TIPNRName
    var verses: [PassageGuideVerse]
}

struct PassageGuideResult {
    let anchor: Anchor
    let verses: [PassageGuideVerse]
    let sources: [PassageGuideSource]
    let crossReferences: [PassageGuideCrossReference]
    let topics: [PassageGuideTopic]
    let people: [PassageGuidePerson]
    let personal: StudyItems
}

enum PassageGuideError: LocalizedError, Equatable {
    case invalidReference
    case tooManyChapters
    case missingChapter(Int)
    case missingVerse(Int, Int)

    var errorDescription: String? {
        switch self {
        case .invalidReference: "Enter one passage, such as Rom 8:28–39 or Rom 8:39–9:5."
        case .tooManyChapters: "Choose a passage of up to 5 chapters. The guide never truncates your scope."
        case .missingChapter(let chapter): "Chapter \(chapter) is unavailable in the bundled BSB reference text."
        case .missingVerse(let chapter, let verse): "Verse \(chapter):\(verse) is not present in the bundled BSB reference text."
        }
    }
}

/// Aggregates existing stores, preserving source IDs, provenance and primary/additional index scope.
/// All anchors use the app's BSB reference versification, independent of the reader's translation.
@MainActor
struct PassageGuideService {
    let library: ScriptureLibrary
    let resources: StudyResourceStore
    let references: ReferenceStore
    let study: StudyStore

    func parse(_ text: String) throws -> Anchor {
        guard let anchor = Anchor.parse(text) ?? Anchor(osis: text) else { throw PassageGuideError.invalidReference }
        _ = try verses(in: anchor)
        return anchor
    }

    func verses(in anchor: Anchor) throws -> [PassageGuideVerse] {
        guard let book = BookTable.info(code: anchor.book),
              anchor.chapterStart >= 1, anchor.chapterEnd >= anchor.chapterStart,
              anchor.chapterEnd <= book.chapters,
              anchor.verseStart >= 0, anchor.verseEnd >= 0,
              anchor.verseStart < Anchor.endOfChapter, anchor.verseEnd <= Anchor.endOfChapter else {
            throw PassageGuideError.invalidReference
        }
        guard anchor.chapterEnd - anchor.chapterStart < 5 else { throw PassageGuideError.tooManyChapters }
        var result: [PassageGuideVerse] = []
        for chapter in anchor.chapterStart...anchor.chapterEnd {
            guard let text = library.chapter(translation: "BSB", bookCode: anchor.book, chapter: chapter),
                  text.contains(where: { $0.number > 0 }) else { throw PassageGuideError.missingChapter(chapter) }
            let numbers = Set(text.filter { $0.number > 0 }.map(\.number))
            let lower = chapter == anchor.chapterStart ? anchor.verseStart : 0
            let upper = chapter == anchor.chapterEnd ? anchor.verseEnd : Anchor.endOfChapter
            if lower > 0, !numbers.contains(lower) { throw PassageGuideError.missingVerse(chapter, lower) }
            if upper != Anchor.endOfChapter, !numbers.contains(upper) { throw PassageGuideError.missingVerse(chapter, upper) }
            result += numbers.sorted().filter { $0 >= lower && $0 <= upper }
                .map { PassageGuideVerse(chapter: chapter, verse: $0) }
        }
        guard !result.isEmpty else { throw PassageGuideError.invalidReference }
        return result
    }

    func build(anchor: Anchor, traditions: Set<SourceTradition>, includeResearch: Bool) throws -> PassageGuideResult {
        let scope = try verses(in: anchor)
        let bookName = anchor.bookInfo?.name ?? anchor.book
        var sources: [String: PassageGuideSource] = [:]
        var sourceOrder: [String] = []
        var crossRefs: [String: PassageGuideCrossReference] = [:]
        var refOrder: [String] = []
        var topics: [String: PassageGuideTopic] = [:]
        var people: [String: PassageGuidePerson] = [:]
        for position in scope {
            for resolved in resources.sources(bookCode: anchor.book, bookName: bookName,
                chapter: position.chapter, verse: position.verse, includeResearchTier: includeResearch)
                where traditions.contains(resolved.entry.tradition) {
                if sources[resolved.id] == nil {
                    sources[resolved.id] = PassageGuideSource(resolved: resolved, verses: [])
                    sourceOrder.append(resolved.id)
                }
                sources[resolved.id]?.verses.append(position)
                for reference in resolved.entry.crossRefs {
                    if crossRefs[reference.id] == nil {
                        crossRefs[reference.id] = PassageGuideCrossReference(reference: reference, from: [])
                        refOrder.append(reference.id)
                    }
                    if crossRefs[reference.id]?.from.contains(position) == false { crossRefs[reference.id]?.from.append(position) }
                    if crossRefs[reference.id]?.sources.contains(where: { $0.id == resolved.id }) == false {
                        crossRefs[reference.id]?.sources.append(resolved)
                    }
                }
            }
            for name in references.topics(bookCode: anchor.book, chapter: position.chapter, verse: position.verse) {
                if topics[name] == nil { topics[name] = PassageGuideTopic(name: name) }
                topics[name]?.direct.append(position)
            }
            for name in references.moreTopics(bookCode: anchor.book, chapter: position.chapter, verse: position.verse) {
                if topics[name] == nil { topics[name] = PassageGuideTopic(name: name) }
                topics[name]?.additional.append(position)
            }
            for name in references.names(bookCode: anchor.book, chapter: position.chapter, verse: position.verse) {
                // TIPNR can contain distinct people bearing the same name. Retain the complete
                // record identity instead of collapsing them by display name.
                let id = ([name.kind, name.name, name.description] + name.refs.map(\.id)).joined(separator: "\u{001F}")
                if people[id] == nil { people[id] = PassageGuidePerson(id: id, name: name, verses: []) }
                people[id]?.verses.append(position)
            }
        }
        return PassageGuideResult(anchor: anchor, verses: scope,
            sources: sourceOrder.compactMap { sources[$0] }, crossReferences: refOrder.compactMap { crossRefs[$0] },
            topics: topics.values.sorted {
                if $0.direct.isEmpty != $1.direct.isEmpty { return !$0.direct.isEmpty }
                return $0.name.localizedStandardCompare($1.name) == .orderedAscending
            }, people: people.values.sorted {
                if $0.name.name != $1.name.name { return $0.name.name.localizedStandardCompare($1.name.name) == .orderedAscending }
                return $0.id < $1.id
            }, personal: study.items(overlapping: anchor))
    }
}
