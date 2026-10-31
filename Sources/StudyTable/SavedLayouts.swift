import AppKit
import SwiftUI

/// A layout is a workspace recipe, never a copy of a person's notes or credentials.
struct WorkspaceRecipe: Codable, Equatable {
    var book: String
    var chapter: Int
    var verse: Int?
    var rangeEnd: Int?
    var translation: String
    var library: Bool
    var sources: Bool
    var notes: Bool
    var focus: Bool
    var sourcesOnLeft: Bool
    var mode: String
    var pinnedGuide: Anchor?
    var order: [String]
    var hidden: [String]
    var banks: [String]
    var type: Double
    var leading: Double
    var readingRatio: Double
    var notesRatio: Double
    /// Separate study windows (0.22+). Absent in older layouts, which open fully docked.
    var windows: [DetachedWindowRecipe]? = nil
}

/// One separate pane window: which pane, its frame in screen points, and whether Notes stays pinned.
struct DetachedWindowRecipe: Codable, Equatable {
    var panel: String
    /// x, y, width, height. Omitted when no on-screen frame was available.
    var frame: [Double]?
    var pinned: Bool?
}

struct SavedWorkspace: Codable, Identifiable, Equatable {
    var id = UUID()
    var name: String
    var favorite = false
    var updated = Date()
    var recipe: WorkspaceRecipe
}

@MainActor
final class LayoutLibrary: ObservableObject {
    private struct File: Codable { var version = 1; var layouts: [SavedWorkspace]; var startup: UUID? }
    @Published private(set) var layouts: [SavedWorkspace] = []
    @Published private(set) var startup: UUID?
    @Published private(set) var message: String?
    private let defaults: UserDefaults
    private var writable = true
    private static let key = "workspace.savedLayouts.v1"
    init(defaults: UserDefaults) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key) {
            do {
                let file = try JSONDecoder().decode(File.self, from: data)
                guard file.version == 1, file.layouts.count <= 100,
                      Set(file.layouts.map(\.id)).count == file.layouts.count else { throw CocoaError(.coderReadCorrupt) }
                layouts = file.layouts; startup = file.startup
            } catch {
                writable = false
                message = "Saved layouts could not be read. Their stored data has been preserved; changes are disabled."
            }
        }
    }
    @discardableResult func save(_ name: String, recipe: WorkspaceRecipe) -> UUID? {
        guard writable else { return nil }
        guard layouts.count < 100 else { message = "At most 100 layouts can be saved."; return nil }
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !trimmed.isEmpty else { return nil }
        let layout = SavedWorkspace(name: trimmed, recipe: recipe)
        layouts.append(layout); persist(); return layout.id
    }
    func update(_ id: UUID, recipe: WorkspaceRecipe) { edit(id) { $0.recipe = recipe; $0.updated = Date() } }
    func rename(_ id: UUID, to name: String) {
        let value = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(80))
        guard !value.isEmpty else { return }
        edit(id) { $0.name = value }
    }
    func favorite(_ id: UUID) { edit(id) { $0.favorite.toggle() } }
    func remove(_ id: UUID) {
        guard writable else { return }
        layouts.removeAll { $0.id == id }; if startup == id { startup = nil }; persist()
    }
    func setStartup(_ id: UUID?) {
        guard writable, id == nil || layouts.contains(where: { $0.id == id }) else { return }
        startup = id; persist()
    }
    private func edit(_ id: UUID, _ change: (inout SavedWorkspace) -> Void) {
        guard writable, let index = layouts.firstIndex(where: { $0.id == id }) else { return }
        change(&layouts[index]); persist()
    }
    private func persist() {
        do { defaults.set(try JSONEncoder().encode(File(layouts: layouts, startup: startup)), forKey: Self.key) }
        catch { message = "This layout could not be saved. Please try again." }
    }
}

extension AppState {
    func workspaceRecipe() -> WorkspaceRecipe {
        WorkspaceRecipe(book: selectedBookCode, chapter: selectedChapter, verse: selectedVerse,
            rangeEnd: rangeEndVerse, translation: translationID, library: showLibrary, sources: showStudyDesk,
            notes: showNotes, focus: focusMode, sourcesOnLeft: sourcesOnLeft, mode: deskMode.rawValue,
            pinnedGuide: guideScope.explicitAnchor, order: deskSectionOrder.map(\.rawValue),
            hidden: hiddenDeskSections.map(\.rawValue), banks: selectedTraditions.map(\.rawValue),
            type: fontSize, leading: lineSpacing, readingRatio: readingRatio, notesRatio: notesRatio,
            windows: detachedWindows.recipes())
    }
    func openLayout(_ layout: SavedWorkspace) {
        let r = layout.recipe
        objectWillChange.send()
        showLibrary = r.library; showStudyDesk = r.sources; showNotes = r.notes; focusMode = r.focus
        sourcesOnLeft = r.sourcesOnLeft
        deskMode = StudyDeskMode(rawValue: r.mode) ?? .guide
        guideScope = PassageGuideScope()
        if let anchor = r.pinnedGuide { guideScope.pin(anchor) }
        deskSectionOrder = StudyDeskSection.normalizedOrder(r.order)
        hiddenDeskSections = Set(r.hidden.compactMap(StudyDeskSection.init(rawValue:)).filter { !$0.isSourceBank })
        selectedTraditions = Set(r.banks.compactMap(SourceTradition.init(rawValue:)))
        fontSize = r.type.isFinite ? min(30, max(15, r.type)) : 20
        lineSpacing = r.leading.isFinite ? min(16, max(2, r.leading)) : 8
        readingRatio = Self.safeRatio(r.readingRatio); notesRatio = Self.safeRatio(r.notesRatio)
        translationID = library.translation(id: r.translation) == nil ? "BSB" : r.translation
        navigate(bookCode: r.book, chapter: r.chapter, verse: r.verse ?? 1)
        if let end = r.rangeEnd, end > 0, end <= verseCount { rangeEndVerse = end }
        applyWindowRecipes(r.windows ?? [])
        // Returning a pane to the workspace reveals its dock; the layout's own choices win.
        showLibrary = r.library; showStudyDesk = r.sources; showNotes = r.notes; focusMode = r.focus
        activeLayoutID = layout.id; layoutRevision = UUID()
    }

