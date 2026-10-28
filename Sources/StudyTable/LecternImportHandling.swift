import SwiftUI
import UniformTypeIdentifiers

// Claude — post-wave-B integration (0.10). Wires `LecternStudyImporter` (S2c, pure logic + tests
// only, no UI) to the app: opening a `.lecternstudy` file (double-click, "Open With…", or a drag
// onto the window) never imports silently — it always shows what would happen first, per
// PASTOR-QA-0.10 §Sharing's "preview before anything leaves/enters the app" rule extended to
// imports. Nothing here re-implements parsing, dedup, or classification; it only presents
// `LecternStudyImportPreview` and calls `LecternStudyImporter.apply` on confirmation.

let lecternStudyUTType = "com.fastermatt.studytable.lecternstudy"

/// One pending import, from either `.onOpenURL` or a drag-and-drop — held until the user
/// confirms or cancels in `LecternImportSheet`.
struct PendingLecternImport: Identifiable {
    let id = UUID()
    var sourceDescription: String
    var outcome: Outcome

    enum Outcome {
        case preview(LecternStudyImportPreview)
        case failed(String)
    }

    @MainActor
    init(url: URL, into store: StudyStore) {
        sourceDescription = url.lastPathComponent
        do {
            let data = try Data(contentsOf: url)
            outcome = .preview(try LecternStudyImporter.preview(data: data, existing: store))
        } catch let error as LecternStudyError {
            // `LecternStudyError` already carries a reader-facing description (`LocalizedError`) —
            // every case covers a file this importer treats as untrusted input, so a malformed or
            // hostile file fails safely with that message, never a crash or a raw decoding error.
            outcome = .failed(error.errorDescription ?? "This file couldn't be read.")
        } catch {
            outcome = .failed("This file couldn't be read.")
        }
    }
}

/// The confirmation sheet: "what will be imported" (per §Sharing's export-preview precedent,
/// applied symmetrically to import), then Import or Cancel — never applied without this.
struct LecternImportSheet: View {
    let pending: PendingLecternImport
    let onImport: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Import Study File").font(.title3.bold())
            Text(pending.sourceDescription).font(.callout).foregroundStyle(.secondary)

            switch pending.outcome {
            case .failed(let message):
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Could not import: \(message)")
            case .preview(let preview):
                VStack(alignment: .leading, spacing: 8) {
                    if !preview.title.isEmpty {
                        Text(preview.title).font(.headline)
                    }
                    if preview.newSavedCount > 0 || preview.duplicateSavedCount > 0 {
                        summaryLine(systemImage: "bookmark", newCount: preview.newSavedCount,
                                    dupCount: preview.duplicateSavedCount, noun: "saved passage")
                    }
                    if preview.newNoteCount > 0 || preview.duplicateNoteCount > 0 {
                        summaryLine(systemImage: "note.text", newCount: preview.newNoteCount,
                                    dupCount: preview.duplicateNoteCount, noun: "note")
                    }
                    if preview.newClipCount > 0 {
                        Text("\(preview.newClipCount) clip\(preview.newClipCount == 1 ? "" : "s")")
                            .font(.callout)
                    }
                    if preview.totalItems == 0 {
                        Text("This file has nothing to import.").foregroundStyle(.secondary)
                    }
                    ForEach(preview.conflicts, id: \.self) { note in
                        Label(note, systemImage: "info.circle").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            }

            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: onCancel).keyboardShortcut(.cancelAction)
                if case .preview(let preview) = pending.outcome, preview.totalItems > 0 {
                    Button("Import") { onImport() }
                        .keyboardShortcut(.defaultAction)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(20)
        .frame(width: 380)
    }

    private func summaryLine(systemImage: String, newCount: Int, dupCount: Int, noun: String) -> some View {
        var parts: [String] = []
        if newCount > 0 { parts.append("\(newCount) new \(noun)\(newCount == 1 ? "" : "s")") }
        if dupCount > 0 { parts.append("\(dupCount) already in My Study") }
        return Label(parts.joined(separator: " · "), systemImage: systemImage).font(.callout)
    }
}

/// Presents `LecternImportSheet` for a URL the app was asked to open (double-click, "Open
/// With…", or a drop onto the window) and applies the import only on explicit confirmation.
struct LecternImportPresenter: ViewModifier {
    @EnvironmentObject private var state: AppState
    @State private var pending: PendingLecternImport?

    func body(content: Content) -> some View {
        content
            .onOpenURL { url in handle(url) }
            .dropDestination(for: URL.self) { urls, _ in
                guard let url = urls.first(where: { $0.pathExtension.lowercased() == "lecternstudy" }) else { return false }
                handle(url)
                return true
            }
            .sheet(item: $pending) { item in
                LecternImportSheet(pending: item) {
                    if case .preview(let preview) = item.outcome {
                        let result = LecternStudyImporter.apply(preview, into: state.notes)
                        Announcer.post(importAnnouncement(preview: preview, result: result))
                    }
                    pending = nil
                } onCancel: { pending = nil }
            }
    }

    @MainActor private func handle(_ url: URL) {
        pending = PendingLecternImport(url: url, into: state.notes)
    }

    private func importAnnouncement(preview: LecternStudyImportPreview, result: LecternStudyApplyResult) -> String {
        let title = preview.title.isEmpty ? "study file" : preview.title
        return "Imported \(title): \(result.addedSavedIDs.count) saved passages, \(result.addedNoteIDs.count) notes."
    }
}

extension View {
    /// Handles `.lecternstudy` files opened via Finder/"Open With…" or dropped onto this view,
    /// always through the confirm-first import sheet.
    func handlesLecternStudyImports() -> some View { modifier(LecternImportPresenter()) }
}
