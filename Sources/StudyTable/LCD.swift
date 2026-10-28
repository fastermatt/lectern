import SwiftUI

/// The black display: chapter numeral, passage, translation and where its text came from — one
/// compact row. Verse navigation used to be duplicated here (a tick-strip chapter map, click/drag
/// to jump) on top of the verse-bar pills under the Scripture text that already do the same job
/// with real per-verse targets; the tick strip was removed 2026-09-22 so the LCD is purely a
/// readout, not a second navigator.
///
/// Degrades by ViewThatFits, never by wrapping: at the true 980pt minimum window width this row
/// has roughly 200-260pt available (the rest goes to Library/Scripture/Desk minimums and the
/// fixed-width keys), which is not enough for the full readout. Three candidates, each a strict
/// subset of the wider one's content, so the LCD always shows *something* legible instead of
/// clipped fragments ("P…", "23: / 1 / 6", "BS/B", "OFFL/INE" was the 0.6.6 failure mode).
struct LCDDisplay: View {
    @EnvironmentObject private var state: AppState

    private var verse: Int { state.selectedVerse ?? 0 }
    private var origin: String {
        switch state.chapterLoad {
        case .loaded(let content):
            switch content.origin {
            case .offline: "OFFLINE"
            case .onlineLive: "ONLINE"
            case .onlineCached: "CACHED"
            }
        case .loading: "LOADING"
        case .unavailable: "UNAVAILABLE"
        }
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            fullRow
            mediumRow
            compactRow
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        // `minWidth` is a sanity floor, not a target — it must never exceed what the deck can
        // actually give the LCD at the true 980pt minimum, or `.frame` forces this view wider
        // than its available slot and `compactRow`'s content (below) draws outside the black
        // rounded-rect `.clipShape` that's supposed to contain it (2026-09 regression: the
        // chapter numeral bled onto the PASSAGE key, the gear got painted over by the TYPE
        // knob). 140 was that stale, too-high floor from before a 4th bank key narrowed the
        // deck's real allocation; 110 stays comfortably under it.
        .frame(minWidth: 110, maxWidth: .infinity, maxHeight: .infinity)
        .background(STColor.lcd, in: RoundedRectangle(cornerRadius: 3))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(STColor.lcdRim, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 3))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Display")
        .accessibilityValue("\(state.passage), \(state.translationID), \(origin.lowercased())")
    }

    // MARK: Candidates (widest to narrowest — ViewThatFits picks the first that fits)

    private var numeral: some View {
        Text("\(state.selectedChapter)")
            .font(STFont.numeral(28, weight: .light))
            .foregroundStyle(STColor.lcdInk)
            .fixedSize()
    }

    private var gear: some View {
        Button { openSettings() } label: {
            Image(systemName: "gearshape.fill").font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .foregroundStyle(STColor.lcdDim)
        .help("Settings…")
        .accessibilityLabel("Settings")
    }

    /// Full readout: numeral, book + chapter:verse/count, the selected verse's original-language
    /// text as a two-line interlinear strip (0.8 — this is the width the old per-chapter bank-
    /// count dots used to claim; those moved out entirely, since the source-key LEDs and each
    /// bank's own desk-section count already say the same thing — see `DESIGN.md`'s LCD section),
    /// translation + origin, gear. What renders at the default window size.
    private var fullRow: some View {
        HStack(alignment: .center, spacing: 10) {
            numeral
            VStack(alignment: .leading, spacing: 1) {
                Text(state.bookName.uppercased()).font(STFont.lcd(14, weight: .medium)).lineLimit(1).fixedSize()
                Text(verse > 0 ? "\(state.selectedChapter):\(verse) / \(state.verseCount)" : "\(state.selectedChapter)")
                    .font(STFont.lcd(12)).foregroundStyle(STColor.lcdDim).monospacedDigit().fixedSize()
            }
            .foregroundStyle(STColor.lcdInk)
            InterlinearStrip()
            VStack(alignment: .trailing, spacing: 1) {
                Text(state.translationID).font(STFont.lcd(13, weight: .medium)).foregroundStyle(STColor.lcdInk).fixedSize()
                Text(origin).font(STFont.lcd(9)).foregroundStyle(STColor.lcdDim).fixedSize()
            }
            gear
        }
    }

    /// Drops the bank counts first — real information, but the readout a reader can live without
    /// (BankCounts duplicates the source-key LEDs and the desk's own card count).
    private var mediumRow: some View {
        HStack(alignment: .center, spacing: 10) {
            numeral
            VStack(alignment: .leading, spacing: 1) {
                Text(state.bookName.uppercased()).font(STFont.lcd(14, weight: .medium)).lineLimit(1).fixedSize()
                Text(verse > 0 ? "\(state.selectedChapter):\(verse) / \(state.verseCount)" : "\(state.selectedChapter)")
                    .font(STFont.lcd(12)).foregroundStyle(STColor.lcdDim).monospacedDigit().fixedSize()
            }
            .foregroundStyle(STColor.lcdInk)
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 1) {
                Text(state.translationID).font(STFont.lcd(13, weight: .medium)).foregroundStyle(STColor.lcdInk).fixedSize()
                Text(origin).font(STFont.lcd(9)).foregroundStyle(STColor.lcdDim).fixedSize()
            }
            gear
        }
    }

    /// The true-980pt floor: book code instead of the full name (still unambiguous — "ROM 8:28"
    /// reads as well as "ROMANS 8:28" at a glance) on one line, translation only (no origin word,
    /// no verse-of-count), gear. Unlike `fullRow`/`mediumRow` — which only ever get chosen once
    /// `ViewThatFits` has confirmed they fit — `compactRow` is the mandatory last resort: if even
    /// *this* doesn't fit, `ViewThatFits` still renders it at whatever width it's given. It used
    /// to mark every piece `.fixedSize()`, which pins a view to its natural size regardless of the
    /// space actually on offer — exactly backwards for a fallback, and the direct cause of a real
    /// bug (the chapter numeral painting outside the LCD onto the PASSAGE key, the gear hidden
    /// under the TYPE knob, once a 4th bank key left this row less width than it demanded). Now
    /// `lineLimit(1)` + `minimumScaleFactor` let the numeral and passage text shrink smoothly
    /// under real duress instead of overflowing the clip — still never wraps, degrades by scale
    /// instead. `numeral` (shared with the wider rows, where there's always slack) stays
    /// `.fixedSize()`; this row uses its own scaled copy.
    private var compactNumeral: some View {
        Text("\(state.selectedChapter)")
            .font(STFont.numeral(28, weight: .light))
            .foregroundStyle(STColor.lcdInk)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
    }

    private var compactRow: some View {
        HStack(alignment: .center, spacing: 6) {
            compactNumeral
            Text(verse > 0 ? "\(state.selectedBookCode) \(state.selectedChapter):\(verse)" : "\(state.selectedBookCode) \(state.selectedChapter)")
                .font(STFont.lcd(13, weight: .medium))
                .foregroundStyle(STColor.lcdInk)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 2)
            Text(state.translationID)
                .font(STFont.lcd(12, weight: .medium))
                .foregroundStyle(STColor.lcdInk)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            gear
        }
    }
}