    /// Windows can only open once the app's scenes exist. Before then (a startup layout
    /// applied during launch), the recipe waits for `restoreWindowsAtLaunch()`.
    func applyWindowRecipes(_ recipes: [DetachedWindowRecipe]) {
        if windowsReady { detachedWindows.apply(recipes) } else { pendingWindowRecipes = recipes }
    }

    /// Called once the workspace window has appeared. A startup layout's windows win;
    /// otherwise the separate windows open at the end of the last session come back.
    func restoreWindowsAtLaunch() {
        guard !windowsReady else { return }
        windowsReady = true
        let recipes = pendingWindowRecipes
            ?? (reopenDetachedWindows ? DetachedWindowManager.savedSession(in: preferenceStore) : [])
        pendingWindowRecipes = nil
        guard !recipes.isEmpty else { return }
        let docked = (showLibrary, showStudyDesk, showNotes, focusMode)
        detachedWindows.apply(recipes)
        (showLibrary, showStudyDesk, showNotes, focusMode) = docked
    }
    static func safeRatio(_ value: Double) -> Double { value.isFinite ? min(0.85, max(0.15, value)) : 0.6 }
}

/// Observe real divider drags; apply saved fractions only on an explicit layout change.
/// Updating the binding during a drag must never cause another setPosition/layout loop.
struct WorkspaceDivider: NSViewRepresentable {
    @Binding var fraction: Double
    let revision: UUID
    var vertical = true
    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView(frame: .zero) }
    func updateNSView(_ view: NSView, context: Context) {
        let coordinator = context.coordinator
        coordinator.changed = { fraction = $0 }
        DispatchQueue.main.async { [weak view] in
            guard let root = view?.window?.contentView else { return }
            // SwiftUI can mount background representables outside their immediate pane.
            // Locate the inner reading split (smallest vertical split) or the notes split
            // by orientation in this window, rather than mutating the navigator's divider.
            func splits(in node: NSView) -> [NSSplitView] {
                let own = (node as? NSSplitView).map { [$0] } ?? []
                return own + node.subviews.flatMap { splits(in: $0) }
            }
            if let split = splits(in: root).filter({ $0.isVertical == vertical && $0.arrangedSubviews.count == 2 })
                .min(by: { $0.bounds.width * $0.bounds.height < $1.bounds.width * $1.bounds.height }) {
                coordinator.connect(split, fraction: fraction, revision: revision)
            }

        }
    }
    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) { coordinator.disconnect() }
    @MainActor final class Coordinator {
        weak var split: NSSplitView?
        var token: NSObjectProtocol?
        var revision: UUID?
        var changed: ((Double) -> Void)?
        var applying = false
        var pendingRestore: DispatchWorkItem?
        func disconnect() { pendingRestore?.cancel(); pendingRestore = nil; if let token { NotificationCenter.default.removeObserver(token) }; token = nil }
        func connect(_ split: NSSplitView, fraction: Double, revision: UUID) {
            if self.split !== split {
                disconnect(); self.split = split; self.revision = nil
                token = NotificationCenter.default.addObserver(forName: NSSplitView.didResizeSubviewsNotification,
                    object: split, queue: .main) { [weak self] _ in
                    MainActor.assumeIsolated { self?.capture() }
                }
            }
            guard self.revision != revision, split.arrangedSubviews.count == 2 else { return }
            let size = split.isVertical ? split.bounds.width : split.bounds.height
            guard size > 0 else { return }
            pendingRestore?.cancel()
            self.revision = revision; applying = true
            split.setPosition(size * AppState.safeRatio(fraction), ofDividerAt: 0)
            // SwiftUI performs a second initial split layout after hosting its children.
            // Restore once after that pass, ignoring its provisional resize notifications.
            let restore = DispatchWorkItem { [weak self, weak split] in
                guard let self, let split, self.revision == revision else { return }
                let total = split.isVertical ? split.bounds.width : split.bounds.height
                split.setPosition(total * AppState.safeRatio(fraction), ofDividerAt: 0)
                self.applying = false; self.pendingRestore = nil
            }
            pendingRestore = restore
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: restore)
        }
        func capture() {
            guard !applying, let split, split.arrangedSubviews.count == 2, let first = split.arrangedSubviews.first else { return }
            let total = split.isVertical ? split.bounds.width : split.bounds.height
            let size = split.isVertical ? first.frame.width : first.frame.height
            guard total > 0 else { return }
            let value = AppState.safeRatio(size / total)
            DispatchQueue.main.async { [weak self] in self?.changed?(value) }
        }
    }
}

