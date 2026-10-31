import SwiftUI

// MARK: - Shared pane furniture

struct TileHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder let trailing: () -> Trailing

    var body: some View {
        HStack(spacing: 8) {
            Text(title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 6)
            trailing()
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
    }
}

/// Small printed chip used for status readouts.
struct LegendChip: View {
    let text: String
    var body: some View {
        Text(text).legend(STColor.secondary, size: 9)
            .padding(.horizontal, 6).padding(.vertical, 2.5)
            .overlay(RoundedRectangle(cornerRadius: 2).stroke(STColor.keyRim, lineWidth: 1))
    }
}

struct SearchField: View {
    @Binding var text: String
    let placeholder: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(STColor.secondary)
            TextField(placeholder, text: $text).textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(STColor.secondary)
                    .accessibilityLabel("Clear search")
            }
        }
        .font(.system(size: 12, design: .rounded))
        .padding(.horizontal, 10).frame(height: 30)
        .background(STColor.tileWell, in: Capsule())
        .overlay(Capsule().stroke(STColor.keyRim.opacity(0.8), lineWidth: 1))
    }
}

// MARK: - Scripture

struct ScripturePane: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            // Translation and online/offline state are the LCD's job (see LCD.swift) — this
            // header used to repeat both as chips, one of three places the same two facts showed
            // up on screen at once. The pane title stays (it's the one place that names *this*
            // pane's contents), the chips don't.
            ReadingNavigation()
            if state.translationID == "DBY" {
                DarbyComparisonNotice(translationID: state.translationID)
                    .padding(.horizontal, 16).padding(.vertical, 8)
                    .background(STColor.paper)
            }
            switch state.chapterLoad {
            case .loading:
                Spacer(); ProgressView().controlSize(.small); Spacer()
            case .unavailable(let message):
                Unavailable(message: message)
            case .loaded(let content):
                ChapterText(content: content)
                    .background(STColor.paper)
            }
        }
        .physicalPaneSurface()
        .pinchToZoomTextSize($state.fontSize, in: 15...30)   // same range as the Type knob
        // A studied word belongs to the verse it was chosen in: moving to another verse drops it.
        .onChange(of: InterlinearSelection.passageID(book: state.selectedBookCode, chapter: state.selectedChapter,
                                                     verse: state.selectedVerse)) { _, passage in
            InterlinearSelection.shared.clear(unlessPassage: passage)
        }
    }
}

private struct Unavailable: View {
    @EnvironmentObject private var state: AppState
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: "book.closed").font(.system(size: 30, weight: .thin)).foregroundStyle(STColor.secondary)
            Text("This text isn't available").font(STFont.title(16))
            Text(message).font(.system(size: 12, design: .rounded)).foregroundStyle(STColor.secondary)
                .multilineTextAlignment(.center).frame(maxWidth: 340)
            HStack(spacing: 10) {
                Button("Open translation settings") { openSettings(.translations) }
                Button("Read BSB offline") { state.translationID = "BSB" }
            }
            .controlSize(.small)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

/// Scroll identity of a section-heading group (distinct from the verse row ids, which are Ints).
private struct SectionHeadingScrollID: Hashable { let verse: Int }

private struct ChapterText: View {
    @EnvironmentObject private var state: AppState
    let content: ChapterContent

    /// Extra space above a verse that starts a paragraph (whole points, so verse rows keep their sub-pixel
    /// positions). Judged from offscreen renders of BSB/WEB/KJV: reads as printed paragraphing, not as gaps.
    static let paragraphGap: CGFloat = 10

    /// The pack's headings and paragraph marks for this chapter. Only bundled/installed offline text has
    /// any, and only when the pack's verses are exactly the verses on screen. The hidden preference
    /// `showSectionHeadings` (default true) turns the whole layer (headings, parallels, paragraph spacing) off.
    private var structure: ChapterStructure? {
        guard content.origin == .offline,
              state.showSectionHeadings,
              let found = state.library.structure(translation: state.translationID, bookCode: state.selectedBookCode,
                                                  chapter: state.selectedChapter),
              found.verseNumbers == content.verses.map(\.number) else { return nil }
        return found
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    // Editorial structure (BSB headings, parallel references, paragraph starts) sits in
                    // rows of its own between verses; VerseRow itself is untouched.
                    let structure = structure
                    ForEach(Array(content.verses.enumerated()), id: \.element.id) { index, verse in
                        if let headings = structure?.headings(before: verse.number), !headings.isEmpty {
                            SectionHeadingRow(headings: headings, isFirst: index == 0)
                                .id(SectionHeadingScrollID(verse: verse.number))
                        } else if index > 0, structure?.startsParagraph(verse.number) == true, Self.paragraphGap > 0 {
                            Color.clear.frame(height: Self.paragraphGap).accessibilityHidden(true)
                        }
                        VerseRow(verse: verse).id(verse.number)
                    }
                    Attribution(content: content).padding(.top, 22)
                }
                .padding(.horizontal, state.focusMode ? 70 : 22)
                .padding(.vertical, 14)
                .frame(maxWidth: 820)
                .frame(maxWidth: .infinity)
            }
            .background(STColor.paper.opacity(0.35))
            .task(id: "\(state.selectedBookCode).\(state.selectedChapter).\(state.selectedVerse ?? 0).\(state.translationID)") {
                // A preselected verse also needs scrolling when this view first mounts (or
                // returns after an online load). Waiting lets LazyVStack register its row IDs.
                await Task.yield()
                guard !Task.isCancelled else { return }
                // A click (or word choice) in Scripture selected this verse: it is already under the
                // pointer, so leave the text where it is -- otherwise the second click of a
                // double-click would land on whatever scrolled into place.
                if let clicked = state.suppressScrollForVerse {
                    state.suppressScrollForVerse = nil
                    if clicked == state.selectedVerse { return }
                }
                if let target = scriptureScrollTarget(verses: content.verses, selected: state.selectedVerse) {
                    // A verse that opens a section scrolls to its heading so the title stays in view.
                    if let structure, !structure.headings(before: target).isEmpty {
                        proxy.scrollTo(SectionHeadingScrollID(verse: target), anchor: .top)
                    } else {
                        proxy.scrollTo(target, anchor: .top)
                    }
                }
            }
            // The "Study a word" command targets the selected verse; bring it into view so its list can open.
            .onChange(of: state.wordPickerVerse) { _, verse in
                if let verse { proxy.scrollTo(verse, anchor: .center) }
            }
            // A translation change keeps a studied word only if it still resolves to the same original word.
            .onChange(of: content) { _, new in InterlinearSelection.shared.reconcile(with: new, state: state) }
            .onAppear { InterlinearSelection.shared.reconcile(with: content, state: state) }
        }
    }
}

