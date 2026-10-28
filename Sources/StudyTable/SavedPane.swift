import SwiftUI
import UniformTypeIdentifiers

// MARK: - Library "SAVED" mode (0.10, S2a)
//
// Saved passages grouped by collection and by tag, a memory-verse filter, a drill-in per
// collection (Back returns to the overview, same as passage navigation's own Back), collection
// create/rename/reorder/delete, drag-to-collect with a full menu alternative, and recently-deleted
// restore. Collection *display order* is a local UI preference (`StudyCollection` carries no
// position field in the S1 schema) kept on the app's own injected preference store — never written
// to `study.json`.

struct SavedLibraryView: View {
    @EnvironmentObject private var state: AppState
    @State private var memoryOnly = false
    @State private var showRecentlyDeleted = false
    @State private var openCollectionID: UUID?

    private var notes: StudyStore { state.notes }

    var body: some View {
        Group {
            if let openCollectionID, let collection = notes.collections.first(where: { $0.id == openCollectionID }) {
                CollectionDetailView(collection: collection, memoryOnly: memoryOnly) { self.openCollectionID = nil }
            } else {
                overview
            }
        }
        .popover(isPresented: $showRecentlyDeleted) { RecentlyDeletedSavedView() }
    }

    private var controlsRow: some View {
        HStack(spacing: 8) {
            Button { memoryOnly.toggle() } label: {
                HStack(spacing: 5) {
                    Image(systemName: memoryOnly ? "checkmark.seal.fill" : "seal")
                    Text("Memory Verses").font(.system(size: 11, design: .rounded))
                }
            }
            .buttonStyle(.plain)
            .foregroundStyle(memoryOnly ? STColor.ink : STColor.secondary)
            .accessibilityAddTraits(memoryOnly ? .isSelected : [])
            .accessibilityLabel(memoryOnly ? "Memory verses only, on" : "Memory verses only, off")
            .help("Show only verses marked as memory verses")
            Spacer()
            Button { showRecentlyDeleted = true } label: { Image(systemName: "trash") }
                .buttonStyle(.plain)
                .help("Recently deleted saved passages")
                .accessibilityLabel("Recently deleted")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    private var visibleSaved: [SavedPassage] {
        memoryOnly ? notes.savedPassages.filter(\.isMemory) : notes.savedPassages
    }

    private var overview: some View {
        VStack(spacing: 0) {
            controlsRow
            if visibleSaved.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 14) {
                        collectionsSection
                        let tagged = tagGroups(visibleSaved)
                        if !tagged.isEmpty {
                            sectionLabel("TAGS")
                            ForEach(tagged, id: \.tag) { group in
                                DisclosureGroup {
                                    ForEach(group.items) { item in SavedRow(item: item) }
                                } label: {
                                    Text("#\(group.tag)").font(.system(size: 11, weight: .medium, design: .rounded)).foregroundStyle(STColor.ink)
                                }
                                .padding(.horizontal, 4)
                            }
                        }
                        let ungrouped = visibleSaved.filter { $0.collectionIDs.isEmpty && $0.tags.isEmpty }
                        if !ungrouped.isEmpty {
                            sectionLabel("ALL SAVED")
                            ForEach(ungrouped) { item in SavedRow(item: item) }
                        }
                    }
                    .padding(.horizontal, 8).padding(.bottom, 12)
                }
            }
        }
    }

    private var collectionsSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                sectionLabel("COLLECTIONS")
                Spacer()
                Button { newCollection() } label: { Image(systemName: "plus.circle") }
                    .buttonStyle(.plain).help("New Collection").accessibilityLabel("New Collection")
            }
            .padding(.horizontal, 4)
            if notes.collections.isEmpty {
                Text("No collections yet. Save a verse (\u{2318}D), then \u{201C}Add to Collection\u{2026}\u{201D}.")
                    .font(.system(size: 11, design: .rounded)).foregroundStyle(STColor.secondary)
                    .padding(.horizontal, 4)
            } else {
                ForEach(orderedCollections()) { collection in
                    CollectionRow(collection: collection, count: notes.savedPassages(in: collection.id).count) {
                        openCollectionID = collection.id
                    } onRename: {
                        if let name = CollectionNamePrompt.ask(defaultName: collection.name) { notes.renameCollection(collection.id, to: name) }
                    } onDelete: {
                        notes.deleteCollection(collection.id)
                    } onMove: { offset in
                        moveCollection(collection, by: offset)
                    } onDropSavedID: { id in
                        notes.addToCollection(savedID: id, collectionID: collection.id)
                    }
                }
            }
        }
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text).legend(STColor.secondary, size: 9).padding(.horizontal, 4)
    }

    private var emptyState: some View {
        ContentUnavailableView("Nothing saved yet", systemImage: "bookmark",
            description: Text("Select a verse and press \u{2318}D to save it here."))
            .padding(.top, 24)
    }

    private struct TagGroup { let tag: String; let items: [SavedPassage] }

    private func tagGroups(_ saved: [SavedPassage]) -> [TagGroup] {
        var buckets: [String: [SavedPassage]] = [:]
        var order: [String] = []
        for item in saved {
            for tag in item.tags {
                if buckets[tag] == nil { order.append(tag); buckets[tag] = [] }
                buckets[tag]!.append(item)
            }
        }
        return order.map { TagGroup(tag: $0, items: buckets[$0] ?? []) }
    }

    private func newCollection() {
        guard let name = CollectionNamePrompt.ask() else { return }
        notes.createCollection(name: name)
    }

    private func orderedCollections() -> [StudyCollection] {
        let all = notes.collections
        let savedOrder = (state.preferenceStore.array(forKey: "savedCollectionOrder") as? [String])?.compactMap { UUID(uuidString: $0) } ?? []
        let position = Dictionary(uniqueKeysWithValues: savedOrder.enumerated().map { ($1, $0) })
        return all.sorted { a, b in
            switch (position[a.id], position[b.id]) {
            case let (pa?, pb?): return pa < pb
            case (.some, nil): return true
            case (nil, .some): return false
            default: return a.createdAt < b.createdAt
            }
        }
    }

    private func moveCollection(_ collection: StudyCollection, by offset: Int) {
        var order = orderedCollections().map(\.id)
        guard let idx = order.firstIndex(of: collection.id), order.indices.contains(idx + offset) else { return }
        order.swapAt(idx, idx + offset)
        state.preferenceStore.set(order.map(\.uuidString), forKey: "savedCollectionOrder")
    }
}

