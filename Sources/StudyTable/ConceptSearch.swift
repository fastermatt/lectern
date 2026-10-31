import Foundation

/// Concept search: older texts rarely use modern terms. Augustine never writes "rapture";
/// he writes "caught up" and "meet the Lord in the air". Each group lists wording a reader
/// would recognise as the same idea, used only to widen a search — never as a claim that
/// two writers meant the same thing. Curated by hand; expand with care.
enum ConceptVocabulary {
    struct Group: Sendable { let name: String; let terms: [String] }

    static let groups: [Group] = [
        .init(name: "Rapture", terms: ["rapture", "caught up", "meet the Lord in the air", "taken up", "translation of the saints", "gathered together unto him"]),
        .init(name: "Millennium", terms: ["millennium", "thousand years", "chiliasm", "chiliast", "chiliasts", "millenarian", "millenarians", "millennial", "kingdom of a thousand years"]),
        .init(name: "Antichrist", terms: ["antichrist", "man of sin", "son of perdition", "lawless one", "the beast", "abomination of desolation"]),
        .init(name: "Tribulation", terms: ["tribulation", "great tribulation", "last persecution", "final persecution", "time of trouble"]),
        .init(name: "Second coming", terms: ["second coming", "second advent", "coming of the Lord", "his appearing", "parousia", "day of the Lord", "return of Christ"]),
        .init(name: "Resurrection", terms: ["resurrection", "rising again", "raised from the dead", "first resurrection", "resurrection of the body", "resurrection of the flesh"]),
        .init(name: "Last judgment", terms: ["last judgment", "day of judgment", "judgment seat", "final judgment", "general judgment"]),
        .init(name: "Israel and the church", terms: ["Israel of God", "true Israel", "spiritual Israel", "Israel according to the flesh", "people of God", "new covenant", "Jews and Gentiles"]),
        .init(name: "Seventy weeks", terms: ["seventy weeks", "seventy hebdomads", "the last week", "weeks of Daniel"]),
        .init(name: "Heaven", terms: ["heaven", "paradise", "kingdom of heaven", "heavenly Jerusalem", "beatific vision"]),
        .init(name: "Hell", terms: ["hell", "Gehenna", "eternal fire", "everlasting punishment", "outer darkness", "lake of fire"]),
        .init(name: "Trinity", terms: ["Trinity", "three persons", "Godhead", "one substance", "consubstantial", "Father, Son and Holy Spirit"]),
        .init(name: "Holy Spirit", terms: ["Holy Spirit", "Holy Ghost", "Paraclete", "Spirit of God", "Comforter"]),
        .init(name: "Incarnation", terms: ["incarnation", "Word made flesh", "took flesh", "became man", "assumed our nature"]),
        .init(name: "Atonement", terms: ["atonement", "propitiation", "ransom", "satisfaction", "expiation", "reconciliation", "blood of Christ"]),
        .init(name: "Justification", terms: ["justification", "justified", "imputed righteousness", "righteousness of faith", "declared righteous"]),
        .init(name: "Grace", terms: ["grace", "unmerited favour", "unmerited favor", "free gift", "prevenient grace"]),
        .init(name: "Predestination", terms: ["predestination", "predestinated", "election", "the elect", "foreknowledge", "chosen before the foundation"]),
        .init(name: "Free will", terms: ["free will", "freedom of the will", "free choice", "liberty of the will"]),
        .init(name: "Baptism", terms: ["baptism", "baptized", "laver of regeneration", "washing of regeneration", "font"]),
        .init(name: "Lord's Supper", terms: ["Lord's Supper", "Eucharist", "communion", "breaking of bread", "the oblation", "sacrament of the altar", "body and blood"]),
        .init(name: "Church", terms: ["church", "catholic church", "body of Christ", "bride of Christ", "communion of saints", "congregation"]),
        .init(name: "Bishops and elders", terms: ["bishop", "bishops", "presbyter", "presbyters", "elder", "elders", "overseer", "deacon"]),
        .init(name: "Scripture", terms: ["Scripture", "Scriptures", "divine oracles", "holy writ", "the sacred writings", "word of God"]),
        .init(name: "Prayer", terms: ["prayer", "supplication", "intercession", "praying"]),
        .init(name: "Repentance", terms: ["repentance", "penitence", "penance", "contrition", "confession of sins"]),
        .init(name: "Satan", terms: ["Satan", "the devil", "the adversary", "the evil one", "the serpent", "prince of this world"]),
        .init(name: "Martyrdom", terms: ["martyr", "martyrs", "martyrdom", "suffered for Christ", "witness unto death"]),
        .init(name: "Heresy and schism", terms: ["heresy", "heresies", "heretic", "heretics", "schism", "schismatics"]),
        .init(name: "Mary", terms: ["Mary", "the Virgin", "Mother of God", "Theotokos", "mother of the Lord"]),
        .init(name: "Providence", terms: ["providence", "divine providence", "fortune", "the counsel of God", "sovereignty of God"]),
        .init(name: "Suffering", terms: ["suffering", "affliction", "afflictions", "trials", "adversity", "chastening"])
    ]