private struct Attribution: View {
    let content: ChapterContent

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if !content.attribution.isEmpty {
                Text(content.attribution).font(.system(size: 10, design: .rounded)).foregroundStyle(STColor.secondary)
            }
            switch content.origin {
            case .offline: EmptyView()
            case .onlineLive:
                Text("Fetched from the publisher's API for personal study; stored only within the publisher's limits.")
                    .font(.system(size: 10, design: .rounded)).foregroundStyle(STColor.secondary)
            case .onlineCached(let date):
                Text("Cached copy fetched \(date.formatted(date: .abbreviated, time: .omitted)); refreshed within the publisher's limits.")
                    .font(.system(size: 10, design: .rounded)).foregroundStyle(STColor.secondary)
            }
        }
        .padding(.leading, 34)
        .textSelection(.enabled)
    }
}

struct VerseRow: View {
    @EnvironmentObject private var state: AppState
    let verse: BibleVerse
    @State private var showWordPicker = false
    @State private var showHighlightPicker = false
    @State private var showCollectionPicker = false

    /// This row's own single-verse anchor (never the multi-verse selection) — what marks (note
    /// ribbon, highlight glyph, saved marker, MEM tick) are keyed to, so a range that covers this
    /// verse shows on it even when it isn't the range's anchor verse.
    private var verseAnchor: Anchor { Anchor(book: state.selectedBookCode, chapter: state.selectedChapter, verse: verse.number) }
    /// What a context-menu action or VoiceOver custom action on THIS row acts on: the current
    /// selection when this row is part of it (so right-clicking anywhere in an active range affects
    /// the whole range, like "Copy verse" already implied for a single selected verse), or just this
    /// verse otherwise.
    private var contextAnchor: Anchor {
        if let selection = state.selectedAnchor, selection.contains(chapter: state.selectedChapter, verse: verse.number) { return selection }
        return verseAnchor
    }
    private var isInSelection: Bool { state.selectedAnchor?.contains(chapter: state.selectedChapter, verse: verse.number) ?? false }
    private var marks: StudyItems { state.notes.items(overlapping: verseAnchor) }
    private var rowHighlight: HighlightColor? { marks.saved.compactMap(\.highlight).first }
    private var rowIsMemory: Bool { marks.saved.contains { $0.isMemory } }
    private var contextSaved: SavedPassage? { state.notes.savedPassage(matching: contextAnchor) }

    private var rowBackground: Color {
        if isInSelection { return STColor.navy.opacity(0.055) }
        if let rowHighlight { return rowHighlight.tint.opacity(0.30) }
        return .clear
    }

    private var accessibilityDescription: String {
        var parts = ["Verse \(verse.number).", verse.text]
        if !marks.saved.isEmpty { parts.append("Saved.") }
        if let rowHighlight { parts.append("Highlighted \(rowHighlight.displayName.lowercased()).") }
        if rowIsMemory { parts.append("Memory verse.") }
        if !marks.notes.isEmpty { parts.append("Has a note.") }
        return parts.joined(separator: " ")
    }

