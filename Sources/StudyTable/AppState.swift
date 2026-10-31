import SwiftUI
import StudyTableCore

/// What the Scripture pane is showing for the selected chapter.
struct ChapterContent: Equatable {
    enum Origin: Equatable {
        case offline
        case onlineLive
        case onlineCached(Date)
    }
    var verses: [BibleVerse]
    var origin: Origin
    var attribution: String
}

enum ChapterLoad: Equatable {
    case loading
    case loaded(ChapterContent)
    case unavailable(String)
}

/// Retained until the notebook mounts, including when it was hidden during navigation.
struct StudyNoteOpenRequest: Equatable {
    let noteID: UUID
    let token = UUID()
}

@MainActor
final class AppState: ObservableObject {
    @Published var palette = WorkspacePalette.standard {
        didSet {
            if let data = try? JSONEncoder().encode(palette) {
                defaults.set(data, forKey: WorkspacePalette.preferenceKey)
            }
            PaletteRuntime.shared.apply(palette)
        }
    }
    @AppStorage("theme") private var storedTheme = AppTheme.system.rawValue
    @AppStorage("showLibrary") var showLibrary = true
    @AppStorage("showStudyDesk") var showStudyDesk = true
    @AppStorage("showNotes") var showNotes = true
    @AppStorage("hasSeenIntro") var hasSeenIntro = false
    @AppStorage("fontSize") var fontSize = 20.0
    @AppStorage("lineSpacing") var lineSpacing = 8.0
    /// Tier 3 (research-only) sources are off by default; see ConfessionalTier.tier3ResearchOnly.
    @AppStorage("showResearchTier") var showResearchTier = false
    /// Which confessional standard, if any, governs the alignment language `AlignmentBadge` shows
    /// on source cards -- independent of `selectedTraditions` (which authors/traditions are
    /// visible at all). Backed like `theme` below: a private AppStorage-held raw string plus a
    /// typed computed wrapper, so it stays on the same injectable `defaults` suite every other
    /// preference here uses (tests must never touch the reader's real choice of lens).
    @AppStorage("alignmentStandard") private var storedAlignmentStandard = AlignmentStandard.none.rawValue
    @AppStorage("showSectionHeadings") private var storedShowSectionHeadings = true
    /// Scripture's chosen reading face. Only Type/Leading remain physical knobs (size/leading);
    /// the typeface itself is a Settings choice, per Matt's 2026-09-27 request. Backed the same
    /// tolerant way as `alignmentStandard`: a raw-string `@AppStorage` plus a typed wrapper that
    /// falls back to `.baskerville` (today's shipped face) for a garbage/future stored value.
    @AppStorage("scriptureTypeface") private var storedScriptureTypeface = ReadingTypeface.baskerville.rawValue
    /// Commentary/study text's own reading face and size/leading — independent of Scripture's,
    /// per Matt's explicit "commentary should have its own separate font controls." Not knobs:
    /// plain Settings controls, since only Type/Leading are physical rotary controls.
    @AppStorage("studyTypeface") private var storedStudyTypeface = ReadingTypeface.baskerville.rawValue
    @AppStorage("studyFontSize") var studyFontSize = 13.5
    @AppStorage("studyLineSpacing") var studyLineSpacing = 3.0
    /// Reopen the separate Bible, Sources and Notes windows that were open at quit.
    @AppStorage("reopenDetachedWindows") var reopenDetachedWindows = true

