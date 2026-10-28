import XCTest
@testable import StudyTable

@MainActor
final class LecternCLITests: XCTestCase {
    private func json(_ response: CLIResponse) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: response.data) as? [String: Any])
    }
    func testHelpWorksWithoutResourcesAndRejectsUnknownOrRepeatedOptions() async throws {
        let help = await LecternCLI.run(["help"], root: nil)
        XCTAssertEqual(help.status, 0)
        XCTAssertEqual(try json(help)["schemaVersion"] as? Int, 1)
        for args in [["delete"], ["read"], ["read", "John", "3"], ["search", "love", "--limit", "0"],
                     ["search", "love", "--limit", "2", "--limit", "3"], ["guide", "John 3", "--unknown", "true"],
                     ["read", "John 3:16", "--translation", "ESV"], ["read", "John 5:4"], ["read", "John 1–6"]] {
            let result = await LecternCLI.run(args)
            XCTAssertEqual(result.status, 2, "\(args)")
            XCTAssertEqual(try json(result)["ok"] as? Bool, false)
        }
        let missing = await LecternCLI.run(["resources"], root: nil)
        XCTAssertEqual(missing.status, 1)
    }
    func testReadPreservesNumberingRangeAndAttribution() async throws {
        let response = await LecternCLI.run(["read", "Romans 8:28–9:5"])
        let data = try XCTUnwrap(try json(response)["data"] as? [String: Any])
        let verses = try XCTUnwrap(data["verses"] as? [[String: Any]])
        XCTAssertEqual(verses.count, 17)
        XCTAssertEqual(verses.last?["chapter"] as? Int, 9)
        XCTAssertFalse((data["attribution"] as? String ?? "").isEmpty)
        let end = await LecternCLI.run(["read", "Romans 16:27"])
        XCTAssertEqual(end.status, 0)
    }
    func testSearchPaginationAndScopeUseRealCorpus() async throws {
        let first = try json(await LecternCLI.run(["search", "faith OR hope", "--limit", "2"]))
        let next = try json(await LecternCLI.run(["search", "faith OR hope", "--limit", "2", "--offset", "2"]))
        let a = try XCTUnwrap(first["data"] as? [String: Any]), b = try XCTUnwrap(next["data"] as? [String: Any])
        XCTAssertEqual(a["total"] as? Int, 388)
        XCTAssertEqual((a["hits"] as? [[String: Any]])?.count, 2)
        XCTAssertNotEqual((a["hits"] as? [[String: Any]])?.first?["reference"] as? String,
                          (b["hits"] as? [[String: Any]])?.first?["reference"] as? String)
        let scoped = try json(await LecternCLI.run(["search", "love", "--in", "John 3"]))
        let hits = (scoped["data"] as? [String: Any])?["hits"] as? [[String: Any]] ?? []
        XCTAssertTrue(hits.allSatisfy { ($0["book"] as? String) == "JHN" && ($0["chapter"] as? Int) == 3 })
    }
    func testGuideExcludesMixedRightsAndPreservesCitations() async throws {
        let response = try json(await LecternCLI.run(["guide", "Romans 8:28–39", "--limit", "100"]))
        let sources = try XCTUnwrap((response["data"] as? [String: Any])?["sources"] as? [[String: Any]])
        XCTAssertFalse(sources.isEmpty)
        XCTAssertTrue(sources.allSatisfy { !($0["id"] as? String ?? "").hasPrefix("hcf") })
        for source in sources {
            XCTAssertNotNil(URL(string: source["sourceURL"] as? String ?? ""))
            XCTAssertFalse((source["license"] as? String ?? "").isEmpty)
            XCTAssertNotNil(source["exactQuote"] as? Bool)
            XCTAssertLessThanOrEqual((source["excerpt"] as? String ?? "").count, 4000)
        }
    }
    func testWordReturnsRealEntryAndBoundedOccurrences() async throws {
        let response = try json(await LecternCLI.run(["word", "G26", "--limit", "3"]))
        let data = try XCTUnwrap(response["data"] as? [String: Any])
        XCTAssertFalse((data["lemma"] as? String ?? "").isEmpty)
        XCTAssertEqual((data["occurrences"] as? [[String: Any]])?.count, 3)
        XCTAssertGreaterThan(data["total"] as? Int ?? 0, 3)
    }
}
