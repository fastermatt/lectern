import Foundation
import Security

// MARK: - Providers and errors

/// Publisher APIs that can supply copyrighted translations with the user's own key.
/// Text obtained this way is fetched on demand and is never bundled with the app.
enum OnlineProvider: String, CaseIterable, Identifiable, Sendable {
    case esv
    case apiBible

    var id: String { rawValue }
    var displayName: String {
        switch self {
        case .esv: "ESV API (Crossway)"
        case .apiBible: "API.Bible (NKJV)"
        }
    }
    var keyHeader: String {
        switch self {
        case .esv: "Authorization: Token …"
        case .apiBible: "api-key: …"
        }
    }
    var registrationURL: URL {
        switch self {
        case .esv: URL(string: "https://api.esv.org/")!
        case .apiBible: URL(string: "https://scripture.api.bible/")!
        }
    }
    var termsURL: URL {
        switch self {
        case .esv: URL(string: "https://api.esv.org/")!
        case .apiBible: URL(string: "https://api.bible/terms-and-conditions")!
        }
    }
    /// The limits this app enforces on your behalf.
    var termsSummary: String {
        switch self {
        case .esv:
            "Non-commercial use. At most 500 verses per request. No more than 500 verses (or half a book) may be stored locally, so this app keeps at most 480 verses cached and clears them after 30 days. Copyright notice is shown with the text."
        case .apiBible:
            "NKJV is available only to non-commercial apps under 5,000 monthly users on a Starter or Pro plan (Terms §9.11). Cached text must be refreshed at least every 30 days (§11); this app expires it after 30 days. FUMS usage reporting (§14) is not implemented, so treat this integration as experimental."
        }
    }
}

enum OnlineError: Error, Equatable, LocalizedError {
    case missingKey
    case unauthorized
    case rateLimited
    case notFound
    case offline
    case badResponse(String)

    var errorDescription: String? {
        switch self {
        case .missingKey: "Add your API key in Settings › Online translations."
        case .unauthorized: "The publisher rejected your API key. Check it in Settings."
        case .rateLimited: "The publisher's rate limit was reached. Try again shortly."
        case .notFound: "The publisher has no text for this passage."
        case .offline: "This translation is online-only and no cached copy is available offline."
        case .badResponse(let detail): "Unexpected response from the publisher (\(detail))."
        }
    }
}

typealias HTTPTransport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

struct RemoteVerse: Codable, Sendable, Equatable {
    let n: Int
    let t: String
}

struct RemoteChapter: Codable, Sendable, Equatable {
    var verses: [RemoteVerse]
    var attribution: String
    var fetchedAt: Date
}

protocol OnlineScriptureProvider: Sendable {
    var provider: OnlineProvider { get }
    func fetchChapter(translationID: String, bookCode: String, bookName: String,
                      chapter: Int, apiKey: String) async throws -> RemoteChapter
}

// MARK: - Verse marker parsing