    @Published var selectedBookCode = "JHN" {
        didSet {
            // Guarded the same way as selectedChapter: a multi-property `navigate {}` batch (a
            // cross-reference or a book+chapter jump) sets both properties, and without this guard
            // this didSet would recurse into its own nested navigate() call mid-batch.
            if oldValue != selectedBookCode { rangeEndVerse = nil }
            guard !navigating, oldValue != selectedBookCode else { return }
            navigate { selectedChapter = 1 }
        }
    }
    @Published var selectedChapter = 1 {
        didSet {
            if oldValue != selectedChapter { rangeEndVerse = nil }
            guard !navigating, oldValue != selectedChapter else { return }
            selectedVerse = 1
            reloadChapter()
        }
    }
    @Published var selectedVerse: Int? = 1 {
        didSet { if oldValue != selectedVerse { rangeEndVerse = nil } }
    }
    /// Last verse of a range selection that starts at `selectedVerse`, in the same chapter.
    /// `nil` means a single-verse selection. Cleared whenever the selected verse, chapter or book
    /// changes through ordinary navigation; range-extending UI sets it after positioning
    /// `selectedVerse`.
    @Published var rangeEndVerse: Int?

    /// The current selection as a study `Anchor` (a single verse, or a range when
    /// `rangeEndVerse` is set). `nil` when no verse is selected. A chapter-only selection
    /// (`selectedVerse <= 0`, the app's "no specific verse" sentinel) anchors the whole chapter.
    var selectedAnchor: Anchor? {
        guard let verse = selectedVerse else { return nil }
        guard verse > 0 else { return Anchor(book: selectedBookCode, chapter: selectedChapter) }
        if let end = rangeEndVerse, end != verse {
            return Anchor(book: selectedBookCode, chapter: selectedChapter, verses: verse, to: end)
        }
        return Anchor(book: selectedBookCode, chapter: selectedChapter, verse: verse)
    }
    @Published var translationID: String = "BSB" {
        didSet {
            guard oldValue != translationID else { return }
            defaults.set(translationID, forKey: "translation")
            reloadChapter()
        }
    }
    @Published var selectedTraditions = Set(SourceTradition.allCases) {
        didSet { defaults.set(selectedTraditions.map(\.rawValue).sorted(), forKey: "desk.sourceBanks") }
    }
    @Published var deskSectionOrder = StudyDeskSection.allCases {
        didSet { defaults.set(deskSectionOrder.map(\.rawValue), forKey: "desk.sectionOrder") }
    }
    @Published var hiddenDeskSections: Set<StudyDeskSection> = [] {
        didSet { defaults.set(hiddenDeskSections.map(\.rawValue).sorted(), forKey: "desk.hiddenSections") }
    }
    @Published var focusMode = false
    /// The dedicated search workspace keeps book navigation available in the Library.
    @Published var showBibleSearch = false
    @Published var requestedStudyTool: StudyDeskSection?
    @Published var requestedStudyNote: StudyNoteOpenRequest?
    @Published var detachedPanels = Set<DetachedPanel>()
    /// A request to open the Library window's reader at a book, section and paragraph.
    @Published var libraryRequest: LibraryFocus?
    /// Opens the Library window at a destination (Fathers & reception opens at Ideas).
    @Published var libraryDestinationRequest: LibraryDestination?
    /// False until the workspace scene exists; window recipes wait until then.
    var windowsReady = false
    var pendingWindowRecipes: [DetachedWindowRecipe]?
    let notebook: NotebookSession
    lazy var detachedWindows = DetachedWindowManager(state: self)
    /// Scene-backed action forwarded to AppKit-hosted panes, whose default openWindow
    /// environment does not belong to the main SwiftUI scene.
    var openSceneWindow: ((String) -> Void)?

    var hasDockedStudyDesk: Bool {
        showStudyDesk && (!detachedPanels.contains(.sources) || (showNotes && !detachedPanels.contains(.notes)))
    }
    @Published var deskMode: StudyDeskMode = .sources
    @Published var guideScope = PassageGuideScope()
    @Published var sourcesOnLeft = false
    @Published var readingRatio = 0.60
    @Published var notesRatio = 0.65
    @Published var layoutRevision = UUID()
    @Published var activeLayoutID: UUID?
    let layouts: LayoutLibrary
    let updater: AppUpdater
    let resourceBooks: ResourceBookLibrary

