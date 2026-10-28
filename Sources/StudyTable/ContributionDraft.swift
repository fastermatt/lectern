import Foundation

/// Only user-entered fields. Does not read notes, accounts, device details or API keys.
struct ContributionDraft: Codable, Equatable {
    enum Kind: String, CaseIterable, Codable {
        case correction = "text-correction", resource = "resource-suggestion", translation, usability
        var title: String {
            switch self { case .correction: "Correct a text or reference"; case .resource: "Suggest a resource"; case .translation: "Help with a language"; case .usability: "Report a usability problem" }
        }
    }
    var schemaVersion = 1
    var kind = Kind.correction
    var title = ""
    var resource = ""
    var reference = ""
    var language = ""
    var details = ""
    var sourceURL = ""

    var validationMessage: String? {
        if schemaVersion != 1 { return "This draft uses an unsupported format version." }
        if title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || details.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return "Add a title and describe your suggestion before exporting." }
        if [title, resource, reference, language, sourceURL].contains(where: { $0.unicodeScalars.count > 1000 }) || details.unicodeScalars.count > 20000 { return "Keep each short field under 1,000 characters and the description under 20,000." }
        if !sourceURL.isEmpty {
            guard let url = URLComponents(string: sourceURL), url.scheme == "https", let host = url.host, !host.isEmpty,
                  url.user == nil, url.password == nil, !sourceURL.contains(where: \.isWhitespace), !sourceURL.unicodeScalars.contains(where: { $0.value < 32 }) else { return "Use an HTTPS source link without a username or password, or leave it blank." }
        }
        return nil
    }
    func encoded() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(self)
    }
}
