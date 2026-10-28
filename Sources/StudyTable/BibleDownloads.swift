import Foundation
import StudyTableCore

struct BibleDownload: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let language: String
    let sourceID: String
    var sourceURL: URL { URL(string: "https://ebible.org/find/show.php?id=\(sourceID)")! }
    var archiveURL: URL { URL(string: "https://ebible.org/Scriptures/\(sourceID)_usfm.zip")! }
    var license: String { "Public domain · eBible.org" }
    static let catalog: [Self] = [
        .init(id: "ASV", name: "American Standard Version (1901)", language: "English", sourceID: "eng-asv"),
        .init(id: "YLT", name: "Young’s Literal Translation", language: "English", sourceID: "engylt"),
        .init(id: "DBY", name: "Darby Translation", language: "English", sourceID: "engDBY"),
        .init(id: "WBS", name: "Noah Webster Bible (1833)", language: "English", sourceID: "engwebster"),
        .init(id: "RV1909", name: "Reina Valera (1909)", language: "Español", sourceID: "spaRV1909"),
        .init(id: "FOB", name: "La Sainte Bible — Ostervald", language: "Français", sourceID: "fra_fob")
    ]
}

enum BibleDownloadError: LocalizedError {
    case invalid(String)
    var errorDescription: String? { if case .invalid(let reason) = self { return reason }; return nil }
}

/// A ZIP reader only for listing vetted members. No archive path is ever written to disk:
/// unzip streams each USFM member to a pipe and we give its output our own safe filename.
enum BibleArchive {
    struct Member: Equatable { let name: String; let size: Int }
    static let maximumArchive = 30 * 1024 * 1024
    static let maximumExpanded = 80 * 1024 * 1024
    static let maximumMember = 8 * 1024 * 1024

    static func members(_ data: Data, extensions: Set<String>? = ["usfm", "sfm"], minimum: Int = 66, memberLimit: Int = maximumMember) throws -> [Member] {
        func fail() -> BibleDownloadError { .invalid("The Bible archive is unsupported or unsafe. Nothing was installed.") }
        guard data.count >= 22, data.count <= maximumArchive else { throw fail() }
        func n(_ p: Int, _ count: Int) -> Int {
            guard p >= 0, p + count <= data.count else { return -1 }
            return (0..<count).reduce(0) { $0 | (Int(data[p + $1]) << (8 * $1)) }
        }
        guard let end = stride(from: data.count - 22, through: max(0, data.count - 65557), by: -1)
            .first(where: { n($0, 4) == 0x06054b50 && $0 + 22 + n($0 + 20, 2) == data.count }),
              n(end + 4, 2) == 0, n(end + 6, 2) == 0,
              n(end + 8, 2) == n(end + 10, 2) else { throw fail() }
        let count = n(end + 10, 2), start = n(end + 16, 4), length = n(end + 12, 4)
        guard count > 0, count <= 500, start >= 0, start + length == end else { throw fail() }
        var offset = start, total = 0, names = Set<String>(), result: [Member] = []
        for _ in 0..<count {
            guard offset + 46 <= end, n(offset, 4) == 0x02014b50 else { throw fail() }
            let size = n(offset + 24, 4), nameLength = n(offset + 28, 2)
            let next = offset + 46 + nameLength + n(offset + 30, 2) + n(offset + 32, 2)
            guard next <= end, nameLength > 0,
                  let name = String(data: data[(offset + 46)..<(offset + 46 + nameLength)], encoding: .utf8),
                  !name.hasPrefix("/"), !name.hasPrefix("-"), !name.contains("\\"),
                  !name.contains(":"), !name.contains("\0"),
                  !name.contains(where: { "*?[]".contains($0) }),
                  !name.split(separator: "/", omittingEmptySubsequences: false).contains(".."),
                  names.insert(name).inserted, n(offset + 8, 2) & 1 == 0,
                  [0, 8].contains(n(offset + 10, 2)),
                  (n(offset + 38, 4) >> 16) & 0xf000 != 0xa000,
                  size >= 0, size <= memberLimit else { throw fail() }
            total += size
            guard total <= maximumExpanded else { throw fail() }
            if !name.hasSuffix("/"), extensions == nil || extensions!.contains((name as NSString).pathExtension.lowercased()) {
                result.append(Member(name: name, size: size))
            }
            offset = next
        }
        guard offset == end, result.count >= minimum else { throw fail() }
        return result
    }