    /// Set just before Scripture itself changes the selected verse (a click, or choosing a word):
    /// the verse is already on screen under the pointer, so the reader must not scroll it away. This
    /// is what keeps the second click of a double-click on the word the reader meant.
    var suppressScrollForVerse: Int?
    /// A verse whose "Study a word" list should open (menu command / VoiceOver route).
    @Published var wordPickerVerse: Int?

    /// Opens the word list for the selected verse (the keyboard route to word study).
    func requestWordPicker() {
        guard let selectedVerse, selectedVerse > 0 else { return }
        wordPickerVerse = selectedVerse
    }

    // MARK: Range selection (0.10, S2a)

    /// A plain click on a verse: selects exactly it, clearing any active range — even when the
    /// clicked verse is already the range's anchor (`selectedVerse`'s own `didSet` only clears
    /// `rangeEndVerse` when the value actually changes, so clicking the anchor again would
    /// otherwise leave a stale range in place).
    func selectSingleVerse(_ verse: Int) {
        suppressScrollForVerse = verse
        if selectedVerse != verse { selectedVerse = verse }
        else if rangeEndVerse != nil { rangeEndVerse = nil }
    }

    /// Shift-click (or the section "Select section" affordance) a verse: extends the active
    /// selection so it now ends at `verse`, keeping `selectedVerse` as the anchor. Collapses back
    /// to a single verse when `verse` lands back on the anchor. No-op with no verse selected.
    func extendRange(to verse: Int) {
        guard let start = selectedVerse, start > 0 else { return }
        suppressScrollForVerse = verse
        rangeEndVerse = verse == start ? nil : verse
    }

    /// ⇧↑ / ⇧↓ from the "My Study" menu: extends the range's far end by one verse (growing away
    /// from the anchor, or shrinking back toward it), clamped to the chapter. No-op with nothing
    /// selected or at the chapter boundary.
    func extendSelection(by delta: Int) {
        guard let start = selectedVerse, start > 0 else { return }
        let currentEnd = rangeEndVerse ?? start
        let next = currentEnd + delta
        guard (1...max(verseCount, 1)).contains(next) else { return }
        rangeEndVerse = next == start ? nil : next
    }

    /// The pericope (section/subsection) containing the current selection's anchor verse, if any —
    /// the target of the "Select Section" command and menu items.
    func currentSection() -> Pericope? {
        guard let verse = selectedVerse, verse > 0 else { return nil }
        return library.pericope(containing: selectedChapter, verse: verse, bookCode: selectedBookCode, translation: translationID)
    }

    /// Selects a whole pericope as a range, anchored at its first verse. A pericope's own span can
    /// cross a chapter boundary (e.g. Romans 8:31–9:5); `rangeEndVerse` is deliberately a
    /// same-chapter offset only (range-aware desk aggregation across chapters is a later wave), so a
    /// cross-chapter section selects from its start through the end of ITS OWN starting chapter —
    /// the closest in-model approximation — rather than silently doing nothing.
    func selectSection(_ pericope: Pericope) {
        guard pericope.bookCode == selectedBookCode || library.books.contains(where: { $0.code == pericope.bookCode }) else { return }
        let startVerse = max(pericope.startVerse, 1)
        if pericope.bookCode != selectedBookCode || selectedChapter != pericope.startChapter {
            navigate(bookCode: pericope.bookCode, chapter: pericope.startChapter, verse: startVerse)
        } else {
            selectSingleVerse(startVerse)
        }
        if pericope.endChapter == pericope.startChapter {
            let end = pericope.endVerse >= Anchor.endOfChapter ? verseCount : pericope.endVerse
            if end > startVerse { rangeEndVerse = end }
        } else if verseCount > startVerse {
            rangeEndVerse = verseCount
        }
    }

    /// Console keys reveal their panel when Focus temporarily hides it, then act as toggles.
    func toggleConsoleLibrary() {
        if focusMode { focusMode = false; showLibrary = true }
        else { showLibrary.toggle() }
    }