/// The selected verse's original-language text (STEPBible-Data TAHOT/TAGNT — see
/// `InterlinearStore`), packed into the LCD's leftover width as a two-line-per-word interlinear
/// strip: the original script on top (Hebrew/Aramaic right-to-left, in LCD ink), its English gloss
/// underneath in dim LCD ink, as many words as actually fit, ending with "… +N" rather than ever
/// wrapping to a second row or clipping mid-word. Replaces the 0.7 `BankCounts` readout entirely
/// (0.8, Matt's direct feedback: "this area takes up a ton of space for no reason") — the source-
/// key LEDs already show which banks are toggled on, and each bank's own desk-section header
/// already prints its count, so `BankCounts` was answering a question twice; this answers a
/// question nothing else in the window does.
///
/// Sizing uses the same "measure the real available width, then compute how many fixed-size items
/// fit" technique as `VerseBar.pills` (`MainView.swift`) — deliberately not a nested
/// `ViewThatFits` over per-count candidates, which would report its *unconstrained* ideal size
/// (all words) to the outer `ViewThatFits` doing full/medium/compact row selection and starve it
/// of the one signal (a small, bounded ideal size, the way the `Spacer(minLength:)` this replaced
/// behaved) it needs to size the row correctly at the 980pt floor.
struct InterlinearStrip: View {
    @EnvironmentObject private var state: AppState
    var store: InterlinearStore = .shared
    @State private var availableWidth: CGFloat = 0

