import SwiftUI

/// Focused offline search workspace. A task's identity includes every input that can change
/// its answer; cancellation and a final identity check prevent late results replacing new ones.
struct BibleSearchView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @FocusState private var queryFocused: Bool
    @ObservedObject var session: BibleSearchSession
    @State private var page: BibleSearchPage?
    @State private var error: String?
    @State private var isLoading = false
    @State private var catalogRevision = UUID()

    private struct Request: Hashable {
        let query: String
        let source: BibleSearchSource?
        let translation: String
        let area: BibleSearchArea
        let book: String
        let passage: String
        let offset: Int
        let catalogRevision: UUID
    }
    private var request: Request {
        Request(query: session.query, source: state.library.searchSource(translationID: session.translationID),
                translation: session.translationID, area: session.area, book: state.selectedBookCode,
                passage: session.passage, offset: session.offset, catalogRevision: catalogRevision)
    }

    init(session: BibleSearchSession) {
        _session = ObservedObject(wrappedValue: session)
    }

    var body: some View {
        VStack(spacing: 0) {
            TileHeader(title: "Search Bible") {
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass").foregroundStyle(STColor.secondary)
                    TextField("Words, a quoted phrase, or a Boolean query", text: $session.query)
                        .textFieldStyle(.plain).font(.system(size: 16)).focused($queryFocused)
                        .accessibilityLabel("Search Bible words or phrases")
                    if !session.query.isEmpty {
                        Button { session.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.plain).accessibilityLabel("Clear search")
                    }
                }
                .padding(11).background(STColor.paper, in: RoundedRectangle(cornerRadius: 5))
                .overlay(RoundedRectangle(cornerRadius: 5).stroke(STColor.hairline))
                HStack(spacing: 16) {
                    Picker("Translation", selection: $session.translationID) {
                        if session.translationID.isEmpty { Text("Choose translation").tag("") }
                        ForEach(state.library.translations) { info in
                            Text("\(info.id) · \(info.isOffline ? "Offline" : "No local pack")").tag(info.id)
                        }
                    }.frame(width: 245)
                    Picker("Search in", selection: $session.area) {
                        ForEach(BibleSearchArea.allCases) { Text($0.rawValue).tag($0) }
                    }.frame(maxWidth: .infinity)
                }
                if session.area == .passage {
                    TextField("Passage, e.g. Romans 8:28–9:5", text: $session.passage)
                        .textFieldStyle(.roundedBorder).accessibilityLabel("Custom search passage")
                } else if session.area == .currentBook {
                    Text("Searching \(state.bookName)").font(.system(size: 12)).foregroundStyle(STColor.secondary)
                }
                Text("Words use AND by default. Try \"in the beginning\", faith OR hope, love NOT world, (faith OR hope) AND lov*.")
                    .font(.system(size: 11)).foregroundStyle(STColor.secondary).fixedSize(horizontal: false, vertical: true)
                Text("Whole words · uppercase operators · phrases ignore punctuation · verse-by-verse matches")
                    .font(.system(size: 10)).foregroundStyle(STColor.secondary)
            }.padding(16)
            if (page?.translationID ?? session.translationID) == "DBY" {
                DarbyComparisonNotice(translationID: "DBY")
                    .padding(.horizontal, 16).padding(.bottom, 10)
            }
            Rectangle().fill(STColor.hairline).frame(height: 1)
            results.frame(maxWidth: .infinity, maxHeight: .infinity).background(STColor.paper)
            Rectangle().fill(STColor.hairline).frame(height: 1)
            if let info = state.library.translation(id: page?.translationID ?? session.translationID), !info.attribution.isEmpty {
                if info.attribution.count <= 150 {
                    Text(info.attribution).font(.system(size: 10)).foregroundStyle(STColor.secondary)
                        .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 14).padding(.top, 9)
                } else {
                    DisclosureGroup("Translation attribution · \(info.id)") {
                        ScrollView {
                            Text(info.attribution).font(.system(size: 11)).textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }.frame(maxHeight: 72)
                    }
                    .font(.system(size: 11)).padding(.horizontal, 14).padding(.top, 9)
                }
            }
            HStack {
                if let page, !isLoading, error == nil {
                    Text(page.total == 0 ? "0 verses · \(page.translationID)" : "\(page.offset + 1)–\(page.offset + page.hits.count) of \(page.total) verses · \(page.translationID)")
                        .font(.system(size: 12, weight: .medium)).monospacedDigit()
                    Spacer()
                    Button("Previous") { session.offset = max(0, session.offset - 40) }.disabled(page.offset == 0)
                    Button("Next") { session.offset += 40 }.disabled(page.offset + page.hits.count >= page.total)
                } else {
                    Text("Local Scripture packs · no network required").font(.system(size: 11)).foregroundStyle(STColor.secondary)
                    Spacer()
                }
            }.padding(14).frame(height: 54)
        }
        .foregroundStyle(STColor.ink).physicalPaneSurface()
        .frame(width: 760, height: 620)
        .onAppear {
            session.prepareContext(translationID: state.translationID,
                                   passage: state.selectedAnchor?.displayString ?? state.passage,
                                   book: state.selectedBookCode)
            queryFocused = true
        }
        .onChange(of: state.selectedBookCode) { _, book in session.updateCurrentBook(book) }
        .onReceive(state.library.objectWillChange) { _ in
            catalogRevision = UUID(); session.offset = 0
        }
        .task(id: request) { await search(request) }
    }

    @ViewBuilder private var results: some View {
        if let error {
            ContentUnavailableView("Search needs attention", systemImage: "exclamationmark.magnifyingglass", description: Text(error))
        } else if isLoading {
            VStack(spacing: 12) {
                ProgressView()
                Text("Searching \(session.translationID)…").font(.system(size: 13)).foregroundStyle(STColor.secondary)
            }
        } else if let page {
            if page.hits.isEmpty {
                ContentUnavailableView("No matching verses", systemImage: "magnifyingglass", description: Text("Try another word or broaden the search area."))
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(page.hits) { hit in
                                Button {
                                    state.translationID = page.translationID
                                    state.navigate(bookCode: hit.bookCode, chapter: hit.chapter, verse: hit.verse)
                                    dismiss()
                                } label: {
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(hit.reference).font(.system(size: 12, weight: .semibold, design: .rounded))
                                        Text(hit.text).font(STFont.reading(16)).multilineTextAlignment(.leading)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 20).padding(.vertical, 12)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain).id(hit.id)
                                .accessibilityHint("Read this verse in \(page.translationID)")
                                Rectangle().fill(STColor.hairline).frame(height: 1).padding(.horizontal, 20)
                            }
                        }
                    }.onChange(of: page.offset) { _, _ in
                        if let first = page.hits.first { proxy.scrollTo(first.id, anchor: .top) }
                    }
                }
            }
        } else {
            ContentUnavailableView("Find words in Scripture", systemImage: "text.magnifyingglass", description: Text("Search an installed translation, then choose a verse to read it in context."))
        }
    }

    @MainActor private func search(_ input: Request) async {
        page = nil; error = nil; isLoading = false
        guard !input.translation.isEmpty else { return }
        guard input.source != nil else { error = BibleSearchError.unavailable.localizedDescription; return }
        guard !input.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        isLoading = true
        do {
            try await Task.sleep(for: .milliseconds(180))
            let scope: BibleSearchScope
            switch input.area {
            case .bible: scope = .bible
            case .oldTestament: scope = .oldTestament
            case .newTestament: scope = .newTestament
            case .currentBook: scope = .book(input.book)
            case .passage:
                guard let anchor = Anchor.parse(input.passage) else {
                    throw BibleSearchError.syntax("Enter one passage, such as John 3:16, Rom 8:28–39, or Romans 8:28–9:5.")
                }
                scope = .passage(anchor)
            }
            let result = try await BibleSearchEngine.shared.search(source: input.source, query: input.query, scope: scope, offset: input.offset)
            try Task.checkCancellation()
            guard input == request else { return }
            page = result; isLoading = false
        } catch is CancellationError {
            // The replacement task owns the current loading/result state.
        } catch {
            guard !Task.isCancelled, input == request else { return }
            self.error = error.localizedDescription; isLoading = false
        }
    }
}
