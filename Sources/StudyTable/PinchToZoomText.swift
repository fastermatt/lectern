import SwiftUI

// PinchToZoomText — Claude, 2026-09-27. Matt: "I also would like to pinch to zoom the text on the
// trackpad like an iPhone does." A trackpad pinch is a second, direct way to reach the same size
// value the Type knob (Scripture) or the Settings stepper (Study) already control — not a new
// preference of its own, so it needs no persistence here: it just moves `AppState.fontSize` /
// `studyFontSize`, exactly as if the reader had turned the knob or nudged the stepper.
private struct PinchToZoomTextSize: ViewModifier {
    @Binding var size: Double
    let range: ClosedRange<Double>
    /// Captured once per gesture (the size when the pinch began), so the gesture's cumulative
    /// scale factor multiplies from a fixed starting point rather than compounding every frame.
    @State private var baseSize: Double?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.highPriorityGesture(
            // `.highPriorityGesture`, not `.gesture`: attached to a pane that contains a
            // `ScrollView` (verse rows, or the commentary/notes lists), a plain `.gesture()` can
            // lose recognition entirely to the ScrollView's own built-in gesture handling on
            // macOS — the exact bug Matt hit ("pinch does NOT change the Bible text"). A pinch is
            // a physically distinct two-finger gesture from scrolling or clicking, so forcing it
            // to win recognition first costs nothing real.
            MagnificationGesture()
                .onChanged { scale in
                    let base = baseSize ?? size
                    if baseSize == nil { baseSize = base }
                    // Direct manipulation tracks the fingers with no easing lag, exactly like the
                    // Type/Leading knobs' own live-drag behavior (`KnobTile`'s `disablesAnimations`).
                    var transaction = Transaction(animation: nil)
                    transaction.disablesAnimations = true
                    withTransaction(transaction) {
                        size = min(range.upperBound, max(range.lowerBound, base * scale))
                    }
                }
                .onEnded { _ in baseSize = nil }
        )
    }
}

extension View {
    /// Pinch-to-zoom for reading text, mirroring iOS's familiar gesture on a trackpad. `size` is
    /// the same `AppState` property the reader's other control (a knob or a Settings stepper)
    /// already drives — this is an additional way to reach it, not a separate setting.
    func pinchToZoomTextSize(_ size: Binding<Double>, in range: ClosedRange<Double>) -> some View {
        modifier(PinchToZoomTextSize(size: size, range: range))
    }
}
