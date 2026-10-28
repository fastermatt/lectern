import SwiftUI

struct PatristicLibraryView: View {
    enum Section: String, CaseIterable { case read = "Read", authors = "Authors", ideas = "Ideas & reception" }
    var initialSection: Section = .read
    let read: (ResourceBook) -> Void
    @State private var section: Section = .read
    @State private var query = ""
    @State private var selectedProfile: FatherProfile?
    @State private var book: ResourceBook?
    @State private var error: String?
    private let profiles = FatherProfileStore.shared.allProfiles

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Church Fathers & reception").font(.title2)
            Text("Read early witnesses. Examine sources, disputed teachings and later interpretations.")
                .font(.callout).foregroundStyle(STColor.secondary)
            Picker("Browse early Christian resources", selection: $section) {
                ForEach(Section.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.pickerStyle(.segmented).labelsHidden()
            if section != .read {
                TextField(section == .authors ? "Find an author, school or council" : "Find an idea, such as Jung or Nicaea", text: $query)
                    .textFieldStyle(.roundedBorder)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    switch section {
                    case .read: reading
                    case .authors: authors
                    case .ideas: ideas
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 4)
            }
        }.padding(24).background(STColor.paper)
            .onAppear { section = initialSection }
            .onChange(of: section) { _, _ in query = "" }
            .task {
                do { book = try PatristicReader.load() }
                catch { self.error = error.localizedDescription }
            }
            .sheet(item: $selectedProfile) { FatherProfileSheet(profile: $0) }
    }

    private var reading: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Included offline", systemImage: "checkmark.circle").font(.caption).foregroundStyle(STColor.secondary)
            Text("The Writings of the Apostolic Fathers").font(.title3)
            Text("Clement, Polycarp, Ignatius, Hermas, Papias and related early writings. English translation edited by Alexander Roberts and James Donaldson, 1870; translated by Roberts, Donaldson and Frederick Crombie.")
            Text("This edition also contains disputed attributions, longer and shorter recensions, and an appendix explicitly labeled spurious. Read the edition’s introductions; inclusion is not proof of authorship or doctrinal endorsement.")
                .foregroundStyle(STColor.secondary)
            if let book {
                Button("Read offline · \(book.articles.count) sections") { read(book) }.buttonStyle(.borderedProminent)
                    .navigationHelp("Open the contents, search within this volume, and read without a connection.")
            } else if let error { Text(error).foregroundStyle(STColor.warning) }
            else { ProgressView("Opening the included reader…") }
            Link("Edition & permissions · Project Gutenberg", destination: URL(string: "https://www.gutenberg.org/ebooks/77576")!)
            Text("Public domain in the USA; other countries’ laws may differ. The ebook’s attribution and license are retained in the reader. This starting volume is not the complete Church Fathers collection and is not yet indexed to Bible verses.")
                .font(.caption).foregroundStyle(STColor.secondary)
            Divider()
            Text("About passage-linked excerpts").font(.headline)
            Text("The separate HCF excerpt collection is withheld from release packages until edition-level distribution permissions are verified. Author profiles remain available; a profile does not mean that author’s full works are installed.")
                .font(.callout).foregroundStyle(STColor.secondary)
        }.font(.callout).textSelection(.enabled)
    }

    private var matchingProfiles: [FatherProfile] {
        profiles.filter { query.isEmpty || ($0.name + " " + ($0.school ?? "") + " " + $0.receptionLabel).localizedStandardContains(query) }
    }
    private var authors: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("\(matchingProfiles.count) sourced profiles · biographies, not an inventory of installed books")
                .font(.caption).foregroundStyle(STColor.secondary)
            Text("Judgments name the council or synod. Reception notes can concern disputed teachings, schism or contested authorship; they are not interchangeable verdicts.")
                .font(.callout).foregroundStyle(STColor.secondary)
            ForEach(matchingProfiles) { profile in
                Button { selectedProfile = profile } label: {
                    VStack(alignment: .leading, spacing: 5) {
                        HStack { Text(profile.name).font(.headline); Spacer(); Image(systemName: "chevron.right") }
                        Text([profile.dates, profile.school].compactMap { $0 }.joined(separator: " · ")).font(.caption)
                        Label(profile.receptionLabel, systemImage: profile.conciliarJudgment == nil ? "info.circle" : "exclamationmark.triangle")
                            .font(.caption).foregroundStyle(profile.conciliarJudgment == nil ? STColor.secondary : STColor.warning)
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityLabel("\(profile.name). \(profile.receptionLabel). Open sourced profile")
                Divider()
            }
            if matchingProfiles.isEmpty { Text("No matching profiles. Try an author or council name.") }
        }
    }
    private var ideas: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Historical comparisons · reference only").font(.headline)
            Text("These editorial summaries identify specific disagreements and their sources. Doctrinal conflicts identify the teaching contradicted. Later origin alone is not a condemnation; an early refutation is not a council judgment. They do not automatically label your imported books.")
                .font(.callout).foregroundStyle(STColor.secondary)
            let matches = ReceptionTopic.topics.filter { query.isEmpty || ($0.title + " " + $0.summary + " " + $0.period).localizedStandardContains(query) }
            ForEach(matches) { topic in
                VStack(alignment: .leading, spacing: 10) {
                    Text(topic.title).font(.headline)
                    Label(topic.kind.rawValue + " · " + topic.period, systemImage: "info.circle").font(.caption).foregroundStyle(STColor.navy)
                    Text(topic.summary)
                    Text(topic.comparison)
                    Text(topic.limit).foregroundStyle(STColor.secondary)
                    ForEach(topic.sources, id: \.title) { source in
                        if let url = source.url { Link(source.title, destination: url).font(.caption) }
                    }
                }.font(.callout).textSelection(.enabled)
                Divider()
            }
            if matches.isEmpty { Text("No matching comparisons. Try Jung, Christ, Valentinian or Nicaea.") }
        }
    }
}
