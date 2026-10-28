import Foundation
import CryptoKit

struct LocalAIModel: Identifiable, Equatable, Sendable {
    let id: String
    let name: String
    let size: String
    let detail: String
    let recommendedRAM: Int
    let repository: String
    let revision: String
    let filename: String
    let bytes: Int64
    let sha256: String
    var downloadURL: URL { URL(string: "https://huggingface.co/\(repository)/resolve/\(revision)/\(filename)")! }
    var sourceURL: URL { URL(string: "https://huggingface.co/\(repository)/tree/\(revision)")! }
    var downloadSize: String { ByteCountFormatter.string(fromByteCount: bytes, countStyle: .decimal) }
    static let catalog: [Self] = [
        .init(id: "qwen35-light", name: "Light", size: "Qwen3.5 · 0.8B · Q4_K_M", detail: "Smallest download and quickest start. Useful for brief summaries and rephrasing; least reliable for nuanced interpretation.", recommendedRAM: 8,
              repository: "unsloth/Qwen3.5-0.8B-GGUF", revision: "6ab461498e2023f6e3c1baea90a8f0fe38ab64d0", filename: "Qwen3.5-0.8B-Q4_K_M.gguf", bytes: 532517120, sha256: "bd258782e35f7f458f8aced1adc053e6e92e89bc735ba3be89d38a06121dc517"),
        .init(id: "qwen35-balanced", name: "Balanced", size: "Qwen3.5 · 2B · Q4_K_M", detail: "A middle ground for passage questions and short comparisons. More room for detail than Light, with a smaller footprint than More capable.", recommendedRAM: 8,
              repository: "unsloth/Qwen3.5-2B-GGUF", revision: "f6d5376be1edb4d416d56da11e5397a961aca8ae", filename: "Qwen3.5-2B-Q4_K_M.gguf", bytes: 1280835840, sha256: "aaf42c8b7c3cab2bf3d69c355048d4a0ee9973d48f16c731c0520ee914699223"),
        .init(id: "qwen35-capable", name: "More capable", size: "Qwen3.5 · 4B · Q4_K_M", detail: "Larger model for more involved questions and comparisons. Needs more memory and takes longer to respond; citations still need checking.", recommendedRAM: 16,
              repository: "unsloth/Qwen3.5-4B-GGUF", revision: "e87f176479d0855a907a41277aca2f8ee7a09523", filename: "Qwen3.5-4B-Q4_K_M.gguf", bytes: 2740937888, sha256: "00fe7986ff5f6b463e62455821146049db6f9313603938a70800d1fb69ef11a4")
    ]
    static func recommended(memory: UInt64) -> String { memory >= 8 * 1024 * 1024 * 1024 ? "qwen35-balanced" : "qwen35-light" }
}

enum LocalAIStorage {
    static var root: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Lectern/LocalAI", isDirectory: true)
    }
    static func validate(_ url: URL, model: LocalAIModel) throws {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let header = try handle.read(upToCount: 4) ?? Data()
        guard header == Data("GGUF".utf8) else { throw AIError.message("The download is not a model file. Nothing was installed.") }
        var hash = SHA256(); hash.update(data: header); var size: Int64 = 4
        while let chunk = try handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            try Task.checkCancellation()
            size += Int64(chunk.count)
            guard size <= model.bytes else { throw AIError.message("The model is larger than expected. Nothing was installed.") }
            hash.update(data: chunk)
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        guard size == model.bytes, digest == model.sha256 else {
            throw AIError.message("The model did not pass its integrity check. Remove it and download again.")
        }
    }
    static func allowedDownloadURL(_ url: URL) -> Bool {
        guard url.scheme == "https", let host = url.host?.lowercased(), url.user == nil, url.password == nil else { return false }
        return host == "huggingface.co" || host.hasSuffix(".huggingface.co") || host.hasSuffix(".hf.co")
    }
}

/// Download to URLSession's temporary file, never into an installed model. No API credentials.
final class LocalModelDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDownloadTask?
    private var session: URLSession?
    private var continuation: CheckedContinuation<URL, Error>?
    private var finishedURL: URL?
    private var failure: Error?
    private let destination: URL
    private let model: LocalAIModel
    private let progress: @Sendable (Double) -> Void
    init(model: LocalAIModel, destination: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.model = model; self.destination = destination; self.progress = progress
    }
    func run() async throws -> URL {
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                lock.lock(); defer { lock.unlock() }
                self.continuation = continuation
                let config = URLSessionConfiguration.ephemeral
                config.timeoutIntervalForRequest = 60; config.timeoutIntervalForResource = 7200
                let session = URLSession(configuration: config, delegate: self, delegateQueue: nil)
                self.session = session
                let task = session.downloadTask(with: model.downloadURL); self.task = task
                if Task.isCancelled { task.cancel() }
                task.resume()
            }
        } onCancel: { self.cancel() }
    }
    func cancel() { lock.lock(); let task = task; lock.unlock(); task?.cancel() }
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url.map(LocalAIStorage.allowedDownloadURL) == true ? request : nil)
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesWritten > model.bytes || totalBytesExpectedToWrite > model.bytes { downloadTask.cancel(); return }
        progress(min(0.99, Double(totalBytesWritten) / Double(model.bytes)))
    }
    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        do {
            guard (downloadTask.response as? HTTPURLResponse)?.statusCode == 200 else {
                throw AIError.message("The model host could not provide this download. Try again later.")
            }
            try FileManager.default.moveItem(at: location, to: destination)
            lock.lock(); finishedURL = destination; lock.unlock()
        } catch { lock.lock(); failure = error; lock.unlock() }
    }
    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        lock.lock()
        let continuation = continuation; self.continuation = nil
        let url = finishedURL; let failure = failure
        self.task = nil; self.session = nil
        lock.unlock()
        session.finishTasksAndInvalidate()
        if let failure = failure ?? error { continuation?.resume(throwing: failure) }
        else if let url { continuation?.resume(returning: url) }
        else { continuation?.resume(throwing: AIError.message("The download did not finish. Please retry.")) }
    }
}
