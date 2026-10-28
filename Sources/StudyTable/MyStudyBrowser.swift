import SwiftUI

// MARK: - My Study browser (0.10 wave B)
//
// Replaces `NotesBrowser`'s job: a single scoped window onto everything the reader has built —
// Notes, Saved passages, Clips, Projects — with text/tag/collection filters, "Rom 8"-style
// anchor-overlap search (via `StudyStore.search`), recent/passage sort, open-in-place navigation
// (a Back-able detail view, distinct from the app's own passage-history Back), and a per-scope
// Recently Deleted section with restore/purge. Clips and Projects have no authoring UI yet in
// this wave, so their scopes show real (usually empty) data with an honest empty state rather
// than placeholder content.

/// Which of the four tabs is showing. Distinct from `StudySearchScope` (which also has `.all`)
/// so the segmented control never offers an "everything" tab that would mix unrelated kinds.
enum MyStudyScope: String, CaseIterable, Identifiable {
    case notes = "Notes", saved = "Saved", clips = "Clips", projects = "Projects"
    var id: String { rawValue }

    var searchScope: StudySearchScope {
        switch self {
        case .notes: return .notes
        case .saved: return .saved
        case .clips: return .clips
        case .projects: return .projects
        }
    }
}

enum MyStudySort: String, CaseIterable, Identifiable {
    case recent = "Most recent", passage = "By passage"
    var id: String { rawValue }
}

