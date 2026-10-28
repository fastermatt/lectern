import SwiftUI
import AppKit

// ReadingTypeface — Claude, 2026-09-27. Matt: "I also want to be able to choose other fonts for
// reading everything." A curated set of reading faces (not a raw system-font dropdown — an
// instrument offers voices, not a settings-app list), mirroring the same considered role Apple
// Books gives its own reader: every option here is a real macOS-bundled book/document face,
// chosen for long-form reading rather than display or UI use.
//
// Correctness constraint this file exists to protect: the double-click-a-word hit-testing layer
// (`ReaderTextLayout` in WordHit.swift, an invisible AppKit TextKit layer sitting behind the
// SwiftUI verse `Text`) must measure glyphs with the *exact* font SwiftUI actually draws, for
// whichever typeface the reader has chosen — any drift breaks word-click accuracy silently. Both
// `STFont.reading` (SwiftUI `Font`) and `STFont.readingNSFont` (AppKit `NSFont`, used by the hit
// layer) now resolve through this one function, so they can never disagree: the `Font.custom`
// SwiftUI builds and the `NSFont` the hit layer measures against always carry the identical
// PostScript name.
enum ReadingTypeface: String, CaseIterable, Identifiable, Codable, Hashable, Sendable {
    case baskerville   // today's shipped default — zero visual change for anyone who never touches this.
    case newYork
    case georgia
    case palatino
    case athelas
    case charter
    case iowanOldStyle
    case timesNewRoman
    case seravek       // the one deliberately non-serif voice, for a reader who wants a lighter register.

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .baskerville: "Baskerville"
        case .newYork: "New York"
        case .georgia: "Georgia"
        case .palatino: "Palatino"
        case .athelas: "Athelas"
        case .charter: "Charter"
        case .iowanOldStyle: "Iowan Old Style"
        case .timesNewRoman: "Times New Roman"
        case .seravek: "Seravek"
        }
    }

    /// One line of real character, not marketing copy — shown as the swatch's caption so the
    /// picker reads as a considered set of voices rather than an alphabetical font list.
    var character: String {
        switch self {
        case .baskerville: "Classic book serif — the console's original voice"
        case .newYork: "Apple's own reading serif"
        case .georgia: "Warm, screen-drawn serif"
        case .palatino: "Renaissance-inspired serif"
        case .athelas: "Literary, high-contrast serif"
        case .charter: "Crisp, ink-trap serif"
        case .iowanOldStyle: "Old-style book serif"
        case .timesNewRoman: "Traditional newsprint serif"
        case .seravek: "Humanist sans — a lighter register"
        }
    }

    /// The real macOS family name to resolve. `nil` for `.newYork`, which — unlike every other
    /// case here — is not a normal nameable family on this system: `NSFont(name: "New York", …)`
    /// and `NSFontManager`'s family enumeration both return nothing for it (confirmed empirically,
    /// not assumed). New York's real PostScript name is a private, dot-prefixed system name
    /// (`.NewYork-Regular`) only reachable through the public `NSFontDescriptor.withDesign(.serif)`
    /// API — the same public route SwiftUI's own `Font.system(design: .serif)` uses — so it gets
    /// its own resolution path below instead of the family-name lookup every other case shares.
    private var familyName: String? {
        switch self {
        case .baskerville: "Baskerville"
        case .newYork: nil
        case .georgia: "Georgia"
        case .palatino: "Palatino"
        case .athelas: "Athelas"
        case .charter: "Charter"
        case .iowanOldStyle: "Iowan Old Style"
        case .timesNewRoman: "Times New Roman"
        case .seravek: "Seravek"
        }
    }

    /// Resolves `familyName` to a real installed regular-weight `NSFont`, trying the family name
    /// as a direct PostScript name first (works for most of these classic families: "Georgia",
    /// "Palatino", "Baskerville", "Times New Roman" are all valid regular-weight PostScript names
    /// on macOS), then falling back to a family-member lookup preferring a "Regular"/"Roman"
    /// trait (covers families — e.g. "Seravek" — whose regular weight has its own PostScript
    /// name distinct from the family name). Not cached: `NSFontManager` lookups here are only a
    /// handful per render, and a `static var` cache would be global mutable state under Swift 6's
    /// strict concurrency checking for no real benefit at this call volume.
    private func resolvedRegular(size: CGFloat) -> NSFont? {
        guard let familyName else { return Self.resolveNewYork(size: size) }
        return Self.resolve(familyName: familyName, size: size)
    }

    /// New York via the public system-font-descriptor route (see `familyName`'s comment). Returns
    /// `nil` only if a future OS removes the `.serif` design entirely, in which case `nsFont(...)`
    /// falls back to Baskerville exactly as it would for any other missing typeface.
    private static func resolveNewYork(size: CGFloat) -> NSFont? {
        let system = NSFont.systemFont(ofSize: size)
        guard let serifDescriptor = system.fontDescriptor.withDesign(.serif) else { return nil }
        return NSFont(descriptor: serifDescriptor, size: size)
    }

    private static func resolve(familyName: String, size: CGFloat) -> NSFont? {
        if let direct = NSFont(name: familyName, size: size) { return direct }
        guard let members = NSFontManager.shared.availableMembers(ofFontFamily: familyName) else { return nil }
        var fallbackName: String?
        for member in members {
            guard let postscriptName = member.first as? String else { continue }
            if fallbackName == nil { fallbackName = postscriptName }
            guard member.count > 1, let trait = member[1] as? String else { continue }
            let isRegular = trait.caseInsensitiveCompare("Regular") == .orderedSame
                || trait.caseInsensitiveCompare("Roman") == .orderedSame
            if isRegular { return NSFont(name: postscriptName, size: size) }
        }
        guard let fallbackName else { return nil }
        return NSFont(name: fallbackName, size: size)
    }

    /// The bold variant of this typeface at `size`, via `NSFontManager`'s trait conversion rather
    /// than guessing a "-Bold" suffix (wrong for several of these families, e.g. Times New
    /// Roman's bold PostScript name is "TimesNewRomanPS-BoldMT", not "Times New Roman-Bold").
    private func resolvedBold(size: CGFloat) -> NSFont? {
        guard let regular = resolvedRegular(size: size) else { return nil }
        return NSFontManager.shared.convert(regular, toHaveTrait: .boldFontMask)
    }

    /// A real, installed `NSFont` for this typeface — the single source of truth both the SwiftUI
    /// `Font` and the AppKit hit-test layer resolve through. Falls back to `.baskerville`'s own
    /// resolution (always available on a real Mac) if this family is somehow missing, then to the
    /// system font as a last resort so reading text is never silently blank.
    func nsFont(size: CGFloat, bold: Bool = false) -> NSFont {
        if let resolved = bold ? resolvedBold(size: size) : resolvedRegular(size: size) { return resolved }
        if self != .baskerville, let fallback = bold ? ReadingTypeface.baskerville.resolvedBold(size: size)
                                                       : ReadingTypeface.baskerville.resolvedRegular(size: size) {
            return fallback
        }
        return bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
    }

    /// The SwiftUI `Font` for this typeface — built from the exact same `NSFont` (by PostScript
    /// name) that `nsFont(size:bold:)` returns, so it can never draw differently from what the
    /// hit-test layer measured.
    func font(size: CGFloat, weight: Font.Weight = .regular) -> Font {
        let bold = weight == .bold || weight == .semibold
        return .custom(nsFont(size: size, bold: bold).fontName, size: size)
    }

    /// Only the typefaces this Mac can actually resolve — filters the picker so a reader is never
    /// offered a swatch that would silently fall back to something else the moment they tap it.
    /// Every case is Apple-bundled and expected to resolve on any Mac running this app's minimum
    /// OS; this exists as a defensive net, not because failures are expected.
    static var available: [ReadingTypeface] {
        allCases.filter { $0 == .baskerville || $0.resolvedRegular(size: 12) != nil }
    }

    /// `false` for `.palatino` and `.newYork`: `ReaderLayoutEquivalenceTests` found — empirically,
    /// not by inspection — that at this app's reading sizes, TextKit's `usedRect` for each of
    /// these two comes out taller than what SwiftUI's `Text` actually laid out at, even though
    /// both resolve the identical PostScript name. Neither font has zero glyph coverage, unusual
    /// `leading`, or a resolution bug in this file — every other typeface here, including two
    /// (Georgia, Times New Roman) with equally "unusual" naming, agree with SwiftUI exactly. The
    /// mismatch traces to something specific to how TextKit and Core Text disagree about these two
    /// fonts' line metrics, and it wasn't worth chasing further under time pressure when the fix
    /// that actually matters — never letting Scripture's hit-test layer silently drift from what's
    /// drawn — is simple and safe: don't offer them there. Commentary/study text has no hit-test
    /// layer to break, so both stay offered for Study. Don't re-include either for Scripture
    /// without first re-running `testTextKitWrapsAndPositionsLikeSwiftUITextForEveryChosenTypeface`
    /// against it and getting a clean pass.
    var isSafeForScripture: Bool { self != .palatino && self != .newYork }

    /// What the Scripture typeface picker actually offers — `available` further narrowed to the
    /// typefaces proven safe for the hit-test layer.
    static var availableForScripture: [ReadingTypeface] { available.filter(\.isSafeForScripture) }
}
