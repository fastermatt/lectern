import Foundation

// MARK: - Models

/// One entry in the Puritan Library catalogue.
struct PuritanCatalogueEntry: Decodable, Sendable, Identifiable {
    let tcpId: String
    let author: String
    let title: String
    let partLabel: String?
    let bibleReference: String?
    let year: Int?
    let note: String?

    var id: String { tcpId }

    /// Human-readable subtitle for list display.
    var displaySubtitle: String {
        var parts: [String] = []
        if let partLabel { parts.append(partLabel) }
        if let bibleReference { parts.append(bibleReference) }
        if let year { parts.append("(\(year))") }
        return parts.joined(separator: " • ")
    }
}

/// The entire Puritan Library catalogue.
struct PuritanLibraryCatalogue: Decodable, Sendable {
    let version: Int
    let source: String
    let sourceURL: String
    let attribution: String
    let works: [PuritanCatalogueEntry]

    /// Uniquely indexed works, keyed by tcpId.
    var byTcpId: [String: PuritanCatalogueEntry] {
        Dictionary(uniqueKeysWithValues: works.map { ($0.tcpId, $0) })
    }

    /// Works grouped by author for list display.
    var groupedByAuthor: [(author: String, works: [PuritanCatalogueEntry])] {
        let grouped = Dictionary(grouping: works, by: { $0.author })
        return grouped.keys.sorted().map { author in
            (author: author, works: grouped[author]!.sorted { $0.title < $1.title })
        }
    }
}

extension PuritanCatalogueEntry {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tcpId = try c.decode(String.self, forKey: .tcpId)
        author = try c.decode(String.self, forKey: .author)
        title = try c.decode(String.self, forKey: .title)
        partLabel = (try? c.decodeIfPresent(String.self, forKey: .partLabel)) ?? nil
        bibleReference = (try? c.decodeIfPresent(String.self, forKey: .bibleReference)) ?? nil
        year = (try? c.decodeIfPresent(Int.self, forKey: .year)) ?? nil
        note = (try? c.decodeIfPresent(String.self, forKey: .note)) ?? nil
    }

    enum CodingKeys: String, CodingKey {
        case tcpId, author, title, partLabel, bibleReference, year, note
    }
}

// MARK: - Parsed Work

/// One section (div1) of a parsed Puritan work, with heading and plain-text body.
struct PuritanWorkSection: Sendable, Identifiable {
    let id: String
    let heading: String
    let body: String

    init(heading: String = "Untitled", body: String) {
        self.heading = heading
        self.body = body
        self.id = UUID().uuidString
    }
}

/// A parsed Puritan work ready for reading.
struct ParsedPuritanWork: Sendable {
    var tcpId: String
    var title: String
    var author: String
    let sections: [PuritanWorkSection]

    var isEmpty: Bool { sections.isEmpty || sections.allSatisfy { $0.body.isEmpty } }
}

// MARK: - TEI XML Parser

/// Parses EEBO-TCP TEI-encoded XML into readable sections.
///
/// IMPORTANT (found by hand-inspecting a real downloaded file, `A63066.xml`, after the first
/// implementation of this parser shipped against a hand-written fixture instead of real data):
/// real EEBO-TCP files use TEI P5's generic `<div type="...">`, arbitrarily nested (commonly to
/// depth 2: a `<div type="commentary">` containing several `<div type="chapter">`/similar), NOT
/// the numbered `<div1>`/`<div2>` of the older P3/P4 DTD. A parser that only matches `div1`/`div2`
/// never matches anything in a real file and silently produces one undivided section for every
/// single work — exactly the "no real table of contents" bug this rewrite fixes. Real files also
/// carry heavy `<note>` (marginal notes) and `<gap>`/`<desc>` (transcriber's note on illegible
/// text, e.g. "2 letters illegible") markup interleaved inside `<p>`, which must be suppressed
/// from the reading text rather than left to bleed into the middle of a sentence.
enum TEIParser {
    static func parse(_ xmlData: Data) -> ParsedPuritanWork? {
        let delegate = TEIParserDelegate()
        let parser = XMLParser(data: xmlData)
        parser.delegate = delegate
        _ = parser.parse()
        return delegate.finalWork()
    }
}

private final class TEIParserDelegate: NSObject, XMLParserDelegate {
    /// One open `<div>`, accumulating its own heading and body text independently of its parent
    /// or children — a stack (not a single mutable "current" value) is what lets nested divs each
    /// become their own section without losing or duplicating text.
    private struct DivFrame {
        var headingText = ""
        var body = ""
        let typeAttribute: String?
    }