    static func unpackMember(_ member: Member, archive: URL, memberLimit: Int = maximumMember) throws -> Data {
        try Task.checkCancellation()
        let process = Process(), pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-p", archive.path, member.name]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        try process.run()
        let timeout = DispatchWorkItem { if process.isRunning { process.terminate() } }
        DispatchQueue.global().asyncAfter(deadline: .now() + 20, execute: timeout)
        defer { timeout.cancel(); if process.isRunning { process.terminate() }; try? pipe.fileHandleForReading.close() }
        var output = Data()
        while let chunk = try pipe.fileHandleForReading.read(upToCount: 65536), !chunk.isEmpty {
            try Task.checkCancellation()
            guard output.count + chunk.count <= member.size,
                  output.count + chunk.count <= memberLimit else {
                throw BibleDownloadError.invalid("The archive expanded beyond its declared size.")
            }
            output.append(chunk)
        }
        process.waitUntilExit()
        guard process.terminationStatus == 0, output.count == member.size else {
            throw BibleDownloadError.invalid("The downloaded archive is damaged. Please retry.")
        }
        return output
    }
}

private final class BibleRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" && request.url?.host == "ebible.org" ? request : nil)
    }
}

actor BibleInstaller {
    typealias Transport = @Sendable (URL, @escaping @Sendable (Double) async -> Void) async throws -> Data
    let root: URL
    private let transport: Transport
    init(root: URL, transport: @escaping Transport = BibleInstaller.fetch) {
        self.root = root; self.transport = transport
    }

    static func fetch(_ url: URL, progress: @escaping @Sendable (Double) async -> Void) async throws -> Data {
        guard url.scheme == "https", url.host == "ebible.org" else { throw BibleDownloadError.invalid("Untrusted download host.") }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45; config.timeoutIntervalForResource = 180
        let session = URLSession(configuration: config, delegate: BibleRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url?.scheme == "https", response.url?.host == "ebible.org",
              response.expectedContentLength <= BibleArchive.maximumArchive else {
            throw BibleDownloadError.invalid("The Bible source is unavailable. Please retry later.")
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < BibleArchive.maximumArchive else { throw BibleDownloadError.invalid("Download exceeded the 30 MB safety limit.") }
            data.append(byte)
            if data.count % 131072 == 0 {
                await progress(response.expectedContentLength > 0 ? Double(data.count) / Double(response.expectedContentLength) : 0)
            }
        }
        return data
    }

    func install(_ edition: BibleDownload, progress: @escaping @Sendable (Double) async -> Void) async throws {
        guard BibleDownload.catalog.contains(edition) else { throw BibleDownloadError.invalid("This edition is not in the trusted catalog.") }
        let fm = FileManager.default
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let target = root.appendingPathComponent(edition.id, isDirectory: true)
        guard !fm.fileExists(atPath: target.path) else { throw BibleDownloadError.invalid("This edition is already installed. Its files were left unchanged.") }
        let stage = root.appendingPathComponent(".download-\(UUID().uuidString)", isDirectory: true)
        try fm.createDirectory(at: stage, withIntermediateDirectories: false)
        defer { try? fm.removeItem(at: stage) }
        let data = try await transport(edition.archiveURL, progress)
        await progress(1)
        try Task.checkCancellation()
        let members = try BibleArchive.members(data)
        let archive = stage.appendingPathComponent("source.zip")
        try data.write(to: archive)
        let source = stage.appendingPathComponent("source", isDirectory: true)
        try fm.createDirectory(at: source, withIntermediateDirectories: false)
        for (index, member) in members.enumerated() {
            try Task.checkCancellation()
            let content = try BibleArchive.unpackMember(member, archive: archive)
            try content.write(to: source.appendingPathComponent("\(index).usfm"))
        }
        let meta: [String: Any] = ["id": edition.id, "abbreviation": edition.id, "name": edition.name,
            "language": edition.language, "sourceURL": edition.sourceURL.absoluteString,
            "license": ["summary": "Public domain", "url": edition.sourceURL.absoluteString,
                        "attribution": "\(edition.name). Public domain. Source: eBible.org. Text rendered from USFM; footnotes and noncanonical books are not included."]]
        try JSONSerialization.data(withJSONObject: meta).write(to: source.appendingPathComponent("translation.json"))
        // Downloaded Bibles are text only: editorial headings/paragraph marks come only from vetted bundled sources.
        let pack = try ScripturePackBuilder.build(sourceDirectory: source, includeStructure: false)
        try Self.validate(pack)
        let ready = stage.appendingPathComponent("ready", isDirectory: true)
        try ScripturePackBuilder.write(pack, to: ready)
        try Data(edition.id.utf8).write(to: ready.appendingPathComponent(".study-table-download"))
        try Task.checkCancellation()
        // Rename on the same volume: a failed/cancelled download never becomes a partial Bible.
        try fm.moveItem(at: ready, to: target)
    }

    static func validate(_ pack: BuiltPack) throws {
        let chapterCounts = [50,40,27,36,34,24,21,4,31,24,22,25,29,36,10,13,10,42,150,31,12,8,66,52,5,48,12,14,3,9,1,4,7,3,3,3,2,14,4,28,16,24,21,28,16,16,13,6,6,4,4,5,3,6,4,3,1,13,5,5,3,5,1,1,1,22]
        guard pack.books.map(\.code) == Canon.bookCodes,
              pack.books.map({ $0.chapters.count }) == chapterCounts,
              pack.books.allSatisfy({ book in
                  book.chapters.map(\.n) == Array(1...book.chapters.count) &&
                  book.chapters.allSatisfy { !$0.v.isEmpty && $0.v.count == $0.t.count &&
                      $0.v.allSatisfy { $0 >= 0 } && $0.v == Array(Set($0.v)).sorted() &&
                      $0.t.allSatisfy { !$0.isEmpty } }
              }), pack.books.reduce(0, { $0 + $1.chapters.reduce(0, { $0 + $1.v.count }) }) >= 30000 else {
            throw BibleDownloadError.invalid("This edition did not pass the 66-book / 1,189-chapter validation. Nothing was installed.")
        }
    }

    static func isManaged(_ edition: BibleDownload, root: URL) -> Bool {
        guard BibleDownload.catalog.contains(edition) else { return false }
        let directory = root.appendingPathComponent(edition.id)
        guard (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { return false }
        return (try? String(contentsOf: directory.appendingPathComponent(".study-table-download"), encoding: .utf8)) == edition.id
    }

    func remove(_ edition: BibleDownload) throws {
        guard Self.isManaged(edition, root: root) else { throw BibleDownloadError.invalid("Only Bibles installed by this download manager can be removed here.") }
        try FileManager.default.removeItem(at: root.appendingPathComponent(edition.id))
    }
}

@MainActor
final class BibleDownloadManager: ObservableObject {
    @Published private(set) var activeID: String?
    @Published private(set) var progress: Double = 0
    @Published private(set) var message: String?
    private var task: Task<Void, Never>?
    func download(_ edition: BibleDownload, root: URL, completed: @escaping @MainActor () -> Void) {
        guard activeID == nil else { return }
        activeID = edition.id; progress = 0; message = nil
        task = Task {
            do {
                try await BibleInstaller(root: root).install(edition) { value in await MainActor.run { self.progress = value } }
                message = "\(edition.id) is ready offline."
                completed()
            } catch is CancellationError { message = "Download cancelled. No Bible files were changed."
            } catch { message = error.localizedDescription }
            activeID = nil; task = nil
        }
    }
    func cancel() { task?.cancel() }
    func remove(_ edition: BibleDownload, root: URL, completed: @escaping @MainActor () -> Void) {
        guard activeID == nil else { return }
        activeID = edition.id
        message = "Removing \(edition.id)…"
        task = Task {
            do { try await BibleInstaller(root: root).remove(edition); message = "\(edition.id) removed. Your notes are unchanged."; completed() }
            catch { message = error.localizedDescription }
            activeID = nil; task = nil
        }
    }
}