    func toggleConsoleNotes() {
        if focusMode || !showStudyDesk { focusMode = false; showStudyDesk = true; showNotes = true }
        else { showNotes.toggle() }
    }

    func toggleConsoleSources() {
        if focusMode { focusMode = false; showStudyDesk = true }
        else { showStudyDesk.toggle() }
    }
    @Published var activePreset: LayoutPreset = .study
    @Published private(set) var chapterLoad: ChapterLoad = .loading
    @Published private(set) var configuredKeys: Set<OnlineProvider> = []

    let library: ScriptureLibrary
    /// The reader's own study data. `notes` is the pre-0.10 name (kept so existing call sites compile).
    let notes: StudyStore
    var study: StudyStore { notes }
    let studyResources: StudyResourceStore
    let online: OnlineTranslationService
    let alignment: AlignmentStore

    private let defaults: UserDefaults
    var preferenceStore: UserDefaults { defaults }
    private var navigating = false
    private var loadGeneration = 0

    /// `defaults` holds only the remembered translation, and `notes` only its storage
    /// directory — both default to the real user data but are injectable so tests never touch
    /// the user's real preferences or real notes file.
    init(library: ScriptureLibrary = ScriptureLibrary(),
         studyResources: StudyResourceStore = StudyResourceStore(),
         online: OnlineTranslationService = OnlineTranslationService(),
         defaults: UserDefaults = .standard,
         notes: StudyStore = StudyStore(),
         alignment: AlignmentStore = AlignmentStore(),
         resourceBooks: ResourceBookLibrary? = nil) {
        self.library = library
        self.studyResources = studyResources
        self.online = online
        self.defaults = defaults
        self.palette = WorkspacePalette.load(from: defaults)
        self.layouts = LayoutLibrary(defaults: defaults)
        self.updater = AppUpdater(defaults: defaults)
        self.resourceBooks = resourceBooks ?? ResourceBookLibrary()
        self.resourceBooks.searchRoots = (studyResources.searchDirectory, AppResources.supportDirectory.appendingPathComponent("PuritanLibrary"))
        self.notes = notes
        self.notebook = NotebookSession(store: notes)
        self.alignment = alignment
        // Every preference uses the injectable suite, not just the remembered translation.
        // Offscreen previews and regression tests must never alter a reader's real workspace.
        _storedTheme = AppStorage(wrappedValue: AppTheme.system.rawValue, "theme", store: defaults)
        _showLibrary = AppStorage(wrappedValue: true, "showLibrary", store: defaults)
        _showStudyDesk = AppStorage(wrappedValue: true, "showStudyDesk", store: defaults)
        _showNotes = AppStorage(wrappedValue: true, "showNotes", store: defaults)
        _hasSeenIntro = AppStorage(wrappedValue: false, "hasSeenIntro", store: defaults)
        _fontSize = AppStorage(wrappedValue: 20.0, "fontSize", store: defaults)
        _lineSpacing = AppStorage(wrappedValue: 8.0, "lineSpacing", store: defaults)
        _showResearchTier = AppStorage(wrappedValue: false, "showResearchTier", store: defaults)
        _storedAlignmentStandard = AppStorage(wrappedValue: AlignmentStandard.none.rawValue, "alignmentStandard", store: defaults)
        _storedShowSectionHeadings = AppStorage(wrappedValue: true, "showSectionHeadings", store: defaults)
        _storedScriptureTypeface = AppStorage(wrappedValue: ReadingTypeface.baskerville.rawValue, "scriptureTypeface", store: defaults)
        _storedStudyTypeface = AppStorage(wrappedValue: ReadingTypeface.baskerville.rawValue, "studyTypeface", store: defaults)
        _studyFontSize = AppStorage(wrappedValue: 13.5, "studyFontSize", store: defaults)
        _studyLineSpacing = AppStorage(wrappedValue: 3.0, "studyLineSpacing", store: defaults)
        _reopenDetachedWindows = AppStorage(wrappedValue: true, "reopenDetachedWindows", store: defaults)
        deskSectionOrder = StudyDeskSection.normalizedOrder(defaults.stringArray(forKey: "desk.sectionOrder") ?? [])
        hiddenDeskSections = Set((defaults.stringArray(forKey: "desk.hiddenSections") ?? [])
            .compactMap(StudyDeskSection.init(rawValue:)).filter { !$0.isSourceBank })
        if let savedBanks = defaults.stringArray(forKey: "desk.sourceBanks") {
            selectedTraditions = Set(savedBanks.compactMap(SourceTradition.init(rawValue:)))
        }
        let remembered = defaults.string(forKey: "translation") ?? "BSB"
        translationID = library.translation(id: remembered) == nil ? "BSB" : remembered
        PaletteRuntime.shared.apply(palette)
        refreshKeyStatus()
        reloadChapter()
        Task { await online.cache.purgeExpired() }
        if let id = layouts.startup, let layout = layouts.layouts.first(where: { $0.id == id }) { openLayout(layout) }
    }