struct LayoutsPanel: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject var library: LayoutLibrary
    @State private var name = ""
    @State private var renameID: UUID?
    @State private var renameText = ""
    @State private var deleteID: UUID?
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Layouts").font(.title2.weight(.semibold))
            Text("Arrange the panes, drag their dividers, then save your workspace. Saved layouts include the passage, translation, source banks, text size and any separate Bible, Sources or Notes windows.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Passage study") { state.applyPreset(.study) }
                Button("Reading") { state.applyPreset(.reading) }
                Button("Research") { state.applyPreset(.research) }
            }
            Toggle("Place sources to the left of the Bible", isOn: $state.sourcesOnLeft)
            HStack {
                Toggle("Book navigator", isOn: $state.showLibrary)
                Toggle("Sources", isOn: $state.showStudyDesk)
                Toggle("Notes", isOn: $state.showNotes)
            }.font(.callout)
            Toggle("Reopen separate windows when Thruline starts", isOn: $state.reopenDetachedWindows)
                .font(.callout)
                .help("Bring back the separate Bible, Sources and Notes windows that were open when you quit. A startup layout uses its own windows instead.")
            HStack {
                TextField("Name this layout", text: $name).textFieldStyle(.roundedBorder)
                Button("Save new") {
                    state.activeLayoutID = library.save(name, recipe: state.workspaceRecipe()); name = ""
                }.disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            if let message = library.message { Text(message).foregroundStyle(.secondary) }
            Divider()
            if library.layouts.isEmpty {
                Text("Your saved workspaces will appear here.").foregroundStyle(.secondary)
            }
            ScrollView {
                VStack(spacing: 10) {
                    ForEach(library.layouts.sorted { $0.favorite != $1.favorite ? $0.favorite : $0.name.localizedStandardCompare($1.name) == .orderedAscending }) { layout in
                        HStack {
                            Button { library.favorite(layout.id) } label: { Image(systemName: layout.favorite ? "star.fill" : "star") }
                                .buttonStyle(.plain).help(layout.favorite ? "Remove from favorites" : "Favorite layout")
                            Button(layout.name) { state.openLayout(layout) }
                                .fontWeight(state.activeLayoutID == layout.id ? .bold : .regular)
                            if library.startup == layout.id { Image(systemName: "power").help("Opens at startup") }
                            if let count = layout.recipe.windows?.count, count > 0 {
                                Label("\(count)", systemImage: "macwindow.on.rectangle").font(.caption).foregroundStyle(.secondary)
                                    .help(count == 1 ? "Includes 1 separate window" : "Includes \(count) separate windows")
                                    .accessibilityLabel(count == 1 ? "Includes 1 separate window" : "Includes \(count) separate windows")
                            }
                            Spacer()
                            Menu {
                                Button("Update from current workspace") { library.update(layout.id, recipe: state.workspaceRecipe()) }
                                Button("Rename…") { renameID = layout.id; renameText = layout.name }
                                Button("Duplicate") { library.save(layout.name + " copy", recipe: layout.recipe) }
                                Button(library.startup == layout.id ? "Stop opening at startup" : "Open at startup") { library.setStartup(library.startup == layout.id ? nil : layout.id) }
                                Divider()
                                Button("Delete…", role: .destructive) { deleteID = layout.id }
                            } label: { Image(systemName: "ellipsis") }.menuStyle(.borderlessButton).frame(width: 24)
                        }
                    }
                }
            }.frame(minHeight: 90, maxHeight: 240)
            Text("Edits do not replace a saved layout until you choose Update. Notes always save separately.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(22).frame(width: 490).foregroundStyle(STColor.ink).background(STColor.paper)
        .alert("Rename layout", isPresented: Binding(get: { renameID != nil }, set: { if !$0 { renameID = nil } })) {
            TextField("Layout name", text: $renameText)
            Button("Save") { if let id = renameID { library.rename(id, to: renameText) }; renameID = nil }
            Button("Cancel", role: .cancel) { renameID = nil }
        }
        .confirmationDialog("Delete this saved layout?", isPresented: Binding(get: { deleteID != nil }, set: { if !$0 { deleteID = nil } }), titleVisibility: .visible) {
            Button("Delete layout", role: .destructive) { if let id = deleteID { library.remove(id); if state.activeLayoutID == id { state.activeLayoutID = nil } }; deleteID = nil }
        } message: { Text("Your notes and resources stay in the library.") }
    }
}
