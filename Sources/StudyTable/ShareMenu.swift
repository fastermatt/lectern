import AppKit
import SwiftUI
import UniformTypeIdentifiers

// ShareMenu — S2c (0.10 wave B). Self-contained SwiftUI: not wired into any pane yet (Claude
// drops it next to verse/note/collection UI after all three wave-B workstreams land). Every path
// — Copy as Text, Copy as Markdown, Share…, Export PDF… — composes through `ExportComposer` and
// then shows `SharePreviewSheet` ("What will be shared": items, translation handling, the
// `ExportReport`) before anything actually leaves the app, per PASTOR-QA-0.10 §Sharing. When the
// selected translation is a capped one (ESV) requiring per-export opt-in, the sheet itself carries
// the opt-in toggle and recomposes live, so the one gate covers both "what would be shared" and
// "does the user actually want the capped text this time."
//
// Side effects (clipboard write, `NSSharingServicePicker`, save panel) are injectable so this
// view stays renderable/testable offscreen without touching the real system pasteboard or
// popping a real panel during a test run; the default arguments are what the shipping app uses.

struct PendingShare: Identifiable {
    enum Action { case copyText, copyMarkdown, share, exportPDF }
    let id = UUID()
    var action: Action
    var format: ExportFormat
}

struct ShareMenu: View {
    let items: [ExportItem]
    let collectionHeading: String?
    var options: ExportOptions
    let verses: VerseSource

    /// Injected side effects — defaulted to the real ones; tests/renders override them.
    var copyToPasteboard: (String) -> Void = { text in
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
    var presentSharingPicker: (String) -> Void = { text in
        let picker = NSSharingServicePicker(items: [text])
        if let window = NSApp.keyWindow, let view = window.contentView {
            picker.show(relativeTo: .zero, of: view, preferredEdge: .minY)
        }
    }
    var savePDF: (Data, String) -> Void = { data, suggestedName in
        let panel = NSSavePanel()
        panel.nameFieldStringValue = suggestedName
        panel.allowedContentTypes = [.pdf]
        if panel.runModal() == .OK, let url = panel.url {
            try? data.write(to: url)
        }
    }

    @State private var pending: PendingShare?

    var body: some View {
        Menu {
            Button("Copy as Text") { pending = PendingShare(action: .copyText, format: .plainText) }
            Button("Copy as Markdown") { pending = PendingShare(action: .copyMarkdown, format: .markdown) }
            Divider()
            Button("Share…") { pending = PendingShare(action: .share, format: .plainText) }
            Button("Export PDF…") { pending = PendingShare(action: .exportPDF, format: .pdf) }
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
        }
        .accessibilityLabel("Share")
        .accessibilityHint("Copy, share, or export this passage")
        .sheet(item: $pending) { pending in
            SharePreviewSheet(items: items, collectionHeading: collectionHeading, format: pending.format,
                               verses: verses, action: pending.action, options: options,
                               onConfirm: { result in confirm(pending.action, result: result) },
                               onCancel: { self.pending = nil })
        }
    }

    private func confirm(_ action: PendingShare.Action, result: ExportResult) {
        defer { self.pending = nil }
        switch action {
        case .copyText, .copyMarkdown:
            guard let text = result.text else { return }
            copyToPasteboard(text)
        case .share:
            guard let text = result.text else { return }
            presentSharingPicker(text)
        case .exportPDF:
            guard let data = result.data else { return }
            let name = (options.title?.isEmpty == false ? options.title! : "Throughline Export") + ".pdf"
            savePDF(data, name)
        }
    }
}

/// "What will be shared" — required before any share/export leaves the app (PASTOR-QA-0.10
/// §Sharing). Lists what is being shared, how the selected translation is handled (with a live
/// opt-in toggle when the translation is a capped one), and the composer's `ExportReport`
/// (what — if anything — was omitted, and why) verbatim.
struct SharePreviewSheet: View {
    let items: [ExportItem]
    let collectionHeading: String?
    let format: ExportFormat
    let verses: VerseSource
    let action: PendingShare.Action
    @State var options: ExportOptions
    let onConfirm: (ExportResult) -> Void
    let onCancel: () -> Void

