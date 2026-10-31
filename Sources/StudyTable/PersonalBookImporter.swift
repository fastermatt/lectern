import Foundation

/// Personal files stay on this Mac. The text reader does not bypass DRM or load web assets.
enum PersonalBookImporter {
    static func read(_ url: URL) throws -> ResourceBook {
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max
        guard size <= BibleArchive.maximumArchive else { throw ResourceBookError.invalid("Choose a book smaller than 30 MB.") }
        let data = try Data(contentsOf: url)
        var title = url.deletingPathExtension().lastPathComponent
        var author = "Personal import"
        var articles: [ResourceArticle] = []
        if url.pathExtension.lowercased() == "txt" {
            guard let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                throw ResourceBookError.invalid("Choose a nonempty UTF-8 text file.")
            }
            // Bounded sections keep large books usable in the native text reader.
            var start = text.startIndex, index = 1
            while start < text.endIndex {
                let end = text.index(start, offsetBy: 12000, limitedBy: text.endIndex) ?? text.endIndex
                articles.append(ResourceArticle(id: "part-\(index)", title: "Part \(index)", body: String(text[start..<end]), anchor: nil))
                start = end; index += 1
            }
        } else if url.pathExtension.lowercased() == "epub" {
            let members = try BibleArchive.members(data, extensions: nil, minimum: 1, memberLimit: ResourceBookFiles.memberLimit)
            let index = Dictionary(uniqueKeysWithValues: members.map { ($0.name, $0) })
            guard index["META-INF/encryption.xml"] == nil else {
                throw ResourceBookError.invalid("This EPUB declares encrypted content. Import an unencrypted edition from the publisher; Thruline does not remove DRM.")
            }
            // Parse a private immutable copy so selecting a file cannot race validation vs unzip.
            let copy = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
            try data.write(to: copy); defer { try? FileManager.default.removeItem(at: copy) }
            func member(_ name: String) throws -> Data {
                guard let entry = index[name] else { throw ResourceBookError.invalid("The EPUB is missing a required file.") }
                return try BibleArchive.unpackMember(entry, archive: copy, memberLimit: ResourceBookFiles.memberLimit)
            }
            let container = EPUBMetadata(); try BookXML.parse(member("META-INF/container.xml"), delegate: container)
            guard let root = container.root, !root.hasPrefix("/"), !root.split(separator: "/").contains("..") else { throw ResourceBookError.invalid("Unsupported EPUB container.") }
            let metadata = EPUBMetadata(); try BookXML.parse(member(root), delegate: metadata)
            if !metadata.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { title = metadata.title.trimmingCharacters(in: .whitespacesAndNewlines) }
            if !metadata.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { author = metadata.author.trimmingCharacters(in: .whitespacesAndNewlines) }
            for (number, id) in metadata.spine.enumerated() {
                try Task.checkCancellation()
                guard let href = metadata.manifest[id], let path = resolve(href, relativeTo: root) else { throw ResourceBookError.invalid("The EPUB reading order contains an unsupported path.") }
                let text = EPUBText(); try BookXML.parse(member(path), delegate: text)
                if !text.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    articles.append(ResourceArticle(id: "spine-\(number)", title: text.heading.isEmpty ? "Section \(number + 1)" : text.heading,
                                                    body: text.body.trimmingCharacters(in: .whitespacesAndNewlines), anchor: nil))
                }
            }
            guard !articles.isEmpty else { throw ResourceBookError.invalid("No readable XHTML chapters were found in this EPUB.") }
        } else { throw ResourceBookError.invalid("Choose an unencrypted EPUB or UTF-8 .txt file.") }
        return ResourceBook(id: UUID().uuidString, title: title, author: author,
            attribution: "Personal copy imported from \(url.lastPathComponent). Copyright remains with the rights holder. Text-only rendering; original pagination, images and styling are not retained. This file is not shared by Thruline.", source: nil, articles: articles)
    }
    static func resolve(_ href: String, relativeTo root: String) -> String? {
        guard let decoded = href.components(separatedBy: "#").first?.removingPercentEncoding,
              !decoded.hasPrefix("/"), !decoded.contains(":"), !decoded.contains("\\"), !decoded.contains("\0") else { return nil }
        var parts = root.split(separator: "/").dropLast().map(String.init)
        for part in decoded.split(separator: "/").map(String.init) {
            if part == ".." { guard !parts.isEmpty else { return nil }; parts.removeLast() }
            else if part != "." { parts.append(part) }
        }
        return parts.joined(separator: "/")
    }
}

