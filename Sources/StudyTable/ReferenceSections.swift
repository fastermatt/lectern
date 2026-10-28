import SwiftUI

// MARK: - Passage Guide desk sections (Workstream J, 0.8)
//
// Three self-contained Study Desk sections built on `DeskComponents.swift`'s shared
// primitives, the same pattern `ProofTextsSection.swift` (workstream B, 0.7) and
// `WordStudySection` (`WordStudy.swift`, workstream D, 0.7) already established: own their
// own lazy store (`ReferenceStore.shared`), read the selected passage from `AppState` via
// `@EnvironmentObject`, collapse to a one-line summary by default (`@AppStorage`-remembered)
// so they never push the commentary banks below the fold, and navigate with
// `state.navigate(bookCode:chapter:verse:)`. K (wave 2) inserts a bare `TopicsSection()` /
// `DictionarySection()` / `PeoplePlacesSection()` into the desk stack.
//
// Color: all three (like Word Study and Proof Texts before them) reuse the fixed
// `STColor.navyOnBlack` header swatch rather than inventing a new accent — DESIGN.md's
// accent palette is deliberately small, and the printed title is what tells these apart, not
// the swatch color.

private let referenceSwatch = STColor.navyOnBlack

// MARK: - Topics (Nave's Topical Bible)

/// For the selected verse: which Nave's Topical Bible topics cite it, each expandable in
/// place to the topic's own full verse list (grouped by the topic's own subheadings where it
/// has them) — "topic → all verses, navigable" per WORKPLAN-0.8 §J.1. A topic's "see also"
/// links open the target topic as an extra row appended below, so browsing stays inside the
/// one section rather than jumping to a separate screen.
struct TopicsSection: View {
    @EnvironmentObject private var state: AppState
    var store: ReferenceStore = .shared
    @AppStorage("desk.topicsExpanded") private var sectionExpanded = false
    @State private var expandedIDs: Set<String> = []
    @State private var extraTopics: [String] = []
    @State private var showWider = false

    private var verseTopics: [String] {
        guard let code = state.book?.code, let verse = state.selectedVerse, verse > 0 else { return [] }
        return store.topics(bookCode: code, chapter: state.selectedChapter, verse: verse)
    }

    /// Topics that cover this verse only through a wide citation (see `ReferenceStore.moreTopics`).
    private var widerTopics: [String] {
        guard let code = state.book?.code, let verse = state.selectedVerse, verse > 0 else { return [] }
        return store.moreTopics(bookCode: code, chapter: state.selectedChapter, verse: verse)
            .filter { !extraTopics.contains($0) }
    }

    /// The verse's own topics plus any "see also" topics the reader has opened, deduplicated
    /// in that order.
    private var displayedTopics: [String] {
        var seen = Set<String>()
        var out: [String] = []
        for name in verseTopics + extraTopics where !seen.contains(name) {
            seen.insert(name)
            out.append(name)
        }
        return out
    }