    private static let index: [String: Group] = {
        var out: [String: Group] = [:]
        for group in groups { for term in group.terms + [group.name] { out[normalize(term)] = out[normalize(term)] ?? group } }
        return out
    }()

    static func normalize(_ text: String) -> String {
        text.lowercased().replacingOccurrences(of: "’", with: "'").split(whereSeparator: \.isWhitespace).joined(separator: " ")
    }

    static func group(for term: String) -> Group? { index[normalize(term)] }
}

/// Turns what a reader types into an FTS5 expression: quoted phrases stay together, every
/// word must appear, and a word or phrase that names a concept also matches its other wordings.
struct SearchPlan: Sendable {
    let expression: String
    /// The concept groups used, so the interface can say "also searched: caught up, …".
    let concepts: [ConceptVocabulary.Group]
    let terms: [String]
    /// The whole query, when more than one word, for listing exact-phrase matches first.
    let phrase: String?

    static func make(_ query: String, concepts useConcepts: Bool = true) -> SearchPlan? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        var terms = TextMatch.terms(trimmed)
        // A whole query that names a concept ("second coming", "man of sin") is one concept, not separate words.
        if useConcepts, terms.count > 1, !trimmed.contains("\""), ConceptVocabulary.group(for: trimmed) != nil {
            terms = [ConceptVocabulary.normalize(trimmed)]
        }
        guard !terms.isEmpty else { return nil }
        var parts: [String] = [], used: [ConceptVocabulary.Group] = []
        for term in terms {
            var alternatives = [term]
            if useConcepts, let group = ConceptVocabulary.group(for: term) {
                alternatives += group.terms.map { $0.lowercased() }
                if !used.contains(where: { $0.name == group.name }) { used.append(group) }
            }
            var seen = Set<String>()
            let quoted = alternatives.filter { seen.insert(ConceptVocabulary.normalize($0)).inserted }.map(Self.literal)
            parts.append(quoted.count == 1 ? quoted[0] : "(" + quoted.joined(separator: " OR ") + ")")
        }
        let phrase = terms.count > 1 ? terms.joined(separator: " ") : (terms[0].contains(" ") ? terms[0] : nil)
        return SearchPlan(expression: parts.joined(separator: " AND "), concepts: used, terms: terms, phrase: phrase)
    }

    /// An FTS5 string: punctuation is kept inside quotes so it can never become query syntax.
    static func literal(_ text: String) -> String {
        let cleaned = text.replacingOccurrences(of: "\"", with: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return "\"" + cleaned + "\""
    }

    /// Words to highlight in results: the typed terms plus each concept's alternate wording.
    var highlightTerms: [String] {
        var out = terms
        for group in concepts { for term in group.terms where !out.contains(term.lowercased()) { out.append(term.lowercased()) } }
        return out
    }
}