    private var words: [InterlinearWord] {
        guard let verse = state.selectedVerse, verse > 0 else { return [] }
        return store.words(bookCode: state.selectedBookCode, chapter: state.selectedChapter, verse: verse)
    }

    private var isRightToLeft: Bool { words.first.map { $0.language != .greek } ?? false }

    /// A rough but serviceable per-word width estimate at the strip's fixed 11pt/8pt type sizes —
    /// good enough for "roughly how many fit"; a few points of slack either way only changes
    /// whether one additional short word shows or falls into the trailing "+N" count instead of
    /// ever causing a clip (this view's own children stay `.fixedSize()`, so an overestimate here
    /// only under-fills the row, it never overflows it).
    private func estimatedWidth(_ word: InterlinearWord) -> CGFloat {
        let chars = CGFloat(max(word.surface.count, word.gloss.count))
        return max(30, chars * 7.6) + 12
    }

    private var visibleCount: Int {
        guard availableWidth > 0, !words.isEmpty else { return 0 }
        let overflowAllowance: CGFloat = 34 // reserves room for a trailing "… +N" once one exists
        var used: CGFloat = 0
        var count = 0
        for word in words {
            let width = estimatedWidth(word) + (count > 0 ? 10 : 0) // inter-word spacing
            let remaining = words.count - count - 1
            let allowance: CGFloat = remaining > 0 ? overflowAllowance : 0
            if used + width + allowance > availableWidth { break }
            used += width
            count += 1
        }
        return count
    }

    var body: some View {
        GeometryReader { proxy in
            stripContent
                .frame(width: proxy.size.width, height: proxy.size.height, alignment: isRightToLeft ? .trailing : .leading)
                .onAppear { availableWidth = proxy.size.width }
                .onChange(of: proxy.size.width) { _, width in availableWidth = width }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(words.isEmpty ? "" : "Original language: " + words.map(\.gloss).joined(separator: " "))
    }

    @ViewBuilder private var stripContent: some View {
        if words.isEmpty {
            Color.clear
        } else {
            let count = visibleCount
            HStack(spacing: 10) {
                ForEach(Array(words.prefix(count).enumerated()), id: \.offset) { index, word in
                    InterlinearWordChip(word: word, index: index)
                }
                if count < words.count {
                    Text("… +\(words.count - count)")
                        .font(STFont.lcd(9))
                        .foregroundStyle(STColor.lcdDim)
                        .fixedSize()
                }
            }
            .environment(\.layoutDirection, isRightToLeft ? .rightToLeft : .leftToRight)
        }
    }
}

/// One clickable word in the LCD's interlinear strip: original script above, gloss below, both
/// `.fixedSize()` so the strip's own width computation (`InterlinearStrip.estimatedWidth`) stays
/// accurate. A click reveals the desk and focuses this word's passage-scoped details.
private struct InterlinearWordChip: View {
    @EnvironmentObject private var state: AppState
    let word: InterlinearWord
    let index: Int

    var body: some View {
        Button {
            InterlinearSelection.shared.reveal(wordIndex: index, state: state)
        } label: {
            VStack(spacing: 1) {
                Text(word.surface)
                    .font(STFont.original(12.5, weight: .medium))
                    .foregroundStyle(STColor.lcdInk)
                Text(word.gloss)
                    .font(STFont.lcd(8))
                    .foregroundStyle(STColor.lcdDim)
                    .lineLimit(1)
            }
            .fixedSize()
        }
        .buttonStyle(.plain)
        .help("\(word.lemma) — \(word.morphDescription). Click to study this word in the Study Desk.")
        .accessibilityLabel("Study \(word.surface), \(word.gloss)")
        .accessibilityHint("Opens original-language details in the Study Desk")
    }
}
