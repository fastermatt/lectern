import AppKit
import SwiftUI

private let gutter: CGFloat = 1

// Selected Precision Console: a continuous paper workspace with a quiet metal rim.
// Navigation | Scripture | sources + notes. Reading and appearance controls use popovers.

struct MainView: View {
    @EnvironmentObject private var state: AppState
    @StateObject private var searchSession = BibleSearchSession()

    var body: some View {
        InstrumentFrame {
            VStack(spacing: gutter) {
                WorkspaceToolbar()
                Workspace()
                WorkspaceFooter()
            }
        }
        .foregroundStyle(STColor.ink)
        .tint(STColor.navy)
        .defaultAppStorage(state.preferenceStore)
        .sheet(isPresented: Binding(get: { !state.hasSeenIntro }, set: { state.hasSeenIntro = !$0 })) { WelcomeSheet() }
        .sheet(isPresented: $state.showBibleSearch) {
            SearchWorkspace(session: searchSession).environmentObject(state).preferredColorScheme(state.colorScheme)
        }
        .task { await state.resourceBooks.load() }
        .captureSettingsOpener()
        .modifier(StudyStoreAlertPresenter(study: state.study))
    }
}

/// Shows the study store's own warnings (0.10, S1's data-safety work). When a notes file is damaged,
/// newer than this app, or can't be saved, the store recovers or goes read-only and *says so through
/// `StudyStore.alert`* — but nothing in the UI displayed it, so the app would have quietly stopped
/// saving. Observes the store directly (AppState doesn't republish the store's changes).
private struct StudyStoreAlertPresenter: ViewModifier {
    @ObservedObject var study: StudyStore

    func body(content: Content) -> some View {
        content.alert(item: Binding(get: { study.alert }, set: { if $0 == nil { study.dismissAlert() } })) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message),
                  dismissButton: .default(Text("OK")) { study.dismissAlert() })
        }
    }
}

// MARK: - Workspace (Library | Scripture | Study Desk)

private struct Workspace: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HSplitView {
            if state.showLibrary && !state.focusMode {
                LibraryPane().frame(minWidth: 220, idealWidth: 290, maxWidth: 360)
            }
            VStack(spacing: gutter) {
                HSplitView {
                    if state.sourcesOnLeft && state.showStudyDesk && !state.focusMode {
                        StudyDesk().frame(minWidth: 290, idealWidth: 350)
                    }
                    ScripturePane().frame(minWidth: 350, idealWidth: 570)
                        .background { if state.showStudyDesk && !state.focusMode { WorkspaceDivider(fraction: $state.readingRatio, revision: state.layoutRevision) } }
                    if !state.sourcesOnLeft && state.showStudyDesk && !state.focusMode {
                        StudyDesk().frame(minWidth: 290, idealWidth: 350, maxWidth: .infinity)
                    }
                }
            }
            .frame(minWidth: 650, maxWidth: .infinity)
        }
        .background(SplitViewAutosave(name: "console-library-split"))
    }
}

/// AppKit's NSSplitView autosaves divider positions on its own once given a stable
/// `autosaveName` — no manual position tracking needed. SwiftUI's HSplitView is backed by a real
/// NSSplitView, so this walks up from an invisible child to find it and set the name once. Best
/// effort: verified by offscreen render that it doesn't break layout or dragging; real
/// launch-to-launch persistence isn't exercised by the offscreen test harness (there is no second
/// launch), and the saved slot is keyed by subview count, so toggling Library or the Study Desk
/// off and back on can land a stale position — acceptable for a first pass, noted in DESIGN.md.
struct SplitViewAutosave: NSViewRepresentable {
    let name: String

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async { configure(view) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { configure(nsView) }
    }

    private func configure(_ view: NSView) {
        var current: NSView? = view
        while let candidate = current {
            if let split = candidate as? NSSplitView {
                let autosaveName = NSSplitView.AutosaveName(name)
                if split.autosaveName != autosaveName { split.autosaveName = autosaveName }
                return
            }
            current = candidate.superview
        }
    }
}

// MARK: - Compact workspace controls

