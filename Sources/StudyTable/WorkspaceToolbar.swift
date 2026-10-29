import SwiftUI

struct WorkspaceToolbar: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var showLayouts = false
    @State private var showAppearance = false
    var body: some View {
        HStack(spacing: 10) {
            Text("Lectern").font(.system(size: 22, weight: .medium)).tracking(-0.6).padding(.trailing, 10)
            Divider().frame(height: 18)
            Button { state.showBibleSearch = true } label: { Label("Search", systemImage: "magnifyingglass") }
                .navigationHelp("Search Scripture and your study library. Shortcut: ⌘F.")
            Button {
                state.focusMode = false
                state.showStudyDesk = true
                state.deskMode = .learn
            } label: { Label("Learn", systemImage: "book.closed") }
                .navigationHelp("Explore a passage with word meanings, grammar help, emphasis notes and your own reflection.")
            Button { openWindow(id: "resource-library") } label: { Label("Library", systemImage: "books.vertical") }
                .navigationHelp("Browse installed Bibles and study resources.")
            Button { openWindow(id: "add-resources") } label: { Label("Add resources", systemImage: "plus") }
                .navigationHelp("Find and add resources to your local library.")
            Spacer(minLength: 8)
            Button { openWindow(id: "ai-assistant") } label: { Label("Your AI", systemImage: "text.bubble") }
                .navigationHelp("Configure your own AI provider, then review the attached context before sending a question.")
            Button { showLayouts.toggle() } label: {
                HStack(spacing: 7) {
                    Image(systemName: "rectangle.split.2x2")
                    ActiveLayoutLabel(library: state.layouts).environmentObject(state)
                    Image(systemName: "chevron.down").font(.system(size: 9))
                }
            }.navigationHelp("Layouts save and restore pane arrangement and study selections.").accessibilityLabel("Layouts")
                .popover(isPresented: $showLayouts) { LayoutsPanel(library: state.layouts).environmentObject(state) }
            Button { showAppearance.toggle() } label: {
                Image(systemName: "circle.lefthalf.filled").font(.system(size: 17))
            }
            .accessibilityLabel("Appearance and colors").navigationHelp("Choose light or dark appearance and customize workspace colors.")
            .popover(isPresented: $showAppearance) { AppearancePanel().environmentObject(state) }
        }
        .buttonStyle(WorkspaceActionStyle()).font(.system(size: 12, weight: .medium))
        .foregroundStyle(STColor.ink)
        .padding(.horizontal, 20).frame(height: 60)
        .background(STColor.tileBottom)
    }
}

private struct ActiveLayoutLabel: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var library: LayoutLibrary
    var body: some View {
        Text(library.layouts.first(where: { $0.id == state.activeLayoutID })?.name
             ?? (state.focusMode ? "Reading focus" : state.activePreset == .study ? "Passage study" : state.activePreset.rawValue.capitalized))
            .lineLimit(1).frame(maxWidth: 150, alignment: .leading)
    }
}

/// Flat, quiet controls with a real hover/pressed affordance; native focus remains intact.
struct WorkspaceActionStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { Face(configuration: configuration) }
    private struct Face: View {
        let configuration: ButtonStyle.Configuration
        @State private var hovering = false
        @Environment(\.isEnabled) private var enabled
        var body: some View {
            configuration.label.padding(.horizontal, 8).padding(.vertical, 8)
                .background(configuration.isPressed ? STColor.gutter : hovering ? STColor.tileWell : .clear,
                            in: RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle()).opacity(enabled ? 1 : 0.45)
                .onHover { hovering = $0 }
        }
    }
}
