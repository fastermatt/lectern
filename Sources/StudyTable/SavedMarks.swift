import SwiftUI

// MARK: - Highlight palette (0.10, S2a)
//
// The Color-Never-Alone rule: a highlight is never carried by colour alone. Each `HighlightColor`
// pairs a theme-adaptive tint (used as a soft row wash) with its OWN glyph shape, so a reader who
// can't distinguish the colours still sees a different mark per highlight.

extension HighlightColor {
    var tint: Color {
        switch self {
        case .yellow: Color(light: 0xF5D742, dark: 0x7A6B1B)
        case .green: Color(light: 0x8FCB86, dark: 0x2F5C2C)
        case .blue: Color(light: 0x8EC1E8, dark: 0x28415C)
        case .pink: Color(light: 0xE79FC4, dark: 0x5C2A44)
        case .orange: Color(light: 0xF2B57A, dark: 0x5C3A1E)
        case .purple: Color(light: 0xC9A6E0, dark: 0x432A5C)
        }
    }

    /// A distinct SF Symbol per colour — never rely on the tint alone to tell them apart.
    var glyphName: String {
        switch self {
        case .yellow: "circle.fill"
        case .green: "triangle.fill"
        case .blue: "square.fill"
        case .pink: "diamond.fill"
        case .orange: "hexagon.fill"
        case .purple: "seal.fill"
        }
    }

    var displayName: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

// MARK: - Verse marks (saved / highlighted / memory / note)

/// The small marks a verse can carry, stacked at its trailing edge: an orange notched ribbon for a
/// note (range-aware — shows on every verse a note's anchor overlaps), a shaped glyph for a saved
/// highlight (or a plain bookmark glyph for a saved-but-not-highlighted verse), and a tiny "MEM"
/// tick for a memory verse. Purely decorative: the row itself states all of this in words for
/// VoiceOver (see `VerseRow.accessibilityDescription`), so every element here is hidden from the
/// accessibility tree and never intercepts clicks meant for the verse button beneath it.
struct VerseMarksBadge: View {
    var hasNote: Bool
    var highlight: HighlightColor?
    var isSaved: Bool
    var isMemory: Bool

    private var summary: String {
        var parts: [String] = []
        if isSaved { parts.append("Saved") }
        if let highlight { parts.append("Highlighted \(highlight.displayName.lowercased())") }
        if isMemory { parts.append("Memory verse") }
        if hasNote { parts.append("Has a note") }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 3) {
            if hasNote {
                BookmarkRibbon()
                    .fill(LinearGradient(colors: [STColor.orange, Color(hex: 0xA94416)], startPoint: .leading, endPoint: .trailing))
                    .frame(width: 12, height: 17)
                    .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.25)).frame(width: 1).padding(.bottom, 4) }
                    .shadow(color: .black.opacity(0.18), radius: 1, x: 1, y: 1)
            }
            if let highlight {
                Image(systemName: highlight.glyphName)
                    .font(.system(size: 8))
                    .foregroundStyle(highlight.tint)
            } else if isSaved {
                Image(systemName: "bookmark.fill")
                    .font(.system(size: 8))
                    .foregroundStyle(STColor.secondary)
            }
            if isMemory {
                Text("MEM")
                    .font(.system(size: 6.5, weight: .bold, design: .rounded))
                    .tracking(0.4)
                    .foregroundStyle(STColor.ink)
                    .padding(.horizontal, 2).padding(.vertical, 1)
                    .background(STColor.tileWell, in: RoundedRectangle(cornerRadius: 2))
                    .overlay(RoundedRectangle(cornerRadius: 2).stroke(STColor.keyRim, lineWidth: 0.6))
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .help(summary.isEmpty ? "" : summary)
    }
}