struct MyStudyBrowser: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var scope: MyStudyScope
    @State private var query = ""
    @State private var sort: MyStudySort = .recent
    @State private var tagFilter: String?
    @State private var collectionFilter: UUID?
    @State private var detail: StudySearchHit?
    @State private var deleteTarget: StudySearchHit?

    init(initialScope: MyStudyScope = .notes) {
        _scope = State(initialValue: initialScope)
    }

    private var effectiveQuery: String {
        var parts = [query]
        if let tagFilter { parts.append("#\(tagFilter)") }
        if scope == .saved, let collectionFilter,
           let name = state.study.collections.first(where: { $0.id == collectionFilter })?.name {
            parts.append(name)
        }
        return parts.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }.joined(separator: " ")
    }

    private var hits: [StudySearchHit] {
        let raw = state.study.search(effectiveQuery, scope: scope.searchScope)
        switch sort {
        case .recent: return raw
        case .passage:
            return raw.sorted { a, b in
                switch (a.anchors.min(), b.anchors.min()) {
                case let (x?, y?): return x < y
                case (nil, _?): return false
                case (_?, nil): return true
                default: return a.date > b.date
                }
            }
        }
    }

    private var tagOptions: [(tag: String, count: Int)] { state.study.tagCounts() }

    private var recentlyDeletedKind: DeletedItem.Kind? {
        switch scope { case .notes: return .note; case .saved: return .saved; default: return nil }
    }
    private var recentlyDeletedForScope: [DeletedItem] {
        guard let kind = recentlyDeletedKind else { return [] }
        return state.study.recentlyDeleted.filter { $0.kind == kind }
    }

    var body: some View {
        VStack(spacing: 0) {
            if let detail {
                StudyItemDetail(hit: detail, onBack: { self.detail = nil }, onOpen: { open(detail) })
            } else {
                header
                Divider()
                list
            }
        }
        .frame(width: 440, height: 560)
        .background(STColor.tileTop)
        .pinchToZoomTextSize($state.studyFontSize, in: 11...20)
        .confirmationDialog(
            deleteTarget.map { "Delete this \(noun(for: $0.kind))?" } ?? "Delete?",
            isPresented: Binding(get: { deleteTarget != nil }, set: { if !$0 { deleteTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let target = deleteTarget { performDelete(target) }
                deleteTarget = nil
            }
            Button("Cancel", role: .cancel) { deleteTarget = nil }
        } message: {
            Text("You can restore it from Recently Deleted for 30 days.")
        }
    }

    // MARK: Header

    private var header: some View {
        VStack(spacing: 8) {
            HStack {
                Text("My Study").font(STFont.title(15)).foregroundStyle(STColor.ink)
                Spacer()
                Text("\(hits.count)").legend()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel("Close My Study")
            }
            Picker("Scope", selection: $scope) {
                ForEach(MyStudyScope.allCases) { s in Text(s.rawValue).tag(s) }
            }
            .pickerStyle(.segmented).labelsHidden()
            .onChange(of: scope) { _, _ in detail = nil; collectionFilter = nil }
            SearchField(text: $query, placeholder: "Search \(scope.rawValue.lowercased())")
            HStack(spacing: 10) {
                Menu {
                    ForEach(MyStudySort.allCases) { option in
                        Button {
                            sort = option
                        } label: {
                            if sort == option { Label(option.rawValue, systemImage: "checkmark") } else { Text(option.rawValue) }
                        }
                    }
                } label: {
                    Label(sort.rawValue, systemImage: "arrow.up.arrow.down").font(.system(size: 11, design: .rounded))
                }
                .menuStyle(.borderlessButton).fixedSize()
                .accessibilityLabel("Sort, \(sort.rawValue)")

                if !tagOptions.isEmpty {
                    Menu {
                        Button("All tags") { tagFilter = nil }
                        Divider()
                        ForEach(tagOptions, id: \.tag) { option in
                            Button("#\(option.tag) (\(option.count))") { tagFilter = option.tag }
                        }
                    } label: {
                        Label(tagFilter.map { "#\($0)" } ?? "Tag", systemImage: "tag").font(.system(size: 11, design: .rounded))
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("Tag filter, \(tagFilter.map { "#\($0)" } ?? "all tags")")
                }

                if scope == .saved, !state.study.collections.isEmpty {
                    Menu {
                        Button("All collections") { collectionFilter = nil }
                        Divider()
                        ForEach(state.study.collections) { collection in
                            Button(collection.name) { collectionFilter = collection.id }
                        }
                    } label: {
                        let name = collectionFilter.flatMap { id in state.study.collections.first { $0.id == id }?.name }
                        Label(name ?? "Collection", systemImage: "folder").font(.system(size: 11, design: .rounded))
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                    .accessibilityLabel("Collection filter")
                }
                Spacer(minLength: 0)
            }
        }
        .padding(12)
    }

    // MARK: List

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                if hits.isEmpty {
                    emptyState.padding(30).frame(maxWidth: .infinity)
                } else {
                    ForEach(hits) { hit in
                        StudyHitRow(hit: hit, onSelect: { detail = hit }, onDelete: isDeletable(hit) ? { deleteTarget = hit } : nil)
                        Rectangle().fill(STColor.hairline).frame(height: 1).padding(.leading, 12)
                    }
                }
                if !recentlyDeletedForScope.isEmpty { recentlyDeletedSection }
            }
        }
    }

    private var emptyState: some View {
        let trimmedQuery = effectiveQuery.trimmingCharacters(in: .whitespaces)
        if !trimmedQuery.isEmpty {
            return ContentUnavailableView("No matches", systemImage: "magnifyingglass",
                                          description: Text("Nothing in \(scope.rawValue.lowercased()) matches “\(query)”."))
        }
        switch scope {
        case .notes:
            return ContentUnavailableView("No notes yet", systemImage: "square.and.pencil",
                                          description: Text("Notes you write on any verse appear here."))
        case .saved:
            return ContentUnavailableView("Nothing saved yet", systemImage: "bookmark",
                                          description: Text("Press ⌘D on a verse, or use its Save action, to save it here."))
        case .clips:
            return ContentUnavailableView("No clips yet", systemImage: "quote.opening",
                                          description: Text("Clipping a commentary excerpt will keep its citation here."))
        case .projects:
            return ContentUnavailableView("No projects yet", systemImage: "doc.text",
                                          description: Text("Sermon and lesson outlines will appear here."))
        }
    }

    private func isDeletable(_ hit: StudySearchHit) -> Bool { hit.kind == .note || hit.kind == .saved }

    private func noun(for kind: StudySearchHit.Kind) -> String {
        switch kind { case .note: return "note"; case .saved: return "saved passage"; case .clip: return "clip"; case .project: return "project" }
    }

    private func performDelete(_ hit: StudySearchHit) {
        switch hit.kind {
        case .note: state.study.deleteNote(hit.id)
        case .saved: state.study.unsave(hit.id)
        case .clip, .project: break
        }
        Announcer.post("Deleted \(noun(for: hit.kind)).")
    }

    private func open(_ hit: StudySearchHit) {
        guard let anchor = hit.anchors.first else { return }
        let start = anchor.startVerse
        state.navigate(bookCode: anchor.book, chapter: start.chapter, verse: start.verse)
        if hit.kind == .note {
            state.showNotes = true
            NotificationCenter.default.post(name: .openStudyNote, object: hit.id)
        }
        dismiss()
    }

    // MARK: Recently deleted

    private var recentlyDeletedSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("RECENTLY DELETED").legend().padding(.horizontal, 12).padding(.top, 16).padding(.bottom, 6)
            ForEach(recentlyDeletedForScope) { item in
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.title.isEmpty ? "Untitled" : item.title)
                            .font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(STColor.ink).lineLimit(1)
                        Text("Deleted \(item.deletedAt.formatted(date: .abbreviated, time: .omitted))")
                            .legend(STColor.secondary, size: 9)
                    }
                    Spacer()
                    Button("Restore") { restore(item) }
                        .buttonStyle(.plain).font(.system(size: 11, weight: .semibold, design: .rounded))
                        .foregroundStyle(STColor.orange)
                    Button { purge(item) } label: { Image(systemName: "trash") }
                        .buttonStyle(.plain).foregroundStyle(STColor.secondary)
                        .accessibilityLabel("Delete permanently")
                }
                .padding(.horizontal, 12).padding(.vertical, 6)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(item.title.isEmpty ? "Untitled" : item.title), deleted, expires \(item.expiresAt.formatted(date: .abbreviated, time: .omitted))")
                .accessibilityAction(named: "Restore") { restore(item) }
                .accessibilityAction(named: "Delete permanently") { purge(item) }
            }
        }
    }

    private func restore(_ item: DeletedItem) {
        state.study.restore(item)
        Announcer.post("Restored \(item.title.isEmpty ? "item" : item.title).")
    }

    private func purge(_ item: DeletedItem) {
        switch item.kind {
        case .note: state.study.purgeNote(item.id)
        case .saved: state.study.purgeSaved(item.id)
        }
    }
}

