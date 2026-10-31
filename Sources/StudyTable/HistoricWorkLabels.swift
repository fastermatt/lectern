import Foundation

/// Reader-facing labels for the historic works, prepared 2026-10-31 by a three-part review
/// (patristics historian, historical theologian, ecumenical editor) with a source for each
/// caution. Labels describe; they are not verdicts. See docs/reviews/historic-works-labels-2026-10-31.md.
struct WorkLabels: Sendable {
    let badge: String
    let era: String
    let genre: String
    let level: String
    let topics: [String]
    let whyRead: String
    let cautions: [String]
    /// Position and where to read, for works that matter to the last things.
    let lastThings: String?
    let sources: [String]

    static let topicOrder = ["Last things", "Israel & the church", "Church & sacraments", "Christ & Trinity",
                             "Grace & salvation", "Scripture & interpretation", "Heresy & orthodoxy",
                             "Church history", "Spiritual formation", "Providence & suffering"]

    static func of(_ id: String) -> WorkLabels? { byID[id] }

    static let byID: [String: WorkLabels] = [
        "apostolic-fathers-1870": .init(badge: "Mixed authenticity", era: "Apostolic age (c. 90–150)", genre: "Letters", level: "Intermediate",
            topics: ["Church & sacraments", "Last things", "Heresy & orthodoxy", "Christ & Trinity", "Church history"],
            whyRead: "The earliest Christian writings after the New Testament, one generation from the apostles.",
            cautions: ["Ignatius appears in three recensions; scholars accept the middle (seven-letter) recension. The longer recension is a 4th-century expansion and the appendix letters are spurious.",
                       "Barnabas is anonymous (c. 70–135) and an early example of supersessionist reading of Israel and the law.",
                       "Papias survives only in later quotations; Eusebius disparaged his millenarian views — his judgment, not a council's.",
                       "No Didache: it was published in 1883, after this edition."],
            lastThings: "Early chiliast (premillennial) witnesses: Papias expects an earthly thousand-year kingdom after the resurrection; Barnabas 15 reads creation's days as ages before a sabbath rest; Hermas, Vision IV, speaks of a coming great tribulation the church must endure. 1 Clement and Diognetus teach no millennium.",
            sources: ["https://www.newadvent.org/cathen/07644a.htm", "https://ccel.org/ccel/schaff/anf01.vii.i.html"]),
        "pg-3296": .init(badge: "Doctor of the Church", era: "Nicene & post-Nicene", genre: "Spiritual autobiography", level: "Intermediate",
            topics: ["Grace & salvation", "Spiritual formation", "Scripture & interpretation"],
            whyRead: "Augustine's restless heart, conversion and grace — written as prayer.",
            cautions: ["Pusey's 1838 English is archaic. Books X–XIII turn to memory, time and Genesis 1.", "Psalms may follow Latin numbering (often one lower for Psalms 10–147)."],
            lastThings: nil, sources: ["https://www.newadvent.org/cathen/02084a.htm"]),
        "pg-45304": .init(badge: "Doctor of the Church", era: "Nicene & post-Nicene", genre: "Apologetic", level: "Advanced",
            topics: ["Providence & suffering", "Church history", "Heresy & orthodoxy"],
            whyRead: "Augustine answers pagan blame for Rome's fall and weighs Roman religion and Platonism.",
            cautions: ["Books I–XIII (Dods, 1871). The millennium discussion is Book XX, in Volume II."],
            lastThings: nil, sources: ["https://ccel.org/ccel/schaff/npnf102.iv.XX.7.html"]),
        "pg-45305": .init(badge: "Doctor of the Church", era: "Nicene & post-Nicene", genre: "Theological treatise", level: "Advanced",
            topics: ["Last things", "Israel & the church", "Church & sacraments", "Providence & suffering"],
            whyRead: "The two cities to their ends — and the foundational spiritual reading of Revelation 20.",
            cautions: ["In XX.7 Augustine says he once held a spiritualized chiliast view and abandoned it.", "Psalms may follow Latin numbering."],
            lastThings: "Amillennial: the thousand years is the church's present age, the first resurrection is regeneration, Satan is bound from deceiving the church. Read XX.6–9; Antichrist XX.19, 23; Elijah and the Jews XX.29–30.",
            sources: ["https://ccel.org/ccel/schaff/npnf102.iv.XX.7.html"]),
        "pg-45843": .init(badge: "Controversy writings", era: "Nicene & post-Nicene", genre: "Polemic", level: "Advanced",
            topics: ["Church & sacraments", "Heresy & orthodoxy", "Church history"],
            whyRead: "Sacraments stand apart from the minister's holiness: Augustine on unity against a schism.",
            cautions: ["Includes Letter 185, defending imperial coercion with 'compel them to come in' (Luke 14:23); all three traditions today reject coerced faith.", "Donatism was a North African schism; the Conference of Carthage (411) was regional, not ecumenical."],
            lastThings: nil, sources: ["https://www.newadvent.org/fathers/1409.htm", "https://www.newadvent.org/cathen/05121a.htm"]),
        "pg-58783": .init(badge: "Doctor of the Church", era: "Nicene & post-Nicene", genre: "Letters", level: "Intermediate",
            topics: ["Church history", "Church & sacraments", "Israel & the church"],
            whyRead: "A bishop confronting emperors: church and state, the Arian struggle, pastoral counsel.",
            cautions: ["Letters 40–41 (388) oppose rebuilding a burned synagogue at Callinicum — troubling for Christian–Jewish relations.", "Benedictine letter numbering and Latin Psalm numbering."],
            lastThings: nil, sources: ["https://earlychurchtexts.com/main/ambrose/letter_40_callinicum_synagogue_01.shtml"]),
        "pg-62447": .init(badge: "Selections only", era: "Nicene & post-Nicene", genre: "Homily excerpts", level: "Introductory",
            topics: ["Spiritual formation", "Scripture & interpretation"],
            whyRead: "Short passages from the golden-mouthed preacher on Scripture, prayer and wealth.",
            cautions: ["An 1889 anthology of excerpts: check the full homily before citing."],
            lastThings: nil, sources: ["https://www.gutenberg.org/ebooks/62447"]),
        "pg-70561": .init(badge: "Read with context", era: "Ante-Nicene", genre: "Theological treatise", level: "Advanced",
            topics: ["Scripture & interpretation", "Christ & Trinity", "Last things"],
            whyRead: "The first systematic Christian theology, and Origen's senses of Scripture (Book IV).",
            cautions: ["De Principiis survives mainly in Rufinus's Latin, which he admits smoothing.",
                       "Origenist propositions were condemned by a Constantinople synod (543); Constantinople II (553), canon 11, names Origen. Whether the fifteen anathemas were conciliar, and how far they describe Origen himself, is debated."],
            lastThings: "Anti-chiliast spiritual reading: rejects a literal earthly Jerusalem (De Principiis II.11); tentative speculation on final restoration (I.6, III.6).",
            sources: ["https://www.newadvent.org/cathen/11306b.htm", "https://orthodoxwiki.org/Origen"]),
        "pg-70693": .init(badge: "Read with context", era: "Ante-Nicene", genre: "Apologetic", level: "Advanced",
            topics: ["Christ & Trinity", "Scripture & interpretation", "Israel & the church"],
            whyRead: "The fullest early Christian answer to an educated pagan critic.",
            cautions: ["Celsus is quoted at length to be answered — don't mistake his words for Origen's.", "Reception of Origen: see Volume I."],
            lastThings: nil, sources: ["https://www.newadvent.org/cathen/11306b.htm"]),
        "pg-65478": .init(badge: "Disputed authorship", era: "Ante-Nicene", genre: "Anti-heresy", level: "Advanced",
            topics: ["Heresy & orthodoxy", "Church history"],
            whyRead: "Gnostic systems traced to Greek philosophy by a hostile contemporary.",
            cautions: ["Once published as Origen's; attributed to Hippolytus, still debated. Books II–III are lost.", "Hippolytus led a rival Roman community, then reconciled before martyrdom (235)."],
            lastThings: nil, sources: ["https://www.britannica.com/biography/Saint-Hippolytus-of-Rome"]),
        "pg-67116": .init(badge: "Disputed authorship", era: "Ante-Nicene", genre: "Anti-heresy", level: "Advanced",
            topics: ["Heresy & orthodoxy", "Christ & Trinity", "Church history"],
            whyRead: "Later heresies, the author's statement of faith, and Rome c. 220.",
            cautions: ["Book IX's account of Zephyrinus and Callistus is partisan, written during a schism."],
            lastThings: nil, sources: ["https://www.britannica.com/biography/Saint-Hippolytus-of-Rome"]),
        "pg-61614": .init(badge: "Disputed authorship", era: "Ante-Nicene", genre: "Church order", level: "Intermediate",
            topics: ["Church & sacraments", "Spiritual formation"],
            whyRead: "Ordination, baptism, Eucharist and daily prayer in an early church order.",
            cautions: ["Now widely read as a composite 'living' text (mid-2nd to 4th century), not a single work of c. 215.", "Easton (1934) predates later reconstructions."],
            lastThings: nil, sources: ["https://en.wikipedia.org/wiki/Apostolic_Tradition"]),
        "pg-24979": .init(badge: "Dated source book", era: "Modern reference (1913)", genre: "Source collection", level: "Intermediate",
            topics: ["Church history", "Last things", "Heresy & orthodoxy"],
            whyRead: "Hundreds of short primary sources, apostles to the 9th century.",
            cautions: ["Ayer's introductions reflect 1913 Protestant scholarship — dated interpretation, not neutral fact."],
            lastThings: "Prints the early chiliast witnesses: Papias (via Eusebius), Irenaeus, Against Heresies V.33, and Justin, Dialogue 80–81 — under 'Chiliastic Expectations'.",
            sources: ["https://www.gutenberg.org/ebooks/24979"]),
        "pg-38326": .init(badge: "Doctor of the Church", era: "Early medieval", genre: "History", level: "Intermediate",
            topics: ["Church history", "Spiritual formation"],
            whyRead: "The founding history of English Christianity, to 731.",
            cautions: ["Bede favours the Roman side at Whitby (664); miracle accounts follow hagiographic convention."],
            lastThings: nil, sources: ["https://www.newadvent.org/cathen/02384a.htm"]),
        "pg-14328": .init(badge: "Philosophical classic", era: "Early medieval", genre: "Philosophy", level: "Intermediate",
            topics: ["Providence & suffering"],
            whyRead: "A condemned man reasons about fortune, evil, providence and freedom.",
            cautions: ["No explicit Christian references; how Christian the Consolation is remains debated."],
            lastThings: nil, sources: ["https://plato.stanford.edu/entries/boethius/"]),
        "pg-45001": .init(badge: "Reformation classic", era: "Reformation", genre: "Theological treatise", level: "Advanced",
            topics: ["Scripture & interpretation", "Christ & Trinity", "Grace & salvation", "Israel & the church"],
            whyRead: "Knowing God, Scripture, providence, the law and Christ's work.",
            cautions: ["Books I–III.13 (Allen, 1813). Reformation polemic: 'Papists' and the like are Calvin's terms, not the app's."],
            lastThings: nil, sources: ["https://www.britannica.com/biography/John-Calvin"]),
        "pg-64392": .init(badge: "Reformation classic", era: "Reformation", genre: "Theological treatise", level: "Advanced",
            topics: ["Grace & salvation", "Church & sacraments", "Last things"],
            whyRead: "Justification, prayer, predestination, resurrection, church and sacraments.",
            cautions: ["Trent (Session VI–VII, 1547) rejects positions defended here; Book IV is sharp polemic."],
            lastThings: "Amillennial: dismisses the millenarians and reads Revelation's thousand years as the church's militant state. Read III.25.5; resurrection III.25.",
            sources: ["https://www.gutenberg.org/ebooks/64392"]),
        "pg-1653": .init(badge: "Devotional classic", era: "Late medieval", genre: "Devotional", level: "Introductory",
            topics: ["Spiritual formation", "Church & sacraments"],
            whyRead: "The most widely read devotional after the Bible: humility and inward life.",
            cautions: ["Book IV assumes Catholic Eucharistic practice; authorship was once disputed."],
            lastThings: nil, sources: ["https://britannica.com/topic/Imitation-of-Christ-devotional-book"])
    ]
}