struct WorkspaceFooter: View {
    @EnvironmentObject private var state: AppState
    @State private var showReading = false
    @State private var showConfessions = false
    private var connection: String {
        switch state.chapterLoad {
        case .loading: "Loading"
        case .unavailable: "Unavailable"
        case .loaded(let content):
            switch content.origin { case .offline: "Offline"; case .onlineLive: "Online"; case .onlineCached: "Cached" }
        }
    }
    var body: some View {
        HStack(spacing: 16) {
            Button { state.focusMode.toggle() } label: {
                Label(state.focusMode ? "Exit reading focus" : "Reading focus", systemImage: state.focusMode ? "arrow.down.right.and.arrow.up.left" : "book")
            }.navigationHelp("Focus on Bible reading by hiding the Library, Study Desk, and Notes. Shortcut: ⇧⌘F.")
            Menu {
                Toggle("Bible navigation", isOn: $state.showLibrary)
                Toggle("Sources & tools", isOn: $state.showStudyDesk)
                Toggle("Notes", isOn: $state.showNotes)
                Divider()
                Toggle("Show disputed-reception sources", isOn: $state.showResearchTier)
                Button("Confessional library…") { showConfessions = true }
                Button("Customize workspace…") { openSettings(.workspace) }
                Button("Help & introduction…") { state.hasSeenIntro = false }
            } label: { Label("View", systemImage: "sidebar.left") }
            .menuStyle(.borderlessButton).fixedSize()
            .navigationHelp("Show or hide workspace panes, customize the workspace, or open the introduction.")
            Spacer()
            Label(connection, systemImage: connection == "Offline" ? "checkmark.circle" : "network")
                .foregroundStyle(STColor.secondary).help("Status of the current Bible text")
            Divider().frame(height: 16)
            Button { showReading.toggle() } label: { Label("Reading options", systemImage: "textformat.size") }
                .navigationHelp("Adjust Bible and study text typefaces, size, line spacing, and section headings.")
                .popover(isPresented: $showReading) { ReadingOptionsPanel().environmentObject(state) }
        }
        .font(.system(size: 12)).buttonStyle(.borderless)
        .padding(.horizontal, 20).frame(height: 38)
        .sheet(isPresented: $showConfessions) { ConfessionalLibrarySheet() }
    }
}

/// Holds the `OpenSettingsAction` (SwiftUI's `@Environment(\.openSettings)`, macOS 14+) captured
/// from the view hierarchy, so the free `openSettings()` function below — called from many
/// non-view sites (`PassageMenuTile`, `ViewMenuTile` in this file; `LCDDisplay`'s gear in
/// `LCD.swift`; `Panes.swift`'s "Settings…" buttons) — keeps working unchanged.
/// `OpenSettingsAction` only exists as an environment value
/// inside a `View`'s body, so it can't be read from a free function directly; `MainView` captures
/// it once via `captureSettingsOpener()` below, before any call site could plausibly need it.
///
/// Root cause of the bug this replaces: the previous `openSettings()` sent the private
/// `showSettingsWindow:` selector via `NSApp.sendAction`, which macOS 14+ silently ignores for a
/// SwiftUI `Settings` scene (it was never public AppKit API to begin with — it happened to work by
/// coincidence on older releases). `OpenSettingsAction` is the actual public, supported API for
/// this exact purpose.
@MainActor
final class SettingsOpener: ObservableObject {
    static let shared = SettingsOpener()
    var action: OpenSettingsAction?
    @Published var destination: SettingsDestination = .workspace
}

enum SettingsDestination: Hashable { case workspace, translations, resources, about }

/// Attached once, to the root `MainView`, so `SettingsOpener.shared.action` is populated before
/// any menu key or button could plausibly call `openSettings()`. `OpenSettingsAction` is tied to
/// the scene, not to transient view state, so a single capture on appearance (re-run on every
/// appearance, which is cheap and idempotent) is sufficient for the app's lifetime — there's no
/// equivalent of "the settings scene changed under us" to additionally watch for.
private struct SettingsOpenerCapture: ViewModifier {
    @Environment(\.openSettings) private var openSettings

    func body(content: Content) -> some View {
        content.onAppear { SettingsOpener.shared.action = openSettings }
    }
}

extension View {
    fileprivate func captureSettingsOpener() -> some View { modifier(SettingsOpenerCapture()) }
}

/// Opens the app's Settings window and brings the app to the front. Free function (not a method)
/// so every existing call site — including ones in files this workstream may not edit — keeps
/// working unchanged; only the implementation behind it changed.
@MainActor func openSettings(_ destination: SettingsDestination? = nil) {
    if let destination { SettingsOpener.shared.destination = destination }
    NSApp.activate(ignoringOtherApps: true)
    SettingsOpener.shared.action?()
}

