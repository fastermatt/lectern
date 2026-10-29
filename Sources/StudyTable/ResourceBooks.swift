import Foundation
import CryptoKit

struct ResourceArticle: Codable, Identifiable, Sendable {
    var id: String
    var title: String
    var body: String
    var anchor: Anchor?
}
struct ResourceBook: Codable, Identifiable, Sendable {
    var id: String
    var title: String
    var author: String
    var attribution: String
    var source: String?
    var articles: [ResourceArticle]
}
struct OpenResource: Identifiable, Sendable {
    let id: String
    let title: String
    let detail: String
    let filename: String
    let checksum: String
    var url: URL { URL(string: "https://tyndaleopenresources.com/wp-content/themes/tyndale-openresources/files/" + filename)! }
    static let catalog: [Self] = [
        .init(id: "tyndale-notes", title: "Tyndale Open Study Notes", detail: "16,923 study notes, 66 book introductions, summaries, profiles and theme articles. Follows your Bible passage.", filename: "tyndale_open-studynotes.zip", checksum: "7b4d5ae088449d5a6925170c4b89b978acee2f78f73dc6b8a278fa948a7e8498"),
        .init(id: "tyndale-dictionary", title: "Tyndale Open Bible Dictionary", detail: "6,010 articles on people, places, theology and biblical culture. Search and read offline. Illustrations are not included in the text edition.", filename: "TyndaleOpenBibleDictionary.zip", checksum: "10758ea00dbea7540f9337e43e59c8e4000295c1261e3426bab6f31c31dcff5b")
    ]
}

enum ResourceBookError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let text) = self { return text }; return nil }
}

/// No external entities, web views, JavaScript, or fetched images are used to read books.
enum BookXML {
    static func parse(_ data: Data, delegate: XMLParserDelegate) throws {
        guard data.count <= 20 * 1024 * 1024,
              let text = String(data: data, encoding: .utf8),
              !text.localizedCaseInsensitiveContains("<!ENTITY") else {
            throw ResourceBookError.invalid("This XML uses an unsupported encoding or document declaration.")
        }
        // Standard XHTML doctypes are harmless after removal; internal subsets are rejected.
        guard !text.contains("<!DOCTYPE") || !text.components(separatedBy: "<!DOCTYPE").dropFirst().contains(where: { $0.components(separatedBy: ">").first?.contains("[") == true }) else { throw ResourceBookError.invalid("Internal XML declarations are unsupported.") }
        let cleaned = text.replacingOccurrences(of: "<!DOCTYPE[^>]*>", with: "", options: [.regularExpression, .caseInsensitive])
        let parser = XMLParser(data: Data(cleaned.utf8))
        parser.shouldResolveExternalEntities = false
        parser.externalEntityResolvingPolicy = .never
        parser.delegate = delegate
        guard parser.parse() else { throw ResourceBookError.invalid("This book contains unsupported or damaged XML.") }
    }
}

final class TyndaleParser: NSObject, XMLParserDelegate {
    var articles: [ResourceArticle] = []
    private var name = "", type = "", title = "", refs = "", body = ""
    private var field = ""
    private var inBody = false
    static func parse(_ data: Data) throws -> [ResourceArticle] {
        let delegate = TyndaleParser(); try BookXML.parse(data, delegate: delegate); return delegate.articles
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        if elementName == "item" { name = attributes["name"] ?? ""; type = attributes["typename"] ?? ""; title = ""; refs = ""; body = "" }
        if ["title", "refs"].contains(elementName), !inBody { field = elementName }
        if elementName == "body" { inBody = true }
        if inBody, elementName == "br" { body += "\n" }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if inBody { body += string } else if field == "title" { title += string } else if field == "refs" { refs += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if inBody, ["p", "li", "tr"].contains(elementName) { body += "\n\n" }
        if elementName == "body" { inBody = false }
        if elementName == field { field = "" }
        if elementName == "item", ["StudyNote", "BookIntro", "BookIntroSummary", "Profile", "ThemeNote", "Article", "Textbox"].contains(type) {
            let text = body.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return }
            articles.append(ResourceArticle(id: type + ":" + name, title: title.isEmpty ? name : title,
                body: text, anchor: Self.reference(refs)))
        }
    }
    static func reference(_ source: String) -> Anchor? {
        var ref = source.trimmingCharacters(in: .whitespacesAndNewlines)
        let aliases = ["Pr": "Prov", "Hagg": "Hag", "Jon": "Jonah", "1Jn": "1John", "2Jn": "2John", "3Jn": "3John", "1Thes": "1Thess", "2Thes": "2Thess"]
        for (a, b) in aliases { if ref.hasPrefix(a + ".") { ref = b + String(ref.dropFirst(a.count)) } }
        return Anchor(osis: ref)
    }
}

private final class ResourceRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" && request.url?.host == "tyndaleopenresources.com" ? request : nil)
    }
}

