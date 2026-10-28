import Foundation

// Plain-text and Markdown rendering for `ExportComposer`. Both share one layout — heading,
// references, verses, notes, citations, licence footer (PASTOR-QA-0.10 §"ExportComposer") — and
// differ only in punctuation, so a change to one's shape is easy to keep in sync with the other
// (and with `ExportPDFRenderer`, which shares the same `ExportBlock`s).

func citationLine(for clip: Clip, markdown: Bool) -> String {
    var parts: [String] = []
    if !clip.citation.author.isEmpty { parts.append(clip.citation.author) }
    if !clip.citation.work.isEmpty { parts.append(markdown ? "*\(clip.citation.work)*" : clip.citation.work) }
    if let era = clip.citation.era, !era.isEmpty { parts.append(era) }
    if let licence = clip.citation.licence, !licence.isEmpty { parts.append(licence) }
    return parts.joined(separator: " · ")
}

func renderPlainText(blocks: [ExportBlock], collectionHeading: String?, options: ExportOptions,
                      policy: TranslationExportPolicy, report: ExportReport) -> String {
    var lines: [String] = []
    if let title = options.title { lines.append(title); lines.append(String(repeating: "=", count: title.count)) }
    if let collectionHeading { lines.append(collectionHeading); lines.append("") }

    for (index, block) in blocks.enumerated() {
        if index > 0 { lines.append("") }
        lines.append(block.referenceLabel)
        if let title = block.noteTitle, !title.isEmpty { lines.append(title) }
        var marks: [String] = []
        if let color = block.highlight { marks.append("Highlight: \(color.rawValue.capitalized)") }
        if block.isMemory { marks.append("Memory verse") }
        if !block.tags.isEmpty { marks.append("Tags: \(block.tags.joined(separator: ", "))") }
        if !marks.isEmpty { lines.append(marks.joined(separator: " · ")) }

        for group in block.verseGroups where !group.lines.isEmpty {
            for line in group.lines where line.number > 0 {
                lines.append("\(line.number). \(line.text)")
            }
        }

        if let body = block.noteBody, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append(body)
        }
        for section in block.noteSections where !section.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("\(section.key.capitalized): \(section.text)")
        }
        for clip in block.clips {
            lines.append("“\(clip.excerpt)”")
            let citation = citationLine(for: clip, markdown: false)
            if !citation.isEmpty { lines.append("— \(citation)") }
        }
    }

    if !report.isEmpty {
        lines.append("")
        lines.append("—")
        for line in report.lines { lines.append(line.message) }
    }
    return lines.joined(separator: "\n")
}

func renderMarkdown(blocks: [ExportBlock], collectionHeading: String?, options: ExportOptions,
                     policy: TranslationExportPolicy, report: ExportReport) -> String {
    var lines: [String] = []
    if let title = options.title { lines.append("# \(title)") }
    if let collectionHeading { lines.append("## \(collectionHeading)") }

    for block in blocks {
        lines.append("")
        lines.append("### \(block.referenceLabel)")
        if let title = block.noteTitle, !title.isEmpty { lines.append("**\(title)**") }
        var marks: [String] = []
        if let color = block.highlight { marks.append("Highlight: \(color.rawValue.capitalized)") }
        if block.isMemory { marks.append("Memory verse") }
        if !block.tags.isEmpty { marks.append("Tags: " + block.tags.map { "`\($0)`" }.joined(separator: ", ")) }
        if !marks.isEmpty { lines.append("_\(marks.joined(separator: " · "))_") }

        for group in block.verseGroups where !group.lines.isEmpty {
            lines.append("")
            for line in group.lines where line.number > 0 {
                lines.append("> **\(line.number)** \(line.text)")
            }
        }

        if let body = block.noteBody, !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append(body)
        }
        for section in block.noteSections where !section.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            lines.append("")
            lines.append("**\(section.key.capitalized).** \(section.text)")
        }
        for clip in block.clips {
            lines.append("")
            lines.append("> \(clip.excerpt)")
            let citation = citationLine(for: clip, markdown: true)
            if !citation.isEmpty { lines.append(">\n> — \(citation)") }
        }
    }

    if !report.isEmpty {
        lines.append("")
        lines.append("---")
        for line in report.lines { lines.append("- \(line.message)") }
    }
    return lines.joined(separator: "\n")
}
