import SwiftUI

/// One precise passage control; reading and verse selection happen in the text itself.
struct ReadingNavigation: View {
    @EnvironmentObject private var state: AppState
    @State private var showingJump = false

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Button { showingJump = true } label: {
                    HStack(spacing: 6) {
                        Text("\(state.bookName) \(state.selectedChapter)").lineLimit(1)
                        Image(systemName: "chevron.down").font(.system(size: 9))
                    }
                    .font(STFont.reading(28))
                    .foregroundStyle(STColor.ink)
                    .frame(minHeight: 38, alignment: .leading)
                }
                .buttonStyle(.plain)
                .help("Jump to a passage")
                .popover(isPresented: $showingJump) {
                    PassageJumpPanel { showingJump = false }.environmentObject(state)
                }
                Spacer(minLength: 0)
                Menu {
                    ForEach(state.library.translations) { info in
                        Button("\(info.id) — \(info.detail)") { state.translationID = info.id }
                    }
                    Divider()
                    Button("Translation settings…") { openSettings(.translations) }
                } label: {
                    Text(state.translationID).font(.system(size: 12, weight: .semibold, design: .monospaced))
                }
                .menuStyle(.borderlessButton).fixedSize()
                .help("Choose translation; manage downloads in Translation settings")
                chapterKey(-1)
                chapterKey(1)
            }
            if let previous = state.passageHistory.last {
                Button { state.returnToPreviousPassage() } label: {
                    Label("Back to \(previous)", systemImage: "arrow.uturn.backward")
                        .font(.system(size: 11)).foregroundStyle(STColor.ink)
                }
                .buttonStyle(.plain).frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.horizontal, 22).padding(.top, 18).padding(.bottom, 8)
    }

    private func chapterKey(_ direction: Int) -> some View {
        let atEnd = direction < 0
            ? state.selectedBookCode == "GEN" && state.selectedChapter == 1
            : state.selectedBookCode == "REV" && state.selectedChapter == 22
        return Button { state.stepChapter(direction) } label: {
            Image(systemName: direction < 0 ? "chevron.left" : "chevron.right")
                .font(.system(size: 11)).frame(width: 32, height: 32)
        }
        .buttonStyle(ReadingKeyStyle())
        .disabled(atEnd).opacity(atEnd ? 0.4 : 1)
        .accessibilityLabel(direction < 0 ? "Previous chapter" : "Next chapter")
        .help(direction < 0 ? "Previous chapter" : "Next chapter")
    }
}

/// Chapter keys use the same ivory cap and dark recess as the instrument deck.
struct ReadingKeyStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.foregroundStyle(STColor.ink)
            .background(configuration.isPressed ? STColor.tileWell : STColor.paper, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(STColor.hairline, lineWidth: 1))

    }
}

struct PassageJumpPanel: View {
    @EnvironmentObject private var state: AppState
    let dismiss: () -> Void
    @State private var query = ""
    @State private var invalid = false
    @FocusState private var editing: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Go to passage").font(STFont.title(17))
            HStack {
                TextField("John 3:16", text: $query).textFieldStyle(.roundedBorder)
                    .focused($editing).onSubmit(jump)
                    .onChange(of: query) { _, _ in invalid = false }
                Button("Go", action: jump).keyboardShortcut(.defaultAction)
            }
            if invalid {
                Text("Enter a book and valid chapter or verse, such as Romans 8:28.")
                    .font(.caption).foregroundStyle(STColor.ink)
            }
            Divider()
            Menu("Book: \(state.bookName)") {
                ForEach(state.library.books) { book in
                    Button(book.name) { state.navigate(bookCode: book.code, chapter: 1, verse: 1) }
                }
            }
            HStack {
                Menu("Chapter: \(state.selectedChapter)") {
                    ForEach(state.book?.chapterNumbers ?? [1], id: \.self) { chapter in
                        Button("\(chapter)") { state.navigate(bookCode: state.selectedBookCode, chapter: chapter, verse: 1) }
                    }
                }
                Menu("Verse: \(state.selectedVerse ?? 1)") {
                    ForEach(1...max(1, state.verseCount), id: \.self) { verse in
                        Button("\(verse)") {
                            state.navigate(bookCode: state.selectedBookCode, chapter: state.selectedChapter, verse: verse)
                            dismiss()
                        }
                    }
                }
            }
            Text("Or click any verse in the reading pane to study it.")
                .font(.caption).foregroundStyle(STColor.secondary)
        }
        .padding(20).frame(width: 330)
        .foregroundStyle(STColor.ink).background(STColor.tileTop)
        .onAppear { editing = true }
    }

    private func jump() {
        if state.jumpToReference(query) { dismiss() } else { invalid = true }
    }
}