/// Publisher APIs return a chapter as one string with `[16]`-style verse markers.
enum VerseMarkerParser {
    static func split(_ raw: String) -> [RemoteVerse] {
        let cleaned = raw.replacingOccurrences(of: "¶", with: " ")
        guard let regex = try? NSRegularExpression(pattern: #"\[(\d+)\]"#) else { return [] }
        let whole = NSRange(cleaned.startIndex..., in: cleaned)
        let matches = regex.matches(in: cleaned, range: whole)
        guard !matches.isEmpty else { return [] }

        var verses: [RemoteVerse] = []
        if let first = matches.first, let range = Range(NSRange(location: 0, length: first.range.location), in: cleaned) {
            let lead = normalize(stripTrailingSpeakerLabel(cleaned[range]))
            if !lead.isEmpty { verses.append(RemoteVerse(n: 0, t: lead)) }
        }
        for (index, match) in matches.enumerated() {
            guard let numberRange = Range(match.range(at: 1), in: cleaned),
                  let number = Int(cleaned[numberRange]) else { continue }
            let start = match.range.location + match.range.length
            let end = index + 1 < matches.count ? matches[index + 1].range.location : whole.length
            guard let range = Range(NSRange(location: start, length: end - start), in: cleaned) else { continue }
            let text = normalize(stripTrailingSpeakerLabel(cleaned[range]))
            if !text.isEmpty { verses.append(RemoteVerse(n: number, t: text)) }
        }
        return verses
    }

    private static func normalize(_ text: Substring) -> String {
        text.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    /// Some publishers (the ESV, for Song of Solomon's dialogue) print a bare speaker label —
    /// "She", "He", "Others" — as its own blank-line-isolated paragraph between two verses. It
    /// carries no verse-number marker of its own, so without this the marker-based split above
    /// attaches it to the end of the *previous* verse's text ("...your companions? He"). Detected
    /// structurally — an isolated, short, capitalized trailing paragraph — not by a fixed word
    /// list, so it generalizes to any publisher/book using the same convention.
    ///
    /// The label is always the LAST paragraph within a verse's captured range (the range is cut
    /// off right at the next verse marker, immediately after the label's own trailing
    /// whitespace) — so this finds every paragraph the blank-line breaks divide the text into,
    /// and checks the last non-blank one, not simply "whatever follows the final break" (which
    /// is usually empty here, since nothing follows the label but the next marker).
    private static func stripTrailingSpeakerLabel(_ text: Substring) -> Substring {
        guard let paragraphBreak = try? NSRegularExpression(pattern: #"\n[ \t]*\n"#) else { return text }
        let nsRange = NSRange(text.startIndex..., in: text)
        let breaks = paragraphBreak.matches(in: String(text), range: nsRange).compactMap { Range($0.range, in: text) }
        guard !breaks.isEmpty else { return text }

        var paragraphStarts = [text.startIndex] + breaks.map(\.upperBound)
        var paragraphEnds = breaks.map(\.lowerBound) + [text.endIndex]
        // Walk paragraphs from the end, skipping any that are blank (pure whitespace), to find
        // the true last paragraph and where it begins.
        while let lastEnd = paragraphEnds.last, let lastStart = paragraphStarts.last,
              text[lastStart..<lastEnd].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            paragraphStarts.removeLast()
            paragraphEnds.removeLast()
            if paragraphStarts.isEmpty { return text }
        }
        guard let lastStart = paragraphStarts.last, let lastEnd = paragraphEnds.last, paragraphStarts.count > 1 else { return text }
        let candidate = text[lastStart..<lastEnd].trimmingCharacters(in: .whitespacesAndNewlines)
        guard looksLikeSpeakerLabel(candidate) else { return text }
        return text[..<lastStart]
    }

    private static func looksLikeSpeakerLabel(_ candidate: String) -> Bool {
        guard !candidate.isEmpty, candidate.count <= 24 else { return false }
        let words = candidate.split(separator: " ")
        guard (1...3).contains(words.count) else { return false }
        return words.allSatisfy { word in
            guard let first = word.first, first.isUppercase else { return false }
            return word.dropFirst().allSatisfy { $0.isLowercase || $0 == "’" || $0 == "'" }
        }
    }
}

// MARK: - ESV API

struct ESVProvider: OnlineScriptureProvider {
    let transport: HTTPTransport
    var provider: OnlineProvider { .esv }
    static let endpoint = URL(string: "https://api.esv.org/v3/passage/text/")!
    static let attribution = "Scripture quotations are from the ESV® Bible (The Holy Bible, English Standard Version®), © 2001 by Crossway, a publishing ministry of Good News Publishers. www.esv.org"

    private struct Response: Decodable { let passages: [String] }

    static func request(query: String, apiKey: String) -> URLRequest {
        var components = URLComponents(url: endpoint, resolvingAgainstBaseURL: false)!
        components.queryItems = [
            ("q", query), ("include-passage-references", "false"), ("include-verse-numbers", "true"),
            ("include-first-verse-numbers", "true"), ("include-footnotes", "false"),
            ("include-footnote-body", "false"), ("include-headings", "false"),
            ("include-short-copyright", "false"), ("include-copyright", "false"),
            ("include-passage-horizontal-lines", "false"), ("include-heading-horizontal-lines", "false"),
            ("include-selahs", "true"), ("indent-using", "space"), ("indent-paragraphs", "0"),
            ("indent-poetry", "false"), ("indent-declares", "0"), ("indent-psalm-doxology", "0"),
            ("line-length", "0")
        ].map { URLQueryItem(name: $0.0, value: $0.1) }
        var request = URLRequest(url: components.url!)
        request.setValue("Token \(apiKey)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 20
        return request
    }

    func fetchChapter(translationID: String, bookCode: String, bookName: String,
                      chapter: Int, apiKey: String) async throws -> RemoteChapter {
        let name = bookCode == "PSA" ? "Psalm" : bookName
        let (data, response) = try await OnlineHTTP.perform(Self.request(query: "\(name) \(chapter)", apiKey: apiKey), transport)
        try OnlineHTTP.check(response)
        guard let decoded = try? JSONDecoder().decode(Response.self, from: data) else {
            throw OnlineError.badResponse("not JSON")
        }
        guard let passage = decoded.passages.first, !passage.isEmpty else { throw OnlineError.notFound }
        let verses = VerseMarkerParser.split(passage)
        guard !verses.isEmpty else { throw OnlineError.badResponse("no verse markers") }
        return RemoteChapter(verses: verses, attribution: Self.attribution, fetchedAt: Date())
    }
}

// MARK: - API.Bible (NKJV)

struct APIBibleProvider: OnlineScriptureProvider {
    let transport: HTTPTransport
    let idStore: BibleIDStore
    var provider: OnlineProvider { .apiBible }
    static let base = URL(string: "https://rest.api.bible/v1")!

    private struct BibleList: Decodable {
        struct Item: Decodable { let id: String; let abbreviation: String?; let abbreviationLocal: String? }
        let data: [Item]
    }
    private struct ChapterResponse: Decodable {
        struct Payload: Decodable { let content: String; let copyright: String? }
        let data: Payload
    }

    static func request(path: String, query: [URLQueryItem], apiKey: String) -> URLRequest {
        var components = URLComponents(url: base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        components.queryItems = query.isEmpty ? nil : query
        var request = URLRequest(url: components.url!)
        request.setValue(apiKey, forHTTPHeaderField: "api-key")
        request.timeoutInterval = 20
        return request
    }

    func resolveBibleID(abbreviation: String, apiKey: String) async throws -> String {
        if let stored = idStore.id(for: abbreviation) { return stored }
        let request = Self.request(path: "bibles", query: [
            URLQueryItem(name: "abbreviation", value: abbreviation), URLQueryItem(name: "language", value: "eng")
        ], apiKey: apiKey)
        let (data, response) = try await OnlineHTTP.perform(request, transport)
        try OnlineHTTP.check(response)
        guard let list = try? JSONDecoder().decode(BibleList.self, from: data) else {
            throw OnlineError.badResponse("bible list")
        }
        let wanted = abbreviation.uppercased()
        guard let match = list.data.first(where: {
            ($0.abbreviation ?? "").uppercased() == wanted || ($0.abbreviationLocal ?? "").uppercased() == wanted
        }) else { throw OnlineError.notFound }
        idStore.set(match.id, for: abbreviation)
        return match.id
    }

    func fetchChapter(translationID: String, bookCode: String, bookName: String,
                      chapter: Int, apiKey: String) async throws -> RemoteChapter {
        let bibleID = try await resolveBibleID(abbreviation: translationID, apiKey: apiKey)
        let request = Self.request(path: "bibles/\(bibleID)/chapters/\(bookCode).\(chapter)", query: [
            URLQueryItem(name: "content-type", value: "text"), URLQueryItem(name: "include-notes", value: "false"),
            URLQueryItem(name: "include-titles", value: "false"), URLQueryItem(name: "include-chapter-numbers", value: "false"),
            URLQueryItem(name: "include-verse-numbers", value: "true"), URLQueryItem(name: "include-verse-spans", value: "false")
        ], apiKey: apiKey)
        let (data, response) = try await OnlineHTTP.perform(request, transport)
        try OnlineHTTP.check(response)
        guard let decoded = try? JSONDecoder().decode(ChapterResponse.self, from: data) else {
            throw OnlineError.badResponse("chapter")
        }
        let verses = VerseMarkerParser.split(decoded.data.content)
        guard !verses.isEmpty else { throw OnlineError.badResponse("no verse markers") }
        let attribution = (decoded.data.copyright ?? "").isEmpty
            ? "Scripture text provided through API.Bible. See the publisher's copyright notice." : decoded.data.copyright!
        return RemoteChapter(verses: verses, attribution: attribution, fetchedAt: Date())
    }
}

/// Remembers the API.Bible identifier discovered for an abbreviation.
struct BibleIDStore: Sendable {
    var defaultsKey = "apibible.bibleIDs"
    func id(for abbreviation: String) -> String? {
        (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String])?[abbreviation.uppercased()]
    }
    func set(_ id: String, for abbreviation: String) {
        var map = (UserDefaults.standard.dictionary(forKey: defaultsKey) as? [String: String]) ?? [:]
        map[abbreviation.uppercased()] = id
        UserDefaults.standard.set(map, forKey: defaultsKey)
    }
}

enum OnlineHTTP {
    static func perform(_ request: URLRequest, _ transport: HTTPTransport) async throws -> (Data, URLResponse) {
        do { return try await transport(request) }
        catch let error as URLError where [.notConnectedToInternet, .networkConnectionLost, .timedOut,
                                           .cannotFindHost, .cannotConnectToHost, .dataNotAllowed].contains(error.code) {
            throw OnlineError.offline
        }
    }

    static func check(_ response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse else { throw OnlineError.badResponse("no HTTP status") }
        switch http.statusCode {
        case 200..<300: return
        case 401, 403: throw OnlineError.unauthorized
        case 404: throw OnlineError.notFound
        case 429: throw OnlineError.rateLimited
        default: throw OnlineError.badResponse("HTTP \(http.statusCode)")
        }
    }

    static let live: HTTPTransport = { request in try await URLSession.shared.data(for: request) }
}

// MARK: - Cache that enforces each publisher's storage limits

struct CachePolicy: Sendable {
    let ttl: TimeInterval
    let maxVerses: Int?
    let maxChapters: Int?

    static let thirtyDays: TimeInterval = 30 * 24 * 60 * 60

    static func policy(for provider: OnlineProvider) -> CachePolicy {
        switch provider {
        // Crossway: do not store more than 500 verses (or half a book). Stay under with margin.
        case .esv: CachePolicy(ttl: thirtyDays, maxVerses: 480, maxChapters: nil)
        // API.Bible §11: refresh cached content at least every 30 days.
        case .apiBible: CachePolicy(ttl: thirtyDays, maxVerses: nil, maxChapters: 60)
        }
    }
}

actor OnlineChapterCache {
    private let directory: URL
    private let clock: @Sendable () -> Date

    init(directory: URL = AppResources.onlineCacheDirectory, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.clock = clock
    }

    private func folder(_ provider: OnlineProvider) -> URL {
        directory.appendingPathComponent(provider.rawValue, isDirectory: true)
    }

    private func file(_ provider: OnlineProvider, _ translation: String, _ book: String, _ chapter: Int) -> URL {
        folder(provider).appendingPathComponent("\(translation).\(book).\(chapter).json")
    }

    /// A cached chapter, unless it is past the publisher's refresh window (expired files are deleted).
    func get(_ provider: OnlineProvider, translation: String, book: String, chapter: Int) -> RemoteChapter? {
        let url = file(provider, translation, book, chapter)
        guard let data = try? Data(contentsOf: url),
              let cached = try? JSONDecoder.iso.decode(RemoteChapter.self, from: data) else { return nil }
        if clock().timeIntervalSince(cached.fetchedAt) > CachePolicy.policy(for: provider).ttl {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return cached
    }

    func put(_ chapter: RemoteChapter, provider: OnlineProvider, translation: String, book: String, number: Int) {
        try? FileManager.default.createDirectory(at: folder(provider), withIntermediateDirectories: true)
        guard let data = try? JSONEncoder.iso.encode(chapter) else { return }
        try? data.write(to: file(provider, translation, book, number), options: .atomic)
        enforceLimits(provider)
    }

    func purgeExpired() {
        for provider in OnlineProvider.allCases { for (url, chapter) in stored(provider) {
            if clock().timeIntervalSince(chapter.fetchedAt) > CachePolicy.policy(for: provider).ttl {
                try? FileManager.default.removeItem(at: url)
            }
        } }
    }

    func clear() { try? FileManager.default.removeItem(at: directory) }

    func totalVerses(_ provider: OnlineProvider) -> Int {
        stored(provider).reduce(0) { $0 + $1.1.verses.filter { $0.n > 0 }.count }
    }

    func chapterCount(_ provider: OnlineProvider) -> Int { stored(provider).count }

    private func stored(_ provider: OnlineProvider) -> [(URL, RemoteChapter)] {
        let urls = (try? FileManager.default.contentsOfDirectory(at: folder(provider), includingPropertiesForKeys: nil)) ?? []
        return urls.compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let chapter = try? JSONDecoder.iso.decode(RemoteChapter.self, from: data) else { return nil }
            return (url, chapter)
        }
    }

    /// Evict the oldest chapters until the publisher's storage limits hold again.
    private func enforceLimits(_ provider: OnlineProvider) {
        let policy = CachePolicy.policy(for: provider)
        var items = stored(provider).sorted { $0.1.fetchedAt < $1.1.fetchedAt }
        func verses(_ items: [(URL, RemoteChapter)]) -> Int { items.reduce(0) { $0 + $1.1.verses.filter { $0.n > 0 }.count } }
        while items.count > 1,
              (policy.maxVerses.map { verses(items) > $0 } ?? false) || (policy.maxChapters.map { items.count > $0 } ?? false) {
            try? FileManager.default.removeItem(at: items.removeFirst().0)
        }
    }
}

extension JSONDecoder {
    static var iso: JSONDecoder { let d = JSONDecoder(); d.dateDecodingStrategy = .iso8601; return d }
}
extension JSONEncoder {
    static var iso: JSONEncoder { let e = JSONEncoder(); e.dateEncodingStrategy = .iso8601; return e }
}

// MARK: - Keychain

enum KeychainStore {
    static let service = "com.fastermatt.studytable.beta.online-keys"

    private static func query(_ account: String) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
    }

    static func read(_ provider: OnlineProvider) -> String? {
        var q = query(provider.rawValue)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        guard SecItemCopyMatching(q as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func save(_ key: String, for provider: OnlineProvider) -> Bool {
        remove(provider)
        var q = query(provider.rawValue)
        q[kSecValueData as String] = Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8)
        return SecItemAdd(q as CFDictionary, nil) == errSecSuccess
    }

    static func remove(_ provider: OnlineProvider) { SecItemDelete(query(provider.rawValue) as CFDictionary) }
}

// MARK: - Orchestration

enum OnlineOrigin: Sendable, Equatable {
    case live
    case cached(Date)
}

enum OnlineOutcome: Sendable, Equatable {
    case verses([BibleVerse], attribution: String, origin: OnlineOrigin)
    case failure(String)
}

/// Cache-first loading of one chapter from a publisher API.
struct OnlineTranslationService: Sendable {
    let cache: OnlineChapterCache
    let esv: ESVProvider
    let apiBible: APIBibleProvider
    let keyReader: @Sendable (OnlineProvider) -> String?

    init(cache: OnlineChapterCache = OnlineChapterCache(), transport: @escaping HTTPTransport = OnlineHTTP.live,
         idStore: BibleIDStore = BibleIDStore(), keyReader: @escaping @Sendable (OnlineProvider) -> String? = KeychainStore.read) {
        self.cache = cache
        self.esv = ESVProvider(transport: transport)
        self.apiBible = APIBibleProvider(transport: transport, idStore: idStore)
        self.keyReader = keyReader
    }

    func provider(_ kind: OnlineProvider) -> OnlineScriptureProvider { kind == .esv ? esv : apiBible }

    func load(kind: OnlineProvider, translationID: String, bookCode: String, bookName: String, chapter: Int) async -> OnlineOutcome {
        if let cached = await cache.get(kind, translation: translationID, book: bookCode, chapter: chapter) {
            return .verses(cached.verses.map { BibleVerse(number: $0.n, text: $0.t) }, attribution: cached.attribution, origin: .cached(cached.fetchedAt))
        }
        guard let key = keyReader(kind), !key.isEmpty else { return .failure(OnlineError.missingKey.localizedDescription) }
        do {
            let fetched = try await provider(kind).fetchChapter(translationID: translationID, bookCode: bookCode,
                                                                bookName: bookName, chapter: chapter, apiKey: key)
            await cache.put(fetched, provider: kind, translation: translationID, book: bookCode, number: chapter)
            return .verses(fetched.verses.map { BibleVerse(number: $0.n, text: $0.t) }, attribution: fetched.attribution, origin: .live)
        } catch {
            return .failure((error as? OnlineError)?.localizedDescription ?? error.localizedDescription)
        }
    }
}
