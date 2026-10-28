import AppKit
import CoreText

// PDF rendering for `ExportComposer`, sharing the same `ExportBlock`s (and therefore the same
// inclusion/omission decisions) as the plain-text/Markdown renderers in `ExportRendering.swift`.
// Built directly on Core Graphics' PDF context (`CGContext(consumer:mediaBox:)`) rather than
// `NSPrintOperation`/a print panel, so it is a pure, headless, testable function: `Data` in,
// `Data` out, no print dialog, no user interaction, safe to call from a unit test.

@MainActor
enum ExportPDFRenderer {
    private static let pageSize = CGSize(width: 612, height: 792)   // US Letter, points
    private static let margin: CGFloat = 56

    static func render(blocks: [ExportBlock], collectionHeading: String?, options: ExportOptions,
                        policy: TranslationExportPolicy, report: ExportReport) -> Data {
        let text = document(blocks: blocks, collectionHeading: collectionHeading, options: options, report: report)
        return paginate(text)
    }

    // MARK: Attributed document

    private static let headingFont = NSFont.systemFont(ofSize: 20, weight: .semibold)
    private static let referenceFont = NSFont.systemFont(ofSize: 13, weight: .semibold)
    private static let bodyFont = NSFont(name: "Georgia", size: 12) ?? NSFont.systemFont(ofSize: 12)
    private static let verseFont = NSFont(name: "Georgia", size: 12) ?? NSFont.systemFont(ofSize: 12)
    private static let noteFont = NSFont.systemFont(ofSize: 11)
    private static let metaFont = NSFont.systemFont(ofSize: 10, weight: .medium)
    private static let footerFont = NSFont.systemFont(ofSize: 9)
    private static let ink = NSColor.labelColor
    private static let secondary = NSColor.secondaryLabelColor

    private static func document(blocks: [ExportBlock], collectionHeading: String?, options: ExportOptions,
                                  report: ExportReport) -> NSAttributedString {
        let result = NSMutableAttributedString()
        func append(_ string: String, _ font: NSFont, _ color: NSColor = ink, spacingAfter: CGFloat = 6, italic: Bool = false) {
            guard !string.isEmpty else { return }
            let paragraph = NSMutableParagraphStyle()
            paragraph.paragraphSpacing = spacingAfter
            var attrs: [NSAttributedString.Key: Any] = [.font: font, .foregroundColor: color, .paragraphStyle: paragraph]
            if italic, let italicFont = NSFontManager.shared.convert(font, toHaveTrait: .italicFontMask) as NSFont? {
                attrs[.font] = italicFont
            }
            result.append(NSAttributedString(string: string + "\n", attributes: attrs))
        }

        if let title = options.title { append(title, headingFont, ink, spacingAfter: 14) }
        if let collectionHeading { append(collectionHeading, referenceFont, secondary, spacingAfter: 10) }

        for block in blocks {
            append(block.referenceLabel, referenceFont, ink, spacingAfter: 4)
            if let title = block.noteTitle, !title.isEmpty { append(title, metaFont, ink, spacingAfter: 2) }
            var marks: [String] = []
            if let color = block.highlight { marks.append("Highlight: \(color.rawValue.capitalized)") }
            if block.isMemory { marks.append("Memory verse") }
            if !block.tags.isEmpty { marks.append("Tags: \(block.tags.joined(separator: ", "))") }
            if !marks.isEmpty { append(marks.joined(separator: "  ·  "), metaFont, secondary, spacingAfter: 6) }

            for group in block.verseGroups where !group.lines.isEmpty {
                let verseText = group.lines.filter { $0.number > 0 }.map { "\($0.number) \($0.text)" }.joined(separator: "  ")
                append(verseText, verseFont, ink, spacingAfter: 8)
            }
            if let body = block.noteBody, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                append(body, noteFont, ink, spacingAfter: 6)
            }
            for section in block.noteSections where !section.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                append("\(section.key.capitalized): \(section.text)", noteFont, ink, spacingAfter: 6)
            }
            for clip in block.clips {
                append("“\(clip.excerpt)”", noteFont, ink, spacingAfter: 2, italic: true)
                let citation = citationLine(for: clip, markdown: false)
                if !citation.isEmpty { append("— \(citation)", footerFont, secondary, spacingAfter: 8) }
            }
            append("", noteFont, spacingAfter: 6)   // block separator
        }

        if !report.isEmpty {
            append("Licence & export notes", metaFont, ink, spacingAfter: 4)
            for line in report.lines { append("• \(line.message)", footerFont, secondary, spacingAfter: 4) }
        }
        return result
    }

    // MARK: Pagination into a PDF via Core Text + a Core Graphics PDF context

    private static func paginate(_ text: NSAttributedString) -> Data {
        let data = NSMutableData()
        guard let consumer = CGDataConsumer(data: data as CFMutableData) else { return Data() }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return Data() }

        let framesetter = CTFramesetterCreateWithAttributedString(text)
        let textRect = CGRect(x: margin, y: margin, width: pageSize.width - margin * 2, height: pageSize.height - margin * 2)
        let path = CGPath(rect: textRect, transform: nil)

        var start = 0
        let length = text.length
        var guardPages = 0
        repeat {
            let frame = CTFramesetterCreateFrame(framesetter, CFRange(location: start, length: 0), path, nil)
            context.beginPDFPage(nil)
            // Core Text draws in a flipped coordinate space relative to AppKit's default; PDF
            // context origin is bottom-left, matching Core Text's own expectation directly.
            CTFrameDraw(frame, context)
            context.endPDFPage()
            let visible = CTFrameGetVisibleStringRange(frame)
            start = visible.location + max(visible.length, 1)
            guardPages += 1
        } while start < length && guardPages < 500   // hard stop against a pathological/hostile input looping forever

        context.closePDF()
        return data as Data
    }
}
