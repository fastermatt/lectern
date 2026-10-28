import SwiftUI

// MARK: - Library

/// Which content the Library pane shows below its header (0.10, S2a).
enum LibraryMode: String { case books, saved, reading }

struct LibraryPane: View {
    @EnvironmentObject private var state: AppState
    @State private var query = ""
    @State private var libraryMode: LibraryMode = .books
    @StateObject private var puritanLibrary = PuritanLibraryService()

    private var filteredBooks: [BookSummary] {
        bookQuery.isEmpty ? state.library.books : state.library.books.filter { $0.name.localizedCaseInsensitiveContains(bookQuery) }
    }
    private var reference: Anchor? {
        state.library.navigationAnchor(for: query, translationID: state.translationID)
    }
    private var hasInvalidReference: Bool {
        guard let split = BookTable.splitReference(query) else { return false }
        return !split.remainder.isEmpty && reference == nil
    }
    private var bookQuery: String {
        BookTable.splitReference(query)?.0.name ?? query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(spacing: 0) {
            LibraryModePicker(mode: $libraryMode)
            if libraryMode == .saved {
                SavedLibraryView()
            } else if libraryMode == .reading {
                PuritanLibraryView(service: puritanLibrary)
            } else {
                SearchField(text: $query, placeholder: "Find a book or reference").padding(10)
                if let reference, !reference.isWholeBook {
                    Button {
                        if reference.spansChapters {
                            let start = reference.startVerse
                            state.navigate(bookCode: reference.book, chapter: start.chapter, verse: start.verse)
                        } else {
                            state.jumpToReference(query)
                        }
                    } label: {
                        Label(reference.spansChapters ? "Open first verse of \(reference.displayString)" : "Go to \(reference.displayString)", systemImage: "arrow.turn.down.right")
                            .font(.system(size: 11, weight: .medium)).multilineTextAlignment(.leading)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.padding(.horizontal, 12).padding(.bottom, 8)
                } else if hasInvalidReference {
                    Text("Check this passage’s chapter and verse numbers.")
                        .font(.system(size: 11)).foregroundStyle(STColor.secondary)
                        .padding(.horizontal, 12).padding(.bottom, 8)
                }
                HStack(spacing: 0) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(spacing: 1) {
                                ForEach(filteredBooks) { book in
                                    BookRow(book: book, selected: book.code == state.selectedBookCode).id(book.code)
                                }
                                if filteredBooks.isEmpty {
                                    Text("No matching books").font(.system(size: 11)).foregroundStyle(STColor.secondary).padding(12)
                                }
                            }
                            .padding(.horizontal, 8).padding(.bottom, 8)
                        }
                        .onAppear { proxy.scrollTo(state.selectedBookCode, anchor: .center) }
                        .onChange(of: state.selectedBookCode) { _, code in
                            withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo(code, anchor: .center) }
                        }
                    }
                    ChapterGrid().id(state.selectedBookCode)
                }
            }
            TranslationFooter()
        }
        .physicalPaneSurface()
    }

}

/// The BOOKS | SAVED segmented header (0.10, S2a). Styled like the Study Desk's own Commentaries /
/// Study tools switch (`SourcesPane.deskTab`) — a checkmark plus weight/background carry the
/// selected state, never colour alone.
struct LibraryModePicker: View {
    @Binding var mode: LibraryMode

    var body: some View {
        HStack(spacing: 0) {
            tab("Bible", "book", .books)
            tab("Saved", "bookmark", .saved)
            tab("Reading", "clock", .reading)
        }
    }
    private func tab(_ title: String, _ symbol: String, _ value: LibraryMode) -> some View {
        let selected = mode == value
        return Button { mode = value } label: {
            VStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: 17))
                Text(title).lineLimit(1).font(.system(size: 13, weight: selected ? .semibold : .regular))
            }
            .frame(maxWidth: .infinity).frame(height: 72)
            .foregroundStyle(selected ? STColor.navy : STColor.secondary)
            .overlay(alignment: .bottom) { if selected { Rectangle().fill(STColor.navy).frame(height: 2).padding(.horizontal, 14) } }
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct ChapterGrid: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                Text(state.bookName).font(.system(size: 12, weight: .semibold)).lineLimit(1)
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 27), spacing: 4)], spacing: 5) {
                    ForEach(state.book?.chapterNumbers ?? [1], id: \.self) { chapter in
                        Button { state.selectedChapter = chapter } label: {
                            Text("\(chapter)").font(.system(size: 12, weight: state.selectedChapter == chapter ? .semibold : .regular))
                                .frame(maxWidth: .infinity).frame(height: 29)
                                .foregroundStyle(state.selectedChapter == chapter ? STColor.navy : STColor.ink)
                                .background(state.selectedChapter == chapter ? STColor.navy.opacity(0.14) : STColor.tileWell,
                                            in: RoundedRectangle(cornerRadius: 5))
                                .overlay(RoundedRectangle(cornerRadius: 5).stroke(state.selectedChapter == chapter ? STColor.navy : .clear, lineWidth: 1))
                        }.buttonStyle(.plain)
                            .accessibilityLabel("\(state.bookName), chapter \(chapter)")
                            .accessibilityAddTraits(state.selectedChapter == chapter ? .isSelected : [])
                    }
                }
            }.padding(8)
        }.frame(width: 116)
        .overlay(alignment: .leading) { Rectangle().fill(STColor.hairline).frame(width: 0.5) }
    }
}

struct BookRow: View {
    @EnvironmentObject private var state: AppState
    let book: BookSummary
    let selected: Bool

    var body: some View {
        Button { state.selectedBookCode = book.code } label: {
            HStack {
                Text(book.name).lineLimit(1).font(.system(size: 13, weight: selected ? .semibold : .regular))
                Spacer()
                Text("\(book.chapterCount)").font(STFont.numeral(12, weight: .light)).monospacedDigit()
                    .foregroundStyle(selected ? STColor.navy : STColor.secondary)
            }
            .foregroundStyle(selected ? STColor.navy : STColor.ink)
            .padding(.horizontal, 8).frame(height: 29)
            .background(selected ? STColor.navy.opacity(0.10) : Color.clear, in: RoundedRectangle(cornerRadius: 3))
            .overlay(alignment: .leading) {
                if selected { Circle().fill(STColor.orange).frame(width: 4, height: 4).padding(.leading, 3) }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct TranslationFooter: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        if let info = state.translation {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(info.name).font(.system(size: 12, weight: .medium, design: .rounded)).lineLimit(1)
                    Spacer(minLength: 4)
                }
                Text(info.detail).font(.system(size: 10, design: .rounded)).foregroundStyle(STColor.secondary).lineLimit(2)
            }
            .padding(11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(STColor.tileWell)
            .overlay(alignment: .top) { Rectangle().fill(STColor.hairline).frame(height: 1) }
        }
    }
}
