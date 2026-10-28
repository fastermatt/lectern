import AppKit

// MARK: - Word tokenizing

/// One English (or other-translation) word in a verse, with the identity the double-click study
/// path needs: where it sits (UTF-16 range in the verse string), which occurrence of that word it
/// is, and the comparison key the original-language alignment uses.
struct WordToken: Equatable, Sendable {
    /// The word as displayed, with surrounding punctuation removed ("God's" stays "God's").
    let text: String
    let range: NSRange
    /// Lowercased, straight apostrophes, English possessive removed ("God's" -> "god").
    let key: String
    /// Position among *all* words in the verse (0-based).
    let index: Int
    /// 0-based occurrence among the verse's words that share this `key`.
    let occurrence: Int
}

enum WordTokenizer {
    private static let apostrophes: Set<Character> = ["'", "\u{2019}", "\u{02BC}", "\u{2018}"]

    private static func isWordCharacter(_ c: Character) -> Bool {
        c.isLetter || c.isNumber || c.unicodeScalars.contains { $0.properties.generalCategory == .nonspacingMark }
    }

    /// Words are runs of letters/digits. An apostrophe joins two letters ("God's", "don't");
    /// a hyphen or dash does not, so "God-fearing" is two words, each studied on its own.
    static func tokens(in text: String) -> [WordToken] {
        let chars = Array(text)
        var offsets: [Int] = []          // UTF-16 offset of each Character
        offsets.reserveCapacity(chars.count + 1)
        var utf16 = 0
        for c in chars { offsets.append(utf16); utf16 += String(c).utf16.count }
        offsets.append(utf16)

        var raw: [(text: String, range: NSRange)] = []
        var runStart: Int?
        func close(at end: Int) {
            guard let s = runStart else { return }
            raw.append((String(chars[s..<end]), NSRange(location: offsets[s], length: offsets[end] - offsets[s])))
            runStart = nil
        }
        for i in chars.indices {
            let c = chars[i]
            if isWordCharacter(c) {
                if runStart == nil { runStart = i }
            } else if apostrophes.contains(c), runStart != nil, i > 0, i + 1 < chars.count,
                      chars[i - 1].isLetter, chars[i + 1].isLetter {
                continue // an apostrophe between two letters stays inside the word
            } else {
                close(at: i)
            }
        }
        close(at: chars.count)

        var seen: [String: Int] = [:]
        return raw.enumerated().map { index, item in
            let key = normalizedKey(item.text)
            let occurrence = seen[key, default: 0]
            seen[key] = occurrence + 1
            return WordToken(text: item.text, range: item.range, key: key, index: index, occurrence: occurrence)
        }
    }

    /// Lowercase, straight apostrophes, and the English possessive stripped so "God's" finds
    /// "God". Only a trailing `'s` is removed; "it's" -> "it", "don't" is untouched.
    static func normalizedKey(_ word: String) -> String {
        var s = word.lowercased()
        for a in apostrophes { s = s.replacingOccurrences(of: String(a), with: "'") }
        if s.hasSuffix("'s"), s.count > 3 { s.removeLast(2) }
        return s
    }
}

// MARK: - TextKit layout that mirrors the reader's SwiftUI Text

extension STFont {
    /// The AppKit face behind `STFont.reading` (regular weight only — Scripture rows never use
    /// bold) — resolved through the exact same `ReadingTypeface` the SwiftUI side used, so the two
    /// can never disagree about which font a word actually sits under.
    static func readingNSFont(_ size: CGFloat, typeface: ReadingTypeface = .baskerville) -> NSFont {
        typeface.nsFont(size: size)
    }
}

/// What a double-click on verse text resolved to.
struct WordHit: Equatable, Sendable {
    let word: String
    let range: NSRange
    /// 0-based occurrence among the verse's words with the same normalized key.
    let occurrence: Int
    let tokenIndex: Int
    let key: String
}

/// A TextKit stack configured to lay a verse out the way `VerseRow`'s SwiftUI `Text` does (same
/// font, size, line spacing, left alignment, no padding). It draws nothing itself: SwiftUI keeps
/// drawing the text. This only answers "where is each word?" for hit-testing and highlighting.
/// `ReaderLayoutEquivalenceTests` proves the two layouts agree.
final class ReaderTextLayout {
    let text: String
    let width: CGFloat
    let storage: NSTextStorage
    let layoutManager = NSLayoutManager()
    let container: NSTextContainer
    let tokens: [WordToken]
    let lineSpacing: CGFloat

