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
        .init(id: "dispensational-rapture", title: "A pre-tribulation rapture and a separate destiny for Israel and the church", period: "19th-century framework (J. N. Darby, c. 1830)", kind: .later,
              summary: "Second-century writers such as Papias, Justin (Dialogue 80–81), Irenaeus (Against Heresies V.32–36) and Tertullian did expect a thousand-year reign after the resurrection — early chiliasm is real, and Justin says other orthodox Christians disagreed. None of these sources describes the church being removed before a tribulation, or two peoples with permanently separate programs. Those distinctives are usually traced to J. N. Darby.",
              comparison: "Read in your library: Ayer's Source Book, Period II §10 'Chiliastic Expectations' (Papias, Irenaeus V.33, Justin 80–81) and §47 (Dionysius against Nepos); Barnabas 15–16 and Hermas, Vision IV ('the great tribulation that is coming', which believers endure); City of God XX.6–9 (the thousand years as the church's present reign), XX.13, 19, 23 (the church passes through Antichrist's persecution) and XX.29 (a future turning of the Jews); Origen, De Principiis II.11; Calvin, Institutes III.25.5 and IV.16.14–15. On Israel and the church: Barnabas 4, 9, 13–14 (covenant language Ayer calls extreme), Ignatius, Magnesians 8–10, Origen, De Principiis IV.1.21–22.",
              limit: "Pastors will meet Pseudo-Ephraem's sermon ('gathered before the tribulation'): its date is disputed (proposals range from the 4th to the 7th century; earliest manuscript 8th century), and scholars such as Gundry contest the pre-tribulation reading while Ice and Demy defend it. Irenaeus V.29.1 ('the Church shall be suddenly caught up') is also debated. This comparison concerns specific distinctives, not the faith of dispensational Christians, and no council has ruled on them. Later origin alone is not a condemnation.",
              sources: [.init(title: "Justin Martyr — Dialogue with Trypho 80–81", url: URL(string: "https://www.newadvent.org/fathers/01286.htm")),
                        .init(title: "Irenaeus — Against Heresies V.29 and V.32–36", url: URL(string: "https://www.newadvent.org/fathers/0103529.htm")),
                        .init(title: "Didache 16 — the world-deceiver and the fire of trial", url: URL(string: "https://www.newadvent.org/fathers/0714.htm")),
                        .init(title: "Hippolytus — On Christ and Antichrist 43–50, 60–64", url: URL(string: "https://www.newadvent.org/fathers/0516.htm")),
                        .init(title: "Augustine — City of God XX (thousand years, Antichrist)", url: URL(string: "https://www.newadvent.org/fathers/120120.htm")),
                        .init(title: "Pseudo-Ephraem — manuscripts and the debated passage (R. Pearse)", url: URL(string: "https://www.roger-pearse.com/weblog/tag/pseudo-ephraim/")),
                        .init(title: "J. N. Darby — The Rapture of the Saints and the Jewish Remnant", url: URL(string: "https://www.stempublishing.com/authors/darby/PROPHET/11007E.html"))]),
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
