import SwiftUI

/// Stable persisted identifiers. Commentary and study tools share ordering, but render in
/// separate tabs so a long passage guide never buries the commentary a reader came to read.
enum StudyDeskSection: String, CaseIterable, Codable, Identifiable {
    case fathers, reformed, exegetes, crossReferences
    case proofTexts, originalLanguage, topics, dictionary, peoplePlaces, compare
    var id: String { rawValue }
    var title: String {
        switch self {
        case .fathers: "Church Fathers"
        case .reformed: "Reformed commentary"
        case .exegetes: "Historic exegetes"
        case .crossReferences: "Cross-references"
        case .proofTexts: "Confessional proof texts"
        case .originalLanguage: "Original language"
        case .topics: "Topics"
        case .dictionary: "Dictionary"
        case .peoplePlaces: "People & Places"
        case .compare: "Compare translations"
        }
    }
    var tradition: SourceTradition? {
        switch self {
        case .fathers: .fathers
        case .reformed: .reformed
        case .exegetes: .exegetes
        case .crossReferences: .crossReferences
        default: nil
        }
    }
    var isSourceBank: Bool { tradition != nil }
    static func normalizedOrder(_ values: [String]) -> [Self] {
        var result: [Self] = []
        for value in values {
            if let section = Self(rawValue: value), !result.contains(section) { result.append(section) }
        }
        return result + allCases.filter { !result.contains($0) }
    }
}

struct WorkspaceCustomization: View {
    @EnvironmentObject private var state: AppState
    @AppStorage(NavigationHelpPreference.key) private var navigationHelpEnabled = NavigationHelpPreference.defaultValue

    @State private var showAppearance = false
    @State private var showReading = false

    var body: some View {
        Form {
            Section("Appearance & reading") {
                Toggle("Show navigation tips", isOn: $navigationHelpEnabled)
                    .help("Show or hide optional workflow tips on navigation controls.")
                Button("Appearance and colors…") { showAppearance = true }
                    .popover(isPresented: $showAppearance) { AppearancePanel().environmentObject(state) }
                Button("Reading options…") { showReading = true }
                    .popover(isPresented: $showReading) { ReadingOptionsPanel().environmentObject(state) }
            }
            Section("Your workspace") {
                Text("Drag the dividers to resize panes. Open Layouts above the Bible to save, favorite, update or restore a workspace. Appearance follows your choice in Settings.")
                    .font(.callout).foregroundStyle(.secondary)
                Text("Use Sources in the study desk to choose commentary banks. Reorder banks and choose Study tools here; changes save automatically.")
                    .font(.callout)
            }
            Section("Scripture typeface") {
                Text("Use Reading options below the Bible for text size and line spacing, or choose a typeface here.")
                    .font(.callout).foregroundStyle(.secondary)
                TypefaceSwatchPicker(selection: state.scriptureTypeface, options: ReadingTypeface.availableForScripture) { state.scriptureTypeface = $0 }
            }
            Section("Commentary & study typeface") {
                Text("Commentary, cross-references and reference articles have their own font, size and leading — independent of Scripture's.")
                    .font(.callout).foregroundStyle(.secondary)
                TypefaceSwatchPicker(selection: state.studyTypeface) { state.studyTypeface = $0 }
                LabeledContent("Size") {
                    // `$state.studyFontSize` (the EnvironmentObject-synthesized binding), not a
                    // hand-built `Binding(get:set:)` that assigns the plain @AppStorage property
                    // directly: a direct assignment never calls `state.objectWillChange.send()`,
                    // so the Settings window would update its own Stepper label but the real
                    // Study Desk in the main window — a separate view hierarchy — never learns to
                    // redraw. `$state.property` routes through ObservedObject's own binding
                    // machinery, which does notify. Same fix, same reason as `lineSpacing` below.
                    Stepper(value: $state.studyFontSize, in: 11...20, step: 0.5) {
                        Text("\(state.studyFontSize, specifier: "%.1f") pt").monospacedDigit()
                    }
                }
                LabeledContent("Line spacing") {
                    Stepper(value: $state.studyLineSpacing, in: 1...8, step: 0.5) {
                        Text("\(state.studyLineSpacing, specifier: "%.1f") pt").monospacedDigit()
                    }
                }
            }
            group("Commentaries", banks: true)
            group("Study tools", banks: false)
            Section {
                Button("Reset section order and visibility") { state.resetDeskCustomization() }
                Text("Restores all source banks and tools. Your notes, Bible downloads, text size and pane widths are unchanged.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private func group(_ title: String, banks: Bool) -> some View {
        let sections = state.deskSectionOrder.filter { $0.isSourceBank == banks }
        return Section(title) {
            ForEach(sections) { section in
                HStack {
                    if banks {
                        Text(section.title)
                    } else {
                        Toggle(section.title, isOn: Binding(
                            get: { state.isDeskSectionVisible(section) },
                            set: { state.setDeskSectionVisible(section, $0) }))
                    }
                    Spacer()
                    Button { state.moveDeskSection(section, by: -1) } label: {
                        Image(systemName: "chevron.up")
                    }
                    .disabled(sections.first == section)
                    .help("Move \(section.title) up")
                    .accessibilityLabel("Move \(section.title) up")
                    Button { state.moveDeskSection(section, by: 1) } label: {
                        Image(systemName: "chevron.down")
                    }
                    .disabled(sections.last == section)
                    .help("Move \(section.title) down")
                    .accessibilityLabel("Move \(section.title) down")
                }
                .controlSize(.small)
            }
        }
    }
}

/// A row of typeface "voices" — a live "Aa" set in the actual face, its one-line character, and
/// the family name — rather than a plain text menu. Selection is never colour alone: a filled
/// tile, a heavier border, *and* a checkmark badge all change together (`ReadingTypeface`'s own
/// header comment explains why every option here is guaranteed to resolve to a real installed
/// font). Each swatch is a plain `Button`, so Tab/Return and VoiceOver work with no custom key
/// handling.
private struct TypefaceSwatchPicker: View {
    let selection: ReadingTypeface
    /// Scripture offers `.availableForScripture` (excludes a typeface the hit-test layer can't
    /// safely measure); Study offers the full `.available` set, since study text has no such layer.
    var options: [ReadingTypeface] = ReadingTypeface.available
    let onSelect: (ReadingTypeface) -> Void

    var body: some View {
        FlowLayout(spacing: 8) {
            ForEach(options) { typeface in
                let isSelected = typeface == selection
                Button { onSelect(typeface) } label: {
                    VStack(spacing: 4) {
                        Text("Aa").font(STFont.reading(19, typeface: typeface)).foregroundStyle(STColor.ink)
                        Text(typeface.displayName)
                            .font(.system(size: 10, weight: isSelected ? .semibold : .regular, design: .rounded))
                            .foregroundStyle(isSelected ? STColor.ink : STColor.secondary)
                            .lineLimit(1).minimumScaleFactor(0.8)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 8)
                    .frame(width: 84)
                    .background(isSelected ? STColor.tileWell : Color.clear, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(isSelected ? STColor.ink : STColor.keyRim, lineWidth: isSelected ? 1.5 : 1))
                    .overlay(alignment: .topTrailing) {
                        if isSelected {
                            Image(systemName: "checkmark.circle.fill")
                                .font(.system(size: 12))
                                .symbolRenderingMode(.palette)
                                .foregroundStyle(STColor.tileTop, STColor.ink)
                                .offset(x: 5, y: -5)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(typeface.character)
                .accessibilityLabel(typeface.displayName)
                .accessibilityHint(typeface.character)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
            }
        }
    }
}
