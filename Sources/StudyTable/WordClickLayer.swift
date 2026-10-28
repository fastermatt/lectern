import AppKit
import SwiftUI

// MARK: - The AppKit layer behind a verse's text

/// Sits *behind* a verse's SwiftUI `Text` (same frame) and does two jobs without drawing any
/// Scripture itself: it answers "which word is under this point?" for double-clicks, and it draws
/// the soft highlight + underline for the word currently open in the Study Desk. SwiftUI keeps
/// drawing the text; `ReaderLayoutEquivalenceTests` proves this layer's TextKit layout is
/// pixel-identical to it. It never takes mouse events (`hitTest` is nil), so single click, right
/// click and the row's Button behave exactly as before.
final class WordHitNSView: NSView {
    var text = "" { didSet { if text != oldValue { invalidate() } } }
    var fontSize: CGFloat = 20 { didSet { if fontSize != oldValue { invalidate() } } }
    var lineSpacing: CGFloat = 8 { didSet { if lineSpacing != oldValue { invalidate() } } }
    /// Must always match whatever `VerseRow`'s SwiftUI `Text` is actually drawing in
    /// (`AppState.scriptureTypeface`) — see `ReadingTypeface`'s header comment.
    var typeface: ReadingTypeface = .baskerville { didSet { if typeface != oldValue { invalidate() } } }
    /// UTF-16 range of the word to highlight (nil for none).
    var highlight: NSRange? { didSet { if highlight != oldValue { needsDisplay = true } } }
    var onWord: ((WordHit) -> Void)?

    private var cachedLayout: ReaderTextLayout?

    override var isFlipped: Bool { true }
    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
    override func isAccessibilityElement() -> Bool { false }

    override func setFrameSize(_ newSize: NSSize) {
        if abs(newSize.width - frame.width) > 0.01 { cachedLayout = nil }
        super.setFrameSize(newSize)
        needsDisplay = true
    }

    private func invalidate() { cachedLayout = nil; needsDisplay = true }

    /// TextKit layout at this view's current width (the width SwiftUI's Text was given).
    var layout: ReaderTextLayout {
        if let cachedLayout, abs(cachedLayout.width - bounds.width) < 0.01 { return cachedLayout }
        let made = ReaderTextLayout(text: text, fontSize: fontSize, lineSpacing: lineSpacing, width: bounds.width, typeface: typeface)
        cachedLayout = made
        return made
    }

    /// The word at `point` in this view's own (flipped, top-left origin) coordinates.
    func word(at point: NSPoint) -> WordHit? {
        guard bounds.width > 1, !text.isEmpty else { return nil }
        return layout.hit(at: point)
    }

    override func draw(_ dirtyRect: NSRect) {
        guard let highlight, highlight.length > 0, NSMaxRange(highlight) <= (text as NSString).length,
              bounds.width > 1,
              let token = layout.tokens.first(where: { $0.range == highlight }) else { return }
        let orange = NSColor(srgbRed: 0xCB / 255.0, green: 0x59 / 255.0, blue: 0x1E / 255.0, alpha: 1)   // STColor.orange
        let isDark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        for rect in layout.rects(for: token) {
            // Soft fill: the selected-verse orange, stronger than the row wash so the word reads on
            // top of it; the 1.5pt underline is what carries the state without relying on colour.
            let box = rect.insetBy(dx: -1.5, dy: 1)
            orange.withAlphaComponent(isDark ? 0.34 : 0.24).setFill()
            NSBezierPath(roundedRect: box, xRadius: 2.5, yRadius: 2.5).fill()
            orange.setFill()
            NSBezierPath(roundedRect: NSRect(x: box.minX, y: box.maxY - 1.5, width: box.width, height: 1.5),
                         xRadius: 0.75, yRadius: 0.75).fill()
        }
    }
}

/// One shared observer of left mouse-downs for every registered verse layer. It only *observes*:
/// every event is returned unchanged, so the first click of a double-click still selects the verse
/// through the row's Button exactly as before. On `clickCount == 2` it finds the registered layer
/// under the pointer and asks it for the word there.
@MainActor
final class WordClickMonitor {
    static let shared = WordClickMonitor()

    private let views = NSHashTable<WordHitNSView>.weakObjects()
    private var token: Any?

    var registeredCount: Int { views.allObjects.count }
    var isInstalled: Bool { token != nil }

    func register(_ view: WordHitNSView) {
        views.add(view)
        guard token == nil else { return }
        token = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated { _ = self?.process(event) }
            return event
        }
    }

    func unregister(_ view: WordHitNSView) {
        views.remove(view)
        if views.allObjects.isEmpty, let token {
            NSEvent.removeMonitor(token)
            self.token = nil
        }
    }

    /// Handles one mouse-down. Returns the word delivered to a layer, if any. The event itself is
    /// never consumed (the monitor closure always hands it back).
    @discardableResult
    func process(_ event: NSEvent) -> WordHit? {
        guard event.type == .leftMouseDown, event.clickCount == 2, let window = event.window else { return nil }
        for view in views.allObjects where view.window === window && !view.isHiddenOrHasHiddenAncestor {
            let point = view.convert(event.locationInWindow, from: nil)
            guard view.visibleRect.contains(point), let hit = view.word(at: point) else { continue }
            view.onWord?(hit)
            return hit
        }
        return nil
    }
}

// MARK: - SwiftUI glue

struct WordHitLayer: NSViewRepresentable {
    let text: String
    let fontSize: CGFloat
    let lineSpacing: CGFloat
    let highlight: NSRange?
    let onWord: (WordHit) -> Void
    var typeface: ReadingTypeface = .baskerville

    func makeNSView(context: Context) -> WordHitNSView {
        let view = WordHitNSView()
        apply(to: view)
        WordClickMonitor.shared.register(view)
        return view
    }

    func updateNSView(_ view: WordHitNSView, context: Context) { apply(to: view) }

    static func dismantleNSView(_ view: WordHitNSView, coordinator: ()) {
        WordClickMonitor.shared.unregister(view)
    }

    private func apply(to view: WordHitNSView) {
        view.text = text
        view.fontSize = fontSize
        view.lineSpacing = lineSpacing
        view.highlight = highlight
        view.typeface = typeface
        view.onWord = onWord
    }
}
