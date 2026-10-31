import SwiftUI

// MARK: - Reader-selected alignment (0.9.5, workstream N)
//
// Implements the 2026-09-24 Decision Log entry ("Thruline uses reader-selected creeds, not a
// declared Reformed product identity"): Thruline must not claim one fixed confessional identity.
// The reader picks an alignment *lens* here, entirely independent of `AppState.selectedTraditions`
// (which authors/traditions are visible at all) -- changing the lens never hides or shows a
// source, it only changes what alignment language, if any, is shown next to it.
//
// This never touches `ConfessionStore` (the curated, human-reviewed WCF-link badge system,
// `wcf-links.json`) or `StandardsStore` (the factual per-verse confessional proof-text index).
// Both of those remain exactly as they are. `AlignmentResult` is a third, new thing: a
// *source-level*, computed characterization ("this author/tier is/isn't confessionally aligned
// with the selected standard"), grounded only in data already sourced elsewhere in the app
// (`ConfessionalTier`, `FatherProfile.conciliarJudgment`, `FatherProfile.controversies`,
// `StudySource.authorTradition`) -- never a new, independently-invented theological judgment.

/// A reader-chosen confessional standard governing the alignment language shown on source cards.
/// `.none` shows no alignment claims at all -- distinct from a real lens returning `.noMapping`
/// for a given source, which means "checked, and nothing sourced connects them."
enum AlignmentStandard: String, CaseIterable, Identifiable, Codable, Sendable {
    case none
    case westminsterStandards = "westminster"
    case threeFormsOfUnity = "three-forms"
    case ecumenicalCreeds = "ecumenical-creeds"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .none: "No alignment lens"
        case .westminsterStandards: "Westminster Standards"
        case .threeFormsOfUnity: "Three Forms of Unity"
        case .ecumenicalCreeds: "Ecumenical creeds"
        }
    }

    /// One sentence for the Settings picker, explaining what changes (and what doesn't) when this
    /// lens is selected.
    var detail: String {
        switch self {
        case .none:
            "Sources are shown without any confessional-alignment labeling. Author traditions (e.g. \u{201C}Particular Baptist\u{201D}) remain visible where already sourced."
        case .westminsterStandards:
            "Labels each source's documented relationship \u{2014} agreement, tension, or no mapping \u{2014} to the Westminster Confession and Catechisms, as a fact about the source, never a verdict on it."
        case .threeFormsOfUnity:
            "Labels each source's documented relationship to the Belgic Confession, Heidelberg Catechism and Canons of Dort."
        case .ecumenicalCreeds:
            "Labels only conciliar and historical facts already recorded in this app (such as a council condemnation) against the Apostles', Nicene and Chalcedonian creeds. Most sources show no mapping here, since ordinary doctrinal agreement with the ecumenical creeds isn't separately sourced in this app."
        }
    }
}

/// The alignment claim for one source against one selected standard. Every case must trace to
/// data already sourced elsewhere in the app -- see the type-level comment above.
enum AlignmentResult: Hashable, Sendable {
    /// A real, sourced connection to the selected standard (e.g. this app's own confessional-tier
    /// categorization of the source as Reformed commentary).
    case documentedAgreement(String)
    /// A sourced, specific disagreement, stated as fact -- never a verdict ("wrong"), just a
    /// difference (e.g. a Particular Baptist author's covenant theology vs. a paedobaptist
    /// confession).
    case tension(String)
    /// Nothing sourced in this app connects the source to the selected standard. The honest
    /// default for most entries.
    case noMapping
    /// Reserved for the existing council-condemned/disputed bucket (`FatherProfile.conciliarJudgment`)
    /// -- a specific council and year, never a generic "condemned" label, and never collapsed into
    /// `.tension`.
    case historicallyDisputed(council: String, year: Int, note: String?)

    var label: String {
        switch self {
        case .documentedAgreement: "AGREEMENT"
        case .tension: "TENSION"
        case .noMapping: "NO MAPPING"
        case .historicallyDisputed(let council, let year, _): "DISPUTED \u{2014} \(council.uppercased()), \(year)"
        }
    }

