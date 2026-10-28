import SwiftUI

enum BibleSearchArea: String, CaseIterable, Identifiable {
    case bible = "Whole Bible", oldTestament = "Old Testament", newTestament = "New Testament"
    case currentBook = "Current book", passage = "Custom passage"
    var id: String { rawValue }
}

/// Owned by the window, so reading a hit and reopening Search keeps the investigation intact.
/// Search translation is independent of subsequent reader translation changes; opening a hit
/// explicitly applies the search translation to the reader.
@MainActor
final class BibleSearchSession: ObservableObject {
    @Published var query: String { didSet { if query != oldValue { offset = 0 } } }
    @Published var translationID: String { didSet { if translationID != oldValue { offset = 0 } } }
    @Published var area: BibleSearchArea { didSet { if area != oldValue { offset = 0 } } }
    @Published var passage: String { didSet { if passage != oldValue { offset = 0 } } }
    @Published var offset: Int
    private var hasInitialContext = false
    private var currentBook: String?

    init(query: String = "", translationID: String = "", area: BibleSearchArea = .bible,
         passage: String = "", offset: Int = 0) {
        self.query = query
        self.translationID = translationID
        self.area = area
        self.passage = passage
        self.offset = max(0, offset)
    }

    /// Seed a new session once; later appearances retain the reader's search choices.
    func prepareContext(translationID readerTranslation: String, passage readerPassage: String, book: String) {
        let preservedOffset = offset
        if translationID.isEmpty { translationID = readerTranslation }
        if !hasInitialContext, passage.isEmpty { passage = readerPassage }
        offset = preservedOffset
        hasInitialContext = true
        updateCurrentBook(book)
    }

    func updateCurrentBook(_ book: String) {
        if let currentBook, currentBook != book, area == .currentBook { offset = 0 }
        currentBook = book
    }
}
