import Foundation

// MARK: - Data model
//
// Matches the schema `scripts/build-standards.py` writes to
// `Resources/Confession/standards/<id>.json` and `proof-index.json`. See
// `scripts/standards-sources/SOURCES.md` for per-document provenance and licence evidence.

/// One Scripture proof text cited by a confession/catechism item, as the confession itself
/// cites it (a specific verse or verse range) — never an app-generated judgment about the verse.
struct StandardProof: Codable, Hashable, Sendable {
    let ref: String
    let code: String
    let chapter: Int
    let start: Int
    let end: Int
}

/// One numbered unit of a standard: a WCF chapter section, a catechism question, a confession
/// article, or a Canons of Dort article/Rejection-of-Errors paragraph.
struct StandardItem: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let label: String
    let heading: String?
    let question: String?
    let text: String
    let proofs: [StandardProof]

    init(id: String, label: String, heading: String? = nil, question: String? = nil,
         text: String, proofs: [StandardProof] = []) {
        self.id = id; self.label = label; self.heading = heading
        self.question = question; self.text = text; self.proofs = proofs
    }
}

/// One confessional document: the Westminster Confession/Larger/Shorter Catechisms, the
/// Heidelberg Catechism, the Belgic Confession, or the Canons of Dort.
struct StandardDocument: Codable, Hashable, Sendable, Identifiable {
    let id: String
    let title: String
    let shortTitle: String
    let year: Int
    let translation: String
    let sourceURL: String
    let license: String
    let kind: String
    let items: [StandardItem]
}

/// One confessional/catechism section resolved against a specific verse — the unit
/// `ProofTextsSection` renders. Always labelled as a citation *by* the document, never as the
/// app's own theological judgment (see `ProofTextsSection`'s header copy).
struct StandardCitation: Identifiable, Hashable, Sendable {
    let docID: String
    let docShortTitle: String
    let docTitle: String
    let item: StandardItem

    var id: String { "\(docID)#\(item.id)" }
    var label: String { item.label }
    var heading: String? { item.heading }
    var question: String? { item.question }
    var text: String { item.text }
    var proofs: [StandardProof] { item.proofs }
}

private struct ProofIndexEntry: Codable { let doc: String; let item: String }
private struct ProofIndexFile: Codable { let schema: Int; let index: [String: [ProofIndexEntry]] }

/// Loads the six bundled confessional standards and their verse -> citation reverse index.
/// Lazy: nothing is read from disk until the first call to `documents` or `citations`; both are
/// then cached for the store's lifetime. Read-only — this never touches `ConfessionStore` /
/// `wcf-links.json` (the curated, human-reviewed Westminster link system), which stays exactly
/// as workstream C/prior passes left it. A proof text here is a fact about the confession's own
/// printed text, not a claim that any particular source or commentary is "WCF-aligned."
@MainActor
final class StandardsStore {
    private let directory: URL?
    private var loadedDocuments: [StandardDocument]?
    private var itemLookup: [String: StandardItem] = [:]  // "docID#itemID" -> item
    private var docLookup: [String: StandardDocument] = [:]
    private var proofIndex: [String: [ProofIndexEntry]]?
    /// Problems found while loading (bad JSON, missing files). Empty is healthy.
    private(set) var diagnostics: [String] = []

    init(directory: URL? = AppResources.url("Confession/standards")) {
        self.directory = directory
    }

    /// All six documents, in a fixed reading order (WCF, WLC, WSC, HC, Belgic, Canons of Dort).
    var documents: [StandardDocument] {
        if let loadedDocuments { return loadedDocuments }
        let order = ["wcf", "wlc", "wsc", "hc", "bc", "cd"]
        var result: [StandardDocument] = []
        for id in order {
            guard let url = directory?.appendingPathComponent("\(id).json"),
                  let data = try? Data(contentsOf: url) else {
                diagnostics.append("\(id): missing")
                continue
            }
            do {
                let doc = try JSONDecoder().decode(StandardDocument.self, from: data)
                result.append(doc)
                docLookup[doc.id] = doc
                for item in doc.items { itemLookup["\(doc.id)#\(item.id)"] = item }
            } catch {
                diagnostics.append("\(id): \(error.localizedDescription)")
            }
        }
        loadedDocuments = result
        return result
    }

    func document(id: String) -> StandardDocument? {
        _ = documents  // ensure loaded
        return docLookup[id]
    }

    /// Which confession/catechism sections cite this verse as a proof text, in the same
    /// document order as `documents`. Empty when nothing does (most verses).
    func citations(bookCode: String, chapter: Int, verse: Int) -> [StandardCitation] {
        _ = documents  // ensure docLookup/itemLookup are populated first
        if proofIndex == nil {
            proofIndex = loadProofIndex()
        }
        let key = "\(bookCode).\(chapter).\(verse)"
        guard let entries = proofIndex?[key] else { return [] }
        let docOrder = documents.map(\.id)
        return entries
            .compactMap { entry -> StandardCitation? in
                guard let doc = docLookup[entry.doc], let item = itemLookup["\(entry.doc)#\(entry.item)"] else { return nil }
                return StandardCitation(docID: doc.id, docShortTitle: doc.shortTitle, docTitle: doc.title, item: item)
            }
            .sorted { a, b in
                let ai = docOrder.firstIndex(of: a.docID) ?? 0
                let bi = docOrder.firstIndex(of: b.docID) ?? 0
                // Number-aware: "3.6" before "20.1", "Q2" before "Q45" (plain string order put WCF 20.1 first).
                return ai != bi ? ai < bi : a.item.id.localizedStandardCompare(b.item.id) == .orderedAscending
            }
    }

    private func loadProofIndex() -> [String: [ProofIndexEntry]] {
        guard let url = directory?.appendingPathComponent("proof-index.json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(ProofIndexFile.self, from: data) else {
            diagnostics.append("proof-index.json: missing or unreadable")
            return [:]
        }
        return file.index
    }
}
