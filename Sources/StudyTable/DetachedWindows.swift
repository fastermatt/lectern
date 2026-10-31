import AppKit
import Combine
import SwiftUI

enum DetachedPanel: String, CaseIterable, Hashable {
    case bible, sources, notes
    var title: String {
        switch self { case .bible: "Bible"; case .sources: "Sources & tools"; case .notes: "Notes" }
    }
    var initialSize: NSSize {
        switch self {
        case .bible: NSSize(width: 620, height: 760)
        case .sources: NSSize(width: 540, height: 720)
        case .notes: NSSize(width: 560, height: 740)
        }
    }
}

/// A single native window for each pane. Views share AppState and its one StudyStore;
/// no duplicate file-backed stores, copied notes, or independent stale notebook sessions.
@MainActor
final class DetachedWindowManager: NSObject, NSWindowDelegate {
    private weak var state: AppState?
    private var controllers: [DetachedPanel: NSWindowController] = [:]
    private var appearanceSubscription: AnyCancellable?
    /// Tests use real offscreen windows without changing saved user window positions.
    var presentsWindows = true

    init(state: AppState) {
        self.state = state
        super.init()
        appearanceSubscription = state.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshAppearances() }
        }
    }

    private func refreshAppearances() {
        for controller in controllers.values { controller.window?.appearance = windowAppearance }
    }

    private var windowAppearance: NSAppearance? {
        switch state?.colorScheme {
        case .dark?: NSAppearance(named: .darkAqua)
        case .light?: NSAppearance(named: .aqua)
        default: nil
        }
    }

    func window(for panel: DetachedPanel) -> NSWindow? { controllers[panel]?.window }

    func detach(_ panel: DetachedPanel) {
        guard let state else { return }
        if controllers[panel] != nil { focus(panel); return }
        if panel == .notes { state.notebook.pin(to: state.notebook.loadedAnchor ?? state.selectedAnchor) }
        state.detachedPanels.insert(panel)
        let content = DetachedPanelRoot(panel: panel).environmentObject(state)
        let host = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: host)
        configure(window, panel: panel)
        controllers[panel] = NSWindowController(window: window)
        if presentsWindows { window.makeKeyAndOrderFront(nil) }
        else { window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000)); window.orderBack(nil) }
    }

    private func configure(_ window: NSWindow, panel: DetachedPanel) {
        window.title = "Throughline · \(panel.title)"
        window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
        window.setContentSize(panel.initialSize)
        window.minSize = NSSize(width: panel == .notes ? 380 : 360, height: 400)
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.appearance = windowAppearance
        window.isExcludedFromWindowsMenu = false
        if presentsWindows {
            window.center()
            window.setFrameAutosaveName("Throughline.Detached.\(panel.rawValue)")
        }
    }

    func focus(_ panel: DetachedPanel) {
        guard presentsWindows else { return }
        guard let window = controllers[panel]?.window else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
    }

    func redock(_ panel: DetachedPanel) {
        guard let window = controllers[panel]?.window else { return }
        window.close()
        if presentsWindows { state?.openSceneWindow?("workspace") }
    }
    func redockAll() { for panel in DetachedPanel.allCases { redock(panel) } }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              let panel = controllers.first(where: { $0.value.window === window })?.key else { return }
        controllers.removeValue(forKey: panel)
        restorePane(panel)
        window.contentView = nil
    }

    private func restorePane(_ panel: DetachedPanel) {
        guard let state else { return }
        if panel == .notes {
            restoreNotebookPassage(state)
            state.notebook.isPinned = false
            state.showNotes = true
        }
        if panel != .bible { state.showStudyDesk = true }
        state.focusMode = false
        state.detachedPanels.remove(panel)
    }

    private func restoreNotebookPassage(_ state: AppState) {
        guard state.notebook.isPinned, let anchor = state.notebook.loadedAnchor ?? state.notebook.pinnedAnchor else { return }
        state.navigate(bookCode: anchor.book, chapter: anchor.chapterStart, verse: anchor.verseStart)
        if anchor.chapterStart == anchor.chapterEnd, anchor.verseEnd != Anchor.endOfChapter,
           anchor.verseEnd > anchor.verseStart { state.rangeEndVerse = anchor.verseEnd }
        // Retain the live fields, including unsaved title/template drafts, across remount.
        state.notebook.loadedAnchor = state.selectedAnchor
    }
}

struct DetachPanelButton: View {
    @EnvironmentObject private var state: AppState
    let panel: DetachedPanel
    var body: some View {
        if !state.detachedPanels.contains(panel) {
            Button { state.detachedWindows.detach(panel) } label: {
                Image(systemName: "arrow.up.forward.square")
            }
            .buttonStyle(.plain).help("Open \(panel.title) in a separate window")
            .accessibilityLabel("Detach \(panel.title)")
        }
    }
}

struct DetachedPanelRoot: View {
    @EnvironmentObject private var state: AppState
    let panel: DetachedPanel
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Text(panel.title).font(.headline)
                Spacer(minLength: 8)
                if panel == .notes { NotebookPinControl(notebook: state.notebook) }
                Button("Return to workspace") { state.detachedWindows.redock(panel) }
                    .controlSize(.small)
            }.padding(12)
            Divider()
            switch panel {
            case .bible: ScripturePane()
            case .sources: SourcesPane()
            case .notes: NoteEditor(startsExpanded: true)
            }
        }
        .foregroundStyle(STColor.ink).background(STColor.paper).tint(STColor.navy)
        .defaultAppStorage(state.preferenceStore)
        .preferredColorScheme(state.colorScheme)
        .modifier(StudyStoreAlertPresenter(study: state.study))
    }
}

private struct NotebookPinControl: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var notebook: NotebookSession
    var body: some View {
        Toggle("Pin note", isOn: Binding(get: { notebook.isPinned }, set: { pinned in
            if pinned { notebook.pin(to: state.selectedAnchor) }
            else { notebook.isPinned = false }
        }))
        .controlSize(.small)
        .help("Keep this notebook on its passage while browsing the Bible. Turn off to follow the workspace.")
    }
}

struct DetachedWorkspacePlaceholder: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        VStack(spacing: 14) {
            Text("Your study is open in separate windows").font(.title3)
            ForEach(DetachedPanel.allCases.filter { state.detachedPanels.contains($0) }, id: \.self) { panel in
                HStack {
                    Button("Show \(panel.title)") { state.detachedWindows.focus(panel) }
                    Button("Return \(panel.title)") { state.detachedWindows.redock(panel) }
                }
            }
        }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(24).background(STColor.paper)
    }
}
