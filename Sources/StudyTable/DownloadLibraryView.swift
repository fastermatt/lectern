import SwiftUI

/// Settings is the single home for downloading and removing optional offline editions.
struct DownloadLibraryView: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow
    @StateObject private var manager: BibleDownloadManager
    @State private var removing: BibleDownload?

    init(manager: BibleDownloadManager? = nil) {
        _manager = StateObject(wrappedValue: manager ?? BibleDownloadManager())
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("OFFLINE LIBRARY").font(.system(size: 11, weight: .semibold, design: .monospaced))
            Text("BSB, KJV and WEB are already included. Add public-domain editions below; downloads are optional and require no account.")
                .font(.system(size: 12)).foregroundStyle(STColor.secondary)
            ForEach(BibleDownload.catalog) { edition in
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        VStack(alignment: .leading, spacing: 3) {
                            Text(edition.name).font(.system(size: 13, weight: .medium))
                            Text("\(edition.language) · \(edition.license)").font(.system(size: 11)).foregroundStyle(STColor.secondary)
                        }
                        Spacer()
                        if manager.activeID == edition.id {
                            Button("Cancel") { manager.cancel() }
                        } else if state.library.translation(id: edition.id)?.isOffline == true {
                            Label("Installed", systemImage: "checkmark.circle").font(.system(size: 11))
                            Button("Read") { state.translationID = edition.id; openWindow(id: "workspace") }
                            if BibleInstaller.isManaged(edition, root: state.library.userPackDirectory) {
                                Button("Remove…") { removing = edition }.disabled(manager.activeID != nil)
                            }
                        } else {
                            Button("Download") {
                                manager.download(edition, root: state.library.userPackDirectory) { state.rescanTranslations() }
                            }.disabled(manager.activeID != nil)
                        }
                    }
                    DarbyComparisonNotice(translationID: edition.id)
                    Link("Source & licence ↗", destination: edition.sourceURL).font(.system(size: 11))
                    if manager.activeID == edition.id {
                        ProgressView(value: manager.progress)
                        Text(manager.progress >= 0.99 ? "Validating and preparing offline text…" : "Downloading from eBible.org…")
                            .font(.system(size: 11)).foregroundStyle(STColor.secondary)
                    }
                }
                Divider()
            }
            if let message = manager.message { Text(message).font(.system(size: 12)).accessibilityAddTraits(.updatesFrequently) }
            Text("The reader includes the 66-book Protestant canon, without source footnotes. Historical editions can differ in individual verse numbering; linked resources use standard Protestant references. ESV, NASB and NKJV require separate publisher permission for complete offline packs.")
                .font(.system(size: 11)).foregroundStyle(STColor.secondary)
        }
        .foregroundStyle(STColor.ink)
        .confirmationDialog("Remove \(removing?.id ?? "Bible") from this Mac?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            if let edition = removing {
                Button("Remove downloaded Bible", role: .destructive) {
                    manager.remove(edition, root: state.library.userPackDirectory) { state.rescanTranslations() }
                    removing = nil
                }
            }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: { Text("Your notes and bundled Bibles will not be changed. You can download this edition again.") }
    }
}