// MARK: - Row

private struct StudyHitRow: View {
    @EnvironmentObject private var state: AppState
    let hit: StudySearchHit
    let onSelect: () -> Void
    let onDelete: (() -> Void)?

    private var reference: String {
        hit.anchors.isEmpty ? "No passage" : hit.anchors.map(\.displayString).joined(separator: "; ")
    }
    private var kindWord: String {
        switch hit.kind { case .note: return "note"; case .saved: return "saved passage"; case .clip: return "clip"; case .project: return "project" }
    }
    /// Extra context read from the full record (tags/collections/memory/highlight) — `StudySearchHit`
    /// itself only carries title/snippet, not enough for the accessibility spec's combined label
    /// ("Romans 8:28–30, note, in Security in Christ").
    private var context: [String] {
        switch hit.kind {
        case .note:
            guard let note = state.study.note(id: hit.id) else { return [] }
            return note.tags.isEmpty ? [] : ["tagged \(note.tags.joined(separator: ", "))"]
        case .saved:
            guard let saved = state.study.savedPassage(id: hit.id) else { return [] }
            var parts: [String] = []
            let names = saved.collectionIDs.compactMap { id in state.study.collections.first { $0.id == id }?.name }
            if !names.isEmpty { parts.append("in \(names.joined(separator: ", "))") }
            if saved.isMemory { parts.append("memory verse") }
            if let highlight = saved.highlight { parts.append("\(highlight.displayName) highlight") }
            return parts
        case .clip, .project:
            return []
        }
    }

