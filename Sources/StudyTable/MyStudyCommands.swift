import SwiftUI
import AppKit

// MARK: - Announcer

/// Posts a VoiceOver announcement for an action a click, menu command or accessibility action
/// just performed ("Saved Romans 8:28"). AppKit's app-wide announcement notification, rather than
/// SwiftUI's iOS-first `AccessibilityNotification.Announcement`, is the reliable macOS route.
enum Announcer {
    @MainActor static func post(_ message: String) {
        NSAccessibility.post(element: NSApp as Any, notification: .announcementRequested,
                             userInfo: [.announcement: message, .priority: NSAccessibilityPriorityLevel.medium.rawValue])
    }
}

// MARK: - New Collection prompt

/// A minimal modal text prompt (`NSAlert` + an accessory field) for naming a new collection —
/// used identically from the verse context menu, the "My Study" menu, and the Library's Saved mode.
enum CollectionNamePrompt {
    @MainActor static func ask(defaultName: String = "") -> String? {
        let alert = NSAlert()
        alert.messageText = "New Collection"
        alert.informativeText = "Name this collection of saved passages."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultName
        field.placeholderString = "Collection name"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }
}

// MARK: - Shared actions
//
// Every save/highlight/memory/collection mutation a verse's context menu, its VoiceOver custom
// actions, and the app-wide "My Study" menu can perform, in one place, so the three call sites
// stay in lockstep and each mutation announces itself the same way regardless of which one fired it.
enum MyStudyActions {
    @MainActor @discardableResult
    static func toggleSave(_ anchor: Anchor, in state: AppState) -> Bool {
        let saved = state.notes.toggleSaved(anchor)
        Announcer.post(saved ? "Saved \(anchor.displayString)" : "Unsaved \(anchor.displayString)")
        return saved
    }

    @MainActor static func setHighlight(_ color: HighlightColor?, for anchor: Anchor, in state: AppState) {
        guard let saved = state.notes.save(anchor) else { return }
        state.notes.setHighlight(saved.id, color)
        Announcer.post(color != nil ? "Highlighted \(anchor.displayString) \(color!.displayName.lowercased())"
                                    : "Highlight removed from \(anchor.displayString)")
    }

    @MainActor static func toggleMemory(_ anchor: Anchor, in state: AppState) {
        guard let saved = state.notes.save(anchor) else { return }
        let newValue = !saved.isMemory
        state.notes.setMemory(saved.id, newValue)
        Announcer.post(newValue ? "Marked \(anchor.displayString) as a memory verse"
                                : "Unmarked \(anchor.displayString) as a memory verse")
    }

    @MainActor static func toggleCollection(_ collection: StudyCollection, for anchor: Anchor, in state: AppState) {
        guard let saved = state.notes.save(anchor) else { return }
        if saved.collectionIDs.contains(collection.id) {
            state.notes.removeFromCollection(savedID: saved.id, collectionID: collection.id)
            Announcer.post("Removed \(anchor.displayString) from \(collection.name)")
        } else {
            state.notes.addToCollection(savedID: saved.id, collectionID: collection.id)
            Announcer.post("Added \(anchor.displayString) to \(collection.name)")
        }
    }

    @MainActor @discardableResult
    static func createCollectionAndAdd(named name: String, anchor: Anchor, in state: AppState) -> StudyCollection? {
        guard let collection = state.notes.createCollection(name: name) else { return nil }
        if let saved = state.notes.save(anchor) { state.notes.addToCollection(savedID: saved.id, collectionID: collection.id) }
        Announcer.post("Added \(anchor.displayString) to \(collection.name)")
        return collection
    }

    /// Copies the anchor's verse text with its reference, exactly as the pre-0.10 "Copy verse"
    /// action did for a single verse (via `VerseClipboard.swift`'s `verseClipboardText`), extended
    /// to a whole range.
    // TODO(share): once S2c's ExportComposer exists, route this through it instead — it carries the
    // translation export policy (ESV/NKJV notices, caps) that a raw clipboard write does not.
    @MainActor static func copyWithReference(_ anchor: Anchor, in state: AppState) {
        let bookName = BookTable.info(code: anchor.book)?.name ?? state.bookName
        let verses = versesInChapter(anchor, state: state)
        guard !verses.isEmpty else { return }
        let text = verses
            .map { verseClipboardText(bookName: bookName, chapter: anchor.chapterStart, verse: $0, translation: state.translationID) }
            .joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        Announcer.post("Copied \(anchor.displayString)")
    }

