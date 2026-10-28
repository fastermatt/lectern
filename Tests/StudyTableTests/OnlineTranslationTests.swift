import XCTest
@testable import StudyTable

final class OnlineTranslationTests: XCTestCase {
    // MARK: Verse-marker parsing

    func testVerseMarkersSplitIntoVersesWithSuperscriptionAsVerseZero() {
        let raw = "To the choirmaster. A Psalm of David.\n\n  [1] O LORD, how many are my foes!\n    Many are rising against me;\n\n[2] many are saying of my soul,  “There is no salvation.” ¶ [3] But you, O LORD…"
        let verses = VerseMarkerParser.split(raw)
        XCTAssertEqual(verses.map(\.n), [0, 1, 2, 3])
        XCTAssertEqual(verses[0].t, "To the choirmaster. A Psalm of David.")
        XCTAssertEqual(verses[1].t, "O LORD, how many are my foes! Many are rising against me;")
        XCTAssertEqual(verses[2].t, "many are saying of my soul, “There is no salvation.”")
    }

    func testTextWithoutMarkersIsRejectedRatherThanGuessed() {
        XCTAssertTrue(VerseMarkerParser.split("No numbers at all.").isEmpty)
    }

    // MARK: ESV

    private static let esvBodyData = Data(#"{"query":"John 1","passages":["[1] In the beginning was the Word, and the Word was with God.\n\n[2] He was in the beginning with God."]}"#.utf8)

    func testESVRequestCarriesTheKeyOnlyInTheAuthorizationHeaderAndAsksForCleanText() async throws {
        let network = MockNetwork { _ in (200, Self.esvBodyData) }
        let chapter = try await ESVProvider(transport: network.transport)
            .fetchChapter(translationID: "ESV", bookCode: "JHN", bookName: "John", chapter: 1, apiKey: "SECRET-KEY")
        XCTAssertEqual(chapter.verses.map(\.n), [1, 2])
        XCTAssertTrue(chapter.attribution.contains("ESV"))
        let request = try XCTUnwrap(network.requests.first)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Token SECRET-KEY")
        XCTAssertFalse(request.url!.absoluteString.contains("SECRET-KEY"), "the key must never appear in the URL")
        let items = Dictionary(uniqueKeysWithValues: URLComponents(url: request.url!, resolvingAgainstBaseURL: false)!.queryItems!.map { ($0.name, $0.value ?? "") })
        XCTAssertEqual(items["q"], "John 1")
        XCTAssertEqual(items["include-footnotes"], "false")
        XCTAssertEqual(items["include-headings"], "false")
        XCTAssertEqual(items["include-verse-numbers"], "true")
        XCTAssertEqual(request.url?.host, "api.esv.org")
    }

    func testESVUsesPsalmNotPsalmsAndMapsHTTPFailuresToActionableErrors() async {
        let network = MockNetwork { _ in (200, Self.esvBodyData) }
        _ = try? await ESVProvider(transport: network.transport).fetchChapter(translationID: "ESV", bookCode: "PSA", bookName: "Psalms", chapter: 23, apiKey: "k")
        XCTAssertTrue(network.requests.first?.url?.absoluteString.contains("q=Psalm%2023") == true || network.requests.first?.url?.absoluteString.contains("q=Psalm+23") == true)

        for (status, expected) in [(401, OnlineError.unauthorized), (403, .unauthorized), (429, .rateLimited), (404, .notFound)] {
            let failing = MockNetwork { _ in (status, Data()) }
            do {
                _ = try await ESVProvider(transport: failing.transport).fetchChapter(translationID: "ESV", bookCode: "JHN", bookName: "John", chapter: 1, apiKey: "k")
                XCTFail("expected failure for \(status)")
            } catch { XCTAssertEqual(error as? OnlineError, expected, "HTTP \(status)") }
        }
    }

    func testOfflineNetworkFailureIsReportedAsOffline() async {
        let transport: HTTPTransport = { _ in throw URLError(.notConnectedToInternet) }
        do {
            _ = try await ESVProvider(transport: transport).fetchChapter(translationID: "ESV", bookCode: "JHN", bookName: "John", chapter: 1, apiKey: "k")
            XCTFail("expected offline")
        } catch { XCTAssertEqual(error as? OnlineError, .offline) }
    }

    // MARK: API.Bible (NKJV)

    func testAPIBibleResolvesTheBibleIDOnceThenFetchesTheChapterWithTheApiKeyHeader() async throws {
        let store = BibleIDStore(defaultsKey: "test.ids.\(UUID().uuidString)")
        defer { UserDefaults.standard.removeObject(forKey: store.defaultsKey) }
        let network = MockNetwork { request in
            if request.url!.path == "/v1/bibles" {
                return (200, Data(#"{"data":[{"id":"nkjv-id-01","abbreviation":"NKJV"},{"id":"other","abbreviation":"NIV"}]}"#.utf8))
            }
            return (200, Data(#"{"data":{"content":"[1] In the beginning was the Word.\n[2] He was in the beginning with God.","copyright":"NKJV © Thomas Nelson"}}"#.utf8))
        }
        let provider = APIBibleProvider(transport: network.transport, idStore: store)
        let first = try await provider.fetchChapter(translationID: "NKJV", bookCode: "JHN", bookName: "John", chapter: 1, apiKey: "K")
        _ = try await provider.fetchChapter(translationID: "NKJV", bookCode: "JHN", bookName: "John", chapter: 2, apiKey: "K")
        XCTAssertEqual(first.verses.count, 2)
        XCTAssertEqual(first.attribution, "NKJV © Thomas Nelson")
        let paths = network.requests.map { $0.url!.path }
        XCTAssertEqual(paths, ["/v1/bibles", "/v1/bibles/nkjv-id-01/chapters/JHN.1", "/v1/bibles/nkjv-id-01/chapters/JHN.2"], "the bible id is looked up once")
        XCTAssertTrue(network.requests.allSatisfy { $0.value(forHTTPHeaderField: "api-key") == "K" })
        XCTAssertTrue(network.requests.allSatisfy { !$0.url!.absoluteString.contains("api-key") })
        XCTAssertEqual(network.requests[0].url?.host, "rest.api.bible")
    }

    func testAPIBibleWithoutAnNKJVEntryForTheKeyIsReportedNotFound() async {
        let network = MockNetwork { _ in (200, Data(#"{"data":[{"id":"x","abbreviation":"NIV"}]}"#.utf8)) }
        let store = BibleIDStore(defaultsKey: "test.ids.\(UUID().uuidString)")
        do {
            _ = try await APIBibleProvider(transport: network.transport, idStore: store)
                .fetchChapter(translationID: "NKJV", bookCode: "JHN", bookName: "John", chapter: 1, apiKey: "K")
            XCTFail("expected notFound")
        } catch { XCTAssertEqual(error as? OnlineError, .notFound) }
    }

    // MARK: Cache limits

    private func chapter(verses: Int, fetched: Date) -> RemoteChapter {
        RemoteChapter(verses: (1...verses).map { RemoteVerse(n: $0, t: "v\($0)") }, attribution: "a", fetchedAt: fetched)
    }

    func testESVCacheNeverHoldsMoreThan480VersesAndEvictsTheOldestChapterFirst() async {
        let clock = TestClock()
        let cache = OnlineChapterCache(directory: temporaryDirectory("esv"), clock: { clock.now })
        for number in 1...6 {
            await cache.put(chapter(verses: 120, fetched: clock.now), provider: .esv, translation: "ESV", book: "PSA", number: number)
            clock.advance(days: 0.01)
        }
        let total = await cache.totalVerses(.esv)
        XCTAssertLessThanOrEqual(total, 480, "Crossway forbids storing more than 500 verses")
        let oldest = await cache.get(.esv, translation: "ESV", book: "PSA", chapter: 1)
        let newest = await cache.get(.esv, translation: "ESV", book: "PSA", chapter: 6)
        XCTAssertNil(oldest); XCTAssertNotNil(newest)
    }

    func testCachedTextExpiresAfterThirtyDaysAndIsDeleted() async {
        let clock = TestClock()
        let directory = temporaryDirectory("expire")
        let cache = OnlineChapterCache(directory: directory, clock: { clock.now })
        await cache.put(chapter(verses: 3, fetched: clock.now), provider: .apiBible, translation: "NKJV", book: "JHN", number: 1)
        clock.advance(days: 29)
        let fresh = await cache.get(.apiBible, translation: "NKJV", book: "JHN", chapter: 1)
        XCTAssertNotNil(fresh)
        clock.advance(days: 2)
        let expired = await cache.get(.apiBible, translation: "NKJV", book: "JHN", chapter: 1)
        XCTAssertNil(expired)
        let count = await cache.chapterCount(.apiBible)
        XCTAssertEqual(count, 0, "expired text is removed from disk")
    }

    func testPurgeExpiredRemovesStaleChaptersAtLaunch() async {
        let clock = TestClock()
        let cache = OnlineChapterCache(directory: temporaryDirectory("purge"), clock: { clock.now })
        await cache.put(chapter(verses: 3, fetched: clock.now), provider: .esv, translation: "ESV", book: "JHN", number: 1)
        clock.advance(days: 45)
        await cache.purgeExpired()
        let count = await cache.chapterCount(.esv)
        XCTAssertEqual(count, 0)
    }

    // MARK: Service behaviour

    private func service(network: MockNetwork, key: String?, directory: URL = temporaryDirectory("svc")) -> OnlineTranslationService {
        OnlineTranslationService(cache: OnlineChapterCache(directory: directory), transport: network.transport,
                                 idStore: BibleIDStore(defaultsKey: "test.ids.\(UUID().uuidString)"), keyReader: { _ in key })
    }

    func testServiceIsCacheFirstSoARepeatVisitMakesNoRequest() async {
        let network = MockNetwork { _ in (200, Self.esvBodyData) }
        let svc = service(network: network, key: "k")
        _ = await svc.load(kind: .esv, translationID: "ESV", bookCode: "JHN", bookName: "John", chapter: 1)
        let second = await svc.load(kind: .esv, translationID: "ESV", bookCode: "JHN", bookName: "John", chapter: 1)
        XCTAssertEqual(network.requests.count, 1)
        guard case .verses(_, _, let origin) = second, case .cached = origin else { return XCTFail("expected a cached result") }
    }

    func testMissingKeyMakesNoRequestAndSaysWhatToDo() async {
        let network = MockNetwork { _ in (200, Self.esvBodyData) }
        let outcome = await service(network: network, key: nil).load(kind: .esv, translationID: "ESV", bookCode: "JHN", bookName: "John", chapter: 1)
        XCTAssertEqual(network.requests.count, 0)
        guard case .failure(let message) = outcome else { return XCTFail() }
        XCTAssertTrue(message.contains("API key"))
    }

    func testOfflineWithNothingCachedExplainsThatTheTranslationIsOnlineOnly() async {
        let network = MockNetwork { _ in throw URLError(.notConnectedToInternet) }
        let outcome = await service(network: network, key: "k").load(kind: .esv, translationID: "ESV", bookCode: "JHN", bookName: "John", chapter: 1)
        guard case .failure(let message) = outcome else { return XCTFail() }
        XCTAssertTrue(message.contains("online-only"))
    }

    func testTheAPIKeyIsNeverWrittenToTheCache() async throws {
        let directory = temporaryDirectory("leak")
        let network = MockNetwork { _ in (200, Self.esvBodyData) }
        _ = await service(network: network, key: "TOP-SECRET-12345", directory: directory)
            .load(kind: .esv, translationID: "ESV", bookCode: "JHN", bookName: "John", chapter: 1)
        let files = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)?.compactMap { $0 as? URL } ?? []
        XCTAssertFalse(files.isEmpty)
        for file in files where !file.hasDirectoryPath {
            XCTAssertFalse(try String(contentsOf: file, encoding: .utf8).contains("TOP-SECRET-12345"))
        }
    }

    func testProviderTermsSummariesStateTheEnforcedLimits() {
        XCTAssertTrue(OnlineProvider.esv.termsSummary.contains("500"))
        XCTAssertTrue(OnlineProvider.apiBible.termsSummary.contains("30 days"))
        XCTAssertEqual(CachePolicy.policy(for: .esv).maxVerses, 480)
        XCTAssertEqual(CachePolicy.policy(for: .apiBible).ttl, 30 * 86_400)
    }
}