    var body: some View {
        let topics = displayedTopics
        Group {
            VStack(alignment: .leading, spacing: 0) {
                DeskSectionHeader(title: "Topics", color: referenceSwatch, count: verseTopics.count,
                                  expanded: $sectionExpanded)
                if sectionExpanded {
                    if topics.isEmpty {
                        Text(widerTopics.isEmpty ? "Nave’s has no indexed topics for this verse."
                                                 : "No topic in Nave’s cites this verse directly.")
                            .font(.system(size: 11)).foregroundStyle(STColor.secondary).padding(12)
                    }
                    ForEach(topics, id: \.self) { name in
                        TopicRow(name: name, store: store, expanded: expandedBinding(name)) { target in
                            state.navigate(bookCode: target.code, chapter: target.chapter, verse: target.start)
                        } onOpenSeeAlso: { seeAlsoName in
                            if !extraTopics.contains(seeAlsoName) && !verseTopics.contains(seeAlsoName) {
                                extraTopics.append(seeAlsoName)
                            }
                            expandedIDs.insert(seeAlsoName)
                        }
                        Rectangle().fill(STColor.hairline).frame(height: 1)
                    }
                    let wider = widerTopics
                    if !wider.isEmpty {
                        WiderPassagesToggle(count: wider.count, noun: "topics", expanded: $showWider)
                        Rectangle().fill(STColor.hairline).frame(height: 1)
                        if showWider {
                            ForEach(wider.filter { !topics.contains($0) }, id: \.self) { name in
                                TopicRow(name: name, store: store, expanded: expandedBinding(name)) { target in
                                    state.navigate(bookCode: target.code, chapter: target.chapter, verse: target.start)
                                } onOpenSeeAlso: { seeAlsoName in
                                    if !extraTopics.contains(seeAlsoName) && !verseTopics.contains(seeAlsoName) {
                                        extraTopics.append(seeAlsoName)
                                    }
                                    expandedIDs.insert(seeAlsoName)
                                }
                                Rectangle().fill(STColor.hairline).frame(height: 1)
                            }
                        }
                    }
                } else {
                    DeskCollapsedSummary(section: "Topics", text: collapsedText) {
                        sectionExpanded = true
                    }
                }
            }
        }
        .onChange(of: state.passage) { _, _ in
            extraTopics = []
            expandedIDs = []
            showWider = false
        }
    }

    private var collapsedText: String {
        let wider = widerTopics.count
        let more = wider > 0 ? "  \u{00B7}  +\(wider) wider" : ""
        if verseTopics.isEmpty { return (wider > 0 ? "No direct topics · \(wider) in wider passages" : "No indexed topics for this verse") }
        return verseTopics.joined(separator: "  \u{00B7}  ") + more
    }

    private func expandedBinding(_ name: String) -> Binding<Bool> {
        Binding(get: { expandedIDs.contains(name) },
                set: { isExpanded in
                    if isExpanded { expandedIDs.insert(name) } else { expandedIDs.remove(name) }
                })
    }
}

private struct TopicRow: View {
    let name: String
    let store: ReferenceStore
    @Binding var expanded: Bool
    let onNavigate: (ReferenceRef) -> Void
    let onOpenSeeAlso: (String) -> Void

    private var topic: NaveTopic? { store.topic(named: name) }

    var body: some View {
        DeskCard {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(name).font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundStyle(STColor.ink)
                Spacer()
                if let topic { Text("\(topic.refs.count)").font(STFont.lcd(10)).monospacedDigit().foregroundStyle(STColor.secondary) }
            }
        } content: {
            if expanded, let topic {
                VStack(alignment: .leading, spacing: 8) {
                    if topic.sections.count > 1 {
                        ForEach(Array(topic.sections.enumerated()), id: \.offset) { _, section in
                            DisclosureGroup(section.heading.isEmpty ? "References" : section.heading) {
                                refChips(section.refs)
                            }
                            .font(.system(size: 11, weight: .medium)).foregroundStyle(STColor.ink)
                        }
                    } else {
                        refChips(topic.refs)
                    }
                    if !topic.seeAlso.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("See also").legend(STColor.secondary, size: 9)
                            FlowLayout(spacing: 6) {
                                ForEach(topic.seeAlso, id: \.self) { other in
                                    Button(other) { onOpenSeeAlso(other) }
                                        .disabled(store.topic(named: other) == nil)
                                        .buttonStyle(.plain)
                                        .font(.system(size: 10, weight: .medium, design: .rounded))
                                        .foregroundStyle(STColor.secondary)
                                        .padding(.horizontal, 7).padding(.vertical, 3)
                                        .overlay(Capsule().stroke(STColor.hairline, lineWidth: 1))
                                }
                            }
                        }
                    }
                }
            } else if expanded {
                Text("This topic's data couldn't be loaded.").font(.system(size: 11, design: .rounded)).foregroundStyle(STColor.secondary)
            }
        } footer: {
            HStack {
                Spacer()
                DeskMoreButton(expanded: $expanded)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(name)
    }

    private func refChips(_ refs: [ReferenceRef]) -> some View {
        PagedReferenceChips(items: refs) { ref in
                Button(chipLabel(ref)) { onNavigate(ref) }
                    .buttonStyle(.plain)
                    .font(.system(size: 10, weight: .medium, design: .rounded))
                    .foregroundStyle(STColor.ink)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(STColor.tileWell, in: Capsule())
                    .overlay(Capsule().stroke(STColor.keyRim, lineWidth: 1))
        }
    }

    private func chipLabel(_ ref: ReferenceRef) -> String {
        ref.start == ref.end ? "\(ref.code) \(ref.chapter):\(ref.start)" : "\(ref.code) \(ref.chapter):\(ref.start)\u{2013}\(ref.end)"
    }
}