    /// The sourced sentence behind the label, where there is one (`.noMapping` has none by
    /// definition -- there is nothing sourced to say).
    var detail: String? {
        switch self {
        case .documentedAgreement(let text): text
        case .tension(let text): text
        case .noMapping: nil
        case .historicallyDisputed(_, _, let note): note
        }
    }
}

/// Computes `AlignmentResult` for a `StudySource` against a reader-selected `AlignmentStandard`.
/// Pure and stateless beyond the `FatherProfileStore` lookup it needs; holds no UserDefaults of
/// its own (`AppState.alignmentStandard` owns the reader's actual choice, the same injectable-
/// preferences pattern every other AppState setting already uses).
@MainActor
final class AlignmentStore {
    private let fatherProfiles: FatherProfileStore

    init(fatherProfiles: FatherProfileStore = .shared) {
        self.fatherProfiles = fatherProfiles
    }

    /// `nil` means "no lens selected -- show nothing," which is a different, stronger claim than
    /// `.noMapping` ("a lens is selected and nothing sourced connects them"). Callers must not
    /// treat the two the same way (see `AlignmentTests.testNoLensReturnsNilForEverySource`).
    func alignment(for source: StudySource, against standard: AlignmentStandard) -> AlignmentResult? {
        guard standard != .none else { return nil }

        // A conciliar/synodal condemnation is a fact about the author, independent of which
        // confessional lens is selected -- every lens on offer presupposes the same ecumenical
        // consensus those councils protected. Checking this first also guarantees a condemned
        // author is never merely "in tension" under any lens (the existing disputed/condemned
        // labeling this app already ships must be preserved, not weakened by this feature).
        if source.tradition == .fathers,
           let judgment = fatherProfiles.profile(forAuthor: source.author)?.conciliarJudgment {
            return .historicallyDisputed(council: judgment.council, year: judgment.year, note: judgment.note)
        }

        switch standard {
        case .none:
            return nil
        case .westminsterStandards, .threeFormsOfUnity:
            return reformedFamilyAlignment(for: source, against: standard)
        case .ecumenicalCreeds:
            return ecumenicalAlignment(for: source)
        }
    }

    /// Westminster Standards and Three Forms of Unity are both historic confessionally-Reformed
    /// documents; this app's existing `ConfessionalTier` categorization (Tier 1 = confessionally
    /// Reformed commentary -- Calvin, Matthew Henry) is not specific to either one document, so
    /// both lenses read it the same way. Flagged as an open call in the workstream report: a
    /// future pass could instead differentiate a continental (Three Forms) vs. British
    /// (Westminster) confessional lineage per author.
    private func reformedFamilyAlignment(for source: StudySource, against standard: AlignmentStandard) -> AlignmentResult {
        switch source.tradition {
        case .reformed:
            guard source.tier == .tier1Confessional else { return .noMapping }
            return .documentedAgreement(
                "\(source.author) is catalogued in this app as confessionally Reformed commentary, "
                + "consistent with the \(standard.label) confessional tradition.")
        case .exegetes:
            // The one specific, sourced denominational tension this app's data already carries:
            // John Gill's Particular Baptist covenant theology vs. a paedobaptist confession --
            // named explicitly as the sanctioned example in WORKPLAN-0.9.5.md section N. Any other
            // `authorTradition` (e.g. "Lutheran", "Presbyterian & Anglican") has no specific,
            // already-sourced point of disagreement recorded in this app, so it stays `.noMapping`
            // rather than inventing one -- see workstream report for real follow-up candidates.
            if let authorTradition = source.authorTradition, authorTradition.contains("Baptist") {
                return .tension(
                    "\(source.author)'s \(authorTradition) covenant theology differs from "
                    + "\(standard.label)'s paedobaptist covenant theology on the subjects of baptism.")
            }
            return .noMapping
        case .fathers, .crossReferences:
            return .noMapping
        }
    }

