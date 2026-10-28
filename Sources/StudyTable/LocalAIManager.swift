import AppKit
import Foundation
import Darwin

@MainActor
final class LocalAIManager: ObservableObject {
    static let shared = LocalAIManager()
    @Published private(set) var installed: Set<String> = []
    @Published private(set) var workingID: String?
    @Published private(set) var progress = 0.0
    @Published private(set) var status = "Choose a model to download."
    @Published private(set) var activeID: String?
    @Published private(set) var connection: AIConnection?
    @Published private(set) var key = ""
    @Published var error: String?
    let root: URL
    private let runtime: URL?
    private var operation: Task<Void, Never>?
    private var verification: Task<Void, Error>?
    private var process: Process?
    private var ticket = UUID()
    private var terminationObserver: NSObjectProtocol?
    var supported: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }
    var memoryGB: Int { Int(ProcessInfo.processInfo.physicalMemory / (1024 * 1024 * 1024)) }
    var ready: Bool { connection != nil && process?.isRunning == true }
    var busy: Bool { workingID != nil }
    init(root: URL = LocalAIStorage.root, runtime: URL? = nil) {
        self.root = root
        self.runtime = runtime ?? Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/LocalAI", isDirectory: true)
        rescan()
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop() }
        }
    }
    func file(_ model: LocalAIModel) -> URL { root.appendingPathComponent(model.filename) }
    private func receipt(_ model: LocalAIModel) -> URL { root.appendingPathComponent(model.id + ".verified") }
    func rescan() {
        installed = Set(LocalAIModel.catalog.filter { model in
            let attrs = try? FileManager.default.attributesOfItem(atPath: file(model).path)
            return (attrs?[.size] as? NSNumber)?.int64Value == model.bytes &&
                (try? String(contentsOf: receipt(model), encoding: .utf8)) == model.sha256
        }.map(\.id))
    }
    func download(_ model: LocalAIModel) {
        guard !busy, supported, LocalAIModel.catalog.contains(model) else { return }
        error = nil; workingID = model.id; progress = 0; status = "Downloading \(model.name)…"
        let id = UUID(); ticket = id
        operation = Task {
            var staging: URL?
            defer { if let staging { try? FileManager.default.removeItem(at: staging) }; if ticket == id { workingID = nil; operation = nil } }
            do {
                try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                let capacity = try root.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]).volumeAvailableCapacityForImportantUsage
                if let capacity, capacity < model.bytes + 512 * 1024 * 1024 {
                    throw AIError.message("Free at least \(model.downloadSize) plus 512 MB of space before downloading.")
                }
                let target = root.appendingPathComponent(UUID().uuidString + ".partial"); staging = target
                let download = LocalModelDownload(model: model, destination: target) { [weak self] value in
                    Task { @MainActor in if self?.ticket == id { self?.progress = value } }
                }
                _ = try await download.run(); try Task.checkCancellation()
                guard ticket == id else { return }; status = "Checking download integrity…"
                try await verify(target, model: model)
                try Task.checkCancellation(); guard ticket == id else { return }
                // Only replace this known catalogue file after the entire download verifies.
                if FileManager.default.fileExists(atPath: file(model).path) { try FileManager.default.removeItem(at: file(model)) }
                try FileManager.default.moveItem(at: target, to: file(model))
                try model.sha256.write(to: receipt(model), atomically: true, encoding: .utf8)
                rescan(); progress = 1; status = "\(model.name) installed. Choose Use model to start."
            } catch is CancellationError { if ticket == id { status = "Download cancelled. You can retry." } }
            catch { if ticket == id { self.error = userMessage(error); status = "Download not installed." } }
        }
    }
    private func verify(_ url: URL, model: LocalAIModel) async throws {
        let job = Task.detached(priority: .utility) { try LocalAIStorage.validate(url, model: model) }
        verification = job
        defer { verification = nil }
        try await withTaskCancellationHandler { try await job.value } onCancel: { job.cancel() }
    }
    func cancel() {
        operation?.cancel(); verification?.cancel()
        // Completion owns cleanup and prevents a second operation racing the first.
    }
    func remove(_ model: LocalAIModel) {
        guard !busy, LocalAIModel.catalog.contains(model) else { return }
        if activeID == model.id { stop() }
        do {
            if FileManager.default.fileExists(atPath: file(model).path) { try FileManager.default.removeItem(at: file(model)) }
            if FileManager.default.fileExists(atPath: receipt(model).path) { try FileManager.default.removeItem(at: receipt(model)) }
            rescan(); status = "\(model.name) removed. Your study notes are unchanged."
        } catch { self.error = "Could not remove the model. Check this Mac's file permissions." }
    }
    func start(_ model: LocalAIModel) {
        guard !busy, supported, installed.contains(model.id) else { return }
        stop(); error = nil; workingID = model.id; status = "Checking and loading \(model.name)…"
        let id = UUID(); ticket = id
        operation = Task {
            defer { if ticket == id { workingID = nil; operation = nil } }
            do {
                try await verify(file(model), model: model)
                try Task.checkCancellation(); guard ticket == id else { return }
                guard let runtime, FileManager.default.isExecutableFile(atPath: runtime.appendingPathComponent("llama-server").path),
                      FileManager.default.isExecutableFile(atPath: runtime.appendingPathComponent("lectern-model-runner").path) else {
                    throw AIError.message("The local engine is missing. Open the packaged Lectern app, or reinstall this beta.")
                }
                let port = try Self.availablePort()
                let secret = UUID().uuidString + UUID().uuidString
                let server = Process()
                server.executableURL = runtime.appendingPathComponent("lectern-model-runner")
                server.arguments = [runtime.appendingPathComponent("llama-server").path, "--model", file(model).path,
                    "--host", "127.0.0.1", "--port", String(port), "--alias", model.id,
                    "--ctx-size", "8192", "--parallel", "1", "--batch-size", "256", "--ubatch-size", "128",
                    "--jinja", "--chat-template-kwargs", "{\"enable_thinking\":false}", "--reasoning-budget", "0",
                    "--no-webui", "--offline", "--log-disable", "--sleep-idle-seconds", "300"]
                server.environment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "LLAMA_API_KEY": secret]
                server.standardOutput = FileHandle.nullDevice; server.standardError = FileHandle.nullDevice
                server.terminationHandler = { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.ticket == id else { return }
                        self.connection = nil; self.activeID = nil; self.key = ""
                        if !self.busy { self.status = "Local model stopped." }
                    }
                }
                try server.run(); process = server
                let chosen = AIConnection(baseURL: "http://127.0.0.1:\(port)/v1", model: model.id)
                var ready = false
                for _ in 0..<120 {
                    try Task.checkCancellation(); guard ticket == id else { return }
                    guard server.isRunning else { throw AIError.message("The local engine stopped while loading. Close other memory-heavy apps or choose a smaller model.") }
                    var request = URLRequest(url: URL(string: chosen.baseURL + "/models")!)
                    request.timeoutInterval = 2; request.setValue("Bearer \(secret)", forHTTPHeaderField: "Authorization")
                    if let (data, response) = try? await AIChatClient().transport(request), (response as? HTTPURLResponse)?.statusCode == 200,
                       let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let models = object["data"] as? [[String: Any]], models.contains(where: { ($0["id"] as? String) == model.id }) {
                        ready = true; break
                    }
                    try await Task.sleep(for: .milliseconds(500))
                }
                guard ready else { throw AIError.message("The local model did not become ready. Try again with a smaller model.") }
                connection = chosen; key = secret; activeID = model.id; status = "\(model.name) ready · Runs on this Mac"
            } catch {
                if ticket == id {
                    process?.terminate(); process = nil; connection = nil; activeID = nil; key = ""
                    status = "Local model is stopped."
                    if !(error is CancellationError) { self.error = userMessage(error) }
                }
            }
        }
    }
    func stop() {
        ticket = UUID(); operation?.cancel(); verification?.cancel(); operation = nil
        if process?.isRunning == true { process?.terminate() }
        process = nil; activeID = nil; connection = nil; key = ""; workingID = nil
        status = "Local model stopped. Installed downloads are kept."
    }
    private func userMessage(_ error: Error) -> String {
        if let error = error as? AIError { return error.localizedDescription }
        if (error as? URLError)?.code == .cancelled { return "Download cancelled. Choose Download to retry." }
        return "The operation could not finish. Check your connection and free disk space, then retry."
    }
    static func availablePort() throws -> UInt16 {
        let fd = socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AIError.message("Could not open a local connection.") }
        defer { close(fd) }
        var address = sockaddr_in(); address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET); address.sin_addr.s_addr = inet_addr("127.0.0.1"); address.sin_port = 0
        let result = withUnsafePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &address) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        guard result == 0, named == 0 else { throw AIError.message("Could not reserve a local connection. Please retry.") }
        return UInt16(bigEndian: address.sin_port)
    }
}