// MARK: - Collection row (overview) & detail (drilled-in, with Back)

private struct CollectionRow: View {
    let collection: StudyCollection
    let count: Int
    let onOpen: () -> Void
    let onRename: () -> Void
    let onDelete: () -> Void
    let onMove: (Int) -> Void
    /// Called with a saved passage's id when one is dropped here — the drag-to-collect target.
    let onDropSavedID: (UUID) -> Void
    @State private var isTargeted = false

    var body: some View {
        Button(action: onOpen) {
            HStack {
                Text(collection.name).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(STColor.ink)
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("\(count)").font(STFont.numeral(11, weight: .light)).monospacedDigit().foregroundStyle(STColor.secondary)
                Image(systemName: "chevron.right").font(.system(size: 9, weight: .medium)).foregroundStyle(STColor.secondary)
            }
            .padding(.horizontal, 8).frame(height: 27)
            .background(isTargeted ? STColor.orange.opacity(0.16) : Color.clear, in: RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).stroke(isTargeted ? STColor.orange : Color.clear, lineWidth: 1.4))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(collection.name), \(count) saved passage\(count == 1 ? "" : "s")")
        .help("Open \(collection.name) (\(count))")
        // Drag-to-collect: dropping a saved-passage row here adds it. The context menu on every
        // saved row's "Add to Collection ▸" submenu is the full non-drag alternative.
        .onDrop(of: [.text], isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            _ = provider.loadObject(ofClass: NSString.self) { reading, _ in
                guard let idString = reading as? String, let id = UUID(uuidString: idString) else { return }
                Task { @MainActor in onDropSavedID(id) }
            }
            return true
        }
        .contextMenu {
            Button("Rename\u{2026}", action: onRename)
            Button("Move Up") { onMove(-1) }
            Button("Move Down") { onMove(1) }
            Divider()
            Button("Delete Collection", role: .destructive, action: onDelete)
        }
    }
}

private struct CollectionDetailView: View {
    @EnvironmentObject private var state: AppState
    let collection: StudyCollection
    let memoryOnly: Bool
    let onBack: () -> Void

    private var items: [SavedPassage] {
        let all = state.notes.savedPassages(in: collection.id)
        return memoryOnly ? all.filter(\.isMemory) : all
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                Button(action: onBack) { Image(systemName: "chevron.left") }
                    .buttonStyle(.plain).accessibilityLabel("Back to collections")
                Text(collection.name).font(.system(size: 12, weight: .semibold, design: .rounded)).lineLimit(1)
                Spacer()
                Text("\(items.count)").legend()
            }
            .padding(.horizontal, 10).frame(height: 30)
            Rectangle().fill(STColor.hairline).frame(height: 1)
            if items.isEmpty {
                ContentUnavailableView("No saved passages here yet", systemImage: "bookmark",
                    description: Text("Right-click a saved verse and choose \u{201C}Add to Collection\u{201D}, or drag it onto this collection."))
                    .padding(.top, 20)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in SavedRow(item: item, collectionContext: collection) }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 6)
                }
            }
        }
    }
}

// MARK: - One saved passage

private struct SavedRow: View {
    @EnvironmentObject private var state: AppState
    let item: SavedPassage
    var collectionContext: StudyCollection? = nil

