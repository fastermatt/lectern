import SwiftUI

struct StudyTableApp: App {
    @Environment(\.openWindow) private var openWindow
    @StateObject private var aiSession = AIChatSession()
    @StateObject private var state: AppState
    /// Observed separately from `state` so "My Study" menu titles (Save/Unsave, highlight
    /// checkmarks, collection membership) refresh the moment the store changes, not only when the
    /// selection itself changes — `AppState`'s own `objectWillChange` doesn't fire for `StudyStore`
    /// mutations that leave the selection untouched.
    @ObservedObject private var notes: StudyStore

    init() {
        let appState = AppState()
        _state = StateObject(wrappedValue: appState)
        notes = appState.notes
    }

    var body: some Scene {
        Window("Lectern", id: "workspace") {
            MainView()
                .environmentObject(state)
                .preferredColorScheme(state.colorScheme)
                .frame(minWidth: 980, minHeight: 650)
                .handlesLecternStudyImports()
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandMenu("Study") {
                Button("Search Bible…") { state.showBibleSearch = true }
                    .keyboardShortcut("f", modifiers: .command)
                Button("Library & resources…") { openWindow(id: "resource-library") }
                Button("Add resources…") { openWindow(id: "add-resources") }
                Button("Your AI & CLI…") { openWindow(id: "ai-assistant") }
                Divider()
                Button("Focus Scripture") { state.focusMode.toggle() }
                    .keyboardShortcut("f", modifiers: [.command, .shift])
                Button("Toggle Library") { state.showLibrary.toggle() }
                    .keyboardShortcut("l", modifiers: [.command, .option])
                Button("Toggle Study Desk") { state.showStudyDesk.toggle() }
                    .keyboardShortcut("d", modifiers: [.command, .option])
                Divider()
                Button("Study a Word in the Selected Verse\u{2026}") { state.requestWordPicker() }
                    .keyboardShortcut("k", modifiers: [.command, .shift])
                Divider()
                Button("Reading Layout") { state.applyPreset(.reading) }
                Button("Study Layout") { state.applyPreset(.study) }
                Button("Research Layout") { state.applyPreset(.research) }
            }
            MyStudyCommands(state: state, notes: notes)
        }
        Window("Your AI", id: "ai-assistant") {
            AIAssistantView(session: aiSession).environmentObject(state).preferredColorScheme(state.colorScheme)
        }
        .defaultSize(width: 760, height: 740)
        Window("Library", id: "resource-library") {
            ResourceLibraryView(books: state.resourceBooks).environmentObject(state).preferredColorScheme(state.colorScheme)
        }.defaultSize(width: 980, height: 740)
        Window("Add resources", id: "add-resources") {
            ResourceLibraryView(books: state.resourceBooks, adding: true).environmentObject(state).preferredColorScheme(state.colorScheme)
        }.defaultSize(width: 980, height: 740)
        Settings {
            SettingsView()
                .environmentObject(state)
                .preferredColorScheme(state.colorScheme)
        }
    }
}