private final class EPUBMetadata: NSObject, XMLParserDelegate {
    var root: String?
    var title = "", author = ""
    var manifest: [String: String] = [:]
    var spine: [String] = []
    private var field = ""
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if local == "rootfile", root == nil { root = attributes["full-path"] }
        if local == "item", let id = attributes["id"], let href = attributes["href"], attributes["media-type"] == "application/xhtml+xml" { manifest[id] = href }
        if local == "itemref", attributes["linear"] != "no", let id = attributes["idref"] { spine.append(id) }
        if ["title", "creator"].contains(local) { field = local }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        if field == "title" { title += string }; if field == "creator" { author += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        if elementName.split(separator: ":").last.map(String.init) == field { field = "" }
    }
}
private final class EPUBText: NSObject, XMLParserDelegate {
    var body = "", heading = ""
    private var inside = false, inHeading = false
    private var skip = 0
    /// Text of a footnote reference link while it is being read; written out as "[n]".
    private var noteText: String?
    private var noteDepth = 0
    private var lastWasSpace = true
    /// HTML whitespace is insignificant: runs collapse to one space; <br> and blocks break lines.
    private func append(_ text: String) {
        for character in text {
            if character.isWhitespace {
                if !lastWasSpace { body.append(" "); lastWasSpace = true }
            } else { body.append(character); lastWasSpace = false }
        }
    }
    private func breakLine(_ marker: String) {
        while body.hasSuffix(" ") { body.removeLast() }
        body += marker; lastWasSpace = true
    }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes: [String: String]) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if name == "body" { inside = true }
        if skip > 0 || ["script", "style", "svg", "nav"].contains(name) { skip += 1 }
        if skip == 0, ["h1", "h2", "h3", "h4"].contains(name), heading.isEmpty { inHeading = true }
        if inside, skip == 0, name == "br" { breakLine("\n") }
        if noteText != nil { noteDepth += 1 }
        else if name == "a", let href = attributes["href"], let fragment = href.split(separator: "#").last.map({ $0.lowercased() }),
                href.contains("#"), ["note", "fn", "foot"].contains(where: { fragment.contains($0) }) {
            noteText = ""; noteDepth = 0
        }
    }
    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard inside, skip == 0 else { return }
        if noteText != nil { noteText! += string; return }
        append(string)
        if inHeading { heading += string }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        let name = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if skip > 0 { skip -= 1; return }
        if let note = noteText {
            if noteDepth > 0 { noteDepth -= 1; return }
            noteText = nil
            let digits = note.filter(\.isNumber)
            if !digits.isEmpty, digits.count <= 4, note.trimmingCharacters(in: CharacterSet(charactersIn: "[]().* ").union(.whitespacesAndNewlines)).allSatisfy(\.isNumber) {
                body += "[\(digits)]"; lastWasSpace = false
            } else { append(note) }
            return
        }
        if ["h1", "h2", "h3", "h4"].contains(name), inHeading {
            inHeading = false
            heading = heading.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        if inside, name == "dt" { append(" ") }
        if inside, ["p", "div", "li", "h1", "h2", "h3", "h4", "tr", "dd", "blockquote"].contains(name) { breakLine("\n\n") }
        if name == "body" { inside = false }
    }
}
