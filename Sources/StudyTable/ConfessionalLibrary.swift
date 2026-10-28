import SwiftUI

/// A browsable reference library, separate from the verse-triggered Study Desk: full text of the
/// three ecumenical creeds, and the full text — with tappable Scripture proof-text chips — of the
/// Westminster Confession, Larger and Shorter Catechisms, the Heidelberg Catechism, and the Belgic
/// Confession (`StandardsStore`, `Resources/Confession/standards/`). The Canons of Dort ship only
/// their 59 positive articles here — the 34 Rejection-of-Errors paragraphs are withheld pending a
/// verified public-domain translation (see `scripts/standards-sources/SOURCES.md` and
/// `build-standards.py`'s `cd`-document comment for why); the document's own `translation` field
/// says so too, in-app, not just here.
/// Nothing here is linked to the *selected* verse; browsing a document and jumping from one of its
/// proof-text chips both navigate the whole app to that passage, same as everywhere else, but
/// nothing here reacts to the current selection the way the Study Desk's `ProofTextsSection` does.
/// Human-reviewed Westminster links (`ConfessionStore` / `wcf-links.json`), where curated, still
/// appear only on individual source cards — this library never touches that system.
struct ConfessionalLibrarySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = StandardsStore()
    @State private var selection: LibrarySection = .creeds

    private enum LibrarySection: Hashable {
        case creeds
        case standard(String)  // StandardDocument.id
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Confessional Library").font(STFont.title(17))
                Spacer()
                Button { dismiss() } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Close Confessional Library")
                    .help("Close")
            }
            .padding(14)
            documentPicker
            Divider()
            switch selection {
            case .creeds:
                CreedsList(store: store)
            case .standard(let id):
                if let doc = store.document(id: id) {
                    StandardDocumentView(document: doc)
                } else {
                    ContentUnavailableView("Not available", systemImage: "exclamationmark.triangle")
                }
            }
        }
        // Kept at the original 460x560: `SnapshotTests.swift` (workstream A) renders this sheet
        // at that exact fixed size, and everything below scrolls (both the horizontal document
        // picker and each document's own item list), so the larger reader still fits.
        .frame(width: 460, height: 560)
        .background(STColor.tileTop)
    }

    private var documentPicker: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                pickerChip("Creeds", isSelected: selection == .creeds) { selection = .creeds }
                ForEach(store.documents) { doc in
                    pickerChip(doc.shortTitle, isSelected: selection == .standard(doc.id)) {
                        selection = .standard(doc.id)
                    }
                }
            }
            .padding(.horizontal, 14)
        }
        .padding(.bottom, 10)
    }

    private func pickerChip(_ title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11.5, weight: .medium, design: .rounded))
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(isSelected ? STColor.navy : STColor.tileWell,
                            in: RoundedRectangle(cornerRadius: 4))
                .foregroundStyle(isSelected ? Color.white : STColor.ink)
        }
        .buttonStyle(.plain)
    }
}

private struct CreedsList: View {
    let store: StandardsStore
    @EnvironmentObject private var state: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                ForEach(state.studyResources.confession.creeds) { creed in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(creed.title).font(STFont.title(15))
                        Text(creed.era).legend()
                        Text(creed.text)
                            .font(STFont.reading(13.5))
                            .lineSpacing(3)
                            .textSelection(.enabled)
                            .padding(.top, 2)
                        Text(creed.note)
                            .font(.system(size: 10.5, design: .rounded))
                            .foregroundStyle(STColor.secondary)
                            .padding(.top, 2)
                    }
                    Rectangle().fill(STColor.hairline).frame(height: 1)
                }
            }
            .padding(16)
        }
    }
}

/// Full text of one confessional standard, with each item's own proof texts as tappable chips.
private struct StandardDocumentView: View {
    let document: StandardDocument
    @EnvironmentObject private var state: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var expandedIDs: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 3) {
                Text(document.title).font(STFont.title(14))
                Text("\(document.year) \u{00B7} \(document.translation)")
                    .font(.system(size: 10, design: .rounded))
                    .foregroundStyle(STColor.secondary)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14).padding(.vertical, 8)
            Divider()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(document.items) { item in
                        StandardItemRow(item: item, expanded: expandedBinding(item.id)) { proof in
                            state.navigate(bookCode: proof.code, chapter: proof.chapter, verse: proof.start)
                            dismiss()
                        }
                        Rectangle().fill(STColor.hairline).frame(height: 1)
                    }
                }
            }
        }
    }

    private func expandedBinding(_ id: String) -> Binding<Bool> {
        Binding(get: { expandedIDs.contains(id) },
                set: { if $0 { expandedIDs.insert(id) } else { expandedIDs.remove(id) } })
    }
}

