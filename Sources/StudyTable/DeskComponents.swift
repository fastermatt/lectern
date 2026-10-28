import SwiftUI

// MARK: - Study Desk shared components
//
// The Study Desk currently holds one kind of section — the source-tradition stack (Fathers /
// Reformed / Cross-References in `Panes.swift`). Two more are coming in wave 2: Proof Texts
// (workstream B, confessional citations) and Word Study (workstream D, Strong's lexicon). Rather
// than let each section invent its own header/card chrome, `SourcesPane` is built on these three
// primitives, and B/D restyle their own views onto the same ones — one shared desk language
// instead of three.
//
// `// DESK SLOT:` markers in `Panes.swift` mark exactly where each wave-2 section's view is a
// one-line insertion into the desk's scroll stack.

/// A colored section header for any Study Desk section: a small tradition-colored swatch, a
/// printed title, an item count, and — combined into the same block, not a separate
/// per-card repeat — a single optional disclaimer line that applies to the whole section. Used
/// today for Fathers/Reformed/Cross-References (`Panes.swift`'s `BankHeader`); Proof Texts and
/// Word Study restyle onto this directly.
struct DeskSectionHeader: View {
    let title: String
    let color: Color
    let count: Int
    var disclaimer: String? = nil
    var isWarning: Bool = false
    /// When set, the header becomes a disclosure control for its section (chevron + click to
    /// toggle). The disclaimer is shown whenever the section's content is — a collapsed section
    /// shows no content, so there is nothing for the disclaimer to qualify. Used by the
    /// reference sections (Proof Texts, Word Study) that sit above the commentary banks: they
    /// collapse to one line by default so the commentary stays above the fold.
    var expanded: Binding<Bool>? = nil

    private var isOpen: Bool { expanded?.wrappedValue ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let expanded {
                Button { expanded.wrappedValue.toggle() } label: { bar }
                    .buttonStyle(.plain)
                    .accessibilityLabel("\(title), \(count)")
                    .accessibilityValue(expanded.wrappedValue ? "expanded" : "collapsed")
                    .accessibilityHint("Shows or hides this section")
            } else {
                bar.accessibilityElement(children: .combine)
            }
            if isOpen, let disclaimer {
                DeskDisclaimer(text: disclaimer, isWarning: isWarning)
            }
        }
    }

    private var bar: some View {
        HStack(spacing: 8) {
            Rectangle().fill(color).frame(width: 7, height: 7)
            Text(title.uppercased()).font(STFont.lcd(10, weight: .medium))
            Spacer()
            Text("\(count)").font(STFont.lcd(10)).monospacedDigit()
            if expanded != nil {
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .bold))
                    .rotationEffect(.degrees(isOpen ? 0 : -90))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(STColor.ink)
        .padding(.horizontal, 12).frame(height: 26)
        .background(STColor.tileTop.opacity(0.55))
        .overlay(alignment: .bottom) { Rectangle().fill(STColor.hairline).frame(height: 0.5) }
        .contentShape(Rectangle())
    }
}

/// The one-line summary a collapsed reference section shows under its header, so the section
/// still tells you something at a glance (e.g. "WCF 3.5 · WCF 3.6 · WSC Q32"). Click to expand.
struct DeskCollapsedSummary: View {
    /// The section this is the collapsed summary for ("Proof Texts", "Word Study"...) — folded
    /// into the accessibility label so VoiceOver announces what expanding reveals, not just the
    /// truncated preview text a sighted reader already sees visually labelled by the section
    /// header just above it.
    let section: String
    let text: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(text)
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(STColor.secondary)
                .lineLimit(1).truncationMode(.tail)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) { Rectangle().fill(STColor.hairline).frame(height: 1) }
        .help("Show all")
        .accessibilityLabel("Show all \(section): \(text)")
        .accessibilityHint("Expands this section")
    }
}

/// A visible, always-shown (never behind an expand toggle) note or warning about an entire desk
/// section. Reads as informational at rest; reads as a warning (icon + color swap) once
/// `isWarning` is set — used for the opt-in disputed-reception bank, never for ordinary historic
/// witness material.
struct DeskDisclaimer: View {
    let text: String
    var isWarning: Bool = false

    private var tint: Color { isWarning ? STColor.warning : STColor.fathers }
    // The icon needs its own, per-finish-tuned foreground (see `STColor.disclaimerInfoIcon`) --
    // `tint` stays reserved for the wash/rule background, which was never the contrast problem.
    private var iconTint: Color { isWarning ? STColor.disclaimerWarningIcon : STColor.disclaimerInfoIcon }

