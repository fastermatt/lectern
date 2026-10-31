import SwiftUI
import Combine

/// One editor session moves between pane and window, retaining even unsaved draft fields.
@MainActor
final class NotebookSession: ObservableObject {
    @Published var anchors: [Anchor] = []
    @Published var noteIDsAtAnchor: [UUID] = []
    @Published var position = 0
    @Published var title = ""
    @Published var kind: NoteKind = .free
    @Published var body = ""
    @Published var fieldTexts: [String: String] = [:]
    @Published var tags: [String] = []
    @Published var newTagText = ""
    @Published var isPinned = false
    var pinnedAnchor: Anchor?
    var loadedAnchor: Anchor?
    var lastRequestToken: UUID?
    var didLoad = false
    var loadedNote: Note?
    private weak var store: StudyStore?
    private var storeSubscription: AnyCancellable?

    init(store: StudyStore) {
        self.store = store
        storeSubscription = store.objectWillChange.sink { [weak self] _ in
            Task { @MainActor [weak self] in self?.refreshSavedNote() }
        }
    }

    var currentNoteID: UUID? {
        noteIDsAtAnchor.indices.contains(position) ? noteIDsAtAnchor[position] : nil
    }

    func pin(to anchor: Anchor?) {
        pinnedAnchor = anchor
        isPinned = true
    }

    func apply(_ note: Note) {
        loadedNote = note
        title = note.title
        kind = note.kind
        body = note.body
        tags = note.tags
        if !note.anchors.isEmpty { anchors = note.anchors }
        var fields = Dictionary(uniqueKeysWithValues: note.sections.map { ($0.key, $0.text) })
        for field in NoteTemplates.definition(for: note.kind).fields where fields[field.key] == nil { fields[field.key] = "" }
        fieldTexts = fields
    }

    private func refreshSavedNote() {
        guard let id = currentNoteID, let note = store?.note(id: id), note != loadedNote else { return }
        apply(note)
    }
}