    private var result: ExportResult { ExportComposer.compose(items: items, format: format, options: options, verses: verses) }

    private var itemLabels: [String] {
        items.map { item in
            switch item {
            case .note(let note): "Note · \(note.referenceLabel)"
            case .saved(let saved): "Saved passage · \(saved.anchor.displayString)"
            case .collection(let collection, let members): "Collection “\(collection.name)” · \(members.count) passage\(members.count == 1 ? "" : "s")"
            case .selection(let anchor): "Selection · \(anchor.displayString)"
            }
        }
    }

    private var actionTitle: String {
        switch action {
        case .copyText: "Copy as Text"
        case .copyMarkdown: "Copy as Markdown"
        case .share: "Share"
        case .exportPDF: "Export PDF"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    section("What will be shared") {
                        ForEach(Array(itemLabels.enumerated()), id: \.offset) { _, label in
                            Text(label).font(.system(size: 12, design: .rounded)).foregroundStyle(STColor.ink)
                        }
                        if let collectionHeading { Text("Collection: \(collectionHeading)").legend() }
                    }
                    section("Translation") {
                        Text("\(options.translation.name) (\(options.translation.id))")
                            .font(.system(size: 12, weight: .medium, design: .rounded))
                        Text(translationHandlingDescription)
                            .font(.system(size: 11, design: .rounded)).foregroundStyle(STColor.secondary)
                        if case .cappedText(_, _, _, let requiresOptIn, _) = options.translation.exportPolicy, requiresOptIn {
                            Toggle(isOn: $options.cappedTranslationOptIn) {
                                Text("Include \(options.translation.name) text (subject to publisher limits)")
                                    .font(.system(size: 11.5, design: .rounded))
                            }
                            .toggleStyle(.checkbox)
                            .accessibilityHint("Turns on capped \(options.translation.name) Scripture text for this export only")
                        }
                    }
                    if !result.report.isEmpty {
                        section("Export notes") {
                            ForEach(result.report.lines) { line in
                                DeskDisclaimer(text: line.message, isWarning: line.kind == .omitted)
                            }
                        }
                    }
                }
                .padding(16)
            }
            footer
        }
        .frame(width: 420, height: 480)
        .background(STColor.paper)
        .accessibilityElement(children: .contain)
    }

    private var translationHandlingDescription: String {
        switch options.translation.exportPolicy {
        case .fullText:
            "Full Scripture text is included, with attribution."
        case .cappedText(let maxVerses, _, _, let requiresOptIn, _):
            if !requiresOptIn { "Scripture text is included." }
            else if options.cappedTranslationOptIn { "Scripture text is included, capped at \(maxVerses) verses per export, with the publisher's required notice." }
            else { "Scripture text is not included unless you opt in below — this translation requires opting in per export." }
        case .referencesOnly:
            "Only the reference is included — no Scripture text (references only for this translation)."
        }
    }

    private var header: some View {
        HStack {
            Text("What Will Be Shared").font(STFont.title(15))
            Spacer()
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(STColor.tileTop)
        .overlay(alignment: .bottom) { Rectangle().fill(STColor.hairline).frame(height: 0.5) }
    }

    private var footer: some View {
        HStack {
            Button("Cancel", role: .cancel, action: onCancel)
                .keyboardShortcut(.cancelAction)
            Spacer()
            Button(actionTitle) { onConfirm(result) }
                .keyboardShortcut(.defaultAction)
        }
        .padding(16)
        .overlay(alignment: .top) { Rectangle().fill(STColor.hairline).frame(height: 0.5) }
    }

    @ViewBuilder
    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased()).legend()
            VStack(alignment: .leading, spacing: 4) { content() }
        }
    }
}
