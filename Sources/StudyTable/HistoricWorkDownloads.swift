import Foundation
import CryptoKit
import SwiftUI

/// Optional public-domain Church Fathers, early church sources and classic Christian works
/// from Project Gutenberg. Downloads are explicit and converted on this Mac into the same
/// text-only `ResourceBook` format as Tyndale resources and personal imports.
///
/// Gutenberg regenerates its ebook files over time, so a byte checksum cannot be pinned the
/// way Tyndale archives are. Instead: one HTTPS host, size limits, the existing safe EPUB
/// reader, and an exact match against the expected title. The installed file's SHA-256 is
/// recorded in the book's attribution for provenance.
struct HistoricWork: Identifiable, Hashable, Sendable {
    enum Shelf: String, CaseIterable, Sendable {
        case fathers = "Church Fathers"
        case history = "Early and medieval church sources"
        case classics = "Classic Christian works"
    }
    let ebook: Int
    let title: String
    let author: String
    /// Translator and original edition, as identified by Project Gutenberg.
    let edition: String
    let shelf: Shelf
    let detail: String
    /// The dc:title the downloaded EPUB must carry (case-insensitive prefix).
    let expectedTitle: String
    /// Exact name of the sourced profile in Fathers & reception, when one exists.
    var profile: String? = nil

    var id: String { "pg-\(ebook)" }
    var url: URL { URL(string: "https://www.gutenberg.org/cache/epub/\(ebook)/pg\(ebook).epub")! }
    var page: URL { URL(string: "https://www.gutenberg.org/ebooks/\(ebook)")! }
    static let host = "www.gutenberg.org"