    private var stack: [DivFrame] = []
    private var sections: [PuritanWorkSection] = []
    /// Depth counters, not booleans: `<hi>`/`<expan>`/etc. nest inside `<p>`/`<head>` without
    /// ending them, so "am I inside a paragraph" must survive nested inline tags.
    private var paragraphDepth = 0
    private var headingDepth = 0
    /// `<note>`, `<gap>`, `<desc>` content is never reading text, even when it sits inside a
    /// `<p>` (a `<gap>`'s `<desc>` describing damage is nested exactly like this in real files).
    private var suppressDepth = 0
    private var paragraphBuffer = ""
    private var headingBuffer = ""
    /// Whole-document plain text, built only from real `<p>` content — the first fallback, used
    /// when no `<div>` grouping produced any section but real paragraphs still exist (e.g. `<p>`
    /// sitting directly under `<body>` with no wrapping `<div>`).
    private var wholeDocumentText = ""
    /// Last-resort fallback: every non-suppressed character anywhere in the document, regardless
    /// of `<p>`/`<head>` nesting — for a document that matches neither expected shape at all (some
    /// very old/unusual TCP files use `<lg>`/`<l>` verse structure with no `<div>` or `<p>`), so
    /// the reader always sees *something* rather than a blank screen.
    private var anyCharacterText = ""

    private static let suppressedElements: Set<String> = ["note", "gap", "desc"]

    func finalWork() -> ParsedPuritanWork? {
        if !sections.isEmpty {
            return ParsedPuritanWork(tcpId: "", title: "", author: "", sections: sections)
        }
        let fromParagraphs = wholeDocumentText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !fromParagraphs.isEmpty {
            return ParsedPuritanWork(tcpId: "", title: "", author: "", sections: [PuritanWorkSection(heading: "Text", body: fromParagraphs)])
        }
        let lenient = anyCharacterText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !lenient.isEmpty else { return nil }
        return ParsedPuritanWork(tcpId: "", title: "", author: "", sections: [PuritanWorkSection(heading: "Text", body: lenient)])
    }

    private func humanized(type: String?) -> String {
        guard let type, !type.isEmpty else { return "Untitled section" }
        return type.replacingOccurrences(of: "_", with: " ").capitalized
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        if Self.suppressedElements.contains(elementName) { suppressDepth += 1; return }
        switch elementName {
        case "div":
            stack.append(DivFrame(typeAttribute: attributeDict["type"]))
        case "head":
            headingDepth += 1
            headingBuffer = ""
        case "p":
            paragraphDepth += 1
            paragraphBuffer = ""
        default:
            break   // <hi>, <expan>, <am>, <ex>, <g>, <pb/>, etc. — their text still flows in below.
        }
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if Self.suppressedElements.contains(elementName) { suppressDepth = max(0, suppressDepth - 1); return }
        switch elementName {
        case "div":
            guard let frame = stack.popLast() else { return }
            let body = frame.body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !body.isEmpty else { break }
            let heading = frame.headingText.trimmingCharacters(in: .whitespacesAndNewlines)
            sections.append(PuritanWorkSection(heading: heading.isEmpty ? humanized(type: frame.typeAttribute) : heading, body: body))
        case "head":
            headingDepth = max(0, headingDepth - 1)
            if !stack.isEmpty { stack[stack.count - 1].headingText += headingBuffer }
            headingBuffer = ""
        case "p":
            paragraphDepth = max(0, paragraphDepth - 1)
            let text = paragraphBuffer.trimmingCharacters(in: .whitespaces)
            if !text.isEmpty {
                if !stack.isEmpty { stack[stack.count - 1].body += text + "\n\n" }
                wholeDocumentText += text + "\n\n"
            }
            paragraphBuffer = ""
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard suppressDepth == 0 else { return }
        anyCharacterText += string
        if headingDepth > 0 { headingBuffer += string }
        else if paragraphDepth > 0 { paragraphBuffer += string }
    }
}

// MARK: - Storage and Download Service

/// Manages downloaded Puritan works and the catalogue.
@MainActor
final class PuritanLibraryService: ObservableObject {
    @Published var catalogue: PuritanLibraryCatalogue?
    @Published var downloadStates: [String: DownloadState] = [:]
    @Published var error: Error?

    nonisolated private let storageDirectory: URL
    nonisolated private let transport: HTTPTransport

