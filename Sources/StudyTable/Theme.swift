import SwiftUI
import AppKit

/// Quiet paper and metal. Color signals interaction; typography carries hierarchy.
enum STColor {
    // Quiet paper and metal surfaces share the reader's selected palette.
    static var paper: Color { Color.workspace { $0.paper } }
    static var ink: Color { Color.workspace { $0.ink } }
    static var secondary: Color { Color.workspace { blendRGB($0.ink, $0.paper, amount: 0.30) } }
    static var chassisTop: Color { Color.workspace { blendRGB($0.paper, $0.ink, amount: 0.07) } }
    static var chassisBottom: Color { Color.workspace { blendRGB($0.paper, $0.ink, amount: 0.13) } }
    static var chassisEdge: Color { Color.workspace { blendRGB($0.paper, $0.ink, amount: 0.30) } }
    static var outline: Color { Color.workspace { $0.ink } }
    static var gutter: Color { Color.workspace { blendRGB($0.paper, $0.ink, amount: 0.12) } }
    static var tileTop: Color { Color.workspace { $0.paper } }
    static var tileBottom: Color { Color.workspace { blendRGB($0.paper, $0.ink, amount: 0.025) } }
    static var tileWell: Color { Color.workspace { blendRGB($0.paper, $0.ink, amount: 0.05) } }
    static let socket = Color(light: 0x242621, dark: 0x0B0C0B)
    static var metalRim: Color { Color.workspace { blendRGB($0.paper, $0.ink, amount: 0.18) } }
    static let highlight = Color(light: 0xFFFFFF, dark: 0x51514C)
    static var hairline: Color { Color.workspace { blendRGB($0.paper, $0.ink, amount: 0.15) } }
    static var keyTop: Color { Color.workspace { $0.paper } }
    static var keyBottom: Color { Color.workspace { blendRGB($0.paper, $0.ink, amount: 0.04) } }
    static var keyRim: Color { Color.workspace { blendRGB($0.paper, $0.ink, amount: 0.19) } }

    // LCD (black in both finishes)
    static let lcd = Color(hex: 0x0A0A0B)
    static let lcdInk = Color(hex: 0xF3F1EA)
    static let lcdDim = Color(hex: 0x9A9C96)
    static let lcdRim = Color(light: 0x000000, dark: 0x5A5B57)

    // Signals
    static let orange = Color(hex: 0xCB591E)
    static var navy: Color { Color.workspace { $0.accent } }
    static let fathers = Color(hex: 0xF0A81C)
    static let reformed = Color(hex: 0x3FAE55)
    // Exegetes bank (Gill/Keil-Delitzsch/Jamieson-Fausset-Brown), new 0.7 wave 2 — a violet
    // distinct from amber/Fathers, green/Reformed and blue/Cross-References in both finishes,
    // and also distinct from the navy/orange knob-cap pair. Slightly lighter in dark mode for
    // the same legibility-against-graphite reason every other dark variant here is lighter.
    static let exegetes = Color(light: 0x7B5EA8, dark: 0xB09BDB)
    static let crossRefs = Color(hex: 0x3F86E8)
    static let warning = Color(hex: 0xC23B2E)
    // Proof Texts and Word Study section-header swatches (`DeskSectionHeader`'s `color`) sit on
    // the invariant-black LCD bar, same as the tradition-bank swatches (fathers/reformed/exegetes/
    // crossRefs) -- but those are all flat hexes, while `navy` is light/dark *adaptive* (a dark
    // navy in light mode, tuned to sit on a light knob-cap tile, not black) and measured ~1.56:1
    // there. This is the dark-mode navy value, used as a fixed swatch color in both finishes
    // instead, matching how every other on-black swatch already behaves.
    static let navyOnBlack = Color(hex: 0x5468B0)

    // `DeskDisclaimer`'s icon (`fathers`/`warning` tint at full strength, on top of that same
    // tint's own 10%-opacity wash) measured ~1.4:1 in light mode -- those two colors were tuned
    // as LEDs/backgrounds, never checked as an icon-on-wash foreground. A single flat hex can't
    // clear 3:1 against both a near-white wash (light) and a near-black one (dark) at once, so
    // these are tuned per finish instead, each independently verified ≥3:1 against the tile
    // gradient behind that wash.
    static let disclaimerInfoIcon = Color(light: 0x8A5E00, dark: 0xE8C468)
    static let disclaimerWarningIcon = Color(light: 0x8F2419, dark: 0xE8776B)
}

extension Color {
    init(hex: UInt) {
        self.init(red: Double((hex >> 16) & 0xff) / 255, green: Double((hex >> 8) & 0xff) / 255, blue: Double(hex & 0xff) / 255)
    }

