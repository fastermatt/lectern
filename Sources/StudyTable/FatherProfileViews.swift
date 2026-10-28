import SwiftUI

/// A compact, tappable one-line label naming an author's theological school/tradition (e.g.
/// "Alexandrian · allegorical exegesis"), for K to place on `SourceCard` next to a Fathers-bank
/// entry's author name — the same spot `authorTradition` already occupies on Exegetes-bank cards
/// (`Panes.swift`). Tapping it opens `FatherProfileSheet` with the full sourced profile; this
/// view owns that sheet's presentation itself, so dropping it onto a card is a one-line insertion
/// with no state to wire up at the call site:
///
///     if entry.tradition == .fathers { FatherBentLabel(authorName: entry.author) }
///
/// Missing profiles receive an explicit unsourced-profile label; quotation coverage must not
/// imply that this beta has completed its author-profile coverage.
struct FatherBentLabel: View {
    let authorName: String
    var store: FatherProfileStore = .shared
    @State private var showingProfile = false

    private var profile: FatherProfile? { store.profile(forAuthor: authorName) }

    var body: some View {
        if let profile, let bent = profile.bentLine {
            Button { showingProfile = true } label: {
                Text(bent)
                    .font(STFont.legend(8.5)).tracking(0.6)
                    .foregroundStyle(STColor.ink)
                    .underline()
                    .fixedSize(horizontal: false, vertical: true)
                    .multilineTextAlignment(.leading)
            }
            .buttonStyle(.plain)
            .help("Theological profile: \(profile.name)")
            .accessibilityLabel("\(profile.name), \(bent). Show theological profile")
            .accessibilityAddTraits(.isButton)
            .sheet(isPresented: $showingProfile) { FatherProfileSheet(profile: profile) }
        } else {
            Text("Historical profile not yet sourced")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(STColor.secondary)
                .help("This quotation is indexed, but a sourced theological profile of this author is not yet available. Inclusion is not a doctrinal endorsement.")
        }
    }
}

private extension FatherProfile {
    /// The compact label's text: the school/tradition line, with the profile source file's
    /// em-dash separator ("Alexandrian — allegorical exegesis") rendered as the spec's own
    /// middle-dot form ("Alexandrian · allegorical exegesis") for a tighter, card-scaled chip.
    /// Falls back to ecclesial recognition or region when a profile has no `school` (both are
    /// rare — every profile written so far has `school` — but a future profile pass may add one
    /// that only has, say, region and dates).
    var bentLine: String? {
        if let school {
            return school.replacingOccurrences(of: " — ", with: " · ")
        }
        return ecclesialRecognition ?? region
    }
}

/// Full theological profile: dates, region/see, language, school/tradition, ecclesial
/// recognition, 1–3 emphases, any controversy or conciliar judgment, reception by the Reformers
/// where sourced, and — always — the citation(s) the whole profile rests on. Neutral, descriptive
/// tone throughout: this describes an author's historical standing, never Study Table's own
/// doctrinal verdict on them (the same discipline the tier system and source-class labels hold
/// to elsewhere in the app).
struct FatherProfileSheet: View {
    let profile: FatherProfile
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    facts
                    if !profile.emphases.isEmpty { emphasesSection }
                    if let conciliar = profile.conciliarJudgment { conciliarSection(conciliar) }
                    if let controversies = profile.controversies { textSection("Controversies & reception", controversies) }
                    if let reception = profile.receptionByReformers { textSection("Reception by the Reformers", reception) }
                    sourcesSection
                }
                .padding(16)
            }
        }
        .frame(width: 420, height: 480)
        .background(STColor.tileTop)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name).font(STFont.title(17))
                if let dates = profile.dates {
                    Text(dates).font(.system(size: 12, design: .rounded)).foregroundStyle(STColor.secondary)
                }
            }
            Spacer()
            Button { dismiss() } label: { Image(systemName: "xmark") }
                .buttonStyle(.plain)
                .accessibilityLabel("Close theological profile")
                .help("Close")
        }
        .padding(14)
    }

    /// Region/see/language/school/ecclesial recognition as a compact label:value stack — the
    /// factual header a reader scans first, before the longer prose sections below.
    private var facts: some View {
        VStack(alignment: .leading, spacing: 6) {
            factRow("Region", profile.region)
            factRow("See", profile.see)
            factRow("Language", profile.language)
            factRow("School / tradition", profile.school)
            factRow("Ecclesial recognition", profile.ecclesialRecognition)
        }
    }

    @ViewBuilder
    private func factRow(_ label: String, _ value: String?) -> some View {
        if let value {
            HStack(alignment: .top, spacing: 8) {
                Text(label.uppercased()).legend(STColor.secondary, size: 9).frame(width: 118, alignment: .leading)
                Text(value).font(.system(size: 12, design: .rounded)).foregroundStyle(STColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var emphasesSection: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("EMPHASES").legend(STColor.secondary, size: 9)
            ForEach(profile.emphases, id: \.self) { emphasis in
                HStack(alignment: .top, spacing: 6) {
                    Text("·").foregroundStyle(STColor.fathers)
                    Text(emphasis).font(.system(size: 12.5, design: .rounded)).foregroundStyle(STColor.ink)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// A conciliar/synodal judgment is the one fact this sheet visually treats as a warning —
    /// matching `DeskDisclaimer`'s existing warning tint, since this is exactly the same "the
    /// reader needs to know why this author is behind the research-only toggle" fact that
    /// disclaimer communicates on the card itself.
    private func conciliarSection(_ judgment: ConciliarJudgment) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 10)).foregroundStyle(STColor.warning)
                Text("RECORDED JUDGMENT: \(judgment.label.uppercased())").legend(STColor.warning, size: 9)
            }
            if let note = judgment.note {
                Text(note).font(.system(size: 12, design: .rounded)).foregroundStyle(STColor.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(8)
        .background(STColor.warning.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func textSection(_ title: String, _ text: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased()).legend(STColor.secondary, size: 9)
            Text(text).font(.system(size: 12.5, design: .rounded)).foregroundStyle(STColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var sourcesSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(profile.sources.count > 1 ? "SOURCES" : "SOURCE").legend(STColor.secondary, size: 9)
            ForEach(profile.sources, id: \.title) { source in
                Button {
                    if let url = source.url { openURL(url) }
                } label: {
                    Text(source.title)
                        .font(.system(size: 10.5, design: .rounded))
                        .foregroundStyle(source.url != nil ? STColor.ink : STColor.secondary)
                        .underline(source.url != nil)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .buttonStyle(.plain)
                .disabled(source.url == nil)
            }
        }
    }
}