    // MARK: Derived state

    var theme: AppTheme {
        get { AppTheme(rawValue: storedTheme) ?? .system }
        set { objectWillChange.send(); storedTheme = newValue.rawValue }
    }
    var colorScheme: ColorScheme? {
        switch theme { case .system: return nil; case .light: return .light; case .dark: return .dark }
    }
    /// The direct deck key switches from the finish currently on screen. This also
    /// handles System mode without guessing the user's macOS appearance setting.
    func switchAppearance(from currentScheme: ColorScheme) {
        theme = currentScheme == .dark ? .light : .dark
    }
    /// The reader's chosen alignment lens. Defaults to `.none` -- per the 2026-09-24 decision,
    /// Thruline does not ship with a fixed confessional identity, so no lens is the shipped
    /// default rather than defaulting to Westminster Standards. See the workstream report for
    /// the reasoning and for flagging this as a default worth Matt confirming directly.
    var alignmentStandard: AlignmentStandard {
        get { AlignmentStandard(rawValue: storedAlignmentStandard) ?? .none }
        set { objectWillChange.send(); storedAlignmentStandard = newValue.rawValue }
    }
    /// Whether the reader shows the Berean text's section headings, "See also" parallel links and
    /// paragraph spacing (0.10, R3). Lives here — not as a view-level `@AppStorage` — so it reads the
    /// app's injected preference store in both the app and the tests, and redraws the reader when
    /// flipped in Settings.
    var showSectionHeadings: Bool {
        get { storedShowSectionHeadings }
        set { objectWillChange.send(); storedShowSectionHeadings = newValue }
    }
    /// The face `VerseRow`'s Scripture text (and its word-click hit-test layer) both draw in.
    var scriptureTypeface: ReadingTypeface {
        get { ReadingTypeface(rawValue: storedScriptureTypeface) ?? .baskerville }
        set { objectWillChange.send(); storedScriptureTypeface = newValue.rawValue }
    }
    /// The face commentary/study text (`SourceCard`'s excerpt, reference articles) draws in —
    /// independent of `scriptureTypeface`.
    var studyTypeface: ReadingTypeface {
        get { ReadingTypeface(rawValue: storedStudyTypeface) ?? .baskerville }
        set { objectWillChange.send(); storedStudyTypeface = newValue.rawValue }
    }
    var translation: TranslationInfo? { library.translation(id: translationID) }
    var book: BookSummary? { library.summary(code: selectedBookCode) }
    var bookName: String { book?.name ?? "John" }
    /// The status display's readout: "Romans 8:28", "Romans 8:28–39" for an active range selection,
    /// or "Romans 8" for a chapter-only selection — all via `selectedAnchor.displayString` (0.10, S2a),
    /// which also gives Psalms its singular "Psalm N" form. Falls back to the old plain formatting
    /// only when nothing at all is selected (`selectedVerse == nil`, not used in the shipped app).
    var passage: String {
        if let anchor = selectedAnchor { return anchor.displayString }
        return "\(bookName) \(selectedChapter)"
    }
    /// Verses in the chapter as the *selected translation* has them (translations differ:
    /// e.g. the KJV keeps verses the BSB omits), falling back to the reference book table.
    var verseCount: Int {
        if case .loaded(let content) = chapterLoad, let last = content.verses.map(\.number).max(), last > 0 { return last }
        return book?.verseCount(chapter: selectedChapter) ?? 0
    }