    static let catalog: [Self] = [
        .init(ebook: 3296, title: "The Confessions", author: "Augustine of Hippo",
              edition: "Translated by E. B. Pusey (Oxford, 1838)", shelf: .fathers,
              detail: "Augustine’s account of his life, conversion and prayer, thirteen books.",
              expectedTitle: "The Confessions of St. Augustine", profile: "Augustine of Hippo"),
        .init(ebook: 45304, title: "The City of God, Volume I", author: "Augustine of Hippo",
              edition: "Translated by Marcus Dods (T&T Clark, 1871)", shelf: .fathers,
              detail: "Books I–XIII: the two cities, Rome’s fall and the critique of pagan religion.",
              expectedTitle: "The City of God, Volume I", profile: "Augustine of Hippo"),
        .init(ebook: 45305, title: "The City of God, Volume II", author: "Augustine of Hippo",
              edition: "Translated by Marcus Dods (T&T Clark, 1871)", shelf: .fathers,
              detail: "Books XIV–XXII: the origin, course and ends of the two cities.",
              expectedTitle: "The City of God, Volume II", profile: "Augustine of Hippo"),
        .init(ebook: 45843, title: "Writings in Connection with the Donatist Controversy", author: "Augustine of Hippo",
              edition: "Translated by J. R. King, ed. Marcus Dods (T&T Clark, 1872)", shelf: .fathers,
              detail: "On baptism, against the Donatists, and related treatises on the church and sacraments.",
              expectedTitle: "Writings in Connection with the Donatist Controversy", profile: "Augustine of Hippo"),
        .init(ebook: 58783, title: "The Letters of S. Ambrose, Bishop of Milan", author: "Ambrose of Milan",
              edition: "Library of the Fathers (Oxford, 1881)", shelf: .fathers,
              detail: "Ambrose’s letters on doctrine, Scripture, church and empire.",
              expectedTitle: "The Letters of S. Ambrose", profile: "Ambrose of Milan"),
        .init(ebook: 62447, title: "Leaves from St. John Chrysostom", author: "John Chrysostom",
              edition: "Selected and translated by Mary H. Allies (1889)", shelf: .fathers,
              detail: "Selected passages from Chrysostom’s homilies on Scripture. An anthology, not complete homilies.",
              expectedTitle: "Leaves from St. John Chrysostom", profile: "John Chrysostom"),
        .init(ebook: 70561, title: "The Writings of Origen, Volume I", author: "Origen of Alexandria",
              edition: "Ante-Nicene Christian Library, translated by Frederick Crombie (T&T Clark, 1869)", shelf: .fathers,
              detail: "De Principiis, letters and related writings. Origen’s reception is contested; read his sourced profile.",
              expectedTitle: "The writings of Origen, Vol. 1", profile: "Origen of Alexandria"),
        .init(ebook: 70693, title: "The Writings of Origen, Volume II", author: "Origen of Alexandria",
              edition: "Ante-Nicene Christian Library, translated by Frederick Crombie (T&T Clark, 1872)", shelf: .fathers,
              detail: "Against Celsus, his reply to a second-century pagan critic of Christianity.",
              expectedTitle: "The writings of Origen, Vol. 2", profile: "Origen of Alexandria"),
        .init(ebook: 65478, title: "Refutation of All Heresies, Volume I", author: "Hippolytus of Rome (attributed)",
              edition: "Philosophumena, translated by F. Legge (SPCK, 1921)", shelf: .fathers,
              detail: "A third-century survey of Greek philosophy and Gnostic systems. Once attributed to Origen; authorship is still discussed.",
              expectedTitle: "Philosophumena; or, The refutation of all heresies, Volume I", profile: "Hippolytus of Rome"),
        .init(ebook: 67116, title: "Refutation of All Heresies, Volume II", author: "Hippolytus of Rome (attributed)",
              edition: "Philosophumena, translated by F. Legge (SPCK, 1921)", shelf: .fathers,
              detail: "Books on later heresies and the author’s own statement of faith.",
              expectedTitle: "Philosophumena; or, The refutation of all heresies, Volume II", profile: "Hippolytus of Rome"),
        .init(ebook: 61614, title: "The Apostolic Tradition", author: "Hippolytus of Rome (attributed)",
              edition: "Translated with introduction and notes by Burton Scott Easton (1934)", shelf: .fathers,
              detail: "An early church order on ordination, baptism and worship. Its date, authorship and layers are debated; read Easton’s introduction.",
              expectedTitle: "The Apostolic Tradition of Hippolytus", profile: "Hippolytus of Rome"),
        .init(ebook: 24979, title: "A Source Book for Ancient Church History", author: "Joseph Cullen Ayer",
              edition: "Charles Scribner’s Sons, 1913", shelf: .history,
              detail: "Translated primary sources from the apostolic age to the end of the conciliar period, with short editorial introductions.",
              expectedTitle: "A Source Book for Ancient Church History"),
        .init(ebook: 38326, title: "Ecclesiastical History of the English Nation", author: "Bede",
              edition: "Translated by A. M. Sellar (1907)", shelf: .history,
              detail: "Bede’s eighth-century history of Christianity in Britain.",
              expectedTitle: "Bede's Ecclesiastical History of England", profile: "Bede"),
        .init(ebook: 14328, title: "The Consolation of Philosophy", author: "Boethius",
              edition: "Translated by H. R. James (1897)", shelf: .history,
              detail: "A sixth-century dialogue on providence, fortune and the highest good, widely read through the Middle Ages.",
              expectedTitle: "The Consolation of Philosophy"),
        .init(ebook: 45001, title: "Institutes of the Christian Religion, Volume I", author: "John Calvin",
              edition: "Translated by John Allen (1813; 1844 American edition)", shelf: .classics,
              detail: "Books I–II: the knowledge of God the Creator and the Redeemer.",
              expectedTitle: "Institutes of the Christian Religion (Vol. 1"),
        .init(ebook: 64392, title: "Institutes of the Christian Religion, Volume II", author: "John Calvin",
              edition: "Translated by John Allen (1813; 1844 American edition)", shelf: .classics,
              detail: "Books III–IV: receiving grace in Christ, and the church and sacraments.",
              expectedTitle: "Institutes of the Christian Religion (Vol. 2"),
        .init(ebook: 1653, title: "The Imitation of Christ", author: "Thomas à Kempis",
              edition: "Translated by William Benham (1874)", shelf: .classics,
              detail: "A fifteenth-century devotional classic in four books.",
              expectedTitle: "The Imitation of Christ")
    ]
    static func works(on shelf: Shelf) -> [Self] { catalog.filter { $0.shelf == shelf } }
}

