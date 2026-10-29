import SwiftUI

// MARK: - Notebook templates (data, not hard-coded UI branches)

/// One field a template asks the reader to fill in, stored as a `NoteSection` keyed by `key`.
struct NoteTemplateField: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let label: String
    let placeholder: String
}

/// A note kind's shape: its menu name/icon and its ordered fields. `.free` has no fields — it
/// edits `Note.body` directly, same as every pre-0.10 note.
struct NoteTemplateDefinition: Identifiable {
    var id: NoteKind { kind }
    let kind: NoteKind
    let name: String
    let systemImage: String
    let fields: [NoteTemplateField]
}

enum NoteTemplates {
    static let all: [NoteTemplateDefinition] = [
        NoteTemplateDefinition(kind: .free, name: "Free", systemImage: "square.and.pencil", fields: []),
        NoteTemplateDefinition(kind: .oia, name: "Observation · Interpretation · Application", systemImage: "list.number", fields: [
            NoteTemplateField(key: "observation", label: "Observation", placeholder: "What does the text say?"),
            NoteTemplateField(key: "interpretation", label: "Interpretation", placeholder: "What does it mean?"),
            NoteTemplateField(key: "application", label: "Application", placeholder: "How should this shape life?")
        ]),
        NoteTemplateDefinition(kind: .wordStudy, name: "Word study", systemImage: "textformat.abc", fields: [
            NoteTemplateField(key: "word", label: "Word or phrase", placeholder: "The word or phrase in view"),
            NoteTemplateField(key: "original", label: "Original language", placeholder: "Hebrew / Greek form, gloss"),
            NoteTemplateField(key: "usage", label: "Usage elsewhere", placeholder: "Other occurrences, nuance"),
            NoteTemplateField(key: "conclusion", label: "Conclusion", placeholder: "What this means here")
        ]),
        NoteTemplateDefinition(kind: .sermonIdea, name: "Sermon idea", systemImage: "mic", fields: [
            NoteTemplateField(key: "bigIdea", label: "Big idea", placeholder: "One sentence"),
            NoteTemplateField(key: "points", label: "Points", placeholder: "Outline"),
            NoteTemplateField(key: "illustration", label: "Illustration", placeholder: "Story or example"),
            NoteTemplateField(key: "application", label: "Application", placeholder: "Call to action")
        ])
    ]

    static func definition(for kind: NoteKind) -> NoteTemplateDefinition { all.first { $0.kind == kind } ?? all[0] }
}

/// Posted with a note's `UUID` as `object` when something outside the notebook (the My Study
/// browser) wants a specific note selected once navigation lands on its passage.
extension Notification.Name {
    static let openStudyNote = Notification.Name("Lectern.openStudyNote")
}