// MARK: - "N more" affordance (0.10, R2)

/// The Topics/Dictionary lists show only what cites the verse directly; headings that reach it only
/// through a wide citation (a bare chapter, a long run) sit behind this control, so nothing the
/// index ever attached is unreachable. Selected state is the chevron + the wording, not colour.
private struct WiderPassagesToggle: View {
    let count: Int
    let noun: String
    @Binding var expanded: Bool

    var body: some View {
        Button {
            expanded.toggle()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: expanded ? "chevron.down" : "chevron.right").font(.system(size: 9, weight: .semibold))
                Text(expanded ? "Hide \(count) cited in wider passages" : "\(count) more \u{00B7} cited in wider passages")
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                Spacer()
            }
            .foregroundStyle(STColor.secondary)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(count) more \(noun), cited in wider passages, \(expanded ? "shown" : "hidden")")
        .accessibilityHint(expanded ? "Hides them" : "Shows them")
    }
}

// MARK: - Dictionary (Easton's Bible Dictionary)

/// For the selected verse: Easton's Bible Dictionary articles linked from it (by name/term
/// present in the verse, or by a Nave's topic already resolved for it — see
/// `ReferenceStore.dictionaryHeadwords`), plus a standing link to the current book's own
/// Easton introduction article (not verse-specific — WORKPLAN-0.8 §J.2's "book
/// introductions... for context").
struct DictionarySection: View {
    @EnvironmentObject private var state: AppState
    var store: ReferenceStore = .shared
    @AppStorage("desk.dictionaryExpanded") private var sectionExpanded = false
    @State private var expandedIDs: Set<String> = []
    @State private var bookIntroExpanded = false
    @State private var showWider = false

    private var headwords: [String] {
        guard let code = state.book?.code, let verse = state.selectedVerse, verse > 0 else { return [] }
        return store.dictionaryHeadwords(bookCode: code, chapter: state.selectedChapter, verse: verse)
    }

    private var widerHeadwords: [String] {
        guard let code = state.book?.code, let verse = state.selectedVerse, verse > 0 else { return [] }
        return store.moreDictionaryHeadwords(bookCode: code, chapter: state.selectedChapter, verse: verse)
    }

    private var bookIntro: EastonArticle? {
        guard let code = state.book?.code else { return nil }
        return store.bookIntroArticle(bookCode: code)
    }