private final class HistoricWorkRedirectPolicy: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping @Sendable (URLRequest?) -> Void) {
        completionHandler(request.url?.scheme == "https" && request.url?.host == HistoricWork.host ? request : nil)
    }
}

enum HistoricWorkFiles {
    static func fetch(_ work: HistoricWork) async throws -> Data {
        guard HistoricWork.catalog.contains(work), work.url.scheme == "https", work.url.host == HistoricWork.host else {
            throw ResourceBookError.invalid("This work is not in the trusted catalogue.")
        }
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 45; config.timeoutIntervalForResource = 180
        let session = URLSession(configuration: config, delegate: HistoricWorkRedirectPolicy(), delegateQueue: nil)
        defer { session.invalidateAndCancel() }
        let (bytes, response) = try await session.bytes(from: work.url)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.url?.scheme == "https", response.url?.host == HistoricWork.host,
              response.expectedContentLength <= BibleArchive.maximumArchive else {
            throw ResourceBookError.invalid("Project Gutenberg is unavailable right now. Please try again later.")
        }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < BibleArchive.maximumArchive else { throw ResourceBookError.invalid("The download exceeded its size limit.") }
            data.append(byte)
        }
        return data
    }

    /// Converts with the same safe EPUB reader used for personal imports, then verifies identity.
    static func convert(_ work: HistoricWork, data: Data, temporary: URL) throws -> ResourceBook {
        guard temporary.pathExtension == "epub" else { throw ResourceBookError.invalid("Unsupported temporary file.") }
        try data.write(to: temporary)
        var book = try PersonalBookImporter.read(temporary)
        guard book.title.lowercased().hasPrefix(work.expectedTitle.lowercased()) else {
            throw ResourceBookError.invalid("The downloaded file did not match \(work.title). Nothing was installed.")
        }
        guard book.articles.count >= 2 else { throw ResourceBookError.invalid("\(work.title) did not contain readable chapters. Nothing was installed.") }
        let checksum = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        book.id = work.id
        book.title = work.title
        book.author = work.author
        book.source = work.page.absoluteString
        book.attribution = "\(work.title) — \(work.author). \(work.edition). Project Gutenberg eBook #\(work.ebook), \(work.page.absoluteString). Public domain in the USA; check the laws of your country before redistributing. Downloaded from Project Gutenberg and converted on this Mac to plain text: original layout, footnote formatting and images are not reproduced. Project Gutenberg’s own notice is retained in the text. Inclusion does not mean doctrinal endorsement. Installed file SHA-256: \(checksum)."
        return book
    }
}

extension ResourceBookLibrary {
    func install(_ work: HistoricWork) {
        installBook(id: work.id, title: work.title, temporaryExtension: "epub",
                    fetch: { try await HistoricWorkFiles.fetch(work) },
                    convert: { try HistoricWorkFiles.convert(work, data: $0, temporary: $1) })
    }
}

