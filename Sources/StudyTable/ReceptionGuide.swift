import Foundation

/// Editorial comparisons, not quotations or automated verdicts about imported books.
/// Each claim is limited to the named work/authority. Later origin alone is not a condemnation.
struct ReceptionTopic: Identifiable, Sendable {
    enum Kind: String, Sendable { case later = "Later framework", conflict = "Doctrinal conflict", refuted = "Early refutation", council = "Council judgment" }
    let id: String
    let title: String
    let period: String
    let kind: Kind
    let summary: String
    let comparison: String
    let limit: String
    let sources: [ProfileSource]

    static let topics: [Self] = [
        .init(id: "jung", title: "Jung: God’s goodness and Christ’s atonement", period: "20th century", kind: .conflict,
              summary: "In Answer to Job (Collected Works 11, §661), Jung favors understanding the atonement as God making reparation for a wrong done to humanity. In §662, he rejects belief in God as the supreme good. These claims are heterodox relative to the historic Christian teaching that God is wholly good and Christ died for our sins.",
              comparison: "The doctrinal conflict is specific: 1 John 1:5 affirms God’s goodness without darkness; 1 Corinthians 15:3 and Romans 5:8 identify human sin and God’s saving love in Christ’s death. The objection is to attributing wrongdoing to God and making the cross its reparation, not to differences among Christian explanations of the atonement.",
              limit: "No early council ruled on Jung; a modern claim can contradict Christian doctrine without an ancient council naming its author. This is a sourced editorial comparison of these claims, not a verdict on every psychological technique or every reader of Jung. His language about a God-image alone does not establish denial of God’s existence. The book is not bundled; its publisher link identifies the edition.",
              sources: [.init(title: "Jung — Answer to Job, CW 11, §§661–662; R. F. C. Hull translation (publisher / edition)", url: URL(string: "https://press.princeton.edu/books/paperback/9780691150475/answer-to-job")),
                        .init(title: "1 John 1:5 — God is light, without darkness", url: URL(string: "https://ebible.org/eng-kjv/1JN01.htm")),
                        .init(title: "1 Corinthians 15:3 — Christ died for our sins", url: URL(string: "https://ebible.org/eng-kjv/1CO15.htm")),
                        .init(title: "Romans 5:8 — God’s love in Christ’s death for us", url: URL(string: "https://ebible.org/eng-kjv/ROM05.htm"))]),
        .init(id: "docetism", title: "Christ only appeared to suffer", period: "Early 2nd-century response", kind: .refuted,
              summary: "Ignatius explicitly rejects the claim that Christ’s suffering was only an appearance. In Smyrnaeans 1–3 he insists on real flesh, suffering and resurrection.",
              comparison: "His argument is evidence of an early Christian rejection of this teaching. It does not mean that no ancient person held it; the letter exists precisely because the claim was being made.",
              limit: "An author’s refutation is identified as such, not relabeled as an ecumenical council judgment.",
              sources: [.init(title: "Ignatius — Epistle to the Smyrnaeans, chapters 1–4", url: URL(string: "https://www.newadvent.org/fathers/0109.htm"))]),
        .init(id: "valentinian", title: "Valentinian reinterpretations of Scripture", period: "2nd century", kind: .refuted,
              summary: "Irenaeus disputes the Valentinian use of biblical language to support a different account of divine beings. Against Heresies I.9–10 contrasts that reading with the faith he says the churches received.",
              comparison: "His stated rule of faith names one creator God and the incarnate Christ. Cite the particular teaching and his response rather than treating every symbolic reading as Gnostic.",
              limit: "Valentinian teaching predates Nicaea. Do not invent a council condemnation of Valentinus by name or equate Jung’s whole system with this ancient movement.",
              sources: [.init(title: "Irenaeus — Against Heresies I.9", url: URL(string: "https://www.newadvent.org/fathers/0103109.htm")),
                        .init(title: "Irenaeus — Against Heresies I.10", url: URL(string: "https://www.newadvent.org/fathers/0103110.htm"))]),
        .init(id: "nicaea", title: "The Son as a creature", period: "Nicaea, AD 325", kind: .council,
              summary: "The creed and anathemas of Nicaea reject the claim that the Son began to exist or is a creature, and affirm his shared divine substance with the Father.",
              comparison: "This is a specific, documented council judgment against a teaching associated with Arius, not merely a later denominational preference.",
              limit: "The profile of Arius is available for historical context. A profile does not imply that his complete writings are included offline.",
              sources: [.init(title: "First Council of Nicaea — creed and anathemas (325)", url: URL(string: "https://www.newadvent.org/fathers/3801.htm"))])
    ]
}

enum PatristicReader {
    static func load(url: URL? = AppResources.url("Reference/apostolic-fathers.json")) throws -> ResourceBook {
        guard let url else { throw ResourceBookError.invalid("The Apostolic Fathers reader is missing from this installation.") }
        let book = try JSONDecoder().decode(ResourceBook.self, from: Data(contentsOf: url))
        guard !book.articles.isEmpty, Set(book.articles.map(\.id)).count == book.articles.count else {
            throw ResourceBookError.invalid("The Apostolic Fathers reader could not be verified.")
        }
        return book
    }
}

extension FatherProfile {
    var receptionLabel: String {
        if let judgment = conciliarJudgment { return "Judgment: " + judgment.label }
        if controversies != nil { return "Reception note — read context" }
        return "Historical profile"
    }
}