    var body: some View {
        if verse.number == 0 {
            Text(verse.text)
                .font(STFont.reading(state.fontSize * 0.82, typeface: state.scriptureTypeface)).italic()
                .foregroundStyle(STColor.secondary)
                .padding(.leading, 43).padding(.vertical, 8)
                .textSelection(.enabled)
        } else {
            Button { selectVerse() } label: {
                HStack(alignment: .firstTextBaseline, spacing: 11) {
                    Text("\(verse.number)")
                        .font(STFont.numeral(12, weight: isInSelection ? .semibold : .light)).monospacedDigit()
                        .foregroundStyle(isInSelection ? STColor.ink : STColor.secondary)
                        .frame(width: 24, alignment: .trailing)
                    Text(verse.text)
                        .font(STFont.reading(state.fontSize, typeface: state.scriptureTypeface))
                        .lineSpacing(state.lineSpacing)
                        .foregroundStyle(STColor.ink)
                        .multilineTextAlignment(.leading)
                        // Word hit-testing and the studied-word highlight live in an AppKit layer
                        // behind the text; SwiftUI still draws every glyph (see WordClickLayer.swift).
                        .background(VerseWordLayer(verse: verse))
                }
                .padding(.horizontal, 9).padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(rowBackground, in: RoundedRectangle(cornerRadius: 3))
                .overlay(alignment: .leading) {
                    if isInSelection { Rectangle().fill(STColor.navy).frame(width: 2).padding(.vertical, 5) }
                }
                .padding(.trailing, 12)
                .overlay(alignment: .topTrailing) {
                    VerseMarksBadge(hasNote: !marks.notes.isEmpty, highlight: rowHighlight,
                                    isSaved: !marks.saved.isEmpty, isMemory: rowIsMemory)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Click to select. Shift-click to extend the range. Double-click a word to study it.")
            .accessibilityLabel(accessibilityDescription)
            .accessibilityAddTraits(isInSelection ? .isSelected : [])
            .accessibilityAction(named: contextSaved != nil ? "Unsave" : "Save") {
                MyStudyActions.toggleSave(contextAnchor, in: state)
            }
            .accessibilityAction(named: "Highlight\u{2026}") { showHighlightPicker = true }
            .accessibilityAction(named: (contextSaved?.isMemory ?? false) ? "Unmark as memory verse" : "Mark as memory verse") {
                MyStudyActions.toggleMemory(contextAnchor, in: state)
            }
            .accessibilityAction(named: "Add to collection\u{2026}") { showCollectionPicker = true }
            .accessibilityAction(named: "Study a word\u{2026}") { showWordPicker = true }
            .popover(isPresented: $showWordPicker, arrowEdge: .trailing) {
                VerseWordPicker(verse: verse) { hit in
                    showWordPicker = false
                    InterlinearSelection.shared.studyWord(hit, in: verse, state: state)
                }
            }
            .popover(isPresented: $showHighlightPicker, arrowEdge: .trailing) {
                HighlightPickerView(current: contextSaved?.highlight) { color in
                    showHighlightPicker = false
                    MyStudyActions.setHighlight(color, for: contextAnchor, in: state)
                }
            }
            .popover(isPresented: $showCollectionPicker, arrowEdge: .trailing) {
                CollectionPickerView(collections: state.notes.collections, selected: Set(contextSaved?.collectionIDs ?? [])) { collection in
                    MyStudyActions.toggleCollection(collection, for: contextAnchor, in: state)
                } createNew: {
                    showCollectionPicker = false
                    guard let name = CollectionNamePrompt.ask() else { return }
                    MyStudyActions.createCollectionAndAdd(named: name, anchor: contextAnchor, in: state)
                }
            }
            .onAppear { openRequestedWordPicker() }
            .onChange(of: state.wordPickerVerse) { _, _ in openRequestedWordPicker() }
            .contextMenu {
                Button(contextSaved != nil ? "Unsave \(contextAnchor.displayString)" : "Save \(contextAnchor.displayString)") {
                    MyStudyActions.toggleSave(contextAnchor, in: state)
                }
                Menu("Highlight") {
                    ForEach(HighlightColor.allCases, id: \.self) { color in
                        Button(contextSaved?.highlight == color ? "\(color.displayName) \u{2713}" : color.displayName) {
                            MyStudyActions.setHighlight(color, for: contextAnchor, in: state)
                        }
                    }
                    Divider()
                    Button("Remove Highlight") { MyStudyActions.setHighlight(nil, for: contextAnchor, in: state) }
                        .disabled(contextSaved?.highlight == nil)
                }
                Button((contextSaved?.isMemory ?? false) ? "Unmark as Memory Verse" : "Mark as Memory Verse") {
                    MyStudyActions.toggleMemory(contextAnchor, in: state)
                }
                Menu("Add to Collection") {
                    ForEach(state.notes.collections) { collection in
                        let already = contextSaved?.collectionIDs.contains(collection.id) == true
                        Button(already ? "Remove from \(collection.name)" : "Add to \(collection.name)") {
                            MyStudyActions.toggleCollection(collection, for: contextAnchor, in: state)
                        }
                    }
                    if !state.notes.collections.isEmpty { Divider() }
                    Button("New Collection\u{2026}") {
                        guard let name = CollectionNamePrompt.ask() else { return }
                        MyStudyActions.createCollectionAndAdd(named: name, anchor: contextAnchor, in: state)
                    }
                }
                Divider()
                Button("Copy with Reference") { MyStudyActions.copyWithReference(contextAnchor, in: state) }
                if let translation = state.library.translation(id: state.translationID) {
                    ShareMenu(items: [.selection(contextAnchor)], collectionHeading: nil,
                              options: ExportOptions(translation: translation, title: contextAnchor.displayString),
                              verses: state.library.localPackVerseSource())
                }
                Divider()
                Button("Open in Study Desk") {
                    state.selectedVerse = verse.number
                    state.focusMode = false
                    state.showStudyDesk = true
                }
                Divider()
                Menu("Study a word") {
                    let tokens = WordTokenizer.tokens(in: verse.text)
                    ForEach(tokens, id: \.index) { token in
                        Button(wordChoiceTitle(token, in: tokens)) {
                            InterlinearSelection.shared.studyWord(token.asHit, in: verse, state: state)
                        }
                    }
                }
            }
        }
    }

    /// Shift-click extends the active range to this verse; a plain click selects just this verse
    /// (collapsing any active range, even a click back on the range's own anchor verse).
    private func selectVerse() {
        if NSEvent.modifierFlags.contains(.shift), let start = state.selectedVerse, start > 0, start != verse.number {
            state.extendRange(to: verse.number)
        } else {
            state.selectSingleVerse(verse.number)
        }
    }

    /// The menu command asks for the selected verse's word list; the row shows it once it exists on screen.
    private func openRequestedWordPicker() {
        guard state.wordPickerVerse == verse.number else { return }
        state.wordPickerVerse = nil
        showWordPicker = true
    }
}

/// "the (2 of 3)" when a word repeats in the verse, so the menu never lists two identical items.
func wordChoiceTitle(_ token: WordToken, in tokens: [WordToken]) -> String {
    let total = tokens.filter { $0.key == token.key }.count
    return total > 1 ? "\(token.text) (\(token.occurrence + 1) of \(total))" : token.text
}

extension WordToken {
    var asHit: WordHit { WordHit(word: text, range: range, occurrence: occurrence, tokenIndex: index, key: key) }
}

/// The AppKit layer behind one verse's text: double-click hit-testing plus the highlight for the
/// word currently open in the Study Desk. Observes only the word selection, so unrelated verses
/// don't redraw when a word is chosen.
private struct VerseWordLayer: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var selection = InterlinearSelection.shared
    let verse: BibleVerse

    var body: some View {
        let passage = InterlinearSelection.passageID(book: state.selectedBookCode, chapter: state.selectedChapter, verse: verse.number)
        WordHitLayer(text: verse.text, fontSize: state.fontSize, lineSpacing: state.lineSpacing,
                     highlight: selection.highlightRange(passage: passage, translationID: state.translationID),
                     onWord: { hit in selection.studyWord(hit, in: verse, state: state) },
                     typeface: state.scriptureTypeface)
            .accessibilityHidden(true)
    }
}

/// Pointer-free route to word study (VoiceOver custom action, menu command): every word of the
/// verse as a button, in reading order.
struct VerseWordPicker: View {
    let verse: BibleVerse
    let choose: (WordHit) -> Void