    /// The verses of `anchor` that are on screen right now. Only resolves same-chapter anchors
    /// against the currently loaded chapter — the reader's own text is never fetched separately
    /// just to build a clipboard string.
    @MainActor private static func versesInChapter(_ anchor: Anchor, state: AppState) -> [BibleVerse] {
        guard anchor.chapterStart == anchor.chapterEnd, anchor.chapterStart == state.selectedChapter,
              case .loaded(let content) = state.chapterLoad else { return [] }
        let lo = max(anchor.verseStart, 1)
        let hi = anchor.verseEnd >= Anchor.endOfChapter ? (content.verses.map(\.number).max() ?? lo) : anchor.verseEnd
        return content.verses.filter { $0.number >= lo && $0.number <= hi }
    }
}

// MARK: - "My Study" app menu

/// `CommandMenu("My Study")` — the keyboard/menu mirror of every verse context-menu action,
/// per PASTOR-QA-0.10's spec. Observes `notes` directly (not just `state`) so item titles like
/// "Unsave…" and checkmarks update immediately after a save/unsave from anywhere in the app, not
/// only after the selection itself changes.
struct MyStudyCommands: Commands {
    @ObservedObject var state: AppState
    @ObservedObject var notes: StudyStore

    var body: some Commands {
        CommandMenu("My Study") {
            let anchor = state.selectedAnchor
            let saved = anchor.flatMap { notes.savedPassage(matching: $0) }
            let label = anchor?.displayString ?? "Selection"

            Button(saved != nil ? "Unsave \(label)" : "Save \(label)") {
                if let anchor { MyStudyActions.toggleSave(anchor, in: state) }
            }
            .keyboardShortcut("d", modifiers: .command)
            .disabled(anchor == nil)

            Menu("Highlight") {
                ForEach(HighlightColor.allCases, id: \.self) { color in
                    Button(saved?.highlight == color ? "\(color.displayName) \u{2713}" : color.displayName) {
                        if let anchor { MyStudyActions.setHighlight(color, for: anchor, in: state) }
                    }
                }
                Divider()
                Button("Remove Highlight") { if let anchor { MyStudyActions.setHighlight(nil, for: anchor, in: state) } }
                    .disabled(saved?.highlight == nil)
            }
            .disabled(anchor == nil)

            Button(saved?.isMemory == true ? "Unmark as Memory Verse" : "Mark as Memory Verse") {
                if let anchor { MyStudyActions.toggleMemory(anchor, in: state) }
            }
            .disabled(anchor == nil)

            Menu("Add to Collection") {
                ForEach(notes.collections) { collection in
                    let already = saved?.collectionIDs.contains(collection.id) == true
                    Button(already ? "Remove from \(collection.name)" : "Add to \(collection.name)") {
                        if let anchor { MyStudyActions.toggleCollection(collection, for: anchor, in: state) }
                    }
                }
                if !notes.collections.isEmpty { Divider() }
                Button("New Collection\u{2026}") {
                    guard let anchor, let name = CollectionNamePrompt.ask() else { return }
                    MyStudyActions.createCollectionAndAdd(named: name, anchor: anchor, in: state)
                }
            }
            .disabled(anchor == nil)

            Divider()

            Button("Select Section") {
                if let section = state.currentSection() { state.selectSection(section) }
            }
            .disabled(state.currentSection() == nil)

            Button("Extend Selection Up") { state.extendSelection(by: -1) }
                .keyboardShortcut(.upArrow, modifiers: [.shift])
                .disabled(anchor == nil)
            Button("Extend Selection Down") { state.extendSelection(by: 1) }
                .keyboardShortcut(.downArrow, modifiers: [.shift])
                .disabled(anchor == nil)

            Divider()

            Button("Copy with Reference") { if let anchor { MyStudyActions.copyWithReference(anchor, in: state) } }
                .keyboardShortcut("c", modifiers: [.command, .shift])
                .disabled(anchor == nil)

            if let anchor, let translation = state.library.translation(id: state.translationID) {
                ShareMenu(items: [.selection(anchor)], collectionHeading: nil,
                          options: ExportOptions(translation: translation, title: anchor.displayString),
                          verses: state.library.localPackVerseSource())
            } else {
                Menu("Share") { Text("Coming soon") }.disabled(true)
            }
        }
    }
}