    // MARK: Navigation

    private func navigate(_ change: () -> Void) {
        navigating = true
        change()
        navigating = false
        rangeEndVerse = nil
        selectedVerse = 1
        reloadChapter()
    }

    /// Jump straight to a passage from search, a cross-reference, or a note. Always lands with
    /// the destination pane visible (Library/Study Desk stay as they are; the navigation itself
    /// is what matters, not which panes happen to be open).
    ///
    /// Clamps chapter to the book's own range and an out-of-range verse down to the chapter's
    /// last verse, rather than leaving a nonexistent selection on screen -- some callers (e.g. a
    /// confession's own printed proof texts, which occasionally cite a verse an old print run got
    /// wrong) can hand this a target that doesn't exist in the bundled canon. `verse <= 0` is left
    /// alone: that's the existing "no specific verse, just the chapter" sentinel used throughout
    /// the app (see `LCDDisplay`'s `verse > 0` checks), not an out-of-range value to correct.
    @Published private(set) var passageHistory: [String] = []
    private var restoringPassage = false

    func returnToPreviousPassage() {
        guard let previous = passageHistory.popLast() else { return }
        restoringPassage = true
        navigate(toStoredPassage: previous)
        restoringPassage = false
    }

    @discardableResult
    func jumpToReference(_ input: String) -> Bool {
        guard let anchor = Anchor.parse(input), anchor.chapterStart == anchor.chapterEnd,
              let book = library.summary(code: anchor.book) else { return false }
        let chapter = anchor.chapterStart
        guard (1...book.chapterCount).contains(chapter) else { return false }
        let text = library.chapter(translation: translationID, bookCode: anchor.book, chapter: chapter)
            ?? library.chapter(translation: "BSB", bookCode: anchor.book, chapter: chapter)
        guard let text else { return false }
        let numbers = Set(text.filter { $0.number > 0 }.map(\.number))
        let first = anchor.verseStart == 0 ? (numbers.min() ?? 1) : anchor.verseStart
        guard numbers.contains(first),
              anchor.verseEnd == Anchor.endOfChapter || numbers.contains(anchor.verseEnd) else { return false }
        navigate(bookCode: anchor.book, chapter: chapter, verse: first)
        if anchor.verseEnd != Anchor.endOfChapter, anchor.verseEnd > first {
            rangeEndVerse = anchor.verseEnd
        }
        return true
    }

    @discardableResult
    func openStudyNote(_ id: UUID) -> Bool {
        guard let note = study.note(id: id), let anchor = note.anchors.first else { return false }
        let start = anchor.startVerse
        navigate(bookCode: anchor.book, chapter: start.chapter, verse: start.verse)
        focusMode = false
        showStudyDesk = true
        showNotes = true
        requestedStudyNote = StudyNoteOpenRequest(noteID: id)
        if detachedPanels.contains(.notes) { detachedWindows.focus(.notes) }
        return true
    }