/// Pure mirror of `NoteEditor.commit()`'s "would this create a ghost?" check — whether a draft
/// with this kind/body/fields carries any real content — pulled out of the view so the "no ghost
/// notes ever created" invariant is directly unit-testable without driving SwiftUI state.
enum NoteEditorContent {
    static func isEmpty(kind: NoteKind, body: String, fieldTexts: [String: String]) -> Bool {
        guard kind != .free else { return body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let fields = NoteTemplates.definition(for: kind).fields
        return fields.allSatisfy { (fieldTexts[$0.key] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
}

// MARK: - Notes

/// Collapses to one printed line ("NOTEBOOK · Add a note for Romans 8:28") until the selected
/// anchor already has a note, or the reader clicks to write one — an empty notebook used to claim
/// ~45% of the Study Desk column by default, on every single passage, whether or not the reader
/// was using it. Re-derives collapsed/expanded from scratch on every passage change: writing a
/// note on Romans 8:28 doesn't leave John 3:16's notebook pre-expanded.
///
/// Rebuilt for 0.10 wave B: an anchor can carry several notes (New/◂/▸ cycles through them, plus
/// one always-available blank slot), a template menu picks Free / Observation-Interpretation-
/// Application / Word study / Sermon idea (data-driven — see `NoteTemplates`), anchors are shown
/// as editable chips defaulting to `state.selectedAnchor`, and Delete is real (confirms, soft-
/// deletes to Recently Deleted, offers Undo). No note is ever created from an empty draft — only
/// real content typed into the body or a template field creates one — and merely visiting a
/// passage (or a note within it) never touches `modifiedAt`: every field is loaded through
/// `isLoading`, which suppresses the `onChange` commit chain while values are being assigned.
struct NoteEditor: View {
    @EnvironmentObject private var state: AppState
    var startsExpanded = false

    @State private var anchors: [Anchor] = []
    @State private var noteIDsAtAnchor: [UUID] = []
    @State private var position = 0

    @State private var title = ""
    @State private var kind: NoteKind = .free
    @State private var body_ = ""
    @State private var fieldTexts: [String: String] = [:]
    @State private var tags: [String] = []
    @State private var newTagText = ""

    @State private var isLoading = false
    @State private var browsingAllNotes = false
    @State private var manuallyExpanded = false

    @State private var showDeleteConfirm = false
    @State private var pendingKind: NoteKind?
    @State private var showKindChangeConfirm = false
    @State private var lastDeleted: (id: UUID, title: String)?
    @State private var undoWorkItem: DispatchWorkItem?

    @State private var editingAnchorIndex: Int?
    @State private var anchorEditText = ""
    @State private var anchorEditError = false

    private var template: NoteTemplateDefinition { NoteTemplates.definition(for: kind) }
    private var currentNoteID: UUID? { noteIDsAtAnchor.indices.contains(position) ? noteIDsAtAnchor[position] : nil }
    private var totalSlots: Int { noteIDsAtAnchor.count + 1 }
    private var hasContent: Bool {
        kind == .free ? !body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                      : fieldTexts.values.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }
    private var expanded: Bool { startsExpanded || manuallyExpanded || hasContent || currentNoteID != nil }

    var body: some View {
        VStack(spacing: 0) {
            if expanded {
                notebookHeader
                anchorChipsRow
                toolRow
                TextField("Note title", text: $title)
                    .textFieldStyle(.plain).font(STFont.reading(max(19, state.studyFontSize * 1.35), typeface: state.studyTypeface))
                    .padding(.horizontal, 14).frame(height: 38)
                    .onChange(of: title) { _, _ in commit() }
                Rectangle().fill(STColor.hairline).frame(height: 1)
                content
                tagsRow
                if let lastDeleted { undoBanner(for: lastDeleted) }
            } else {
                collapsedBar
            }
        }
        .frame(minHeight: expanded ? 160 : 34, idealHeight: expanded ? 230 : 34, maxHeight: expanded ? .infinity : 34)
        .background(STColor.tileWell.opacity(0.5))
        .overlay(alignment: .top) { Rectangle().fill(STColor.hairline).frame(height: 1) }
        .onAppear { load() }
        .onChange(of: state.passage) { _, _ in load(); manuallyExpanded = false }
        .confirmationDialog("Delete this note?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete", role: .destructive) { confirmDelete() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You can restore it from Recently Deleted for 30 days.")
        }
        .confirmationDialog("Switch template?", isPresented: $showKindChangeConfirm, titleVisibility: .visible) {
            Button("Switch and clear fields", role: .destructive) {
                if let pendingKind { setKind(pendingKind) }
                pendingKind = nil
            }
            Button("Cancel", role: .cancel) { pendingKind = nil }
        } message: {
            Text("Changing the template starts new fields; the current text won't carry over.")
        }
    }

    // MARK: Header

    private var notebookHeader: some View {
        TileHeader(title: "Notes") {
            if totalSlots > 1 || currentNoteID != nil {
                Text(position < noteIDsAtAnchor.count ? "\(position + 1) of \(noteIDsAtAnchor.count)" : "New")
                    .legend(STColor.secondary, size: 9)
            }
            Button { goToPrevious() } label: { Image(systemName: "chevron.left") }
                .buttonStyle(.plain).disabled(position == 0)
                .accessibilityLabel("Previous note at \(state.passage)")
            Button { startNew() } label: { Image(systemName: "plus") }
                .buttonStyle(.plain)
                .accessibilityLabel("New note at \(state.passage)")
            Button { goToNext() } label: { Image(systemName: "chevron.right") }
                .buttonStyle(.plain).disabled(position >= totalSlots - 1)
                .accessibilityLabel("Next note at \(state.passage)")
            if !state.study.allNotes.isEmpty {
                Button { browsingAllNotes = true } label: { Image(systemName: "list.bullet") }
                    .buttonStyle(.plain).help("Browse My Study")
                    .accessibilityLabel("Browse all notes")
            }
            Button { state.showNotes = false } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain).accessibilityLabel("Close notebook")
        }
        .popover(isPresented: $browsingAllNotes) { NotesBrowser().preferredColorScheme(state.colorScheme) }
    }

    private var toolRow: some View {
        HStack(spacing: 10) {
            Menu {
                ForEach(NoteTemplates.all) { def in
                    Button {
                        requestKindChange(def.kind)
                    } label: {
                        if def.kind == kind { Label(def.name, systemImage: "checkmark") } else { Text(def.name) }
                    }
                }
            } label: {
                Label(template.name, systemImage: template.systemImage).font(.system(size: 11, design: .rounded))
            }
            .menuStyle(.borderlessButton).fixedSize()
            .accessibilityLabel("Template, \(template.name)")
            Spacer()
            Button(role: .destructive) { showDeleteConfirm = true } label: { Image(systemName: "trash") }
                .buttonStyle(.plain).disabled(currentNoteID == nil)
                .foregroundStyle(currentNoteID == nil ? STColor.secondary.opacity(0.5) : STColor.warning)
                .accessibilityLabel("Delete this note")
        }
        .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 6)
    }

    // MARK: Anchor chips

    private var anchorChipsRow: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(anchors.enumerated()), id: \.offset) { index, anchor in
                anchorChip(anchor, index: index)
            }
            Button { addAnchor() } label: { Image(systemName: "plus.circle") }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(STColor.secondary)
                .accessibilityLabel("Add another anchor")
                .disabled(state.selectedAnchor == nil)
        }
        .padding(.horizontal, 14).padding(.top, 8)
    }

    private func anchorChip(_ anchor: Anchor, index: Int) -> some View {
        HStack(spacing: 4) {
            Text(anchor.displayString).font(.system(size: 10, weight: .medium, design: .rounded))
            if anchors.count > 1 {
                Button { removeAnchor(at: index) } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).font(.system(size: 8))
                    .accessibilityLabel("Remove anchor \(anchor.displayString)")
            }
        }
        .foregroundStyle(STColor.ink)
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(STColor.tileTop, in: Capsule())
        .overlay(Capsule().stroke(editingAnchorIndex == index && anchorEditError ? STColor.warning : STColor.keyRim, lineWidth: 1))
        .onTapGesture { beginEditingAnchor(index) }
        .popover(isPresented: Binding(get: { editingAnchorIndex == index }, set: { if !$0 { editingAnchorIndex = nil } })) {
            anchorEditPopover(index: index)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Anchor \(anchor.displayString)")
        .accessibilityHint("Double-tap to edit")
        .accessibilityAction { beginEditingAnchor(index) }
    }

    private func anchorEditPopover(index: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Edit anchor").font(.system(size: 12, weight: .semibold, design: .rounded))
            TextField("Romans 8:28–39", text: $anchorEditText)
                .textFieldStyle(.roundedBorder).frame(width: 200)
                .onSubmit { commitAnchorEdit(index: index) }
            if anchorEditError { Text("Not a passage Throughline recognizes.").font(.system(size: 10)).foregroundStyle(STColor.warning) }
            HStack {
                Spacer()
                Button("Cancel") { editingAnchorIndex = nil }
                Button("Save") { commitAnchorEdit(index: index) }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(12)
    }

    private func beginEditingAnchor(_ index: Int) {
        anchorEditText = anchors[index].displayString
        anchorEditError = false
        editingAnchorIndex = index
    }

    private func commitAnchorEdit(index: Int) {
        guard let parsed = Anchor.parse(anchorEditText) else { anchorEditError = true; return }
        anchors[index] = parsed
        editingAnchorIndex = nil
        commit()
    }

    private func addAnchor() {
        guard let anchor = state.selectedAnchor else { return }
        anchors.append(anchor)
        commit()
    }

    private func removeAnchor(at index: Int) {
        guard anchors.count > 1 else { return }
        anchors.remove(at: index)
        commit()
    }

    // MARK: Content

    @ViewBuilder private var content: some View {
        if kind == .free {
            TextEditor(text: $body_)
                .font(STFont.reading(state.studyFontSize, typeface: state.studyTypeface))
                .scrollContentBackground(.hidden)
                .padding(8)
                .overlay(alignment: .topLeading) {
                    if body_.isEmpty {
                        Text("Write a note about \(state.passage)…")
                            .font(STFont.reading(state.studyFontSize, typeface: state.studyTypeface)).foregroundStyle(STColor.secondary)
                            .padding(.horizontal, 13).padding(.top, 9)
                            .allowsHitTesting(false)
                    }
                }
                .onChange(of: body_) { _, _ in commit() }
                .accessibilityLabel("Note text")
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(template.fields) { field in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(field.label.uppercased()).legend(STColor.secondary, size: 9)
                            TextEditor(text: fieldBinding(field.key))
                                .font(STFont.reading(max(state.studyFontSize - 1, 10), typeface: state.studyTypeface))
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 44)
                                .padding(6)
                                .background(STColor.paper.opacity(0.6), in: RoundedRectangle(cornerRadius: 3))
                                .overlay(alignment: .topLeading) {
                                    if (fieldTexts[field.key] ?? "").isEmpty {
                                        Text(field.placeholder).font(STFont.reading(max(state.studyFontSize - 1, 10), typeface: state.studyTypeface)).foregroundStyle(STColor.secondary)
                                            .padding(.horizontal, 11).padding(.top, 7).allowsHitTesting(false)
                                    }
                                }
                                .accessibilityLabel(field.label)
                        }
                    }
                }
                .padding(.horizontal, 14).padding(.vertical, 8)
            }
        }
    }

    private func fieldBinding(_ key: String) -> Binding<String> {
        Binding(get: { fieldTexts[key] ?? "" }, set: { fieldTexts[key] = $0; commit() })
    }

    private var tagsRow: some View {
        FlowLayout(spacing: 5) {
            ForEach(tags, id: \.self) { tag in
                HStack(spacing: 3) {
                    Text("#\(tag)").font(.system(size: 10, design: .rounded))
                    Button { removeTag(tag) } label: { Image(systemName: "xmark") }
                        .buttonStyle(.plain).font(.system(size: 7))
                        .accessibilityLabel("Remove tag \(tag)")
                }
                .foregroundStyle(STColor.secondary)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .overlay(Capsule().stroke(STColor.keyRim, lineWidth: 1))
            }
            TextField("+ tag", text: $newTagText)
                .textFieldStyle(.plain).font(.system(size: 10, design: .rounded))
                .frame(width: 56)
                .onSubmit { addTag() }
                .accessibilityLabel("Add a tag")
        }
        .padding(.horizontal, 14).padding(.vertical, 8)
    }

    private func addTag() {
        let clean = StudyTag.normalize(newTagText)
        newTagText = ""
        guard !clean.isEmpty, !tags.contains(where: { $0.caseInsensitiveCompare(clean) == .orderedSame }) else { return }
        tags.append(clean)
        commit()
    }

    private func removeTag(_ tag: String) {
        tags.removeAll { $0 == tag }
        commit()
    }

    private func undoBanner(for deleted: (id: UUID, title: String)) -> some View {
        HStack {
            Text("Deleted \(deleted.title.isEmpty ? "note" : "\u{201C}\(deleted.title)\u{201D}")").font(.system(size: 11, design: .rounded))
                .foregroundStyle(STColor.secondary).lineLimit(1)
            Spacer()
            Button("Undo") { undoDelete() }.buttonStyle(.plain).font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(STColor.orange)
                .accessibilityLabel("Undo delete")
        }
        .padding(.horizontal, 14).padding(.vertical, 6)
        .background(STColor.tileTop)
        .overlay(alignment: .top) { Rectangle().fill(STColor.hairline).frame(height: 1) }
    }

    private var collapsedBar: some View {
        HStack(spacing: 0) {
            Button { manuallyExpanded = true } label: {
                HStack(spacing: 6) {
                    Image(systemName: "square.and.pencil").font(.system(size: 11))
                    Text("NOTEBOOK").font(STFont.legend(9)).tracking(0.9)
                    Text("Add a note for \(state.passage)")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(STColor.secondary).lineLimit(1)
                    Spacer(minLength: 4)
                }
                .foregroundStyle(STColor.ink)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Notebook, add a note for \(state.passage)")
            if !state.study.allNotes.isEmpty {
                Button { browsingAllNotes = true } label: {
                    Image(systemName: "list.bullet")
                        .frame(width: 28, height: 34)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Browse My Study")
                .accessibilityLabel("Browse all notes")
            }
        }
        .padding(.leading, 14).padding(.trailing, 7)
        .popover(isPresented: $browsingAllNotes) { NotesBrowser().preferredColorScheme(state.colorScheme) }
    }

    // MARK: Loading & navigation among notes at the anchor

    private func load() {
        let anchor = state.selectedAnchor
        let atAnchor = anchor.map { state.study.notes(exactlyAt: $0) } ?? []
        isLoading = true
        anchors = anchor.map { [$0] } ?? []
        noteIDsAtAnchor = atAnchor.sorted { $0.createdAt < $1.createdAt }.map(\.id)
        position = 0
        if let id = currentNoteID, let note = state.study.note(id: id) { applyNote(note) } else { applyDraft() }
        isLoading = false
        lastDeleted = nil
        undoWorkItem?.cancel()
    }

    private func loadSlot(_ index: Int) {
        isLoading = true
        position = index
        if let id = currentNoteID, let note = state.study.note(id: id) { applyNote(note) } else { applyDraft() }
        isLoading = false
    }

    private func goToPrevious() { guard position > 0 else { return }; loadSlot(position - 1) }
    private func goToNext() { guard position < totalSlots - 1 else { return }; loadSlot(position + 1) }
    private func startNew() { loadSlot(noteIDsAtAnchor.count); manuallyExpanded = true }

    private func applyNote(_ note: Note) {
        title = note.title
        kind = note.kind
        body_ = note.body
        tags = note.tags
        if !note.anchors.isEmpty { anchors = note.anchors }
        var texts = Dictionary(uniqueKeysWithValues: note.sections.map { ($0.key, $0.text) })
        for field in NoteTemplates.definition(for: note.kind).fields where texts[field.key] == nil { texts[field.key] = "" }
        fieldTexts = texts
    }

    private func applyDraft() {
        title = ""
        kind = .free
        body_ = ""
        tags = []
        fieldTexts = [:]
    }

    // MARK: Editing

    private func requestKindChange(_ newKind: NoteKind) {
        guard newKind != kind else { return }
        if hasContent {
            pendingKind = newKind
            showKindChangeConfirm = true
        } else {
            setKind(newKind)
        }
    }

    private func setKind(_ newKind: NoteKind) {
        isLoading = true
        kind = newKind
        if newKind != .free { body_ = "" }
        var texts: [String: String] = [:]
        for field in NoteTemplates.definition(for: newKind).fields { texts[field.key] = "" }
        fieldTexts = texts
        isLoading = false
        commit()
    }

    /// Writes the current fields to the store. Suppressed while `load()`/`applyNote`/`applyDraft`
    /// are assigning `@State` in sequence (`isLoading`), so visiting a note or cycling between
    /// notes at the same anchor never fires a spurious edit — the PASTOR-QA "visiting bumps
    /// modifiedAt" defect, reproduced by an `onChange` chain that commits mid-assignment with a
    /// mix of the old note's and the new note's fields.
    private func commit() {
        guard !isLoading else { return }
        let sections: [NoteSection] = kind == .free ? [] : template.fields.map { NoteSection(key: $0.key, text: fieldTexts[$0.key] ?? "") }
        let bodyText = kind == .free ? body_ : ""
        let contentEmpty = NoteEditorContent.isEmpty(kind: kind, body: body_, fieldTexts: fieldTexts)
        if let id = currentNoteID {
            state.study.editNote(id) { note in
                note.title = title
                note.kind = kind
                note.sections = sections
                note.body = bodyText
                note.tags = tags
                if !anchors.isEmpty { note.anchors = anchors }
            }
        } else {
            // Never create a note from an empty draft (no ghost notes) — only real field/body text does.
            guard !contentEmpty, !anchors.isEmpty else { return }
            guard let created = state.study.addNote(anchors: anchors, title: title, kind: kind, body: bodyText, sections: sections, tags: tags) else { return }
            noteIDsAtAnchor.append(created.id)
            position = noteIDsAtAnchor.count - 1
        }
    }

    private func confirmDelete() {
        guard let id = currentNoteID else { return }
        let deletedTitle = title.isEmpty ? (anchors.first?.displayString ?? "") : title
        state.study.deleteNote(id)
        lastDeleted = (id, deletedTitle)
        Announcer.post("Note deleted. Undo available.")
        let removedIndex = position
        noteIDsAtAnchor.removeAll { $0 == id }
        loadSlot(min(removedIndex, noteIDsAtAnchor.count))
        let work = DispatchWorkItem { if lastDeleted?.id == id { lastDeleted = nil } }
        undoWorkItem?.cancel()
        undoWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 6, execute: work)
    }

    private func undoDelete() {
        guard let deleted = lastDeleted else { return }
        state.study.restoreNote(deleted.id)
        lastDeleted = nil
        undoWorkItem?.cancel()
        Announcer.post("Note restored.")
        load()
    }
}

/// Thin, zero-argument wrapper kept so existing call sites (and `SnapshotTests`) compile
/// unchanged; the real browser is `MyStudyBrowser`, scoped to Notes.
struct NotesBrowser: View {
    var body: some View { MyStudyBrowser(initialScope: .notes) }
}
