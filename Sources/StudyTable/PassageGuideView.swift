import SwiftUI

enum StudyDeskMode: String, CaseIterable, Identifiable {
    case guide = "Guide", sources = "Sources", tools = "Tools"
    var id: String { rawValue }
}

private struct PassageGuideRequest: Equatable {
    let anchor: Anchor?
    let traditions: Set<SourceTradition>
    let research: Bool
}

/// The range overview uses existing desk materials and real stores. Detail tools continue to
/// follow one reader verse; their scope is always named before a reader leaves the guide.
struct PassageGuideView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var study: StudyStore
    let references: ReferenceStore
    @Binding var scope: PassageGuideScope
    let openDetail: (StudyDeskMode, Anchor, StudyDeskSection?) -> Void

    @State private var referenceText = ""
    @State private var inputError: String?
    @State private var result: PassageGuideResult?
    @State private var loadError: String?
    @State private var showAllSources = false
    @State private var showAllReferences = false
    @State private var showAllTopics = false
    @State private var showAllPeople = false
    @State private var sourceDetail: ResolvedSource?
    @State private var showingMyStudy = false

    private var service: PassageGuideService {
        PassageGuideService(library: state.library, resources: state.studyResources, references: references, study: study)
    }
    private var request: PassageGuideRequest {
        PassageGuideRequest(anchor: scope.anchor(selection: state.selectedAnchor),
            traditions: state.selectedTraditions, research: state.showResearchTier)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            scopeControls
            if let inputError { message(inputError, warning: true) }
            if let loadError {
                message(loadError, warning: true)
            } else if let result {
                overview(result)
            } else {
                message("Select a passage to gather its offline study resources.")
            }
        }
        .task(id: request) { refresh() }
        .onAppear { referenceText = request.anchor?.displayString ?? "" }
        .onChange(of: state.selectedAnchor) { _, anchor in
            if scope.followsSelection { referenceText = anchor?.displayString ?? ""; inputError = nil }
        }
        .sheet(item: $sourceDetail) { source in
            VStack(spacing: 0) {
                HStack {
                    Text("Source · \(source.passage)").font(.headline)
                    Spacer()
                    Button("Done") { sourceDetail = nil }.keyboardShortcut(.cancelAction)
                }.padding()
                ScrollView {
                    SourceCard(resolved: source, bookName: result?.anchor.bookInfo?.name ?? "",
                        startExpanded: true) { reference in
                        if let anchor = result?.anchor { scope.pin(anchor) }
                        state.navigate(bookCode: reference.code, chapter: reference.chapter, verse: reference.start)
                        sourceDetail = nil
                    }
                }
            }
            .frame(width: 440, height: 580)
            .background(STColor.paper)
            .environmentObject(state)
        }
        .sheet(isPresented: $showingMyStudy) { MyStudyBrowser().environmentObject(state) }
    }

    private var scopeControls: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                TextField("Rom 8:28–39", text: $referenceText)
                    .textFieldStyle(.roundedBorder).font(.system(size: 12))
                    .accessibilityLabel("Passage Guide reference")
                    .onSubmit { applyReference() }
                Button("Go") { applyReference() }.buttonStyle(ReadingKeyStyle())
                    .accessibilityLabel("Build guide for entered passage")
            }
            if scope.followsSelection {
                Text("Following selection · BSB numbering").font(.system(size: 10)).foregroundStyle(STColor.secondary)
            } else {
                Text("Fixed passage · BSB numbering").font(.system(size: 10)).foregroundStyle(STColor.secondary)
                Button("Follow Scripture selection") {
                    scope.followSelection()
                    referenceText = state.selectedAnchor?.displayString ?? ""
                    inputError = nil
                }.font(.system(size: 11))
            }
        }
        .help("Enter a verse or passage spanning up to 5 chapters. References use BSB numbering.")
        .padding(12)
        .background(STColor.paper)
    }

    @ViewBuilder private func overview(_ result: PassageGuideResult) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("\(result.verses.count) \(result.verses.count == 1 ? "verse" : "verses") · resources across this passage")
                .font(.system(size: 11)).foregroundStyle(STColor.secondary)
            HStack(spacing: 10) {
                Button("Read") {
                    // Keep the guide stable as reading and linked references move its cursor.
                    scope.pin(result.anchor)
                    navigate(result.anchor, at: result.verses.first)
                }
                Button(study.isSaved(result.anchor) ? "Unsave" : "Save") {
                    MyStudyActions.toggleSave(result.anchor, in: state)
                }
                Menu("Details") {
                    Text("At the passage’s first verse")
                    Button("Open Sources") { open(.sources, result: result) }
                    Button("Open Tools") { open(.tools, result: result) }
                }.fixedSize()
                    .help("Detailed Sources and Tools follow the first verse. This guide retains the full passage.")
            }.font(.system(size: 11))
        }.padding(.horizontal, 12).padding(.bottom, 12)

        sources(result)
        crossReferences(result)
        topics(result)
        people(result)
        personal(result)
    }

    private func sources(_ result: PassageGuideResult) -> some View {
        let commentaries = result.sources.filter { $0.resolved.entry.tradition != .crossReferences }
        return VStack(alignment: .leading, spacing: 0) {
            DeskSectionHeader(title: "Commentary excerpts", color: STColor.reformed, count: commentaries.count)
            message("Enabled banks · overlapping excerpts grouped")
            if commentaries.isEmpty { message("No commentary indexed for this passage in the enabled banks.") }
            ForEach(Array(commentaries.prefix(showAllSources ? commentaries.count : 6))) { item in
                Button { sourceDetail = item.resolved } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.resolved.entry.author).font(.system(size: 12, weight: .semibold))
                        Text(item.resolved.entry.work).font(.system(size: 11)).foregroundStyle(STColor.secondary)
                        Text("\(item.resolved.entry.tradition.rawValue) · \(item.resolved.entry.isExactQuote ? "Quoted excerpt" : "Editorial summary")")
                            .font(.system(size: 10)).foregroundStyle(STColor.secondary)
                        if item.resolved.entry.tier == .tier3ResearchOnly {
                            Text("Disputed / research-only witness").font(.system(size: 10, weight: .medium))
                        }
                        Text(item.resolved.entry.excerpt).font(STFont.reading(state.studyFontSize, typeface: state.studyTypeface))
                            .lineLimit(3)
                        Text("Matches \(coverage(item.verses))").font(.system(size: 10)).foregroundStyle(STColor.secondary)
                        Text("Read excerpt & provenance ›").font(.system(size: 11, weight: .medium))
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(12).contentShape(Rectangle())
                }.buttonStyle(.plain)
                rule
            }
            showAllButton(total: commentaries.count, limit: 6, expanded: $showAllSources, noun: "excerpts")
        }
    }

    private func crossReferences(_ result: PassageGuideResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DeskSectionHeader(title: "Cross-references", color: STColor.crossRefs, count: result.crossReferences.count)
            if result.crossReferences.isEmpty { message("No cross-references in the enabled source banks.") }
            ForEach(Array(result.crossReferences.prefix(showAllReferences ? result.crossReferences.count : 8))) { item in
                VStack(alignment: .leading, spacing: 3) {
                    Button(item.reference.label) {
                        scope.pin(result.anchor)
                        state.navigate(bookCode: item.reference.code, chapter: item.reference.chapter, verse: item.reference.start)
                    }.font(.system(size: 12, weight: .medium))
                    Text("Linked from \(coverage(item.from))").font(.system(size: 10)).foregroundStyle(STColor.secondary)
                    Text(Array(Set(item.sources.map { $0.entry.work })).sorted().joined(separator: "; "))
                        .font(.system(size: 10)).foregroundStyle(STColor.secondary)
                    if let source = item.sources.first {
                        Button("Index provenance") { sourceDetail = source }.font(.system(size: 10))
                    }
                }.padding(.horizontal, 12).padding(.vertical, 6)
            }
            showAllButton(total: result.crossReferences.count, limit: 8, expanded: $showAllReferences, noun: "references")
        }
    }

    private func topics(_ result: PassageGuideResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DeskSectionHeader(title: "Topics · Nave’s", color: STColor.navy, count: result.topics.count)
            if result.topics.isEmpty { message("Nave’s has no indexed topics for this passage.") }
            ForEach(Array(result.topics.prefix(showAllTopics ? result.topics.count : 8))) { item in
                DisclosureGroup {
                    if let topic = references.topic(named: item.name) {
                        Text("Nave’s Topical Bible · \(topic.refs.count) cited passages")
                            .font(.system(size: 10)).foregroundStyle(STColor.secondary)
                        ForEach(Array(topic.refs.prefix(20))) { reference in
                            Button(Anchor(book: reference.code, chapter: reference.chapter, verses: reference.start, to: reference.end).displayString) {
                                scope.pin(result.anchor)
                                state.navigate(bookCode: reference.code, chapter: reference.chapter, verse: reference.start)
                            }.font(.system(size: 11))
                        }
                        if topic.refs.count > 20 {
                            Text("First 20 citations shown. Open Tools for the complete topic at a matching verse.")
                                .font(.system(size: 10)).foregroundStyle(STColor.secondary)
                        }
                        if let first = item.direct.first ?? item.additional.first {
                            Button("Topic tools at \(first.id)") { open(.tools, result: result, at: first, tool: .topics) }
                                .font(.system(size: 11))
                        }
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 3) {
                        Text(item.name).font(.system(size: 12, weight: .medium))
                        if !item.direct.isEmpty {
                            Text("Direct index: \(coverage(item.direct))").font(.system(size: 10)).foregroundStyle(STColor.secondary)
                        }
                        if !item.additional.isEmpty {
                            Text("Additional index matches (may include broader passages): \(coverage(item.additional))")
                                .font(.system(size: 10)).foregroundStyle(STColor.secondary)
                        }
                    }
                }.padding(.horizontal, 12).padding(.vertical, 7)
            }
            showAllButton(total: result.topics.count, limit: 8, expanded: $showAllTopics, noun: "topics")
            message(references.attribution.nave)
        }
    }

    private func people(_ result: PassageGuideResult) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            DeskSectionHeader(title: "People & places", color: STColor.navy, count: result.people.count)
            if result.people.isEmpty { message("No proper names indexed by TIPNR for this passage.") }
            ForEach(Array(result.people.prefix(showAllPeople ? result.people.count : 6))) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text("\(item.name.name) · \(item.name.kind)").font(.system(size: 12, weight: .semibold))
                    Text(item.name.description).font(STFont.reading(state.studyFontSize, typeface: state.studyTypeface))
                    Text("Named at \(coverage(item.verses))").font(.system(size: 10)).foregroundStyle(STColor.secondary)
                    if let first = item.verses.first {
                        Button("Open name tools at \(first.id)") { open(.tools, result: result, at: first, tool: .peoplePlaces) }
                            .font(.system(size: 11))
                    }
                }.padding(12)
                rule
            }
            showAllButton(total: result.people.count, limit: 6, expanded: $showAllPeople, noun: "names")
            message(references.attribution.tipnr + " Some upstream descriptions are AI-assisted source text, not generated by Lectern.")
        }
    }

    private func personal(_ result: PassageGuideResult) -> some View {
        let items = study.items(overlapping: result.anchor)
        return VStack(alignment: .leading, spacing: 0) {
            DeskSectionHeader(title: "Your study", color: STColor.navy, count: items.notes.count + items.saved.count)
            if items.notes.isEmpty { message("No notes overlap this passage yet.") }
            ForEach(Array(items.notes.prefix(3))) { note in
                VStack(alignment: .leading, spacing: 3) {
                    Text(note.title.isEmpty ? note.referenceLabel : note.title).font(.system(size: 12, weight: .semibold))
                    Text(note.plainText).font(STFont.reading(state.studyFontSize, typeface: state.studyTypeface)).lineLimit(3)
                }.padding(12)
            }
            HStack(spacing: 10) {
                Button("My Study") { showingMyStudy = true }
                Button("Notes at first verse") {
                    scope.pin(result.anchor)
                    navigate(result.anchor, at: result.verses.first)
                    state.showNotes = true
                }
            }.font(.system(size: 11)).padding(12)
            if items.saved.count > 0 { message("\(items.saved.count) saved passage\(items.saved.count == 1 ? " overlaps" : "s overlap") this guide.") }
        }
    }

    private var rule: some View { Rectangle().fill(STColor.hairline).frame(height: 1) }

    private func message(_ text: String, warning: Bool = false) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(warning ? STColor.ink : STColor.secondary)
            .fixedSize(horizontal: false, vertical: true).padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(warning ? STColor.warning.opacity(0.08) : Color.clear)
            .accessibilityLabel(warning ? "Passage Guide: " + text : text)
    }

    @ViewBuilder private func showAllButton(total: Int, limit: Int, expanded: Binding<Bool>, noun: String) -> some View {
        if total > limit {
            Button(expanded.wrappedValue ? "Show fewer \(noun)" : "Show all \(total) \(noun)") { expanded.wrappedValue.toggle() }
                .font(.system(size: 11, weight: .medium)).padding(12)
        }
    }

    private func coverage(_ positions: [PassageGuideVerse]) -> String {
        positions.prefix(5).map(\.id).joined(separator: ", ") + (positions.count > 5 ? " + \(positions.count - 5) more verses" : "")
    }

    private func applyReference() {
        do {
            let anchor = try service.parse(referenceText)
            scope.pin(anchor)
            referenceText = anchor.displayString
            inputError = nil
        } catch { inputError = error.localizedDescription }
    }

    private func refresh() {
        result = nil
        loadError = nil
        guard let anchor = request.anchor else { return }
        do {
            result = try service.build(anchor: anchor, traditions: request.traditions, includeResearch: request.research)
        } catch { loadError = error.localizedDescription }
        showAllSources = false; showAllReferences = false; showAllTopics = false; showAllPeople = false
    }

    private func navigate(_ anchor: Anchor, at position: PassageGuideVerse?) {
        guard let position else { return }
        state.navigate(bookCode: anchor.book, chapter: position.chapter, verse: position.verse)
    }

    private func open(_ mode: StudyDeskMode, result: PassageGuideResult, at position: PassageGuideVerse? = nil,
                      tool: StudyDeskSection? = nil) {
        scope.pin(result.anchor)
        let first = position ?? result.verses.first
        guard let first else { return }
        openDetail(mode, Anchor(book: result.anchor.book, chapter: first.chapter, verse: first.verse), tool)
    }
}