    var body: some View {
        let tokens = WordTokenizer.tokens(in: verse.text)
        VStack(alignment: .leading, spacing: 8) {
            Text("STUDY A WORD \u{00B7} VERSE \(verse.number)").legend(STColor.secondary, size: 9)
            ScrollView {
                FlowLayout(spacing: 5) {
                    ForEach(tokens, id: \.index) { token in
                        Button { choose(token.asHit) } label: {
                            Text(token.text).font(STFont.reading(14)).foregroundStyle(STColor.ink)
                                .padding(.horizontal, 7).padding(.vertical, 3)
                                .background(STColor.tileWell, in: RoundedRectangle(cornerRadius: 4))
                                .overlay(RoundedRectangle(cornerRadius: 4).stroke(STColor.keyRim, lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Study \(wordChoiceTitle(token, in: tokens))")
                    }
                }
            }
            .frame(maxHeight: 220)
            Text("Opens the word in the Study Desk with its original-language study.")
                .font(.system(size: 10.5, design: .rounded)).foregroundStyle(STColor.secondary)
        }
        .padding(12)
        .frame(width: 300)
    }
}

// MARK: - Study Desk

func scriptureScrollTarget(verses: [BibleVerse], selected: Int?) -> Int? {
    if let selected, verses.contains(where: { $0.number == selected }) { return selected }
    return verses.first?.number
}

struct StudyDesk: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VSplitView {
            if !state.detachedPanels.contains(.sources) {
                SourcesPane().frame(minHeight: 190, idealHeight: 380).physicalPaneSurface()
                .background(WorkspaceDivider(fraction: $state.notesRatio, revision: state.layoutRevision, vertical: false))
            }
            // Notes are a real, resizable aperture in the console. NOTES hides it entirely.
            if state.showNotes && !state.detachedPanels.contains(.notes) {
                NoteEditor(startsExpanded: true).frame(minHeight: 230, idealHeight: 280).physicalPaneSurface()
            }
        }
        
        // Here, not just on SourcesPane: a pinch anywhere in the Study Desk — commentary, study
        // tools, or the notes aperture below — moves the one `studyFontSize` every one of them
        // reads (Matt: "no matter where"), matching how `ScripturePane` covers the whole reading
        // pane, not just the verse text itself.
        .pinchToZoomTextSize($state.studyFontSize, in: 11...20)
    }
}

struct SourcesPane: View {
    @State private var availableHeight: CGFloat = 500
    @EnvironmentObject private var state: AppState
    @ObservedObject private var wordSelection = InterlinearSelection.shared
    private var mode: StudyDeskMode { get { state.deskMode } nonmutating set { state.deskMode = newValue } }
    
