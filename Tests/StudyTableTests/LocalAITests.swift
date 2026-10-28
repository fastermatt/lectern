import XCTest
import CryptoKit
@testable import StudyTable

@MainActor
final class LocalAITests: XCTestCase {
    func testIntegrityRejectsCorruptionAndIncompleteDownloads() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: url) }
        let content = Data("GGUFtest model".utf8)
        let digest = SHA256.hash(data: content).map { String(format: "%02x", $0) }.joined()
        let model = LocalAIModel(id: "test", name: "Test", size: "test", detail: "", recommendedRAM: 8, repository: "test/test", revision: "abc", filename: "test.gguf", bytes: Int64(content.count), sha256: digest)
        try content.write(to: url); XCTAssertNoThrow(try LocalAIStorage.validate(url, model: model))
        try Data("GGUFtest modeX".utf8).write(to: url); XCTAssertThrowsError(try LocalAIStorage.validate(url, model: model))
        try Data("GGUF".utf8).write(to: url); XCTAssertThrowsError(try LocalAIStorage.validate(url, model: model))
        try Data("<html>error</html>".utf8).write(to: url); XCTAssertThrowsError(try LocalAIStorage.validate(url, model: model))
    }
    func testDownloadsArePinnedAndRedirectsStayOnHTTPSModelHosts() {
        XCTAssertEqual(Set(LocalAIModel.catalog.map(\.id)).count, 3)
        for model in LocalAIModel.catalog {
            XCTAssertEqual(model.revision.count, 40); XCTAssertEqual(model.sha256.count, 64)
            XCTAssertTrue(model.downloadURL.path.contains(model.revision))
        }
        for value in ["https://huggingface.co/a", "https://cas-bridge.xethub.hf.co/a"] { XCTAssertTrue(LocalAIStorage.allowedDownloadURL(URL(string: value)!)) }
        for value in ["http://huggingface.co/a", "https://huggingface.co.evil.test/a", "https://user:secret@huggingface.co/a", "file:///tmp/a"] { XCTAssertFalse(LocalAIStorage.allowedDownloadURL(URL(string: value)!)) }
    }
    func testLocalContextBudgetRejectsBeforeNetwork() async {
        let client = AIChatClient(transport: { _ in XCTFail("Oversized context reached transport"); throw CancellationError() })
        do {
            _ = try await client.reply(connection: AIConnection(model: "local"), key: "", messages: [.init(role: "user", content: String(repeating: "x", count: 6001))], local: true)
            XCTFail("Expected rejection")
        } catch { XCTAssertTrue(error.localizedDescription.contains("too large")) }
    }
    func testLocalMessageBudgetRejectsExcessTemplateOverhead() async {
        let client = AIChatClient(transport: { _ in XCTFail("Too many messages reached transport"); throw CancellationError() })
        do {
            _ = try await client.reply(connection: AIConnection(model: "local"), key: "", messages: Array(repeating: AIMessage(role: "user", content: "x"), count: 33), local: true)
            XCTFail("Expected rejection")
        } catch { XCTAssertTrue(error.localizedDescription.contains("too large")) }
    }
    func testRealDownloadLoadChatStopRestartAndRemove() async throws {
        guard let runtimePath = ProcessInfo.processInfo.environment["LECTERN_TEST_RUNTIME"] else { throw XCTSkip("Opt-in real model download/inference integration test") }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lectern-local-test-" + UUID().uuidString)
        let manager = LocalAIManager(root: root, runtime: URL(fileURLWithPath: runtimePath))
        defer { manager.stop(); try? FileManager.default.removeItem(at: root) }
        let index = Int(ProcessInfo.processInfo.environment["LECTERN_TEST_MODEL_INDEX"] ?? "0") ?? 0
        let model = LocalAIModel.catalog[index]
        // A cancelled download must never appear installed; retry uses a fresh temporary file.
        manager.download(model); manager.cancel()
        while manager.busy { try await Task.sleep(for: .milliseconds(50)) }
        XCTAssertFalse(manager.installed.contains(model.id))
        manager.download(model)
        while manager.busy { try await Task.sleep(for: .milliseconds(200)) }
        XCTAssertNil(manager.error); XCTAssertTrue(manager.installed.contains(model.id))
        guard manager.installed.contains(model.id) else { return }
        for iteration in 0..<2 {
            manager.start(model)
            while manager.busy { try await Task.sleep(for: .milliseconds(200)) }
            XCTAssertNil(manager.error); XCTAssertTrue(manager.ready)
            guard let connection = manager.connection else { return }
            let unauthorized = try await AIChatClient().transport(URLRequest(url: URL(string: connection.baseURL + "/models")!))
            XCTAssertEqual((unauthorized.1 as? HTTPURLResponse)?.statusCode, 401)
            let reply = try await AIChatClient().reply(connection: connection, key: manager.key, messages: [
                .init(role: "system", content: "Use only the supplied verse. Do not invent citations."),
                .init(role: "user", content: "Romans 8:28: And we know that God works all things together for the good of those who love Him, who are called according to His purpose. Summarize this verse in one sentence and cite Romans 8:28.")], local: true)
            XCTAssertFalse(reply.isEmpty)
            // Citation adherence is an observed model-quality result, not a transport guarantee.
            print("Citation present: \(reply.contains("8:28"))")
            print("Local model integration iteration \(iteration): \(reply)")
            manager.stop(); XCTAssertFalse(manager.ready)
            try await Task.sleep(for: .seconds(4))
            do { _ = try await AIChatClient().transport(URLRequest(url: URL(string: connection.baseURL + "/models")!)); XCTFail("Engine still listening after Stop") } catch { }
        }
        let reloaded = LocalAIManager(root: root, runtime: URL(fileURLWithPath: runtimePath))
        XCTAssertTrue(reloaded.installed.contains(model.id))
        reloaded.remove(model); XCTAssertFalse(reloaded.installed.contains(model.id))
        XCTAssertFalse(FileManager.default.fileExists(atPath: manager.file(model).path))
    }
}