    var body: some View {
        Button(action: onSelect) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(reference).font(.system(size: 12, weight: .semibold, design: .rounded)).foregroundStyle(STColor.ink).lineLimit(1)
                    if hit.viaAnchor {
                        Image(systemName: "book.closed").font(.system(size: 9)).foregroundStyle(STColor.secondary)
                            .help("Matched by overlapping passage")
                    }
                    Spacer()
                    Text(hit.date.formatted(date: .abbreviated, time: .omitted)).legend(STColor.secondary, size: 9)
                }
                Text(hit.title).font(.system(size: 12, weight: .medium, design: .rounded)).foregroundStyle(STColor.ink).lineLimit(1)
                if !hit.snippet.isEmpty {
                    Text(hit.snippet).font(.system(size: 11, design: .rounded)).foregroundStyle(STColor.secondary).lineLimit(2)
                }
                if !context.isEmpty {
                    Text(context.joined(separator: " · ")).legend(STColor.secondary, size: 9)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12).padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(([reference, kindWord] + context).joined(separator: ", "))
        .accessibilityAddTraits(.isButton)
        .accessibilityAction(named: "Open") { onSelect() }
        .accessibilityAction(named: "Delete") { onDelete?() }
    }
}

// MARK: - Detail (open-in-place, with its own Back)

private struct StudyItemDetail: View {
    @EnvironmentObject private var state: AppState
    let hit: StudySearchHit
    let onBack: () -> Void
    let onOpen: () -> Void
    @State private var showDeleteConfirm = false

