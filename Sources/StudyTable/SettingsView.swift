import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @ObservedObject private var opener = SettingsOpener.shared

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                tab("Workspace", symbol: "slider.horizontal.3", destination: .workspace)
                tab("Resources", symbol: "square.stack.3d.up", destination: .resources)
                tab("Translations", symbol: "books.vertical", destination: .translations)
                tab("About", symbol: "info.circle", destination: .about)
            }
            .padding(14)
            Rectangle().fill(STColor.hairline).frame(height: 1)
            Group {
                switch opener.destination {
                case .workspace: WorkspaceCustomization()
                case .resources: ResourceCenterView()
                case .translations: TranslationSettings()
                case .about: AboutSettings()
                }
            }
            .scrollContentBackground(.hidden)
        }
        .background(STColor.tileTop)
        .frame(width: 620, height: 660)
        .preferredColorScheme(state.colorScheme)
        .defaultAppStorage(state.preferenceStore)
    }

    private func tab(_ title: String, symbol: String, destination: SettingsDestination) -> some View {
        let selected = opener.destination == destination
        return Button { opener.destination = destination } label: {
            Label(title, systemImage: selected ? "checkmark" : symbol)
                .font(STFont.legend(12))
                .frame(maxWidth: .infinity).padding(.vertical, 10)
                .foregroundStyle(selected ? STColor.lcdInk : STColor.ink)
                .background(selected ? STColor.lcd : STColor.tileWell, in: RoundedRectangle(cornerRadius: 3))
                .overlay(RoundedRectangle(cornerRadius: 3).stroke(STColor.keyRim, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// Source attribution the app is obligated to show for its CC BY-licensed data (public-domain
/// sources need no attribution; this tab is specifically for the ones that do). New in 0.8 for
/// the original-language interlinear data — see `Resources/Licenses/interlinear-stepbible.txt`
/// for the full licence text this string is drawn from verbatim.
private struct AboutSettings: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            // Placed here (rather than the Workspace tab) because this round's workstream owns
            // SettingsView.swift but not WorkspaceCustomization.swift or the SettingsDestination
            // enum (MainView.swift) needed to add a dedicated tab -- see the workstream report.
            // Claude may want to relocate this to Workspace, alongside source-bank visibility,
            // during wave-2 integration now that it can touch those files.
            Section("Confessional alignment lens") {
                Text("Lectern does not claim one fixed doctrinal identity. Choose which confessional standard, if any, governs the alignment language (agreement / tension / no mapping / historically disputed) shown on source cards. This is independent of which authors or traditions you display in Fathers, Reformed, Exegetes or Cross-References \u{2014} changing the lens never hides or shows a source.")
                    .font(.caption).foregroundStyle(.secondary)
                AlignmentLensPicker()
            }
            Section("Original-language data") {
                Text("Hebrew/Aramaic Old Testament and Greek New Testament word-level tagging is from STEPBible-Data (Tyndale House Cambridge, curated by STEPBible.org), used under CC BY 4.0.")
                    .font(.caption)
                Link("creativecommons.org/licenses/by/4.0", destination: URL(string: "https://creativecommons.org/licenses/by/4.0/")!)
                    .font(.caption)
                Link("github.com/STEPBible/STEPBible-Data", destination: URL(string: "https://github.com/STEPBible/STEPBible-Data")!)
                    .font(.caption)
            }
            Section("Scripture") {
                Text("Berean Standard Bible, King James Version (1769 text) and World English Bible are bundled public-domain texts.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Show section headings and paragraph spacing", isOn: Binding(get: { state.showSectionHeadings }, set: { state.showSectionHeadings = $0 }))
                Text("Headings, \u{201C}See also\u{201D} links to parallel passages, and paragraph breaks come from the Berean Standard Bible\u{2019}s own markup (the KJV and WEB carry very few). Downloaded and online translations show none.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Passage guide sources") {
                Text(ReferenceStore.shared.attribution.nave).font(.caption).textSelection(.enabled)
                Text(ReferenceStore.shared.attribution.easton).font(.caption).textSelection(.enabled)
                Text(ReferenceStore.shared.attribution.tipnr).font(.caption).textSelection(.enabled)
                Text("STEPBible person and place summaries include AI-assisted drafts from the source dataset. These are labelled bundled source text. The optional Your AI panel connects only to a model you configure and only when you send a question.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

private struct TranslationSettings: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        Form {
            DownloadLibraryView()
            Section("Installed and available") {
                ForEach(state.library.translations) { info in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("\(info.id) — \(info.name)")
                            Text(info.detail).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if info.id == state.translationID { Image(systemName: "checkmark.circle.fill") }
                        else { Button("Use") { state.translationID = info.id }.controlSize(.small) }
                    }
                }
            }
            Section("Licensed offline packs") {
                Text("ESV, NASB and NKJV cannot be bundled without written offline-distribution rights. If you hold those rights, build a pack from your USFM files with scripts/build-scripture-packs.sh and copy its folder into the Translations folder. It then appears here as an offline translation.")
                    .font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button("Open Translations folder") {
                        try? FileManager.default.createDirectory(at: state.library.userPackDirectory, withIntermediateDirectories: true)
                        NSWorkspace.shared.open(state.library.userPackDirectory)
                    }
                    Button("Rescan") { state.rescanTranslations() }
                }
            }
            ForEach(OnlineProvider.allCases) { provider in
                OnlineKeySection(provider: provider)
            }
            Section("Online cache") {
                Button("Clear cached online text") { Task { await state.online.cache.clear(); state.reloadChapter() } }
            }
        }
        .formStyle(.grouped)
    }
}

private struct OnlineKeySection: View {
    @EnvironmentObject private var state: AppState
    let provider: OnlineProvider
    @State private var draft = ""

    private var hasKey: Bool { state.configuredKeys.contains(provider) }

    var body: some View {
        Section(provider.displayName) {
            SecureField(hasKey ? "Key saved in Keychain. Paste to replace." : "Paste your API key", text: $draft)
            HStack {
                Button("Save key") { state.saveKey(draft, for: provider); draft = "" }.disabled(draft.trimmingCharacters(in: .whitespaces).isEmpty)
                Button("Remove key") { state.saveKey("", for: provider) }.disabled(!hasKey)
                Spacer()
                Link("Get a key", destination: provider.registrationURL)
                Link("Terms", destination: provider.termsURL)
            }
            .controlSize(.small)
            Text(provider.termsSummary).font(.caption).foregroundStyle(.secondary)
            Text("Your key is stored in the macOS Keychain and sent only to the publisher's API. Text from this source needs a network connection unless it is already in the limited cache.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