    private var guideTool: StudyDeskSection? { get { state.requestedStudyTool } nonmutating set { state.requestedStudyTool = newValue } }
    var references: ReferenceStore = .shared
    private var sources: [ResolvedSource] { state.sourcesForPassage() }
    private var passageID: String {
        InterlinearSelection.passageID(book: state.selectedBookCode, chapter: state.selectedChapter, verse: state.selectedVerse)
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach([StudyDeskMode.sources, .tools, .guide, .learn]) { choice in deskTab(choice) }
            }.padding(.horizontal, 16)
            HStack {
                Label("Linked to \(state.passage)", systemImage: "link")
                    .font(.system(size: 11)).foregroundStyle(STColor.secondary).lineLimit(1)
                Spacer(minLength: 4)
                DetachPanelButton(panel: .sources)
                if mode == .sources {
                    Menu {
                        ForEach(SourceTradition.allCases) { tradition in
                            Toggle(tradition.rawValue, isOn: Binding(
                                get: { state.selectedTraditions.contains(tradition) },
                                set: { _ in state.toggleTradition(tradition) }))
                        }
                    } label: { Image(systemName: "line.3.horizontal.decrease") }
                    .menuStyle(.borderlessButton).fixedSize().help("Choose source banks")
                    .accessibilityLabel("Choose source banks")
                }
            }.padding(.horizontal, 18).padding(.vertical, 12)
            ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    if mode == .sources || mode == .guide {
                        DownloadedPassageNotes(books: state.resourceBooks, anchor: mode == .guide ? state.guideScope.anchor(selection: state.selectedAnchor) : state.selectedAnchor)
                    }
                    if mode == .learn {
                        GuidedStudyView(study: state.study)
                    } else if mode == .guide {
                        PassageGuideView(study: state.study, references: references, scope: $state.guideScope) { destination, anchor, tool in
                            state.navigate(bookCode: anchor.book, chapter: anchor.chapterStart, verse: anchor.verseStart)
                            if let tool { state.setDeskSectionVisible(tool, true) }
                            guideTool = tool
                            mode = destination
                        }
                    } else if mode == .tools {
                        Text("TOOLS FOR \(state.passage.uppercased())")
                            .font(STFont.legend(9)).foregroundStyle(STColor.secondary).padding(12)
                        let tools = state.visibleDeskSections.filter { !$0.isSourceBank }
                        if tools.isEmpty {
                            ContentUnavailableView("Study tools are hidden", systemImage: "slider.horizontal.3",
                                description: Text("Choose the sections you want in Settings → Workspace."))
                        }
                        ForEach(tools) { section in
                            toolSection(section).id(section)
                        }
                    } else if state.selectedTraditions.isEmpty {
                        ContentUnavailableView("All source banks are off", systemImage: "switch.2",
                                               description: Text("Use the source filter above to enable commentary and cross-references."))
                    } else if sources.isEmpty {
                        ContentUnavailableView("Nothing indexed for this verse", systemImage: "text.book.closed",
                                               description: Text("The desk is locked to \(state.passage), but the enabled offline indexes hold no entry that covers it."))
                    } else {
                        PassageSourceBrowser(sources: sources, compact: availableHeight < 410)

                    }
                }
            }
            .background(STColor.tileWell.opacity(0.5))
            .onChange(of: wordSelection.requestToken) { _, _ in revealWord(proxy) }
            .onChange(of: guideTool) { _, section in
                if mode == .tools, let section { proxy.scrollTo(section, anchor: .top) }
            }
            .onChange(of: mode) { _, value in
                if value == .tools, let section = guideTool {
                    Task { @MainActor in
                        await Task.yield()
                        guard mode == .tools, guideTool == section else { return }
                        proxy.scrollTo(section, anchor: .top)
                        guideTool = nil
                    }
                }
            }
            .onAppear { revealWord(proxy) }
            }
        }
        .background {
            GeometryReader { geometry in
                Color.clear.onAppear { availableHeight = geometry.size.height }
                    .onChange(of: geometry.size.height) { _, height in availableHeight = height }
            }
        }
        // Pinch-to-zoom is attached at `StudyDesk` (this pane's container), not here, so it also
        // covers the notes aperture below Commentaries/Study tools.
    }

    private func deskTab(_ choice: StudyDeskMode) -> some View {
        let selected = mode == choice
        return Button { mode = choice } label: {
            Text(choice.rawValue).font(.system(size: 12, weight: selected ? .semibold : .regular))
                .frame(maxWidth: .infinity).frame(height: 48)
                .foregroundStyle(selected ? STColor.navy : STColor.secondary)
                .overlay(alignment: .bottom) { if selected { Rectangle().fill(STColor.navy).frame(height: 2) } }
                .contentShape(Rectangle())

        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
        .help(choice == .learn ? "Read, explore words and grammar, and save a reflection" : choice == .guide ? "Overview of a selected or entered passage" : choice == .tools
            ? "Original languages, proof texts, topics, dictionary, people and translations for the reader's verse"
            : "Commentary and cross-reference banks for the reader's verse")
    }

    @ViewBuilder private func toolSection(_ section: StudyDeskSection) -> some View {
        switch section {
        case .proofTexts: ProofTextsSection()
        case .originalLanguage: OriginalLanguageSection()
        case .topics: TopicsSection()
        case .dictionary: DictionarySection()
        case .peoplePlaces: PeoplePlacesSection()
        case .compare: CompareSection()
        default: EmptyView()
        }
    }

    private func revealWord(_ proxy: ScrollViewProxy) {
        guard wordSelection.hasFocus(for: passageID) else { return }
        let requestedPassage = passageID
        let requestToken = wordSelection.requestToken
        mode = .tools
        // Wait for the newly revealed section to enter the layout before scrolling to its word.
        Task { @MainActor in
            await Task.yield()
            guard passageID == requestedPassage, wordSelection.requestToken == requestToken else { return }
            proxy.scrollTo(StudyDeskSection.originalLanguage, anchor: .top)
            await Task.yield()
            guard passageID == requestedPassage, wordSelection.requestToken == requestToken else { return }
            if wordSelection.mode(for: requestedPassage) == .single {
                proxy.scrollTo(InterlinearSelection.cardID(passage: requestedPassage), anchor: .top)
            } else if let index = wordSelection.focusedIndex(for: requestedPassage) {
                proxy.scrollTo(InterlinearSelection.rowID(passage: requestedPassage, index: index), anchor: .top)
            }
        }
    }
}