    func navigate(bookCode: String, chapter: Int, verse: Int) {
        if !restoringPassage, library.books.contains(where: { $0.code == bookCode }),
           bookCode != selectedBookCode || chapter != selectedChapter || verse != selectedVerse {
            passageHistory.append(passage)
            if passageHistory.count > 50 { passageHistory.removeFirst() }
        }
        guard let book = library.books.first(where: { $0.code == bookCode }) else {
            // Unknown book code: nothing in the canon to clamp against, so fall back to the prior
            // unclamped behavior rather than silently discarding the navigation.
            navigate { selectedBookCode = bookCode; selectedChapter = chapter }
            selectedVerse = verse
            return
        }
        let clampedChapter = min(max(chapter, 1), max(book.chapterCount, 1))
        navigate {
            selectedBookCode = bookCode
            selectedChapter = clampedChapter
        }
        guard verse > 0 else {
            selectedVerse = verse
            return
        }
        // A manifest stores counts, not the largest verse identifier: omitted verse numbers
        // make these differ (e.g. BSB Romans 16 has 26 verses ending at verse 27).
        let target = library.chapter(translation: translationID, bookCode: bookCode, chapter: clampedChapter)
            ?? library.chapter(translation: "BSB", bookCode: bookCode, chapter: clampedChapter)
        let lastVerse = target?.map(\.number).max() ?? book.verseCount(chapter: clampedChapter)
        selectedVerse = lastVerse > 0 ? min(verse, lastVerse) : verse
    }

    /// Shows a cited passage, keeping a same-chapter verse range selected.
    func openPassage(_ anchor: Anchor) {
        navigate(bookCode: anchor.book, chapter: anchor.chapterStart, verse: max(1, anchor.verseStart))
        if anchor.chapterStart == anchor.chapterEnd, anchor.verseEnd != Anchor.endOfChapter,
           anchor.verseEnd > anchor.verseStart, anchor.verseEnd <= verseCount { rangeEndVerse = anchor.verseEnd }
    }

    /// Parses a stored passage string ("Genesis 1:1", "Song of Solomon 2:1") back into a
    /// navigation target. Used by the notes browser, which only stores the display string.
    func navigate(toStoredPassage passage: String) {
        // Ranges ("Romans 8:28–39", "Romans 8:39–9:5"), abbreviations and "Psalm"/"Psalms" all
        // resolve through `Anchor`; a range lands on its first verse.
        if let anchor = Anchor.parse(passage) {
            let start = anchor.startVerse
            navigate(bookCode: anchor.book, chapter: start.chapter, verse: start.verse)
            return
        }
        guard let book = library.books.first(where: { passage.hasPrefix($0.name + " ") || passage == $0.name }) else { return }
        let remainder = passage.dropFirst(book.name.count).trimmingCharacters(in: .whitespaces)
        let parts = remainder.split(separator: ":")
        let chapter = parts.first.flatMap { Int($0) } ?? 1
        let verse = parts.count > 1 ? (Int(parts[1]) ?? 1) : 1
        navigate(bookCode: book.code, chapter: chapter, verse: verse)
    }

    func stepChapter(_ delta: Int) {
        guard let book else { return }
        let next = selectedChapter + delta
        if book.chapterNumbers.contains(next) {
            selectedChapter = next
        } else if let index = library.books.firstIndex(where: { $0.code == selectedBookCode }) {
            let target = index + (delta > 0 ? 1 : -1)
            guard library.books.indices.contains(target) else { return }
            let destination = library.books[target]
            navigate {
                selectedBookCode = destination.code
                selectedChapter = delta > 0 ? 1 : destination.chapterCount
            }
        }
    }

    func applyPreset(_ preset: LayoutPreset) {
        activePreset = preset
        activeLayoutID = nil
        sourcesOnLeft = false
        readingRatio = 0.60; notesRatio = 0.65; layoutRevision = UUID()
        deskMode = preset == .research ? .tools : .sources
        guideScope.followSelection()
        focusMode = false
        switch preset {
        case .reading: showLibrary = false; showStudyDesk = false; showNotes = false
        case .study: showLibrary = true; showStudyDesk = true; showNotes = true
        case .research: showLibrary = true; showStudyDesk = true; showNotes = false
        }
    }

    // MARK: Scripture loading

