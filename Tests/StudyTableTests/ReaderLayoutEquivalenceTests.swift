import AppKit
import SwiftUI
import XCTest
@testable import StudyTable

/// The mandatory gate for double-click word study: word hit-testing uses a TextKit stack while
/// SwiftUI keeps drawing the verse `Text`. That is only sound if both wrap and position text the
/// same way. These tests render the real SwiftUI `Text` offscreen and compare it, ink for ink,
/// with TextKit's layout of the same string.
@MainActor
final class ReaderLayoutEquivalenceTests: XCTestCase {
    // MARK: Rendering helpers

    private final class SizeBox { var size: CGSize = .zero }

    private struct Ink {
        let width: Int, height: Int, scale: CGFloat
        var dark: [Float]   // 0...1 darkness, row-major, top-left origin
        func at(_ x: Int, _ y: Int) -> Float {
            (x < 0 || y < 0 || x >= width || y >= height) ? 0 : dark[y * width + x]
        }
    }

    private func ink(from rep: NSBitmapImageRep) -> Ink {
        var dark = [Float](repeating: 0, count: rep.pixelsWide * rep.pixelsHigh)
        for y in 0..<rep.pixelsHigh {
            for x in 0..<rep.pixelsWide {
                let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) ?? .white
                dark[y * rep.pixelsWide + x] = Float(1 - (c.redComponent + c.greenComponent + c.blueComponent) / 3)
            }
        }
        return Ink(width: rep.pixelsWide, height: rep.pixelsHigh, scale: 1, dark: dark)
    }

    /// SwiftUI's own drawing of a verse, in the row's real modifier order, proposed `width`.
    private func swiftUIRender(text: String, size: CGFloat, spacing: CGFloat, width: CGFloat, height: CGFloat,
                                typeface: ReadingTypeface = .baskerville)
        throws -> (ink: Ink, reported: CGSize, scale: CGFloat) {
        let box = SizeBox()
        let view = Text(text)
            .font(STFont.reading(size, typeface: typeface))
            .lineSpacing(spacing)
            .foregroundStyle(Color.black)
            .multilineTextAlignment(.leading)
            .background(GeometryReader { proxy in
                Color.clear.onAppear { box.size = proxy.size }.onChange(of: proxy.size) { _, new in box.size = new }
            })
            .frame(width: width, alignment: .topLeading)
            .frame(height: height, alignment: .topLeading)
            .background(Color.white)
            .environment(\.colorScheme, .light)
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        window.appearance = NSAppearance(named: .aqua)
        window.contentView = host
        window.setFrameOrigin(NSPoint(x: -20_000, y: -20_000))
        window.orderBack(nil)
        defer { window.orderOut(nil) }
        for _ in 0..<4 {
            host.layoutSubtreeIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.08))
        }
        let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
        host.cacheDisplay(in: host.bounds, to: rep)
        let scale = CGFloat(rep.pixelsWide) / width
        return (ink(from: rep), box.size, scale)
    }

    /// TextKit's drawing of the same string at the same pixel scale.
    private func textKitRender(_ layout: ReaderTextLayout, width: CGFloat, height: CGFloat, scale: CGFloat) -> Ink {
        let pw = Int((width * scale).rounded()), ph = Int((height * scale).rounded())
        let space = CGColorSpaceCreateDeviceRGB()
        let cg = CGContext(data: nil, width: pw, height: ph, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        cg.setFillColor(NSColor.white.cgColor)
        cg.fill(CGRect(x: 0, y: 0, width: pw, height: ph))
        cg.scaleBy(x: scale, y: scale)
        cg.translateBy(x: 0, y: height)
        cg.scaleBy(x: 1, y: -1)
        let ctx = NSGraphicsContext(cgContext: cg, flipped: true)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        let range = layout.layoutManager.glyphRange(for: layout.container)
        layout.layoutManager.drawGlyphs(forGlyphRange: range, at: .zero)
        NSGraphicsContext.restoreGraphicsState()
        let rep = NSBitmapImageRep(cgImage: cg.makeImage()!)
        return ink(from: rep)
    }

    /// Symmetric ink mismatch at the best whole-pixel offset (search +/-`search` px): the larger of
    /// "SwiftUI ink not found in TextKit" and "TextKit ink not found in SwiftUI", where a pixel is
    /// found when the other image has ink at that exact pixel (no neighbour tolerance).
    private func mismatch(_ a: Ink, _ b: Ink, search: Int = 0) -> (fraction: Double, dx: Int, dy: Int) {
        func count(_ i: Ink) -> Int { i.dark.reduce(0) { $0 + ($1 > 0.45 ? 1 : 0) } }
        let totalA = count(a), totalB = count(b)
        guard totalA > 0, totalB > 0 else { return (1, 0, 0) }
        var best = (Double.infinity, 0, 0)
        for dy in -search...search {
            for dx in -search...search {
                var missA = 0, missB = 0
                for y in 0..<a.height {
                    for x in 0..<a.width {
                        if a.dark[y * a.width + x] > 0.45, b.at(x + dx, y + dy) <= 0.30 { missA += 1 }
                        if b.dark[y * b.width + x] > 0.45, a.at(x - dx, y - dy) <= 0.30 { missB += 1 }
                    }
                }
                let f = max(Double(missA) / Double(totalA), Double(missB) / Double(totalB))
                if f < best.0 { best = (f, dx, dy) }
            }
        }
        return (best.0, best.1, best.2)
    }

    /// (rows containing ink) -> contiguous bands, in pixel rows.
    private func inkBands(_ ink: Ink) -> [ClosedRange<Int>] {
        var bands: [ClosedRange<Int>] = []
        var start: Int?
        for y in 0..<ink.height {
            var any = false
            for x in 0..<ink.width where ink.dark[y * ink.width + x] > 0.45 { any = true; break }
            if any { if start == nil { start = y } }
            else if let s = start { bands.append(s...(y - 1)); start = nil }
        }
        if let s = start { bands.append(s...(ink.height - 1)) }
        return bands
    }

    private func rightmostInk(_ ink: Ink, rows: ClosedRange<Int>) -> Int {
        var maxX = -1
        for y in rows { for x in stride(from: ink.width - 1, through: 0, by: -1) where ink.dark[y * ink.width + x] > 0.45 { maxX = max(maxX, x); break } }
        return maxX
    }

    // MARK: Verses

    private func verse(_ translation: String, _ book: String, _ chapter: Int, _ number: Int) throws -> String {
        let library = ScriptureLibrary()
        let verses = try XCTUnwrap(library.chapter(translation: translation, bookCode: book, chapter: chapter))
        return try XCTUnwrap(verses.first { $0.number == number }).text
    }

    private var samples: [(String, String, Int, Int)] {
        [("BSB", "JHN", 3, 16), ("KJV", "JHN", 3, 16), ("BSB", "GEN", 1, 1), ("KJV", "PSA", 23, 1),
         ("BSB", "ROM", 8, 28), ("WEB", "PSA", 119, 105), ("BSB", "PSA", 119, 176), ("WEB", "REV", 21, 4)]
    }

    // MARK: Tests

    func testTextKitWrapsAndPositionsLikeSwiftUIText() throws {
        var checked = 0
        var worst = 0.0
        var report: [String] = []
        // Measured 2026-09-24: all 72 combinations of 12 verses x 6 configurations were pixel-
        // identical at offset (0,0) at 2x. This shipped subset keeps the suite fast; widen the
        // lists locally when changing fonts or line-spacing handling.
        let configs: [(size: CGFloat, spacing: CGFloat, width: CGFloat)] = [
            (20, 8, 300), (16, 4, 380), (26, 12, 420), (18, 0, 250)
        ]
        for (translation, book, chapter, number) in samples {
            guard let text = try? verse(translation, book, chapter, number) else { continue }
            for config in configs {
                let layout = ReaderTextLayout(text: text, fontSize: config.size, lineSpacing: config.spacing, width: config.width)
                let height = ceil(layout.usedRect.height) + 30
                let render = try swiftUIRender(text: text, size: config.size, spacing: config.spacing, width: config.width, height: height)
                // Text reports the width it actually used (its frame, which is the width the AppKit
                // layer behind it is given); hit-testing lays TextKit out at exactly that width.
                let reported = render.reported
                let hitLayout = ReaderTextLayout(text: text, fontSize: config.size, lineSpacing: config.spacing,
                                                 width: max(reported.width, 1))
                let tk = textKitRender(hitLayout, width: config.width, height: height, scale: render.scale)
                let bands = inkBands(render.ink), tkBands = inkBands(tk)
                let result = mismatch(render.ink, tk)
                worst = max(worst, result.fraction)
                XCTAssertEqual([result.dx, result.dy], [0, 0], "\(translation) \(book) \(chapter):\(number) is offset from SwiftUI's drawing")
                report.append("\(translation) \(book) \(chapter):\(number) size \(config.size) ls \(config.spacing) w \(config.width): lines TK \(hitLayout.lineCount) ink bands SwiftUI \(bands.count) TK \(tkBands.count) scale \(render.scale) reportedW \(reported.width) H \(reported.height) TKused \(hitLayout.usedRect.size) mismatch \(String(format: "%.3f", result.fraction)) off (\(result.dx),\(result.dy))")
                checked += 1
            }
        }
        XCTAssertGreaterThanOrEqual(checked, 30)
        XCTAssertLessThan(worst, 0.005, "TextKit ink diverges from SwiftUI Text ink")
    }

    /// 0.10.2: Scripture's typeface is now a reader choice (`AppState.scriptureTypeface`), not
    /// always Baskerville. This is the same gate as above, run for every typeface the Scripture
    /// picker can actually offer (`.availableForScripture` — NOT the full `.available` set: this
    /// exact test is what found Palatino's real TextKit line-height divergence and got it excluded
    /// from Scripture; re-running it against the full set is how a future change would re-earn
    /// Palatino's spot, not a judgment call). Proves `ReadingTypeface`'s shared resolver keeps
    /// `STFont.reading` (what SwiftUI draws) and `STFont.readingNSFont` (what the hit-test layer
    /// measures) in lock-step for each offered typeface individually.
    func testTextKitWrapsAndPositionsLikeSwiftUITextForEveryChosenTypeface() throws {
        let text = try verse("BSB", "ROM", 8, 28)
        let config: (size: CGFloat, spacing: CGFloat, width: CGFloat) = (20, 8, 340)
        var worst = 0.0
        var checked = 0
        for typeface in ReadingTypeface.availableForScripture {
            let layout = ReaderTextLayout(text: text, fontSize: config.size, lineSpacing: config.spacing, width: config.width, typeface: typeface)
            let height = ceil(layout.usedRect.height) + 30
            let render = try swiftUIRender(text: text, size: config.size, spacing: config.spacing, width: config.width, height: height, typeface: typeface)
            let reported = render.reported
            let hitLayout = ReaderTextLayout(text: text, fontSize: config.size, lineSpacing: config.spacing,
                                             width: max(reported.width, 1), typeface: typeface)
            let tk = textKitRender(hitLayout, width: config.width, height: height, scale: render.scale)
            let result = mismatch(render.ink, tk)
            worst = max(worst, result.fraction)
            XCTAssertEqual([result.dx, result.dy], [0, 0], "\(typeface.displayName) is offset from SwiftUI's drawing")
            checked += 1
        }
        XCTAssertEqual(checked, ReadingTypeface.availableForScripture.count)
        XCTAssertLessThan(worst, 0.005, "TextKit ink diverges from SwiftUI Text ink for at least one typeface offered for Scripture")
    }
}
