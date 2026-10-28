import SwiftUI

// LECTERN MATERIAL CONTRACT — approved console mockup (2026-09-24).
// One continuous bevelled metal enclosure carries recessed reading apertures and a bottom
// control rail; ivory/aluminium and full graphite use the same physical geometry.
// Keycaps are round, compact and tactile; only Type and Leading are rotary cylinders.
// Light stays upper-left while knob bodies rotate. Press travel is 1–2 pt in 100 ms,
// with no bounce; direct drag has no animation lag and Reduce Motion removes travel.
// Verify both finishes at full and minimum window widths, plus keyboard/VoiceOver controls.

// MARK: - Frame

/// One continuous aluminum shell: the content sits within its machined lip and a small
/// horizontal maker's mark is printed on the lower rim.
struct InstrumentFrame<Content: View>: View {
    @ObservedObject private var updates = AppearanceUpdates.shared
    @ViewBuilder let content: () -> Content

    var body: some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(STColor.paper)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(STColor.chassisEdge.opacity(0.55), lineWidth: 1).allowsHitTesting(false))
            .padding(8)
            .background(STColor.chassisTop)
    }

}

// MARK: - Keys

enum KeyGlyph {
    case symbol(String)
    case numeral(String)
    case text(String)
}

/// Round injection-molded pushbutton, with a narrow seam and visible sidewall.
struct RoundKeyStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var size: CGFloat = 44
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed || selected
        ZStack {
            Circle()
                .fill(STColor.metalRim)
                .frame(width: size + 2, height: size + 2)
                .overlay(Circle().strokeBorder(STColor.highlight.opacity(0.8), lineWidth: 0.6))
            Circle()
                .fill(LinearGradient(colors: [STColor.keyBottom, STColor.keyRim, STColor.chassisEdge], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size, height: size)
                .offset(y: 2)
                .shadow(color: .black.opacity(down ? 0.10 : 0.20), radius: down ? 1 : 3, x: 0, y: down ? 1 : 2)
            Circle()
                .fill(LinearGradient(colors: [STColor.keyTop, STColor.keyTop, STColor.keyBottom],
                                     startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: size - 1, height: size - 1)
                .overlay(Circle().strokeBorder(LinearGradient(colors: [STColor.highlight, STColor.keyRim], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.2))
                .overlay { MaterialGrain(opacity: 0.04).clipShape(Circle()) }
                .offset(y: down ? -1 : -3)
            configuration.label
                .foregroundStyle(STColor.ink)
                .shadow(color: STColor.highlight.opacity(0.75), radius: 0, x: 0, y: 0.6)
                .offset(y: down ? -1 : -3)
        }
        .frame(width: size + 5, height: size + 6)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct PillKeyStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    var selected = false

    func makeBody(configuration: Configuration) -> some View {
        let down = configuration.isPressed || selected
        // The recess and cap are drawn as a background so the caller's frame, not the shapes,
        // decides the pill's size.
        configuration.label
            .foregroundStyle(STColor.ink)
            .offset(y: down ? 1 : 0)
            .background {
                ZStack {
                    Capsule().fill(STColor.tileWell)
                        .overlay(Capsule().stroke(STColor.keyRim.opacity(0.75), lineWidth: 1))
                    Capsule()
                        .fill(LinearGradient(colors: selected ? [STColor.keyRim.opacity(0.95), STColor.keyBottom]
                                                                : (down ? [STColor.keyBottom, STColor.keyTop] : [STColor.keyTop, STColor.keyBottom]),
                                             startPoint: .top, endPoint: .bottom))
                        .padding(3)
                        .overlay(Capsule().inset(by: 3).stroke(STColor.keyRim, lineWidth: 1))
                        .overlay(Capsule().inset(by: 6.5).stroke(STColor.ink.opacity(selected ? 0.4 : 0), lineWidth: 1))
                        .shadow(color: .black.opacity(down ? 0.08 : 0.26), radius: down ? 0.5 : 2, x: 0, y: down ? 0.5 : 2)
                        .offset(y: down ? 1 : 0)
                }
            }
            .animation(reduceMotion ? nil : .easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct KeyFace: View {
    let glyph: KeyGlyph
    var size: CGFloat = 44

    var body: some View {
        Group {
            switch glyph {
            case .symbol(let name): Image(systemName: name).font(.system(size: size * 0.40, weight: .light))
            case .numeral(let value): Text(value).font(STFont.numeral(size * 0.52, weight: .thin))
            case .text(let value): Text(value).font(STFont.numeral(size * 0.30, weight: .regular)).minimumScaleFactor(0.7).lineLimit(1)
            }
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
    }
}

struct LED: View {
    let on: Bool
    var body: some View {
        Circle()
            .fill(on ? STColor.orange : Color.clear)
            .overlay(Circle().stroke(on ? STColor.orange : STColor.secondary.opacity(0.5), lineWidth: 1))
            .frame(width: 5, height: 5)
            .accessibilityHidden(true)
    }
}

/// One molded key on the shared metal control rail.
struct KeyTile: View {
    let title: String
    let glyph: KeyGlyph
    var selected = false
    var size: CGFloat = 38
    var help: String? = nil
    var accessibilityLabel: String? = nil
    let action: () -> Void

    var body: some View {
        VStack(spacing: 3) {
            Button(action: action) { KeyFace(glyph: glyph, size: size) }
                .buttonStyle(RoundKeyStyle(size: size, selected: selected))
                .accessibilityLabel(accessibilityLabel ?? title.capitalized)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .help(help ?? title.capitalized)
            Text(title).legend(STColor.secondary, size: size < 40 ? 8 : 9).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A key that opens a menu (book, chapter, translation, theme).
struct MenuKeyTile<Items: View>: View {
    let title: String
    let glyph: KeyGlyph
    var size: CGFloat = 38
    var help: String? = nil
    @ViewBuilder let items: () -> Items

    var body: some View {
        VStack(spacing: 3) {
            Menu(content: items) { KeyFace(glyph: glyph, size: size) }
                .menuStyle(.button)
                .buttonStyle(RoundKeyStyle(size: size))
                .menuIndicator(.hidden)
                .accessibilityLabel(title.capitalized)
                .help(help ?? title.capitalized)
            Text(title).legend(STColor.secondary, size: size < 40 ? 8 : 9).lineLimit(1).minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Rotary knob (Type and Leading only)

struct KnobTile: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let label: String
    let unit: String
    let cap: Color

    @State private var dragOrigin: Double?

    private var fraction: Double { (value - range.lowerBound) / (range.upperBound - range.lowerBound) }
    private var angle: Double { -135 + fraction * 270 }
    private var valueText: String { "\(Int(value)) \(unit)" }

    var body: some View {
        VStack(spacing: 0) {
            knob
                .frame(width: 50, height: 54)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if dragOrigin == nil { dragOrigin = value }
                            guard let dragOrigin else { return }
                            let travel = -gesture.translation.height + gesture.translation.width * 0.35
                            let raw = dragOrigin + travel / 110 * (range.upperBound - range.lowerBound)
                            var transaction = Transaction(animation: nil)
                            transaction.disablesAnimations = true
                            withTransaction(transaction) { value = KnobValue.clamp(raw, to: range, step: step) }
                        }
                        .onEnded { _ in dragOrigin = nil }
                )
            HStack(spacing: 4) {
                Text(label).legend().lineLimit(1).fixedSize()
                Spacer(minLength: 2)
                Text(valueText).font(STFont.numeral(11, weight: .regular)).foregroundStyle(STColor.ink).monospacedDigit().lineLimit(1).fixedSize()
            }
            .padding(.horizontal, 8)
            .padding(.top, 5)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .help("Drag up or down to change \(label.lowercased())")
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label.capitalized)
        .accessibilityValue(valueText)
        .focusable()
        .onKeyPress(.upArrow) { adjust(1); return .handled }
        .onKeyPress(.rightArrow) { adjust(1); return .handled }
        .onKeyPress(.downArrow) { adjust(-1); return .handled }
        .onKeyPress(.leftArrow) { adjust(-1); return .handled }
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: adjust(1)
            case .decrement: adjust(-1)
            @unknown default: break
            }
        }
    }

    private func adjust(_ direction: Double) {
        withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) {
            value = KnobValue.clamp(value + direction * step, to: range, step: step)
        }
    }

    private var knob: some View {
        ZStack {
            // Smooth molded base and cap, following the supplied physical knob photo.
            // Illumination remains fixed while the recessed position dot travels around it.
            // A thin ring of `cap`'s color at the foot of the knob — like the colored trim ring
            // on a hardware synth knob — is the one deliberate hit of color in an otherwise
            // neutral ivory/graphite deck; it's what tells Type from Leading at a glance, echoed
            // by the (already-existing) matching color of the recessed position dot.
            Ellipse()
                .fill(LinearGradient(colors: [STColor.keyTop, STColor.keyRim, STColor.keyBottom], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 48, height: 43).offset(y: 5)
                .shadow(color: .black.opacity(0.30), radius: 4, x: 4, y: 5)
                .overlay {
                    Ellipse().strokeBorder(cap.opacity(0.55), lineWidth: 1.5)
                        .frame(width: 46.5, height: 41.5).offset(y: 5)
                }
            Ellipse()
                .fill(LinearGradient(colors: [STColor.keyTop, STColor.keyBottom, STColor.keyRim], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 44, height: 43).offset(y: 1)
                .overlay {
                    Ellipse().strokeBorder(STColor.highlight.opacity(0.5), lineWidth: 0.8)
                        .frame(width: 44, height: 43).offset(y: 1)
                }
            Circle()
                .fill(RadialGradient(colors: [STColor.keyTop, STColor.keyTop, STColor.keyBottom], center: .topLeading, startRadius: 2, endRadius: 49))
                .frame(width: 43, height: 43)
                .overlay {
                    Circle().strokeBorder(LinearGradient(colors: [STColor.highlight.opacity(0.85), STColor.keyBottom], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.8)
                }
                .shadow(color: .black.opacity(0.14), radius: 1.5, x: 1, y: 2)
                .offset(y: -3)
            Circle()
                .fill(cap.shadow(.inner(color: .black.opacity(0.55), radius: 1.5, x: 1, y: 1.5)))
                .frame(width: 5.5, height: 5.5)
                .overlay(Circle().strokeBorder(LinearGradient(colors: [STColor.keyRim, STColor.highlight], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 0.65))
                .offset(x: sin(angle * .pi / 180) * 13,
                        y: -cos(angle * .pi / 180) * 13 - 3)
                .animation(reduceMotion || dragOrigin != nil ? nil : .easeOut(duration: 0.16), value: angle)
        }
        .frame(width: 50, height: 54)
        .contentShape(Circle())
    }
}

enum KnobValue {
    static func clamp(_ raw: Double, to range: ClosedRange<Double>, step: Double) -> Double {
        guard step > 0 else { return min(range.upperBound, max(range.lowerBound, raw)) }
        let snapped = range.lowerBound + ((raw - range.lowerBound) / step).rounded() * step
        return min(range.upperBound, max(range.lowerBound, snapped))
    }
}

// MARK: - Speaker grille

struct GrilleTile: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 9
            let columns = Int((size.width - 20) / spacing)
            let rows = Int((size.height - 20) / spacing)
            let origin = CGPoint(x: (size.width - CGFloat(columns - 1) * spacing) / 2,
                                 y: (size.height - CGFloat(rows - 1) * spacing) / 2)
            for row in 0..<rows {
                for column in 0..<columns {
                    let dx = (CGFloat(column) - CGFloat(columns - 1) / 2) / (CGFloat(columns) / 2)
                    let dy = (CGFloat(row) - CGFloat(rows - 1) / 2) / (CGFloat(rows) / 2)
                    guard pow(abs(dx), 3.2) + pow(abs(dy), 3.2) <= 1 else { continue }
                    let rect = CGRect(x: origin.x + CGFloat(column) * spacing - 2, y: origin.y + CGFloat(row) * spacing - 2, width: 4, height: 4)
                    context.fill(Path(ellipseIn: rect), with: .color(STColor.ink.opacity(0.78)))
                }
            }
        }
        .tileFace()
        .accessibilityHidden(true)
    }
}
