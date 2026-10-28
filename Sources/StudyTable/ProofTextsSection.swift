import SwiftUI

/// Study Desk section showing, for the selected verse, which Westminster/Heidelberg/Belgic/Dort
/// sections cite it as a proof text. Self-contained (owns its own lazy `StandardsStore`, reads the
/// selected passage from `AppState`) so `SourcesPane` (Panes.swift, workstream A) can insert it
/// with a bare `ProofTextsSection()` at the `// DESK SLOT: proof texts` marker — see that file's
/// comment there. Restyled directly onto `DeskComponents.swift`'s shared primitives (no wave-2
/// rework needed): `DeskSectionHeader`, `DeskCard`, `DeskExpandableText`, `DeskMoreButton`.
///
/// Never a doctrinal judgment: every row is a fact about the document's own printed text ("this
/// section cites this verse"), not a claim that the verse, or any commentary on it, is
/// "WCF-aligned." That distinction is carried in the header copy itself, always visible, not
/// buried behind an info button — matching the project's existing rule for source-card
/// disclaimers (see `DeskSectionHeader`'s `disclaimer` parameter in `Panes.swift`'s usage).
struct ProofTextsSection: View {
    @EnvironmentObject private var state: AppState
    @State private var store = StandardsStore()
    @State private var expandedIDs: Set<String> = []
    /// Collapsed by default so the commentary banks below stay above the fold; remembered.
    @AppStorage("desk.proofTextsExpanded") private var sectionExpanded = false

    private var citations: [StandardCitation] {
        guard let code = state.book?.code else { return [] }
        guard let verse = state.selectedVerse, verse > 0 else { return [] }
        return store.citations(bookCode: code, chapter: state.selectedChapter, verse: verse)
    }

    var body: some View {
        let items = citations
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                DeskSectionHeader(
                    title: "Proof Texts",
                    color: STColor.navyOnBlack,
                    count: items.count,
                    disclaimer: "Cited as a proof text by the confession itself \u{2014} not an app judgment.",
                    expanded: $sectionExpanded
                )
                if sectionExpanded {
                    ForEach(items) { citation in
                        ProofTextRow(citation: citation, expanded: expandedBinding(citation.id)) {
                            state.navigate(bookCode: $0.code, chapter: $0.chapter, verse: $0.start)
                        }
                        Rectangle().fill(STColor.hairline).frame(height: 1)
                    }
                } else {
                    DeskCollapsedSummary(section: "Proof Texts", text: items.map(\.label).joined(separator: "  \u{00B7}  ")) {
                        sectionExpanded = true
                    }
                }
            }
        }
    }

    private func expandedBinding(_ id: String) -> Binding<Bool> {
        Binding(
            get: { expandedIDs.contains(id) },
            set: { isExpanded in
                if isExpanded { expandedIDs.insert(id) } else { expandedIDs.remove(id) }
            }
        )
    }
}

/// One compact row: "WSC Q.20" (plus a heading/Lord's Day/chapter title when the document has
/// one) collapsed to a couple of lines, expanding in place to the section's full text and its own
/// list of proof-text chips (tappable — jumps the reader straight to that verse, same pattern as
/// `SourceCard`'s cross-reference chips).
private struct ProofTextRow: View {
    @EnvironmentObject private var state: AppState
    let citation: StandardCitation
    @Binding var expanded: Bool
    let onNavigate: (StandardProof) -> Void

    var body: some View {
        DeskCard {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(citation.label)
                    .font(.system(size: 12.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(STColor.ink)
                if let heading = citation.heading {
                    Text("\u{00B7} \(heading)").legend(STColor.secondary, size: 10)
                }
                Spacer()
            }
        } content: {
            VStack(alignment: .leading, spacing: 6) {
                if let question = citation.question {
                    Text(question)
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(STColor.secondary)
                }
                if expanded {
                    Text(citation.text)
                        .font(STFont.reading(state.studyFontSize, typeface: state.studyTypeface))
                        .lineSpacing(state.studyLineSpacing)
                        .foregroundStyle(STColor.ink)
                        .textSelection(.enabled)
                    if !citation.proofs.isEmpty {
                        FlowLayout(spacing: 6) {
                            ForEach(citation.proofs, id: \.ref) { proof in
                                Button(proof.ref) { onNavigate(proof) }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(STColor.ink)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(STColor.tileWell, in: Capsule())
                                    .overlay(Capsule().stroke(STColor.keyRim, lineWidth: 1))
                            }
                        }
                    }
                } else {
                    Text(citation.text)
                        .font(STFont.reading(state.studyFontSize, typeface: state.studyTypeface))
                        .lineSpacing(state.studyLineSpacing)
                        .lineLimit(2)
                        .foregroundStyle(STColor.secondary)
                }
            }
        } footer: {
            HStack {
                Spacer()
                DeskMoreButton(expanded: $expanded)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(citation.label)\(citation.heading.map { ", \($0)" } ?? "")")
        .accessibilityAction(named: expanded ? "Show less" : "Show full text") { expanded.toggle() }
    }
}
