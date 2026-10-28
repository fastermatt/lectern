import Foundation

/// The curated Westminster Confession link index.
///
/// A link exists only because a named human reviewed a specific excerpt against a
/// specific WCF article. Being a Reformed source never creates one, and records in the
/// `candidate` or `rejected` state are never exposed to the interface.
@MainActor
final class ConfessionStore {
    private struct LinkFile: Codable { let schema: Int; let links: [ConfessionLink] }
    private struct ChapterFile: Codable { let schema: Int; let chapters: [ConfessionChapter] }
    private struct CreedsFile: Codable { let schema: Int; let creeds: [Creed] }

    private(set) var chapters: [Int: ConfessionChapter] = [:]
    private(set) var chapterList: [ConfessionChapter] = []
    private(set) var creeds: [Creed] = []
    private(set) var allRecords: [ConfessionLink] = []
    private var displayable: [String: [ConfessionLink]] = [:]

    init(chaptersURL: URL? = AppResources.url("Confession/wcf-chapters.json"),
         bundledLinksURL: URL? = AppResources.url("Confession/wcf-links.json"),
         localLinksURL: URL? = AppResources.localConfessionLinks,
         creedsURL: URL? = AppResources.url("Confession/creeds.json")) {
        if let chaptersURL, let file: ChapterFile = Self.decode(chaptersURL) {
            chapters = Dictionary(uniqueKeysWithValues: file.chapters.map { ($0.n, $0) })
            chapterList = file.chapters.sorted { $0.n < $1.n }
        }
        if let creedsURL, let file: CreedsFile = Self.decode(creedsURL) {
            creeds = file.creeds
        }
        var merged: [String: ConfessionLink] = [:]
        for url in [bundledLinksURL, localLinksURL].compactMap({ $0 }) {
            guard let file: LinkFile = Self.decode(url), file.schema == 1 else { continue }
            for link in file.links { merged["\(link.entryID)#\(link.wcf.label)"] = link }
        }
        allRecords = merged.values.sorted { $0.id < $1.id }
        for link in allRecords where isValid(link) {
            displayable[link.entryID, default: []].append(link)
        }
    }

    /// Links that may be shown next to an entry: curated, attributed, dated, and pointing
    /// at a real chapter and section.
    func links(forEntryID id: String) -> [ConfessionLink] { displayable[id] ?? [] }

    var displayableCount: Int { displayable.values.reduce(0) { $0 + $1.count } }

    func isValid(_ link: ConfessionLink) -> Bool {
        guard link.isDisplayable, let chapter = chapters[link.wcf.chapter] else { return false }
        if let section = link.wcf.section { return (1...chapter.sections).contains(section) }
        return true
    }

    /// Problems in the loaded records (unknown entries, bad references). Used by tests
    /// and the review tooling; an empty result means the store is internally consistent.
    func problems(knownEntryIDs: Set<String>) -> [String] {
        var found: [String] = []
        for link in allRecords {
            if !knownEntryIDs.contains(link.entryID) { found.append("orphaned link \(link.id)") }
            guard let chapter = chapters[link.wcf.chapter] else {
                found.append("unknown WCF chapter in \(link.id)"); continue
            }
            if let section = link.wcf.section, !(1...chapter.sections).contains(section) {
                found.append("WCF \(chapter.n) has no section \(section) (\(link.id))")
            }
            if link.state == .curated, !link.isDisplayable {
                found.append("curated link without reviewer or date: \(link.id)")
            }
        }
        return found
    }

    private static func decode<T: Decodable>(_ url: URL) -> T? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