    var body: some View {
        let words = headwords
        if !words.isEmpty || bookIntro != nil {
            VStack(alignment: .leading, spacing: 0) {
                DeskSectionHeader(title: "Dictionary", color: referenceSwatch, count: words.count,
                                  expanded: $sectionExpanded)
                if sectionExpanded {
                    if let bookIntro {
                        ArticleRow(title: "About \(state.bookName)", article: bookIntro, expanded: $bookIntroExpanded)
                        Rectangle().fill(STColor.hairline).frame(height: 1)
                    }
                    ForEach(words, id: \.self) { headword in
                        if let article = store.article(headword: headword) {
                            ArticleRow(title: article.title, article: article, expanded: expandedBinding(headword))
                            Rectangle().fill(STColor.hairline).frame(height: 1)
                        }
                    }
                    let wider = widerHeadwords
                    if !wider.isEmpty {
                        WiderPassagesToggle(count: wider.count, noun: "articles", expanded: $showWider)
                        Rectangle().fill(STColor.hairline).frame(height: 1)
                        if showWider {
                            ForEach(wider, id: \.self) { headword in
                                if let article = store.article(headword: headword) {
                                    ArticleRow(title: article.title, article: article, expanded: expandedBinding(headword))
                                    Rectangle().fill(STColor.hairline).frame(height: 1)
                                }
                            }
                        }
                    }
                } else {
                    DeskCollapsedSummary(section: "Dictionary", text: collapsedText(words)) {
                        sectionExpanded = true
                    }
                }
            }
            .onChange(of: state.passage) { _, _ in
                expandedIDs = []
                showWider = false
            }
        }
    }

    private func collapsedText(_ words: [String]) -> String {
        let wider = widerHeadwords.count
        if words.isEmpty { return wider > 0 ? "About \(state.bookName) · Easton’s · \(wider) in wider passages" : "About \(state.bookName) · Easton’s" }
        return words.joined(separator: "  \u{00B7}  ") + (wider > 0 ? "  \u{00B7}  +\(wider) wider" : "")
    }

    private func expandedBinding(_ headword: String) -> Binding<Bool> {
        Binding(get: { expandedIDs.contains(headword) },
                set: { isExpanded in
                    if isExpanded { expandedIDs.insert(headword) } else { expandedIDs.remove(headword) }
                })
    }
}

private struct ArticleRow: View {
    @EnvironmentObject private var state: AppState
    let title: String
    let article: EastonArticle
    @Binding var expanded: Bool

    var body: some View {
        DeskCard {
            Text(title).font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundStyle(STColor.ink)
        } content: {
            // Same Study voice as commentary excerpts (0.10.2) — a reference article is the same
            // kind of reading text as a commentary excerpt, so it shares the same font controls.
            DeskExpandableText(text: article.text, expanded: $expanded,
                               typeface: state.studyTypeface, fontSize: state.studyFontSize, lineSpacing: state.studyLineSpacing)
        } footer: {
            Text("Easton’s Bible Dictionary (1897) · related article")
                .font(.system(size: 10)).foregroundStyle(STColor.secondary)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
    }
}

// MARK: - People & Places (STEPBible TIPNR)

/// For the selected verse: the people and places it mentions, each with a compact STEPBible
/// description and its other references — WORKPLAN-0.8 §J.3.
struct PeoplePlacesSection: View {
    @EnvironmentObject private var state: AppState
    var store: ReferenceStore = .shared
    @AppStorage("desk.peoplePlacesExpanded") private var sectionExpanded = false
    @State private var expandedIDs: Set<String> = []

    private var entries: [TIPNRName] {
        guard let code = state.book?.code, let verse = state.selectedVerse, verse > 0 else { return [] }
        return store.names(bookCode: code, chapter: state.selectedChapter, verse: verse)
    }

    var body: some View {
        let items = entries
        Group {
            VStack(alignment: .leading, spacing: 0) {
                DeskSectionHeader(title: "People & Places", color: referenceSwatch, count: items.count,
                                  expanded: $sectionExpanded)
                if sectionExpanded {
                    if items.isEmpty {
                        Text("No indexed people or places for this verse.")
                            .font(.system(size: 11)).foregroundStyle(STColor.secondary).padding(12)
                    }
                    ForEach(Array(items.enumerated()), id: \.offset) { index, entry in
                        NameRow(entry: entry, article: store.article(headword: entry.name.uppercased()), expanded: expandedBinding(index)) { ref in
                            state.navigate(bookCode: ref.code, chapter: ref.chapter, verse: ref.verse)
                        }
                        .id("\(state.passage)-\(index)")
                        Rectangle().fill(STColor.hairline).frame(height: 1)
                    }
                } else {
                    DeskCollapsedSummary(section: "People & Places", text: items.isEmpty ? "No indexed names for this verse" : items.map(\.name).joined(separator: "  \u{00B7}  ")) {
                        sectionExpanded = true
                    }
                }
            }
        }
        .onChange(of: state.passage) { _, _ in expandedIDs = [] }
    }

