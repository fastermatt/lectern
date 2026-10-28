import SwiftUI

/// One translation's rendering of the selected verse, for `CompareSection`.
struct CompareRow: Identifiable, Equatable {
    let id: String        // translation id, e.g. "BSB"
    let label: String     // "BSB", "ESV"...
    let text: String
    let isCached: Bool     // true only for an online translation served from its local cache
    var attribution: String = ""
}

/// Every bundled/installed (fully offline) translation's rendering of one verse — the part of
/// `CompareSection` that never needs a `.task` round trip, pulled out as a free function so
/// `ReferenceTests.swift` can assert "≥3 offline translations for John 3:16" directly against
/// the exact code path the view uses, not a reimplementation of it.
@MainActor
func compareOfflineRows(library: ScriptureLibrary, bookCode: String, chapter: Int, verse: Int) -> [CompareRow] {
    guard verse > 0 else { return [] }
    var rows: [CompareRow] = []
    for info in library.translations where info.isOffline {
        guard let verses = library.chapter(translation: info.id, bookCode: bookCode, chapter: chapter),
              let match = verses.first(where: { $0.number == verse }), !match.text.isEmpty else { continue }
        rows.append(CompareRow(id: info.id, label: info.id, text: match.text, isCached: false,
                               attribution: info.attribution))
    }
    return rows
}

/// Study Desk section showing the selected verse in every translation available *offline*
/// right now — every bundled/installed pack, plus ESV/NKJV only when a copy is already
/// cached from an earlier online read (WORKPLAN-0.8 §J.4). Never triggers a network fetch:
/// bundled/installed packs are read synchronously from `ScriptureLibrary` (already local
/// data), and the online providers are checked with `OnlineChapterCache.get`, which only
/// reads what's on disk and expires stale entries — the same cache-only call every other
/// online-aware view in this app already treats as free. Self-contained: reads `ScriptureLibrary`
/// read-only via `AppState.library`, never a `Package.swift`/`ScriptureLibrary.swift` change.
struct CompareSection: View {
    @EnvironmentObject private var state: AppState
    @AppStorage("desk.compareExpanded") private var sectionExpanded = false
    @State private var cachedRows: [CompareRow] = []
    @State private var cachedPassage: String?

    private var passageKey: String {
        "\(state.selectedBookCode).\(state.selectedChapter).\(state.selectedVerse ?? 0)"
    }

    private var verse: Int? {
        guard let v = state.selectedVerse, v > 0 else { return nil }
        return v
    }

    /// Bundled/installed offline translations only need a synchronous local read — no
    /// `.task` round trip, so these are always present even before the online cache check
    /// below finishes.
    private var offlineRows: [CompareRow] {
        guard let code = state.book?.code, let verse else { return [] }
        return compareOfflineRows(library: state.library, bookCode: code, chapter: state.selectedChapter, verse: verse)
    }

    private var onlineRows: [CompareRow] {
        guard state.book != nil, verse != nil, cachedPassage == passageKey else { return [] }
        return cachedRows
    }

    private var rows: [CompareRow] { offlineRows + onlineRows }

    var body: some View {
        let items = rows
        VStack(alignment: .leading, spacing: 0) {
            DeskSectionHeader(title: "Compare", color: STColor.navyOnBlack, count: items.count,
                              expanded: $sectionExpanded)
            if sectionExpanded {
                if items.isEmpty {
                    Text("No translations available for this verse.")
                        .font(.system(size: 11, design: .rounded))
                        .foregroundStyle(STColor.secondary)
                        .padding(.horizontal, 12).padding(.vertical, 10)
                } else {
                    ForEach(items) { row in
                        CompareRowView(row: row)
                        Rectangle().fill(STColor.hairline).frame(height: 1)
                    }
                }
            } else if !items.isEmpty {
                DeskCollapsedSummary(section: "Compare", text: items.map(\.label).joined(separator: "  \u{00B7}  ")) {
                    sectionExpanded = true
                }
            }
        }
        .task(id: passageKey) {
            await loadCachedOnlineTranslations()
        }
    }

    /// Reads (never fetches) each online provider's local cache for this exact chapter, per
    /// the publisher storage limits `OnlineTranslations.swift` already enforces on write.
    private func loadCachedOnlineTranslations() async {
        cachedRows = []
        cachedPassage = nil
        let requestedPassage = passageKey
        guard let code = state.book?.code else { return }
        let chapter = state.selectedChapter
        guard let verse = state.selectedVerse, verse > 0 else { return }
        var result: [CompareRow] = []
        for info in state.library.translations {
            guard case .online(let provider) = info.delivery else { continue }
            if let cached = await state.online.cache.get(provider, translation: info.id, book: code, chapter: chapter),
               let match = cached.verses.first(where: { $0.n == verse }), !match.t.isEmpty {
                result.append(CompareRow(id: info.id, label: info.id, text: match.t, isCached: true,
                                         attribution: cached.attribution.isEmpty ? info.attribution : cached.attribution))
            }
        }
        guard !Task.isCancelled, passageKey == requestedPassage else { return }
        cachedRows = result
        cachedPassage = requestedPassage
    }
}

private struct CompareRowView: View {
    @EnvironmentObject private var state: AppState
    let row: CompareRow

    var body: some View {
        DeskCard {
            HStack(spacing: 6) {
                Text(row.label).font(STFont.lcd(11, weight: .medium)).foregroundStyle(STColor.ink)
                if row.isCached {
                    Text("CACHED").legend(STColor.secondary, size: 8)
                }
                Spacer()
            }
        } content: {
            // Study's size/typeface, not Scripture's: this row lives inside the Study Desk, so a
            // pinch anywhere in that pane (SourcesPane's `pinchToZoomTextSize`) must actually move
            // what's drawn here too — matching by container, not by "this happens to quote the
            // Bible," is what keeps every pinch gesture predictable.
            Text(row.text)
                .font(STFont.reading(state.studyFontSize, typeface: state.studyTypeface))
                .lineSpacing(state.studyLineSpacing)
                .foregroundStyle(STColor.ink)
                .textSelection(.enabled)
        } footer: {
            if !row.attribution.isEmpty {
                Text(row.attribution)
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(STColor.secondary)
                    .textSelection(.enabled)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(row.label): \(row.text)")
    }
}