enum ResourceBookFiles {
    static let memberLimit = 20 * 1024 * 1024
    static func fetch(_ resource: OpenResource) async throws -> Data {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45; config.timeoutIntervalForResource = 180
        let session = URLSession(configuration: config, delegate: ResourceRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: resource.url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url?.host == resource.url.host, response.url?.scheme == "https",
              response.expectedContentLength <= BibleArchive.maximumArchive else {
            throw ResourceBookError.invalid("The publisher download is unavailable. Please try again later.")
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < BibleArchive.maximumArchive else { throw ResourceBookError.invalid("The download exceeded its size limit.") }
            data.append(byte)
        }
        return data
    }
    static func convert(_ resource: OpenResource, data: Data, temporary: URL) throws -> ResourceBook {
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        guard checksum == resource.checksum else { throw ResourceBookError.invalid("The publisher file has changed. Nothing was installed; Throughline needs an updated catalogue before importing this edition.") }
        try data.write(to: temporary)
        let members = try BibleArchive.members(data, extensions: ["xml"], minimum: 1, memberLimit: memberLimit)
        var articles: [ResourceArticle] = []
        for member in members {
            try Task.checkCancellation()
            articles += try TyndaleParser.parse(BibleArchive.unpackMember(member, archive: temporary, memberLimit: memberLimit))
        }
        guard !articles.isEmpty, Set(articles.map(\.id)).count == articles.count else { throw ResourceBookError.invalid("The resource did not pass validation.") }
        return ResourceBook(id: resource.id, title: resource.title, author: "Tyndale House Publishers",
            attribution: "Adapted from \(resource.title). The original work by Tyndale House Publishers is available for free at https://tyndaleopenresources.com. Copyright © \(resource.id == "tyndale-dictionary" ? "2023" : "2022") Tyndale House Publishers. Licensed under CC BY-SA 4.0: https://creativecommons.org/licenses/by-sa/4.0/. Throughline converts XML to plain text, omits illustrations, and adds passage links. This text adaptation is also CC BY-SA 4.0.",
            source: "https://tyndaleopenresources.com/", articles: articles)
    }
    static func store(_ book: ResourceBook, root: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = root.appendingPathComponent(book.id + ".json")
        guard !fm.fileExists(atPath: destination.path) else { throw ResourceBookError.invalid("This resource is already installed. Its contents were left unchanged.") }
        let stage = root.appendingPathComponent(".import-" + UUID().uuidString)
        defer { try? fm.removeItem(at: stage) }
        try JSONEncoder().encode(book).write(to: stage, options: .atomic)
        try Task.checkCancellation()
        try fm.moveItem(at: stage, to: destination)
    }
    struct Scan: Sendable { var books: [ResourceBook]; var unreadable: Int }
    static func scan(root: URL) throws -> Scan {
        guard FileManager.default.fileExists(atPath: root.path) else { return Scan(books: [], unreadable: 0) }
        let files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.fileSizeKey, .isSymbolicLinkKey])
        var result = Scan(books: [], unreadable: 0)
        for url in files.filter({ $0.pathExtension == "json" }) {
            do {
                let values = try url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
                guard values.isSymbolicLink != true, (values.fileSize ?? Int.max) <= 80 * 1024 * 1024 else { throw CocoaError(.fileReadCorruptFile) }
                let book = try JSONDecoder().decode(ResourceBook.self, from: Data(contentsOf: url))
                guard url.deletingPathExtension().lastPathComponent == book.id, Set(book.articles.map(\.id)).count == book.articles.count else { throw CocoaError(.fileReadCorruptFile) }
                result.books.append(book)
            } catch { result.unreadable += 1 }
        }
        return result
    }
    static func load(root: URL) throws -> [ResourceBook] { try scan(root: root).books }

}

@MainActor
final class ResourceBookLibrary: ObservableObject {
    @Published private(set) var books: [ResourceBook] = []
    @Published private(set) var activeID: String?
    @Published private(set) var message: String?
    let root: URL
    private var task: Task<Void, Never>?
    private var loadWarning: String?
    init(root: URL = AppResources.supportDirectory.appendingPathComponent("ResourceBooks")) {
        self.root = root
    }
    func load() async {
        do {
            let root = root
            let result = try await Task.detached { try ResourceBookFiles.scan(root: root) }.value
            books = result.books
            loadWarning = result.unreadable == 0 ? nil : "\(result.unreadable) library files could not be read; they were preserved. Other books are available."
            if let loadWarning { message = loadWarning }
        }
        catch { message = "Some library files could not be read. They have been preserved." }
    }
    func install(_ resource: OpenResource) {
        guard activeID == nil else { return }
        activeID = resource.id; message = nil
        task = Task {
            do {
                let data = try await ResourceBookFiles.fetch(resource), root = root
                let worker = Task.detached {
                    let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".zip")
                    defer { try? FileManager.default.removeItem(at: tmp) }
                    let book = try ResourceBookFiles.convert(resource, data: data, temporary: tmp)
                    try ResourceBookFiles.store(book, root: root)
                }
                try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                await load(); message = "\(resource.title) is ready to read offline." + (loadWarning.map { " " + $0 } ?? "")
            } catch is CancellationError { message = "Download cancelled." }
            catch { message = (error as? LocalizedError)?.errorDescription ?? "The download could not be installed. Please try again." }
            activeID = nil; task = nil
        }
    }
    func cancel() { task?.cancel() }
    func importBook(_ url: URL) {
        guard activeID == nil else { return }
        activeID = "import"; message = nil
        task = Task {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() }; activeID = nil; task = nil }
            do {
                let root = root
                let worker = Task.detached {
                    let book = try PersonalBookImporter.read(url)
                    try ResourceBookFiles.store(book, root: root)
                }
                try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
                await load(); message = "Your book is ready to read and search offline." + (loadWarning.map { " " + $0 } ?? "")
            } catch is CancellationError { message = "Import cancelled." }
            catch { message = (error as? LocalizedError)?.errorDescription ?? "This book could not be imported. Use an unencrypted EPUB or a UTF-8 text file." }
        }
    }
}