    private func expandedBinding(_ index: Int) -> Binding<Bool> {
        Binding(get: { expandedIDs.contains("\(index)") },
                set: { isExpanded in
                    if isExpanded { expandedIDs.insert("\(index)") } else { expandedIDs.remove("\(index)") }
                })
    }
}

private struct NameRow: View {
    @EnvironmentObject private var state: AppState
    let entry: TIPNRName
    let article: EastonArticle?
    @Binding var expanded: Bool
    let onNavigate: (TIPNRRef) -> Void

    private var kindLabel: String {
        switch entry.kind { case "person": "PERSON"; case "place": "PLACE"; default: "OTHER" }
    }

    var body: some View {
        DeskCard {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(entry.name).font(.system(size: 12.5, weight: .semibold, design: .rounded)).foregroundStyle(STColor.ink)
                Text(kindLabel).legend(STColor.secondary, size: 9)
                Spacer()
                Text("\(entry.refs.count)").font(STFont.lcd(10)).monospacedDigit().foregroundStyle(STColor.secondary)
            }
        } content: {
            VStack(alignment: .leading, spacing: 8) {
                Text(article.map { expanded ? $0.text : String($0.text.prefix(600)) + ($0.text.count > 600 ? "…" : "") } ?? entry.description)
                    .font(STFont.reading(state.studyFontSize, typeface: state.studyTypeface))
                    .lineSpacing(state.studyLineSpacing)
                    .foregroundStyle(STColor.ink)
                    .textSelection(.enabled)
                Text(article == nil ? "STEPBible summary · AI-assisted source text" : "Easton’s (1897) · related article matched by name")
                    .font(.system(size: 10, weight: .medium)).foregroundStyle(STColor.secondary)
                if expanded {
                    PagedReferenceChips(items: entry.refs) { ref in
                            Button("\(ref.code) \(ref.chapter):\(ref.verse)") { onNavigate(ref) }
                                .buttonStyle(.plain)
                                .font(.system(size: 10, weight: .medium, design: .rounded))
                                .foregroundStyle(STColor.ink)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(STColor.tileWell, in: Capsule())
                                .overlay(Capsule().stroke(STColor.keyRim, lineWidth: 1))
                    }
                }
            }
        } footer: {
            if entry.refs.count > 1 || (article?.text.count ?? 0) > 600 {
                HStack {
                    Spacer()
                    DeskMoreButton(expanded: $expanded)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(entry.name), \(kindLabel.lowercased())")
    }
}

/// Large topics/names can cite thousands of passages. Page the chips rather than constructing
/// thousands of buttons in a FlowLayout on the main thread. Index identity tolerates duplicate
/// historic references without SwiftUI reusing the wrong button.
private struct PagedReferenceChips<Item, Content: View>: View {
    let items: [Item]
    @ViewBuilder let content: (Item) -> Content
    @State private var page = 0
    private let pageSize = 40

    var body: some View {
        let pageCount = max(1, (items.count + pageSize - 1) / pageSize)
        let current = min(page, pageCount - 1)
        let start = current * pageSize
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6) {
                ForEach(start..<min(start + pageSize, items.count), id: \.self) { index in
                    content(items[index])
                }
            }
            if pageCount > 1 {
                HStack {
                    Button("Previous") { page = max(0, current - 1) }.disabled(current == 0)
                    Text("\(current + 1) / \(pageCount)").font(STFont.lcd(10))
                    Button("Next") { page = min(pageCount - 1, current + 1) }.disabled(current == pageCount - 1)
                }
                .controlSize(.small)
                .accessibilityLabel("Reference pages, page \(current + 1) of \(pageCount)")
            }
        }
    }
}