    var body: some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: isWarning ? "exclamationmark.triangle.fill" : "info.circle.fill")
                .font(.system(size: 10))
                .foregroundStyle(iconTint)
                .accessibilityHidden(true)
            Text(text)
                .font(.system(size: 10.5, weight: .regular, design: .rounded))
                .foregroundStyle(STColor.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(isWarning ? 0.10 : 0.035))
        .overlay(alignment: .bottom) { Rectangle().fill(STColor.hairline).frame(height: 0.5) }
        .accessibilityElement(children: .combine)
        .accessibilityLabel((isWarning ? "Warning: " : "Note: ") + text)
    }
}

/// The shared outer shell for one entry on the desk: consistent padding and a header/content/
/// footer slot order. `SourceCard` (`Panes.swift`) is the reference implementation; a future
/// `ProofTextCard`/`WordStudyCard` supplies the same three closures with its own content.
struct DeskCard<Header: View, Content: View, Footer: View>: View {
    @ViewBuilder var header: () -> Header
    @ViewBuilder var content: () -> Content
    @ViewBuilder var footer: () -> Footer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            header()
            content()
            footer()
        }
        .padding(.horizontal, 12).padding(.vertical, 11)
        .background(STColor.paper)
    }
}

/// A small printed label marking a run of cards inside a section as belonging to one author or
/// document — used when a bank holds more than one voice (Reformed will soon carry Calvin, Henry
/// and Gill together) so a reader can scan past a voice they've already read. Deliberately quiet:
/// this is a scanning aid, not a second header.
struct DeskAuthorGroupHeader: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .legend(STColor.secondary, size: 9)
            .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 2)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Collapsed-by-default long-form text with an obvious expand affordance: a bottom fade plus a
/// small chevron when the text is actually cut off, matching the collapse pattern every long
/// desk entry needs now that commentary can run thousands of words (Gill, Henry's *Complete*
/// Commentary). Caller owns the `expanded` binding so it can pair with a footer MORE/LESS control
/// if it wants one, and text selection stays enabled either way.
struct DeskExpandableText: View {
    let text: String
    var collapsedLines: Int = 6
    @Binding var expanded: Bool
    /// The solid color the fade dissolves into — must match whatever's actually behind this text
    /// (`SourceCard` sits on `SourcesPane`'s `tileWell`-tinted scroll background, not a card
    /// background of its own, so the default is `tileWell`, not `tileTop`).
    var fadeColor: Color = STColor.tileWell
    /// Defaults match the fixed face/size this text always rendered at, so a caller that never
    /// passes these is unaffected. `SourceCard`'s commentary excerpt and `ArticleRow`'s reference
    /// articles both pass `AppState.studyTypeface`/`studyFontSize`/`studyLineSpacing` (0.10.2) —
    /// commentary/study text's own font controls, independent of Scripture's Type/Leading knobs.
    var typeface: ReadingTypeface = .baskerville
    var fontSize: CGFloat = 13.5
    var lineSpacing: CGFloat = 3

    var body: some View {
        // E5(b), 0.7 wave 2: the "Show more" pill used to sit *on top of* the faded last line
        // (an overlay at the text's own bottom edge), so the pill visually collided with
        // whatever word happened to fall underneath it. The fade (a "there's more below" cue)
        // still overlays the cut-off line, but the pill itself is now a normal row placed below
        // the text, never covering a single character of it.
        VStack(alignment: .trailing, spacing: 6) {
            Text(text)
                .font(STFont.reading(fontSize, typeface: typeface))
                .lineSpacing(lineSpacing)
                .lineLimit(expanded ? nil : collapsedLines)
                .textSelection(.enabled)
                .overlay(alignment: .bottom) {
                    if !expanded {
                        LinearGradient(colors: [fadeColor.opacity(0), fadeColor], startPoint: .top, endPoint: .bottom)
                            .frame(height: 18)
                            .allowsHitTesting(false)
                    }
                }
            if !expanded {
                Button { expanded = true } label: {
                    HStack(spacing: 2) {
                        Text("Show more").font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.down").font(.system(size: 8, weight: .semibold))
                    }
                    .foregroundStyle(STColor.ink)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(fadeColor, in: Capsule())
                    .overlay(Capsule().stroke(STColor.keyRim, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAction(named: expanded ? "Show less" : "Show more") { expanded.toggle() }
    }
}

/// The small MORE/LESS toggle used in a desk card's footer.
struct DeskMoreButton: View {
    @Binding var expanded: Bool

    var body: some View {
        Button(expanded ? "LESS" : "MORE") { expanded.toggle() }
            .buttonStyle(.plain)
            .legend(STColor.ink, size: 9)
            .accessibilityLabel(expanded ? "Show less" : "Show more detail")
    }
}
