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
    private var terminationObserver: NSObjectProtocol?
    /// Set while quitting: windows torn down by termination are still part of the session.
    private var terminating = false
    /// Set while a layout or the launch session is applied, so intermediate states are not recorded.
    private var restoring = false
    /// Tests use real offscreen windows without changing saved user window positions.
    var presentsWindows = true
    static let sessionKey = "workspace.detachedSession.v1"

    init(state: AppState) {
        self.state = state
        super.init()
        appearanceSubscription = state.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshAppearances() }
        }
        terminationObserver = NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification,
            object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.persistSession(); self.terminating = true
            }
        }
    }

    // MARK: Layout and session recipes

    /// The detached windows as they are now: which panes, where, and whether Notes is pinned.
    /// Frames are recorded only for real on-screen windows, never for offscreen test windows.
    func recipes() -> [DetachedWindowRecipe] {
        guard let state else { return [] }
        return DetachedPanel.allCases.filter { state.detachedPanels.contains($0) }.map { panel in
            let frame = presentsWindows ? controllers[panel]?.window?.frame : nil
            return DetachedWindowRecipe(panel: panel.rawValue,
                frame: frame.map { [$0.origin.x, $0.origin.y, $0.size.width, $0.size.height] },
                pinned: panel == .notes ? state.notebook.isPinned : nil)
        }
    }

    /// Makes the separate windows match a recipe: panes not listed return to the workspace,
    /// listed panes open (or stay open) at their saved place when that place is still on a screen.
    func apply(_ recipes: [DetachedWindowRecipe]) {
        guard let state else { return }
        restoring = true
        defer { restoring = false; persistSession() }
        var wanted: [DetachedPanel: DetachedWindowRecipe] = [:]
        for recipe in recipes { if let panel = DetachedPanel(rawValue: recipe.panel), wanted[panel] == nil { wanted[panel] = recipe } }
        for panel in DetachedPanel.allCases where wanted[panel] == nil && controllers[panel] != nil {
            redock(panel, revealWorkspace: false)
        }
        for panel in DetachedPanel.allCases {
            guard let recipe = wanted[panel] else { continue }
            detach(panel, activate: false)
            if presentsWindows, let window = controllers[panel]?.window, let values = recipe.frame,
               let frame = Self.placeableFrame(values, screens: NSScreen.screens.map(\.visibleFrame), minimum: window.minSize) {
                window.setFrame(frame, display: true)
            }
            if panel == .notes, recipe.pinned == false { state.notebook.isPinned = false }
        }
    }

    /// A saved frame is used only when its title bar is reachable on a current screen.
    /// Displays get unplugged and resolutions change; unusable frames fall back to the default.
    static func placeableFrame(_ values: [Double], screens: [NSRect], minimum: NSSize = NSSize(width: 360, height: 400)) -> NSRect? {
        guard values.count == 4, values.allSatisfy({ $0.isFinite }) else { return nil }
        var frame = NSRect(x: values[0], y: values[1], width: values[2], height: values[3])
        guard frame.width >= 200, frame.height >= 200, frame.width <= 20_000, frame.height <= 20_000 else { return nil }
        let titleBar = NSRect(x: frame.minX, y: frame.maxY - 28, width: frame.width, height: 28)
        guard let screen = screens.first(where: { titleBar.intersection($0).width >= 120 && titleBar.intersection($0).height >= 20 }) else { return nil }
        frame.size.width = min(max(frame.width, minimum.width), screen.width)
        frame.size.height = min(max(frame.height, minimum.height), screen.height)
        // Keep the whole title bar on the screen it already overlaps.
        if frame.maxY > screen.maxY { frame.origin.y = screen.maxY - frame.height }
        if frame.minY < screen.minY { frame.origin.y = screen.minY }
        if frame.minX < screen.minX { frame.origin.x = screen.minX }
        if frame.maxX > screen.maxX { frame.origin.x = screen.maxX - frame.width }
        return frame
    }

    /// The windows that were open when Thruline last quit, if any.
    static func savedSession(in defaults: UserDefaults) -> [DetachedWindowRecipe] {
        guard let data = defaults.data(forKey: sessionKey),
              let recipes = try? JSONDecoder().decode([DetachedWindowRecipe].self, from: data), recipes.count <= DetachedPanel.allCases.count else { return [] }
        return recipes
    }

    private func persistSession() {
        guard let state, !restoring, !terminating, let data = try? JSONEncoder().encode(recipes()) else { return }
        state.preferenceStore.set(data, forKey: Self.sessionKey)
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

    func detach(_ panel: DetachedPanel, activate: Bool = true) {
        guard let state else { return }
        if controllers[panel] != nil { if activate { focus(panel) }; return }
        if panel == .notes { state.notebook.pin(to: state.notebook.loadedAnchor ?? state.selectedAnchor) }
        state.detachedPanels.insert(panel)
        let content = DetachedPanelRoot(panel: panel).environmentObject(state)
        let host = NSHostingController(rootView: content)
        let window = NSWindow(contentViewController: host)
        configure(window, panel: panel)
        controllers[panel] = NSWindowController(window: window)
        if presentsWindows { activate ? window.makeKeyAndOrderFront(nil) : window.orderFront(nil) }
        else { window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000)); window.orderBack(nil) }
        persistSession()
    }

    private func configure(_ window: NSWindow, panel: DetachedPanel) {
        window.title = "Thruline Bible · \(panel.title)"
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

    func redock(_ panel: DetachedPanel, revealWorkspace: Bool = true) {
        guard let window = controllers[panel]?.window else { return }
        window.close()
        if presentsWindows, revealWorkspace { state?.openSceneWindow?("workspace") }
    }
    func redockAll() { for panel in DetachedPanel.allCases { redock(panel) } }

    func windowWillClose(_ notification: Notification) {
        guard !terminating, let window = notification.object as? NSWindow,
              let panel = controllers.first(where: { $0.value.window === window })?.key else { return }
        controllers.removeValue(forKey: panel)
        restorePane(panel)
        window.contentView = nil
        persistSession()
    }
    func windowDidMove(_ notification: Notification) { if presentsWindows { persistSession() } }
    func windowDidEndLiveResize(_ notification: Notification) { if presentsWindows { persistSession() } }

    private func restorePane(_ panel: DetachedPanel) {
        guard let state else { return }
        if panel == .notes {
            // A layout being opened chooses the passage; only a reader's own return follows the pin.
            if !restoring { restoreNotebookPassage(state) }
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
