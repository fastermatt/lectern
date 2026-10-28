import SwiftUI
import StudyTableCore

/// A quiet editorial heading above the verse it introduces (BSB section titles and their
/// parallel-passage references). It is a separate row: `VerseRow` and the verse `Text` inside it
/// are untouched, so verse typography is exactly what it was before headings existed.
///
/// Levels: 0 a major division (Psalms "BOOK I"), 1 a section, 2 a subsection, 3 an acrostic
/// letter. Reference chips navigate through `AppState.navigate`, so the Back key returns here,
/// the same way desk cross-reference chips do.
struct SectionHeadingRow: View {
    @EnvironmentObject private var state: AppState
    let headings: [SectionHeading]
    /// True when nothing precedes this group in the chapter (no top gap needed).
    var isFirst = false

    /// Titles follow the Type knob loosely but never grow past a caption: Scripture must stay the loudest thing.
    private var titleSize: CGFloat { min(28, max(19, state.fontSize * 1.08)) }

    var body: some View {
        // The group is rounded up to a whole number of points tall, so every verse below it moves by
        // an exact pixel multiple and keeps the sub-pixel position (and so the exact rasterisation)
        // it had before headings existed.
        WholePointHeight {
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(headings.enumerated()), id: \.offset) { index, heading in
                    HeadingBlock(heading: heading, titleSize: titleSize, topGap: gap(before: index))
                }
            }
            .padding(.leading, 43).padding(.trailing, 21)
            .padding(.bottom, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain)
    }

    private func gap(before index: Int) -> CGFloat {
        if index == 0 { return isFirst ? 2 : 18 }
        return 6
    }
}

/// Wraps one child and reports its height rounded up to a whole point.
private struct WholePointHeight: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        guard let child = subviews.first else { return .zero }
        let size = child.sizeThatFits(proposal)
        return CGSize(width: size.width, height: size.height.rounded(.up))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: bounds.origin, anchor: .topLeading,
                              proposal: ProposedViewSize(width: bounds.width, height: nil))
    }
}

private struct HeadingBlock: View {
    @EnvironmentObject private var state: AppState
    let heading: SectionHeading
    let titleSize: CGFloat
    let topGap: CGFloat

    /// The pericope this heading opens, for the "Select section" affordance below — only for real
    /// sections/subsections (level 1–2). A division ("BOOK I") or an acrostic stanza (level 0/3) is
    /// either too broad or too narrow to be a useful single-chapter range selection (0.10, S2a).
    private var section: Pericope? {
        guard heading.level == 1 || heading.level == 2 else { return nil }
        return state.library.pericope(containing: state.selectedChapter, verse: heading.verse,
                                      bookCode: state.selectedBookCode, translation: state.translationID, level: heading.level)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            titleLine
                .accessibilityAddTraits(.isHeader)
                .accessibilityLabel(accessibleTitle)
            if let parallels = heading.parallels, !parallels.isEmpty {
                ParallelChips(parallels: parallels, size: 10)
            }
            if let section {
                SelectSectionButton(section: section, size: 10)
            }
        }
        .padding(.top, topGap)
        .contextMenu {
            if let section { Button("Select Section") { state.selectSection(section) } }
        }
    }

    @ViewBuilder private var titleLine: some View {
        switch heading.level {
        case 0:
            // Division: printed-legend voice, like the console's other labels.
            (Text(heading.title.uppercased()) + Text(heading.subtitle.map { "  \u{00B7}  \($0)" } ?? ""))
                .legend(STColor.secondary, size: max(9.5, titleSize - 2))
        case 3:
            Text(heading.title.uppercased()).legend(STColor.secondary, size: max(9.5, titleSize - 2.5))
        case 2:
            Text(heading.title)
                .font(.system(size: max(10.5, titleSize - 1), weight: .medium, design: .rounded))
                .foregroundStyle(STColor.secondary)
                .fixedSize(horizontal: false, vertical: true)
        default:
            Text(heading.title)
                .font(STFont.reading(titleSize, typeface: state.scriptureTypeface))
                .foregroundStyle(STColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var accessibleTitle: String {
        switch heading.level {
        case 0: [heading.title, heading.subtitle].compactMap { $0 }.joined(separator: ", ")
        case 3: "Stanza \(heading.title)"
        default: "Section: \(heading.title)"
        }
    }
}

/// A quiet click/keyboard/VoiceOver route to selecting a whole pericope as a range (0.10, S2a) —
/// the right-click context menu on the heading is the mouse alternative to the same action.
struct SelectSectionButton: View {
    @EnvironmentObject private var state: AppState
    let section: Pericope
    var size: CGFloat = 9

    private var rangeCaption: String {
        section.startChapter == section.endChapter
            ? "\(section.startChapter):\(section.startVerse)\u{2013}\(section.endVerse)"
            : "\(section.startChapter):\(section.startVerse)\u{2013}\(section.endChapter):\(section.endVerse)"
    }

    var body: some View {
        Button { state.selectSection(section) } label: {
            Text("SELECT SECTION").legend(STColor.secondary, size: size)
        }
        .buttonStyle(.plain)
        .help("Select \(section.title) as a range (\(rangeCaption))")
        .accessibilityLabel("Select section: \(section.title), \(rangeCaption)")
    }
}

enum ParallelNavigation {
    /// Opens a parallel reference at its first verse. Goes through `AppState.navigate`, so the
    /// passage we left is pushed on the history and the Back key returns to it.
    @MainActor static func open(_ reference: ParallelReference, in state: AppState) {
        guard let book = reference.book, reference.chapter > 0 else { return }
        state.navigate(bookCode: book, chapter: reference.chapter, verse: max(reference.verse, 1))
    }
}

/// "See also" reference chips. Shape and a quiet label carry meaning; nothing relies on colour.
struct ParallelChips: View {
    @EnvironmentObject private var state: AppState
    let parallels: [ParallelReference]
    var size: CGFloat = 10.5

    var body: some View {
        FlowLayout(spacing: 5) {
            Text("SEE ALSO").legend(STColor.secondary, size: max(8.5, size - 1.5))
                .padding(.trailing, 2).accessibilityHidden(true)
            ForEach(Array(parallels.enumerated()), id: \.offset) { _, reference in
                chip(reference)
            }
        }
    }

    @ViewBuilder private func chip(_ reference: ParallelReference) -> some View {
        let label = Text(reference.label).font(.system(size: size, weight: .medium, design: .rounded))
        if reference.isNavigable {
            Button {
                ParallelNavigation.open(reference, in: state)
            } label: {
                label.foregroundStyle(STColor.ink)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(STColor.tileWell, in: RoundedRectangle(cornerRadius: 4))
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(STColor.keyRim, lineWidth: 1))
            }
            .buttonStyle(.plain)
            .help("Go to \(reference.label)")
            .accessibilityLabel("Go to \(reference.label)")
        } else {
            label.foregroundStyle(STColor.secondary)
        }
    }
}