    private var accessibilitySummary: String {
        var parts = [item.anchor.displayString]
        if item.isMemory { parts.append("memory verse") }
        if let highlight = item.highlight { parts.append("highlighted \(highlight.displayName.lowercased())") }
        let names = item.collectionIDs.compactMap { id in state.notes.collections.first { $0.id == id }?.name }
        if !names.isEmpty { parts.append("in \(names.joined(separator: ", "))") }
        if !item.tags.isEmpty { parts.append(item.tags.map { "#\($0)" }.joined(separator: " ")) }
        return parts.joined(separator: ", ")
    }

    var body: some View {
        Button(action: open) {
            HStack(spacing: 8) {
                if let highlight = item.highlight {
                    Image(systemName: highlight.glyphName).font(.system(size: 8)).foregroundStyle(highlight.tint)
                } else {
                    Image(systemName: "bookmark.fill").font(.system(size: 8)).foregroundStyle(STColor.secondary)
                }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(item.anchor.displayString).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(STColor.ink)
                        if item.isMemory {
                            Text("MEM").font(.system(size: 7, weight: .bold, design: .rounded)).tracking(0.4)
                                .padding(.horizontal, 3).padding(.vertical, 1)
                                .background(STColor.tileWell, in: RoundedRectangle(cornerRadius: 2))
                                .overlay(RoundedRectangle(cornerRadius: 2).stroke(STColor.keyRim, lineWidth: 0.6))
                        }
                    }
                    if !item.tags.isEmpty {
                        Text(item.tags.map { "#\($0)" }.joined(separator: " "))
                            .font(.system(size: 10, design: .rounded)).foregroundStyle(STColor.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
            }
            .padding(.horizontal, 8).frame(height: 34)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(accessibilitySummary)
        .help("Go to \(item.anchor.displayString)")
        .onDrag { NSItemProvider(object: item.id.uuidString as NSString) }
        .contextMenu {
            Menu("Add to Collection") {
                ForEach(state.notes.collections) { collection in
                    let already = item.collectionIDs.contains(collection.id)
                    Button(already ? "Remove from \(collection.name)" : "Add to \(collection.name)") {
                        MyStudyActions.toggleCollection(collection, for: item.anchor, in: state)
                    }
                }
                if !state.notes.collections.isEmpty { Divider() }
                Button("New Collection\u{2026}") {
                    guard let name = CollectionNamePrompt.ask() else { return }
                    MyStudyActions.createCollectionAndAdd(named: name, anchor: item.anchor, in: state)
                }
            }
            if let collectionContext {
                Button("Remove from \(collectionContext.name)") {
                    state.notes.removeFromCollection(savedID: item.id, collectionID: collectionContext.id)
                }
            }
            Divider()
            Button(item.isMemory ? "Unmark as Memory Verse" : "Mark as Memory Verse") {
                MyStudyActions.toggleMemory(item.anchor, in: state)
            }
            Button("Unsave", role: .destructive) { state.notes.unsave(item.id) }
        }
    }

    private func open() {
        let anchor = item.anchor
        let start = anchor.startVerse
        state.navigate(bookCode: anchor.book, chapter: start.chapter, verse: start.verse)
        if anchor.chapterStart == anchor.chapterEnd, anchor.verseEnd > anchor.verseStart, anchor.verseEnd < Anchor.endOfChapter {
            state.rangeEndVerse = anchor.verseEnd
        }
        state.showLibrary = true
    }
}

// MARK: - Recently deleted (saved passages)

private struct RecentlyDeletedSavedView: View {
    @EnvironmentObject private var state: AppState

    private var items: [DeletedItem] { state.notes.recentlyDeleted.filter { $0.kind == .saved } }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Recently Deleted").font(STFont.title(15)).foregroundStyle(STColor.ink)
                Spacer()
                Text("\(items.count)").legend()
            }
            .padding(12)
            Divider()
            if items.isEmpty {
                ContentUnavailableView("Nothing deleted", systemImage: "trash",
                    description: Text("Unsaved passages stay here for 30 days.")).padding(24)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(items) { item in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.title).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(STColor.ink)
                                    Text("Deleted \(item.deletedAt.formatted(date: .abbreviated, time: .omitted))")
                                        .font(.system(size: 10, design: .rounded)).foregroundStyle(STColor.secondary)
                                }
                                Spacer()
                                Button("Restore") { state.notes.restore(item) }.controlSize(.small)
                                    .accessibilityLabel("Restore \(item.title)")
                            }
                            .padding(.horizontal, 12).padding(.vertical, 8)
                            Rectangle().fill(STColor.hairline).frame(height: 1).padding(.leading, 12)
                        }
                    }
                }
            }
        }
        .frame(width: 300, height: 360)
        .background(STColor.tileTop)
    }
}