/// One optional historic work: add, progress, or read once installed, with its reading labels.
struct HistoricWorkRow: View {
    @ObservedObject var books: ResourceBookLibrary
    let work: HistoricWork
    let read: (ResourceBook) -> Void
    var showProfile: ((FatherProfile) -> Void)? = nil
    @State private var notesOpen = false

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(work.title).font(.headline)
                if let labels = WorkLabels.of(work.id) { WorkBadge(text: labels.badge) }
            }
            Text("\(work.author) · \(work.edition)").font(.caption).foregroundStyle(STColor.secondary)
            if let labels = WorkLabels.of(work.id) {
                Text([labels.era, labels.genre, labels.level].joined(separator: " · ")).font(.caption).foregroundStyle(STColor.secondary)
                Text(labels.whyRead).font(.callout)
            } else { Text(work.detail).font(.callout) }
            HStack {
                if let installed = books.books.first(where: { $0.id == work.id }) {
                    Label("Installed", systemImage: "checkmark.circle")
                    Button("Read") { read(installed) }.help("Open this book in the reader")
                } else if books.activeID == work.id {
                    ProgressView().controlSize(.small)
                    Text("Downloading & preparing…")
                    Button("Cancel") { books.cancel() }
                } else {
                    Button("Add to library") { books.install(work) }.disabled(books.activeID != nil)
                        .help("Download once from Project Gutenberg, then read, search and link offline")
                        .accessibilityLabel("Add \(work.title) to library")
                }
                if let name = work.profile, let showProfile, let profile = FatherProfileStore.shared.profile(forAuthor: name) {
                    Button("Author profile") { showProfile(profile) }.help("Dates, school and how later councils and traditions received this author")
                }
                Spacer()
                Link("Edition · Project Gutenberg", destination: work.page)
            }.font(.callout)
            if let labels = WorkLabels.of(work.id) { WorkReadingNotes(labels: labels, expanded: $notesOpen) }
        }.padding(.vertical, 8)
    }
}

/// A small text badge; meaning is in the words, not the colour.
struct WorkBadge: View {
    let text: String
    var body: some View {
        Text(text).font(.system(size: 10.5, weight: .semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .foregroundStyle(STColor.navy)
            .background(STColor.navy.opacity(0.10), in: Capsule())
            .overlay(Capsule().stroke(STColor.navy.opacity(0.25), lineWidth: 0.5))
            .accessibilityLabel("Label: \(text)")
    }
}

/// Cautions, last-things notes and sources from the review team.
struct WorkReadingNotes: View {
    let labels: WorkLabels
    @Binding var expanded: Bool
    var body: some View {
        DisclosureGroup("Reading notes", isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 8) {
                if let last = labels.lastThings {
                    Label { Text(last) } icon: { Image(systemName: "hourglass") }.font(.callout)
                }
                ForEach(labels.cautions, id: \.self) { caution in
                    Label { Text(caution) } icon: { Image(systemName: "info.circle") }.font(.callout).foregroundStyle(STColor.secondary)
                }
                Text("Topics: " + labels.topics.joined(separator: ", ")).font(.caption).foregroundStyle(STColor.secondary)
                HStack(spacing: 12) {
                    ForEach(labels.sources, id: \.self) { source in
                        if let url = URL(string: source), let host = url.host { Link(host.replacingOccurrences(of: "www.", with: ""), destination: url).font(.caption) }
                    }
                }
                Text("Descriptive labels from a historian, theologian and ecumenical editor review (2026-10-31); not verdicts.").font(.caption2).foregroundStyle(STColor.secondary)
            }.padding(.top, 6).textSelection(.enabled)
        }.font(.callout).tint(STColor.ink)
        .help("Authorship, reception and translation notes, with sources")
    }
}

/// Topic chips: selection is shown with a checkmark as well as tint.
struct TopicChips: View {
    let topics: [String]
    @Binding var selected: String?
    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                chip(nil, "All")
                ForEach(topics, id: \.self) { chip($0, $0) }
            }.padding(.vertical, 2)
        }
    }
    private func chip(_ value: String?, _ title: String) -> some View {
        let on = selected == value
        return Button { selected = value } label: {
            HStack(spacing: 4) {
                if on { Image(systemName: "checkmark").font(.system(size: 9, weight: .bold)) }
                Text(title)
            }.font(.system(size: 12, weight: on ? .semibold : .regular))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .foregroundStyle(on ? STColor.navy : STColor.ink)
            .background(on ? STColor.navy.opacity(0.12) : STColor.tileWell, in: Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(on ? .isSelected : [])
        .help(value == nil ? "Show every work" : "Show works that speak to \(title.lowercased())")
    }
}