func bankColor(_ tradition: SourceTradition) -> Color {
    switch tradition {
    case .fathers: STColor.fathers
    case .reformed: STColor.reformed
    case .exegetes: STColor.exegetes
    case .crossReferences: STColor.crossRefs
    }
}

/// The tier most entries in a bank share, so a lone differing entry (e.g. one disputed-reception
/// Father surfaced in an otherwise ordinary Fathers bank once the reader opts in) can still carry
/// its own disclaimer at the card level, while the common case renders once, at the bank header.
private func dominantTier(_ bank: [ResolvedSource]) -> ConfessionalTier? {
    guard !bank.isEmpty else { return nil }
    return ConfessionalTier.allCases.max { a, b in
        bank.filter { $0.entry.tier == a }.count < bank.filter { $0.entry.tier == b }.count
    }
}

/// Same idea for `SourceClass`, compared by label since `SourceClass` (Models.swift, frozen for
/// wave 1) doesn't declare `Equatable`.
private func dominantClassLabel(_ bank: [ResolvedSource]) -> String? {
    guard !bank.isEmpty else { return nil }
    var counts: [String: Int] = [:]
    for item in bank { counts[item.entry.sourceClass.label, default: 0] += 1 }
    return counts.max(by: { $0.value < $1.value })?.key
}

/// UI-facing tier disclaimer text. Matches `ConfessionalTier.disclaimer` except for Tier 3, whose
/// stock wording ("Research-only: …") collided with the RESEARCH workspace key and the
/// "RESEARCH ONLY" class badge appearing on screen at the same time (QA 0.6.1) — same meaning,
/// renamed copy. `ConfessionalTier` itself lives in Models.swift, frozen for wave 1, so this is a
/// presentation-layer override, not a model change.
private func displayDisclaimer(_ tier: ConfessionalTier) -> String? {
    guard tier == .tier3ResearchOnly else { return tier.disclaimer }
    return "Disputed / research-only witness: significant doctrinal controversy or departure from the confessional standard."
}

/// Same renaming for the per-card class badge (`ClassChip`). Short badges stay clear of the word
/// "RESEARCH" entirely (unlike the longer disclaimer sentence, which keeps "research-only" as a
/// descriptive compound per the must-fix's own example) — a one-or-two-word badge sitting next to
/// a RESEARCH workspace key is exactly the collision this rename exists to avoid.
private func displayClassLabel(_ sourceClass: SourceClass) -> String {
    sourceClass.label == "RESEARCH ONLY" ? "DISPUTED RECEPTION" : sourceClass.label
}

/// Groups a bank's cards by author, preserving first-appearance order, so a bank holding more
/// than one voice (Reformed carries Calvin and Matthew Henry; Exegetes carries Gill, Keil &
/// Delitzsch and Jamieson-Fausset-Brown) scans as distinct runs instead of an undifferentiated
/// list. `showsHeader` is false both when a bank has only one author (the group header would
/// just repeat the bank header's own implied single voice) and — fixed in 0.7 wave 2, E5(a) —
/// when this particular author only has a single card in the bank: the small-caps group header
/// and the card's own author-name title were repeating the same name twice in a row for exactly
/// that case, which a lone card gains nothing from.
private struct AuthorGroup {
    let author: String
    let items: [ResolvedSource]
    let showsHeader: Bool
}

private func groupedByAuthor(_ bank: [ResolvedSource]) -> [AuthorGroup] {
    var order: [String] = []
    var buckets: [String: [ResolvedSource]] = [:]
    for item in bank {
        let author = item.entry.author
        if buckets[author] == nil { order.append(author); buckets[author] = [] }
        buckets[author]!.append(item)
    }
    let multipleAuthors = order.count > 1
    return order.map { author in
        let items = buckets[author]!
        return AuthorGroup(author: author, items: items, showsHeader: multipleAuthors && items.count >= 2)
    }
}