/// True when `proof` names a real, existing verse in the bundled canon (`books` should be
/// `state.library.books`, which is always keyed to the BSB structure regardless of the currently
/// selected translation -- see `ScriptureLibrary.rescan()` -- so this checks the canon's actual
/// shape, not whichever translation happens to be open). ~13 confession citations point at
/// old-print-run errors (e.g. 1 Tim 4:19, which doesn't exist -- see `StandardsTests`'s
/// `knownMismatches`) that resolve nowhere; those must never be a dead-end tap (item 7, 0.7 fix
/// batch). Not `private` so `ConfessionalLibraryTests` can exercise it directly against real
/// `knownMismatches` entries without rendering.
func standardProofResolves(_ proof: StandardProof, in books: [BookSummary]) -> Bool {
    guard let book = books.first(where: { $0.code == proof.code }),
          (1...max(book.chapterCount, 1)).contains(proof.chapter) else { return false }
    let count = book.verseCount(chapter: proof.chapter)
    guard count > 0 else { return false }
    return proof.start >= 1 && proof.end >= proof.start && proof.end <= count
}

private struct StandardItemRow: View {
    let item: StandardItem
    @Binding var expanded: Bool
    let onNavigate: (StandardProof) -> Void
    @EnvironmentObject private var state: AppState

    private func resolves(_ proof: StandardProof) -> Bool {
        standardProofResolves(proof, in: state.library.books)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.label).font(.system(size: 12.5, weight: .semibold, design: .rounded))
                if let heading = item.heading {
                    Text(heading).font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(STColor.secondary)
                }
            }
            if let question = item.question {
                Text(question)
                    .font(.system(size: 12, weight: .medium, design: .rounded))
                    .italic()
            }
            Text(item.text)
                .font(STFont.reading(13.5))
                .lineSpacing(3)
                .lineLimit(expanded ? nil : 4)
                .textSelection(.enabled)
            if !item.proofs.isEmpty {
                if expanded {
                    FlowLayout(spacing: 6) {
                        ForEach(item.proofs, id: \.ref) { proof in
                            if resolves(proof) {
                                Button(proof.ref) { onNavigate(proof) }
                                    .buttonStyle(.plain)
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(STColor.tileWell, in: Capsule())
                                    .overlay(Capsule().stroke(STColor.keyRim, lineWidth: 1))
                            } else {
                                // Old-print-run citation error (e.g. 1 Tim 4:19): the confession's
                                // own text really does print this reference, so it still needs to
                                // be shown verbatim (never silently dropped) -- but it can't
                                // navigate anywhere real, so it's plain text, not a button, with a
                                // help tooltip explaining why rather than a dead-end tap.
                                Text(proof.ref)
                                    .font(.system(size: 10, weight: .medium, design: .rounded))
                                    .foregroundStyle(STColor.secondary)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(STColor.tileWell.opacity(0.5), in: Capsule())
                                    .overlay(Capsule().stroke(STColor.keyRim.opacity(0.5), lineWidth: 1))
                                    .help("Reference not found in this Bible")
                                    .accessibilityLabel("\(proof.ref), reference not found in this Bible")
                            }
                        }
                    }
                    Text("Cited as a proof text by the confession itself \u{2014} not an app judgment.")
                        .font(.system(size: 9.5, design: .rounded))
                        .foregroundStyle(STColor.secondary)
                } else {
                    Text("\(item.proofs.count) proof text\(item.proofs.count == 1 ? "" : "s")").legend()
                }
            }
            HStack {
                Spacer()
                Button(expanded ? "LESS" : "MORE") { expanded.toggle() }
                    .buttonStyle(.plain)
                    .legend(STColor.ink, size: 9)
            }
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .accessibilityElement(children: .combine)
    }
}