    private var isDeletable: Bool { hit.kind == .note || hit.kind == .saved }
    private var kindNoun: String {
        switch hit.kind { case .note: return "note"; case .saved: return "saved passage"; case .clip: return "clip"; case .project: return "project" }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button(action: onBack) { Label("Back", systemImage: "chevron.left") }
                    .buttonStyle(.plain).font(.system(size: 12, weight: .medium, design: .rounded))
                    .foregroundStyle(STColor.ink)
                    .accessibilityLabel("Back to My Study list")
                Spacer()
            }
            .padding(12)
            Divider()
            ScrollView { detailContent.padding(14).frame(maxWidth: .infinity, alignment: .leading) }
            Divider()
            HStack {
                if isDeletable {
                    Button(role: .destructive) { showDeleteConfirm = true } label: { Label("Delete", systemImage: "trash") }
                        .buttonStyle(.plain).foregroundStyle(STColor.warning)
                }
                Spacer()
                Button(action: onOpen) { Label("Open in Reader", systemImage: "arrow.right.circle") }
                    .buttonStyle(.plain).foregroundStyle(STColor.orange)
                    .disabled(hit.anchors.isEmpty)
            }
            .padding(12)
        }
        .background(STColor.tileTop)
        .confirmationDialog("Delete this \(kindNoun)?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { performDelete(); onBack() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can restore it from Recently Deleted for 30 days.")
        }
    }

    private func performDelete() {
        switch hit.kind {
        case .note: state.study.deleteNote(hit.id)
        case .saved: state.study.unsave(hit.id)
        case .clip, .project: break
        }
        Announcer.post("Deleted \(kindNoun).")
    }

    @ViewBuilder private var detailContent: some View {
        switch hit.kind {
        case .note: noteDetail
        case .saved: savedDetail
        case .clip: clipDetail
        case .project: projectDetail
        }
    }

    @ViewBuilder private var noteDetail: some View {
        if let note = state.study.note(id: hit.id) {
            VStack(alignment: .leading, spacing: 10) {
                if !note.title.isEmpty { Text(note.title).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(STColor.ink) }
                Text(NoteTemplates.definition(for: note.kind).name.uppercased()).legend()
                FlowLayout(spacing: 6) {
                    ForEach(note.anchors, id: \.self) { anchor in
                        Text(anchor.displayString).font(.system(size: 11, weight: .medium, design: .rounded))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(STColor.tileWell, in: Capsule())
                    }
                }
                if note.kind == .free {
                    Text(note.body.isEmpty ? "(No text)" : note.body)
                        .font(STFont.reading(state.studyFontSize, typeface: state.studyTypeface)).foregroundStyle(STColor.ink)
                } else {
                    ForEach(note.sections, id: \.key) { section in
                        if !section.text.isEmpty {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(NoteTemplates.definition(for: note.kind).fields.first { $0.key == section.key }?.label.uppercased() ?? section.key.uppercased())
                                    .legend(STColor.secondary, size: 9)
                                Text(section.text).font(STFont.reading(state.studyFontSize, typeface: state.studyTypeface)).foregroundStyle(STColor.ink)
                            }
                        }
                    }
                }
                if !note.tags.isEmpty { Text(note.tags.map { "#\($0)" }.joined(separator: "  ")).legend(STColor.orange, size: 10) }
                Text("Created \(note.createdAt.formatted(date: .abbreviated, time: .omitted)) · Modified \(note.modifiedAt.formatted(date: .abbreviated, time: .omitted))")
                    .legend(STColor.secondary, size: 9)
            }
        } else {
            Text("This note is no longer available.").foregroundStyle(STColor.secondary)
        }
    }

    @ViewBuilder private var savedDetail: some View {
        if let saved = state.study.savedPassage(id: hit.id) {
            VStack(alignment: .leading, spacing: 10) {
                Text(saved.anchor.displayString).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(STColor.ink)
                HStack(spacing: 10) {
                    if let highlight = saved.highlight {
                        Label(highlight.displayName, systemImage: highlight.glyphName)
                            .font(.system(size: 11, design: .rounded)).foregroundStyle(highlight.tint)
                    }
                    if saved.isMemory { Label("Memory verse", systemImage: "brain").font(.system(size: 11, design: .rounded)) }
                }
                .foregroundStyle(STColor.secondary)
                let names = saved.collectionIDs.compactMap { id in state.study.collections.first { $0.id == id }?.name }
                if !names.isEmpty { Text("In \(names.joined(separator: ", "))").font(.system(size: 12, design: .rounded)).foregroundStyle(STColor.ink) }
                if !saved.tags.isEmpty { Text(saved.tags.map { "#\($0)" }.joined(separator: "  ")).legend(STColor.orange, size: 10) }
                Text("Saved \(saved.createdAt.formatted(date: .abbreviated, time: .omitted))").legend(STColor.secondary, size: 9)
            }
        } else {
            Text("This saved passage is no longer available.").foregroundStyle(STColor.secondary)
        }
    }

    @ViewBuilder private var clipDetail: some View {
        if let clip = state.study.clips.first(where: { $0.id == hit.id }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(clip.excerpt).font(STFont.reading(13)).foregroundStyle(STColor.ink)
                Text("\(clip.citation.author.isEmpty ? "Unknown author" : clip.citation.author)\(clip.citation.work.isEmpty ? "" : ", \(clip.citation.work)")")
                    .legend(STColor.secondary, size: 10)
                if let anchor = clip.anchor { Text(anchor.displayString).legend(STColor.secondary, size: 9) }
            }
        } else {
            Text("This clip is no longer available.").foregroundStyle(STColor.secondary)
        }
    }

    @ViewBuilder private var projectDetail: some View {
        if let project = state.study.projects.first(where: { $0.id == hit.id }) {
            VStack(alignment: .leading, spacing: 10) {
                Text(project.title).font(.system(size: 15, weight: .semibold, design: .rounded)).foregroundStyle(STColor.ink)
                Text("\(project.kind.rawValue.capitalized) · \(project.status.rawValue.capitalized)").legend(STColor.secondary, size: 10)
                if let anchor = project.primaryAnchor { Text(anchor.displayString).legend(STColor.secondary, size: 9) }
                Text("\(project.outline.count) outline item\(project.outline.count == 1 ? "" : "s")").legend(STColor.secondary, size: 9)
            }
        } else {
            Text("This project is no longer available.").foregroundStyle(STColor.secondary)
        }
    }
}