// MARK: - Source card

struct SourceCard: View {
    let resolved: ResolvedSource
    let bookName: String
    /// The bank's dominant tier/class (see `dominantTier`/`dominantClassLabel` in `SourcesPane`).
    /// When this card's own tier or class matches, its per-card badge/disclaimer is suppressed —
    /// the bank header already said it once. `nil` (the default) always shows both, which keeps
    /// every existing call site and the snapshot-test fixtures that render a lone `SourceCard`
    /// without a surrounding bank working exactly as before.
    var bankTier: ConfessionalTier? = nil
    var expectedClassLabel: String? = nil
    var onNavigate: (CrossReference) -> Void = { _ in }
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var state: AppState
    @State private var expanded: Bool

    init(resolved: ResolvedSource, bookName: String, startExpanded: Bool = false,
         bankTier: ConfessionalTier? = nil, expectedClassLabel: String? = nil,
         onNavigate: @escaping (CrossReference) -> Void = { _ in }) {
        self.resolved = resolved
        self.bookName = bookName
        self.bankTier = bankTier
        self.expectedClassLabel = expectedClassLabel
        self.onNavigate = onNavigate
        _expanded = State(initialValue: startExpanded)
    }

    private var entry: StudySource { resolved.entry }

    /// Shown only when this card's tier differs from the bank it's in (or when rendered alone,
    /// with no bank context at all) — the common case already carries its disclaimer once, on the
    /// `DeskSectionHeader` above the whole bank (must-fix: a Tier-2 disclaimer was repeating on
    /// every single Father card).
    private var ownDisclaimer: String? {
        guard entry.tier != bankTier, let text = entry.tier.disclaimer else { return nil }
        return entry.tier == .tier3ResearchOnly
            ? "Disputed / research-only witness: significant doctrinal controversy or departure from the confessional standard."
            : text
    }

    private var rangeText: String {
        let base = entry.rangeLabel(bookName: bookName).uppercased()
        return entry.rangeBasis == .anchored ? "AT \(base)" : base
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header
            if let disclaimer = ownDisclaimer {
                DeskDisclaimer(text: disclaimer, isWarning: entry.tier == .tier3ResearchOnly)
            }
            if entry.tradition == .crossReferences, !entry.crossRefs.isEmpty {
                crossReferenceChips
            } else {
                // Commentary/study text has its own font, size and leading (0.10.2) — independent
                // of Scripture's Type/Leading knobs, per Matt's explicit request. An 0.10.1
                // stopgap briefly scaled this off the Scripture knobs; this replaces that.
                DeskExpandableText(text: entry.excerpt, expanded: $expanded,
                                   typeface: state.studyTypeface, fontSize: state.studyFontSize, lineSpacing: state.studyLineSpacing)
            }
            footer
            if expanded { details }
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
    }