    init(light: UInt, dark: UInt) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value = isDark ? dark : light
            return NSColor(
                red: CGFloat((value >> 16) & 0xff) / 255,
                green: CGFloat((value >> 8) & 0xff) / 255,
                blue: CGFloat(value & 0xff) / 255,
                alpha: 1
            )
        })
    }
}

/// Type roles. Instrument legends and numerals use the thin rounded system face; Scripture
/// and commentary keep a serif for sustained reading; monospace is reserved for LCD data.
enum STFont {
    static func legend(_ size: CGFloat = 9) -> Font { .system(size: size, weight: .medium, design: .rounded) }
    static func numeral(_ size: CGFloat, weight: Font.Weight = .thin) -> Font { .system(size: size, weight: weight, design: .rounded) }
    static func lcd(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .monospaced) }
    static func title(_ size: CGFloat = 17) -> Font { .system(size: size, weight: .regular, design: .rounded) }
    /// Defaults to `.baskerville` — today's shipped face — so every pre-existing call site is
    /// unaffected. A caller tied to a reader-chosen voice (`AppState.scriptureTypeface`/
    /// `.studyTypeface`, 0.10.2) passes `typeface:` instead. See `ReadingTypeface` for why this
    /// and `readingNSFont` (WordHit.swift) must always resolve the identical font.
    static func reading(_ size: CGFloat, weight: Font.Weight = .regular, typeface: ReadingTypeface = .baskerville) -> Font {
        typeface.font(size: size, weight: weight)
    }
    /// Hebrew/Aramaic/Greek original-language text (`OriginalLanguageSection`, the LCD's
    /// interlinear strip). Deliberately `design: .default` rather than `.serif`/`.rounded` —
    /// New York and SF Pro Rounded's non-Latin fallback behavior is inconsistent for Hebrew
    /// niqqud/cantillation stacking, while the plain system font's own Hebrew/Greek fallback
    /// (SF Hebrew / the system's Greek-covering face) is what macOS actually ships and tests
    /// glyph shaping against.
    static func original(_ size: CGFloat, weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight) }
}

extension View {
    /// Printed legend under or beside a control.
    func legend(_ color: Color = STColor.secondary, size: CGFloat = 9) -> some View {
        self.font(STFont.legend(size)).tracking(0.9).foregroundStyle(color)
    }

    /// A warm-white tile face: soft vertical falloff and a lit top edge.
    func tileFace() -> some View { modifier(TileFace()) }

    func physicalPaneSurface() -> some View { modifier(PhysicalPaneSurface()) }
}

/// Static raster material, cached once and never used behind reading text.
struct MaterialGrain: View {
    private static let texture: NSImage? = {
        guard let url = AppResources.url("Materials/lectern-micrograin.png"),
              let image = NSImage(contentsOf: url) else { return nil }
        // The source is 1254px: its native point size makes speckle look like stone.
        // A small repeating material sample produces fine bead-blasted grain instead.
        image.size = NSSize(width: 96, height: 96)
        return image
    }()
    var opacity: Double = 0.045

    var body: some View {
        Group {
            if let texture = Self.texture {
                Image(nsImage: texture).resizable(resizingMode: .tile)
                    .blendMode(.softLight).opacity(opacity)
            }
        }
        .allowsHitTesting(false).accessibilityHidden(true)
    }
}

/// A reading aperture sunk into the common machined plate.
struct PhysicalPaneSurface: ViewModifier {
    @ObservedObject private var updates = AppearanceUpdates.shared
    func body(content: Content) -> some View {
        content.background(STColor.paper)
            .clipShape(RoundedRectangle(cornerRadius: 3))
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(STColor.hairline, lineWidth: 0.6).allowsHitTesting(false))
    }
}

struct TileFace: ViewModifier {
    @ObservedObject private var updates = AppearanceUpdates.shared
    func body(content: Content) -> some View {
        content.background(STColor.tileBottom, in: RoundedRectangle(cornerRadius: 3))
    }
}

/// Wraps its children left-to-right, breaking to a new line when a child would overflow —
/// for chip/tag collections (cross-reference links, filters) where an HStack would clip.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var origin = CGPoint.zero
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > width, origin.x > 0 {
                origin.x = 0
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            origin.x += size.width + spacing
            maxX = max(maxX, origin.x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: min(maxX, width), height: origin.y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var origin = CGPoint(x: bounds.minX, y: bounds.minY)
        var rowHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if origin.x + size.width > bounds.maxX, origin.x > bounds.minX {
                origin.x = bounds.minX
                origin.y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: origin, proposal: .unspecified)
            origin.x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