    /// `Equatable` compares every associated value (a real `.downloading(0.3)` must not read as
    /// equal to `.downloading(0.7)`, and two different `.failed` messages are two different
    /// states) — the original hand-rolled `==` treated any two cases of the same kind as equal
    /// regardless of payload, which is exactly the sort of bug that makes `@Published` skip a
    /// real UI update (SwiftUI/Combine use `Equatable` to decide whether a change actually
    /// happened) and lets a test's `XCTAssertEqual` pass against the wrong error message. Letting
    /// the compiler synthesize it (by dropping the hand-written `==`) is strictly correct here —
    /// every case's payload is itself `Equatable`.
    enum DownloadState: Sendable, Equatable {
        case notDownloaded
        case downloading(progress: Double)
        case downloaded
        case failed(String)

        var isDownloading: Bool {
            if case .downloading = self { return true }
            return false
        }
    }

    /// `storageDirectory`/`transport` are `nonisolated let`s only so the initializer's default
    /// arguments can be computed without hopping actors; every method below runs on `@MainActor`
    /// like the rest of the class (no `nonisolated func` here), so state mutations are plain,
    /// synchronous assignments — never wrapped in `DispatchQueue.main.async`, which would (this
    /// class already being `@MainActor`) needlessly defer the mutation to a later run-loop turn
    /// instead of applying it before the calling `await` resumes, a real race a caller doing
    /// `await service.downloadAndStore(entry)` immediately followed by reading `downloadStates`
    /// could actually hit.
    init(storageDirectory: URL? = nil, transport: (HTTPTransport)? = nil) {
        self.storageDirectory = storageDirectory ?? AppResources.supportDirectory.appendingPathComponent("PuritanLibrary", isDirectory: true)
        self.transport = transport ?? { request in try await URLSession.shared.data(for: request) }
        Task { await loadCatalogue() }
    }

    // MARK: - Catalogue

    func loadCatalogue() async {
        guard let catalogueURL = AppResources.url("PuritanLibrary/catalog.json") else {
            error = NSError(domain: "PuritanLibrary", code: -1, userInfo: [NSLocalizedDescriptionKey: "Catalogue not found"])
            return
        }

        do {
            let data = try Data(contentsOf: catalogueURL)
            let decoded = try JSONDecoder().decode(PuritanLibraryCatalogue.self, from: data)
            catalogue = decoded

            var states: [String: DownloadState] = [:]
            for entry in decoded.works {
                states[entry.tcpId] = isDownloaded(entry.tcpId) ? .downloaded : .notDownloaded
            }
            downloadStates = states
        } catch {
            self.error = error
        }
    }

    // MARK: - Download & Storage

    private func isDownloaded(_ tcpId: String) -> Bool {
        let path = storageDirectory.appendingPathComponent("\(tcpId).xml")
        return FileManager.default.fileExists(atPath: path.path)
    }

    func downloadAndStore(_ entry: PuritanCatalogueEntry) async {
        downloadStates[entry.tcpId] = .downloading(progress: 0)

        let url = URL(string: "https://raw.githubusercontent.com/textcreationpartnership/\(entry.tcpId)/master/\(entry.tcpId).xml")!
        var request = URLRequest(url: url)
        request.timeoutInterval = 30

        do {
            let (data, response) = try await transport(request)
            guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
                let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                throw NSError(domain: "PuritanLibrary", code: -2, userInfo: [NSLocalizedDescriptionKey: "HTTP \(statusCode)"])
            }

            try FileManager.default.createDirectory(at: storageDirectory, withIntermediateDirectories: true)
            let path = storageDirectory.appendingPathComponent("\(entry.tcpId).xml")
            try data.write(to: path)

            downloadStates[entry.tcpId] = .downloaded
        } catch {
            downloadStates[entry.tcpId] = .failed(error.localizedDescription)
        }
    }

    func delete(_ tcpId: String) {
        let path = storageDirectory.appendingPathComponent("\(tcpId).xml")
        try? FileManager.default.removeItem(at: path)
        downloadStates[tcpId] = .notDownloaded
    }

    func loadWork(_ entry: PuritanCatalogueEntry) async -> ParsedPuritanWork? {
        let path = storageDirectory.appendingPathComponent("\(entry.tcpId).xml")
        guard let data = try? Data(contentsOf: path) else { return nil }
        guard var work = TEIParser.parse(data) else { return nil }
        work.tcpId = entry.tcpId
        work.title = entry.title
        work.author = entry.author
        return work
    }
}