    /// Cross-references render as tappable chips instead of inert text — clicking one jumps
    /// straight to that passage, the way eSword and Logos treat a cross-reference panel.
    private var crossReferenceChips: some View {
        FlowLayout(spacing: 6) {
            ForEach(entry.crossRefs) { ref in
                Button { onNavigate(ref) } label: {
                    Text(ref.label)
                        .font(.system(size: 11, weight: .medium, design: .rounded))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(STColor.tileWell, in: RoundedRectangle(cornerRadius: 4))
                .overlay(RoundedRectangle(cornerRadius: 4).stroke(STColor.keyRim, lineWidth: 1))
                .help("Go to \(ref.label)")
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.author).font(STFont.reading(15, weight: .semibold))
                Text("\(entry.work) · \(entry.era)").font(.system(size: 11, design: .rounded)).foregroundStyle(STColor.secondary)
                if entry.tradition == .fathers { FatherBentLabel(authorName: entry.author) }
                // Exegetes bank cards (E2, 0.7 wave 2): every card names its own author's
                // confessional tradition — these are received, valuable exegetes, but the whole
                // point of the bank is that none of them is confessionally Reformed, and lumping
                // a Particular Baptist, a Lutheran and a Presbyterian/Anglican together without
                // saying which is which would misrepresent all three.
                if let authorTradition = entry.authorTradition {
                    Text(authorTradition.uppercased())
                        .font(STFont.legend(8.5)).tracking(0.6)
                        .foregroundStyle(STColor.exegetes)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 4) {
                // The class badge ("RECEIVED FATHER", "REFORMED SOURCE"...) repeated the bank
                // header on every single card. Now it only shows when this card's class differs
                // from what the bank already says (e.g. a research-only card surfaced inside an
                // otherwise-ordinary bank) — or always, for the fixture/preview call sites that
                // render a lone card with no bank context.
                if expectedClassLabel == nil || displayClassLabel(entry.sourceClass) != expectedClassLabel {
                    ClassChip(entry: entry)
                }
                ForEach(resolved.confessionLinks) { WCFStamp(link: $0) }
                // Reader-selected alignment lens (0.9.5): a fact about this source against
                // whichever standard the reader picked in Settings, never an app-wide verdict.
                // `.noMapping` is the common case once a lens is on and would just repeat itself
                // on nearly every card, so it's suppressed here at the display layer — the store
                // itself still computes and tests it, this just keeps cards from filling up with
                // a gray "no mapping" tag that says nothing. `.none` (no lens) already renders
                // nothing from `AlignmentBadge` itself.
                if state.alignmentStandard != .none,
                   let alignment = state.alignment.alignment(for: entry, against: state.alignmentStandard),
                   alignment != .noMapping {
                    AlignmentBadge(result: alignment)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 7) {
            Text(rangeText).font(STFont.legend(10)).tracking(0.5).monospacedDigit().foregroundStyle(STColor.ink)
                .help(entry.rangeBasis.caption)
            Text("·").foregroundStyle(STColor.secondary)
            Text(resolved.record?.short ?? entry.source).font(.system(size: 10, design: .rounded))
                .foregroundStyle(STColor.secondary).lineLimit(1)
            Spacer(minLength: 4)
            if let url = resolved.provenanceURL {
                // Honest about what's actually being linked (0.9.5, workstream M's audit): most
                // Fathers rows carry no per-excerpt URL and fall back to the whole source
                // database, which used to read identically to a real, specific citation. A
                // database-only link is dimmer and says so, rather than overclaiming precision
                // this app doesn't have.
                let isSpecific = resolved.provenanceScope == .specificWork
                Button { openURL(url) } label: { Image(systemName: "arrow.up.right") }
                    .buttonStyle(.plain)
                    .foregroundStyle(isSpecific ? STColor.ink : STColor.secondary)
                    .help(isSpecific
                        ? "Open the source: \(url.host ?? url.absoluteString)"
                        : "No page for this specific work was found — opens the source database instead: \(url.host ?? url.absoluteString)")
                    .accessibilityLabel(isSpecific ? "Open source" : "Open source database (no page for this specific work)")
            }
            DeskMoreButton(expanded: $expanded)
        }
    }

    private var details: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 10, verticalSpacing: 5) {
            detail("SOURCE", resolved.record.map { "\($0.title) — \($0.publisher)" } ?? entry.source)
            detail("LICENSE", resolved.record?.license ?? "—")
            detail("RANGE", "\(entry.rangeLabel(bookName: bookName)). \(entry.rangeBasis.caption).")
            if let review = resolved.record?.review {
                detail("REVIEW", "\(review.state.label). \(review.note)")
            }
            if entry.truncated == true { detail("EXCERPT", "Shortened from the original; the source link has the full text.") }
            detail("KIND", entry.contentKind.label)
            detail("WCF", wcfDetail)
            detail("ID", entry.id, mono: true)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(STColor.tileWell, in: RoundedRectangle(cornerRadius: 3))
        .gridColumnAlignment(.leading)
    }

    private var wcfDetail: String {
        guard !resolved.confessionLinks.isEmpty else {
            return "No reviewed Westminster link. Being a Reformed source is not a link."
        }
        return resolved.confessionLinks.map { link in
            var line = "\(link.wcf.label), \(link.relation.rawValue). Reviewed by \(link.reviewer ?? "—") on \(link.reviewedOn ?? "—")."
            if let note = link.note, !note.isEmpty { line += " \(note)" }
            return line
        }.joined(separator: "\n")
    }

    private func detail(_ label: String, _ value: String, mono: Bool = false) -> some View {
        GridRow(alignment: .firstTextBaseline) {
            Text(label).legend(STColor.secondary, size: 8.5).frame(width: 52, alignment: .leading)
            Text(value)
                .font(mono ? STFont.lcd(10) : .system(size: 11, design: .rounded))
                .foregroundStyle(STColor.ink)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// Per-card tier disclaimer is `DeskDisclaimer` (`DeskComponents.swift`) now, rendered only when
// `SourceCard.ownDisclaimer` says this card differs from its bank's dominant tier — the bank
// header (`DeskSectionHeader`) already carries the common-case disclaimer once.

private struct ClassChip: View {
    let entry: StudySource

    var body: some View {
        HStack(spacing: 5) {
            Rectangle().fill(bankColor(entry.tradition)).frame(width: 6, height: 6)
            Text(displayClassLabel(entry.sourceClass)).legend(STColor.ink, size: 8.5)
        }
        .padding(.horizontal, 6).padding(.vertical, 3)
        .overlay(RoundedRectangle(cornerRadius: 2).stroke(STColor.keyRim, lineWidth: 1))
    }
}

/// A human-reviewed Westminster link. Black LCD stamp: visibly unlike any source-class chip.
private struct WCFStamp: View {
    let link: ConfessionLink

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(STColor.orange).frame(width: 5, height: 5)
            Text(link.wcf.label).font(STFont.lcd(10, weight: .medium)).monospacedDigit()
        }
        .foregroundStyle(STColor.lcdInk)
        .padding(.horizontal, 7).padding(.vertical, 3)
        .background(STColor.lcd, in: RoundedRectangle(cornerRadius: 2))
        .help("Reviewed link: \(link.relation.rawValue) \(link.wcf.label). Reviewer: \(link.reviewer ?? "—"), \(link.reviewedOn ?? "—").")
        .accessibilityLabel("Reviewed Westminster link, \(link.wcf.label), \(link.relation.rawValue)")
    }
}