    func reloadChapter() {
        loadGeneration += 1
        let generation = loadGeneration
        guard let info = translation else { chapterLoad = .unavailable("Unknown translation."); return }
        switch info.delivery {
        case .bundled, .installedPack:
            if let verses = library.chapter(translation: info.id, bookCode: selectedBookCode, chapter: selectedChapter) {
                chapterLoad = .loaded(ChapterContent(verses: verses, origin: .offline, attribution: info.attribution))
            } else {
                chapterLoad = .unavailable("This chapter is missing from the \(info.id) pack.")
            }
        case .licensePackRequired:
            chapterLoad = .unavailable("\(info.id) needs a licensed offline pack. Install one in the Translations folder (Settings › Translations).")
        case .online(let kind):
            chapterLoad = .loading
            let code = selectedBookCode, name = bookName, chapter = selectedChapter, id = info.id
            let service = online
            Task {
                let outcome = await service.load(kind: kind, translationID: id, bookCode: code, bookName: name, chapter: chapter)
                guard generation == self.loadGeneration else { return }
                switch outcome {
                case .verses(let verses, let attribution, let origin):
                    self.chapterLoad = .loaded(ChapterContent(
                        verses: verses,
                        origin: { if case .cached(let date) = origin { return .onlineCached(date) } else { return .onlineLive } }(),
                        attribution: attribution))
                case .failure(let message):
                    self.chapterLoad = .unavailable(message)
                }
            }
        }
    }

    // MARK: Online keys

    func refreshKeyStatus() {
        configuredKeys = Set(OnlineProvider.allCases.filter { KeychainStore.read($0) != nil })
    }

    func saveKey(_ key: String, for provider: OnlineProvider) {
        let trimmed = key.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { KeychainStore.remove(provider) } else { KeychainStore.save(trimmed, for: provider) }
        refreshKeyStatus()
        reloadChapter()
    }

    func rescanTranslations() {
        library.rescan()
        if library.translation(id: translationID) == nil { translationID = "BSB" }
        reloadChapter()
    }

    // MARK: Study sources

    var visibleDeskSections: [StudyDeskSection] { deskSectionOrder.filter(isDeskSectionVisible) }

    func isDeskSectionVisible(_ section: StudyDeskSection) -> Bool {
        if let tradition = section.tradition { return selectedTraditions.contains(tradition) }
        return !hiddenDeskSections.contains(section)
    }

    func setDeskSectionVisible(_ section: StudyDeskSection, _ visible: Bool) {
        if let tradition = section.tradition {
            if visible { selectedTraditions.insert(tradition) } else { selectedTraditions.remove(tradition) }
        } else {
            if visible { hiddenDeskSections.remove(section) } else { hiddenDeskSections.insert(section) }
        }
    }

    func moveDeskSection(_ section: StudyDeskSection, by offset: Int) {
        let group = deskSectionOrder.filter { $0.isSourceBank == section.isSourceBank }
        guard let index = group.firstIndex(of: section), group.indices.contains(index + offset),
              let source = deskSectionOrder.firstIndex(of: section),
              let target = deskSectionOrder.firstIndex(of: group[index + offset]) else { return }
        deskSectionOrder.swapAt(source, target)
    }

    func resetDeskCustomization() {
        deskSectionOrder = StudyDeskSection.allCases
        hiddenDeskSections = []
        selectedTraditions = Set(SourceTradition.allCases)
    }

    func sourcesForPassage() -> [ResolvedSource] {
        guard let selectedVerse, selectedVerse > 0, book != nil else { return [] }
        return studyResources.sources(bookCode: selectedBookCode, bookName: bookName, chapter: selectedChapter,
                                      verse: selectedVerse, includeResearchTier: showResearchTier)
            .filter { selectedTraditions.contains($0.entry.tradition) }
    }

    func toggleTradition(_ tradition: SourceTradition) {
        if selectedTraditions.contains(tradition) { selectedTraditions.remove(tradition) }
        else { selectedTraditions.insert(tradition) }
    }
}
