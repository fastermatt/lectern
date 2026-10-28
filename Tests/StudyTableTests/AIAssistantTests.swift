import XCTest
@testable import StudyTable

@MainActor
final class AIAssistantTests: XCTestCase {
    private let reply = Data(#"{"choices":[{"message":{"content":"Read Romans 8:28 in context."},"finish_reason":"stop"}]}"#.utf8)

    func testEndpointValidationAndKeyAccountIsolation() throws {
        for base in ["https://api.example.com/v1", "http://localhost:1234/v1", "http://127.0.0.1:1234/v1"] {
            XCTAssertEqual(try AIConnection(baseURL: base).endpoint().path, "/v1/chat/completions")
        }
        for base in ["http://example.com/v1", "file:///tmp/api", "https://user:secret@example.com/v1", "https://example.com/v1?key=secret", "https://example.com/v1#x"] {
            XCTAssertThrowsError(try AIConnection(baseURL: base).endpoint())
        }
        XCTAssertNotEqual(try AIKeyStore.account(AIConnection(baseURL: "https://a.example/v1")),
                          try AIKeyStore.account(AIConnection(baseURL: "https://b.example/v1")))
    }
    func testRequestContainsOnlyExplicitConversationAndUsesBearerHeader() async throws {
        let body = reply
        let network = MockNetwork { request in
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.url?.absoluteString, "https://ai.example/v1/chat/completions")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer test-only-key")
            let data = try JSONSerialization.jsonObject(with: request.httpBody!) as! [String: Any]
            XCTAssertEqual(data["model"] as? String, "my-model")
            XCTAssertEqual(data["stream"] as? Bool, false)
            XCTAssertFalse(String(data: request.httpBody!, encoding: .utf8)!.contains("test-only-key"))
            XCTAssertEqual((data["messages"] as? [[String: Any]])?.count, 1)
            return (200, body)
        }
        let result = try await AIChatClient(transport: network.transport).reply(connection: AIConnection(baseURL: "https://ai.example/v1", model: "my-model"),
            key: "test-only-key", messages: [AIMessage(role: "user", content: "Explain Romans 8:28")])
        XCTAssertTrue(result.contains("Romans"))
    }
    func testServerErrorsDoNotExposeResponseBodyAndMalformedResponsesFail() async {
        for (code, data) in [(401, Data("reflected-private-key".utf8)), (200, Data("not json".utf8)),
                             (200, Data(#"{"choices":[]}"#.utf8))] {
            let network = MockNetwork { _ in (code, data) }
            do {
                _ = try await AIChatClient(transport: network.transport).reply(connection: AIConnection(model: "test"), key: "", messages: [])
                XCTFail("Expected rejection")
            } catch { XCTAssertFalse(error.localizedDescription.contains("reflected-private-key")) }
        }
    }
    func testSessionKeepsContextAndBlocksTransferToAnotherProvider() async throws {
        let body = reply
        let network = MockNetwork { _ in (200, body) }
        let session = AIChatSession()
        session.connection.model = "test"
        session.draft = "Explain this"; session.context = "BSB Romans 8:28"
        session.send(key: "", client: AIChatClient(transport: network.transport))
        for _ in 0..<100 where session.isSending { try await Task.sleep(for: .milliseconds(10)) }
        XCTAssertEqual(session.messages.count, 2)
        XCTAssertTrue(session.messages.first?.content.contains("BSB Romans 8:28") == true)
        session.connection.baseURL = "https://other.example/v1"
        session.draft = "Continue"
        session.send(key: "", client: AIChatClient(transport: network.transport))
        XCTAssertNotNil(session.error)
        XCTAssertEqual(network.requests.count, 1)
        session.clear()
        XCTAssertTrue(session.messages.isEmpty)
    }
    func testStopDiscardsLateReplyAndPreferencesContainNoKeyOrChat() async throws {
        let session = AIChatSession(), defaults = ephemeralDefaults()
        session.connection.model = "test"; session.draft = "private question"
        try session.save(defaults)
        XCTAssertEqual(defaults.string(forKey: "ai.model"), "test")
        XCTAssertNil(defaults.object(forKey: "ai.key"))
        let body = reply
        let client = AIChatClient(transport: { request in
            try? await Task.sleep(for: .milliseconds(80))
            return (body, HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!)
        })
        session.send(key: "", client: client)
        session.stop()
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertTrue(session.messages.isEmpty)
        XCTAssertFalse(session.isSending)
        XCTAssertEqual(session.draft, "private question")
    }

    func testRedirectsAreRefused() {
        let request = URLRequest(url: URL(string: "https://second.example/chat/completions")!)
        let task = URLSession.shared.dataTask(with: request) // Never resumed; no network.
        let response = HTTPURLResponse(url: URL(string: "https://first.example")!, statusCode: 307, httpVersion: nil, headerFields: nil)!
        AIRedirectPolicy().urlSession(.shared, task: task, willPerformHTTPRedirection: response, newRequest: request) {
            XCTAssertNil($0, "No redirect may forward a credential or conversation")
        }
    }

    func testLocalHTTPContractWhenFixtureServerProvided() async throws {
        guard let base = ProcessInfo.processInfo.environment["LECTERN_AI_FIXTURE_URL"] else {
            throw XCTSkip("Optional isolated loopback HTTP fixture")
        }
        let client = AIChatClient()
        let answer = try await client.reply(connection: AIConnection(baseURL: base + "/v1", model: "fixture-model"),
            key: "fixture-only-key", messages: [AIMessage(role: "user", content: "Read Romans 8:28")])
        XCTAssertEqual(answer, "Fixture response for Romans 8:28.")
        do {
            _ = try await client.reply(connection: AIConnection(baseURL: base + "/redirect", model: "fixture-model"),
                key: "fixture-only-key", messages: [])
            XCTFail("Redirect should be rejected")
        } catch { XCTAssertTrue(error.localizedDescription.contains("307")) }
    }
}