    init(text: String, fontSize: CGFloat, lineSpacing: CGFloat, width: CGFloat, typeface: ReadingTypeface = .baskerville) {
        self.text = text
        self.width = width
        self.lineSpacing = lineSpacing
        let style = NSMutableParagraphStyle()
        style.lineSpacing = lineSpacing
        style.lineBreakMode = .byWordWrapping
        style.alignment = .left
        style.hyphenationFactor = 0
        storage = NSTextStorage(string: text, attributes: [
            .font: STFont.readingNSFont(fontSize, typeface: typeface),
            .paragraphStyle: style,
            .foregroundColor: NSColor.black
        ])
        container = NSTextContainer(size: NSSize(width: max(width, 1), height: .greatestFiniteMagnitude))
        container.lineFragmentPadding = 0
        container.lineBreakMode = .byWordWrapping
        container.widthTracksTextView = false
        container.heightTracksTextView = false
        layoutManager.addTextContainer(container)
        storage.addLayoutManager(layoutManager)
        layoutManager.ensureLayout(for: container)
        tokens = WordTokenizer.tokens(in: text)
    }

    /// Glyph extents of the laid-out text, in the text's own top-left-origin space.
    var usedRect: CGRect { layoutManager.usedRect(for: container) }

    /// Number of laid-out lines (line fragments).
    var lineCount: Int {
        var count = 0
        let glyphs = layoutManager.numberOfGlyphs
        guard glyphs > 0 else { return 0 }
        var index = 0
        while index < glyphs {
            var range = NSRange()
            layoutManager.lineFragmentRect(forGlyphAt: index, effectiveRange: &range)
            count += 1
            index = NSMaxRange(range)
        }
        return count
    }

    /// One rect per line the token occupies (almost always one), in text space.
    func rects(for token: WordToken) -> [CGRect] {
        let glyphRange = layoutManager.glyphRange(forCharacterRange: token.range, actualCharacterRange: nil)
        var result: [CGRect] = []
        layoutManager.enumerateEnclosingRects(forGlyphRange: glyphRange,
            withinSelectedGlyphRange: NSRange(location: NSNotFound, length: 0), in: container) { rect, _ in
            result.append(rect)
        }
        return result
    }

    /// The word under `point` (text space, top-left origin). A point within `slop` points of a
    /// word's box counts as on that word, so a click on the comma after "world," or the hair of
    /// space beside a word still lands on it; a click in the wider gap between words, in the
    /// margin, or below the last line is not a word. Between two candidates the nearer wins.
    func hit(at point: CGPoint, slop: CGFloat = 2.5) -> WordHit? {
        guard !tokens.isEmpty else { return nil }
        let vertical = lineSpacing / 2
        var best: (token: WordToken, distance: CGFloat)?
        for token in tokens {
            for rect in rects(for: token) {
                let inflated = rect.insetBy(dx: -slop, dy: -vertical)
                guard inflated.contains(point) else { continue }
                let dx = point.x < rect.minX ? rect.minX - point.x : (point.x > rect.maxX ? point.x - rect.maxX : 0)
                if best == nil || dx < best!.distance { best = (token, dx) }
            }
        }
        guard let token = best?.token else { return nil }
        return WordHit(word: token.text, range: token.range, occurrence: token.occurrence,
                       tokenIndex: token.index, key: token.key)
    }
}

/// Pure hit-test: which word of `text`, laid out at `fontSize`/`lineSpacing` in `width` points,
/// is at `point` (top-left origin, the verse text's own coordinate space)? `nil` for margins,
/// gaps between words, and below the last line.
func wordHit(text: String, fontSize: CGFloat, lineSpacing: CGFloat, width: CGFloat, point: CGPoint,
             typeface: ReadingTypeface = .baskerville) -> WordHit? {
    ReaderTextLayout(text: text, fontSize: fontSize, lineSpacing: lineSpacing, width: width, typeface: typeface).hit(at: point)
}