    /// The ecumenical creeds (Apostles', Nicene, Chalcedonian) are Trinitarian/Christological, not
    /// confession-specific proof-text documents -- see WORKPLAN-0.9.5.md section N item 1. The
    /// only per-source data this app has that is actually about that territory is a Father's own
    /// profile: a documented controversy (without a settled conciliar judgment, which is already
    /// handled above) is a real, sourced tension worth naming here specifically, since patristic-
    /// era controversies are most often Trinitarian/Christological in nature. Every other source
    /// (Reformed, Exegetes, Cross-References, and any Father with no profile or no controversy)
    /// shows `.noMapping` -- this app has no sourced data connecting them to the creeds one way or
    /// the other, and inventing agreement would be exactly the kind of unsourced claim the
    /// decision forbids.
    private func ecumenicalAlignment(for source: StudySource) -> AlignmentResult {
        guard source.tradition == .fathers,
              let profile = fatherProfiles.profile(forAuthor: source.author),
              profile.conciliarJudgment == nil,
              let controversies = profile.controversies else {
            return .noMapping
        }
        return .tension(controversies)
    }
}

// MARK: - Views (self-contained; wave-2 integration drops these onto owned UI files)

/// A compact, tappable chip for a source card. Self-contained: pass an already-computed
/// `AlignmentResult?` (the `nil` case renders nothing, including no layout space -- see the
/// `Group { if let }` body), or use the convenience initializer with the source/standard/store
/// directly. Not owned by any console UI file this round; Claude wires this onto `SourceCard`
/// (`Panes.swift`) during wave-2 integration once the shipped console layout is visible.
struct AlignmentBadge: View {
    let result: AlignmentResult?

    init(result: AlignmentResult?) {
        self.result = result
    }

    /// Convenience for call sites that have the source, the reader's selected standard, and a
    /// store on hand rather than an already-computed result.
    init(source: StudySource, standard: AlignmentStandard, store: AlignmentStore) {
        self.result = store.alignment(for: source, against: standard)
    }

    var body: some View {
        if let result {
            HStack(spacing: 4) {
                Circle().fill(dotColor(for: result)).frame(width: 6, height: 6)
                Text(result.label)
                    .font(STFont.legend(8.5)).tracking(0.5)
                    .foregroundStyle(STColor.ink)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7).padding(.vertical, 3)
            .background(STColor.tileWell, in: Capsule())
            .overlay(Capsule().stroke(STColor.keyRim, lineWidth: 1))
            .help(result.detail ?? result.label)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(accessibilityText(for: result))
        }
        // `nil`: intentionally renders nothing -- see `AlignmentStore.alignment(for:against:)`'s
        // doc comment on why this must differ from a rendered "no mapping" chip.
    }

    // Color is never the only carrier of meaning here (DESIGN.md's Color-Never-Alone rule): the
    // dot is always paired with `result.label` text, never shown alone.
    private func dotColor(for result: AlignmentResult) -> Color {
        switch result {
        case .documentedAgreement: STColor.reformed
        case .tension: STColor.disclaimerInfoIcon
        case .noMapping: STColor.secondary
        case .historicallyDisputed: STColor.warning
        }
    }

    private func accessibilityText(for result: AlignmentResult) -> String {
        if let detail = result.detail { return "Alignment: \(result.label). \(detail)" }
        return "Alignment: \(result.label)"
    }
}

/// Reader-facing control for `AppState.alignmentStandard`. Self-contained (reads/writes
/// `AppState` directly) so it can be dropped into any owned settings surface with a bare
/// `AlignmentLensPicker()` -- currently wired into `SettingsView.swift`'s About tab (see that
/// file's comment on why About rather than Workspace, which this workstream doesn't own).
struct AlignmentLensPicker: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Alignment lens", selection: Binding(
                get: { state.alignmentStandard },
                set: { state.alignmentStandard = $0 }
            )) {
                ForEach(AlignmentStandard.allCases) { standard in
                    Text(standard.label).tag(standard)
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Alignment lens")
            Text(state.alignmentStandard.detail)
                .font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
