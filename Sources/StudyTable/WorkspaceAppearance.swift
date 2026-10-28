import AppKit
import SwiftUI

/// Each finish is independent: changing a light page never turns the dark page white.
struct ReadingColors: Codable, Equatable, Sendable {
    var accent: UInt
    var paper: UInt
    var ink: UInt
    var isValid: Bool { [accent, paper, ink].allSatisfy { $0 <= 0xFFFFFF } }
    static let light = ReadingColors(accent: 0x94531F, paper: 0xF7F4EC, ink: 0x232621)
    static let dark = ReadingColors(accent: 0xDFAD78, paper: 0x242622, ink: 0xF2F0E8)
}

struct WorkspacePalette: Codable, Equatable, Sendable {
    var light = ReadingColors.light
    var dark = ReadingColors.dark
    static let standard = WorkspacePalette()
    static let preferenceKey = "workspace.palette.v1"
    static func load(from defaults: UserDefaults) -> Self {
        guard let data = defaults.data(forKey: preferenceKey),
              let palette = try? JSONDecoder().decode(Self.self, from: data),
              palette.light.isValid, palette.dark.isValid else { return .standard }
        return palette
    }
    static func preset(_ name: String) -> Self {
        switch name {
        case "Classic": return Self(light: .init(accent: 0x1C416C, paper: 0xFAF9F5, ink: 0x202326),
                                    dark: .init(accent: 0x91B5DE, paper: 0x232629, ink: 0xEFEDE6))
        case "Sage": return Self(light: .init(accent: 0x42624E, paper: 0xF4F6F0, ink: 0x202820),
                                 dark: .init(accent: 0xA3C5A8, paper: 0x222923, ink: 0xEEF3EB))
        case "Plum": return Self(light: .init(accent: 0x754968, paper: 0xFAF6F8, ink: 0x29212A),
                                 dark: .init(accent: 0xDCACD0, paper: 0x2A232B, ink: 0xF2ECF2))
        case "Slate": return Self(light: .init(accent: 0x405B72, paper: 0xF4F7FA, ink: 0x202932),
                                  dark: .init(accent: 0xA3C2DB, paper: 0x20272F, ink: 0xEDF2F8))
        default: return .standard
        }
    }
}

/// All Lectern windows share one palette. Tokens snapshot its light/dark pair when
/// SwiftUI redraws. A lock also makes background color resolution safe.
@MainActor
final class AppearanceUpdates: ObservableObject {
    static let shared = AppearanceUpdates()
    @Published var revision = 0
}

final class PaletteRuntime: @unchecked Sendable {
    static let shared = PaletteRuntime()
    private let lock = NSLock()
    private var value = WorkspacePalette.standard
    var palette: WorkspacePalette {
        get { lock.lock(); defer { lock.unlock() }; return value }
        set { lock.lock(); value = newValue; lock.unlock() }
    }
    @MainActor func apply(_ palette: WorkspacePalette) {
        self.palette = palette
        AppearanceUpdates.shared.revision += 1
        func invalidate(_ view: NSView) {
            view.needsDisplay = true
            for child in view.subviews { invalidate(child) }
        }
        for window in NSApp?.windows ?? [] {
            if let view = window.contentView { invalidate(view) }
        }
    }
}

extension Color {
    static func workspace(_ resolve: @escaping @Sendable (ReadingColors) -> UInt) -> Color {
        let palette = PaletteRuntime.shared.palette
        return Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let value = resolve(dark ? palette.dark : palette.light)
            return NSColor(srgbRed: CGFloat((value >> 16) & 255) / 255,
                           green: CGFloat((value >> 8) & 255) / 255,
                           blue: CGFloat(value & 255) / 255, alpha: 1)
        })
    }
}

func blendRGB(_ first: UInt, _ second: UInt, amount: Double) -> UInt {
    [16, 8, 0].reduce(UInt(0)) { result, shift in
        let a = Double((first >> shift) & 255), b = Double((second >> shift) & 255)
        return result | (UInt((a + (b - a) * amount).rounded()) << shift)
    }
}

struct AppearancePanel: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.colorScheme) private var scheme
    @AppStorage(NavigationHelpPreference.key) private var navigationHelpEnabled = NavigationHelpPreference.defaultValue
    @State private var editingDark = false
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Appearance").font(.headline)
            Picker("Mode", selection: Binding(get: { state.theme }, set: { state.theme = $0 })) {
                Text("System").tag(AppTheme.system)
                Text("Light").tag(AppTheme.light)
                Text("Dark").tag(AppTheme.dark)
            }.pickerStyle(.segmented)
            HStack {
                ForEach(["Ivory", "Classic", "Sage", "Slate", "Plum"], id: \.self) { name in
                    Button(name) { state.palette = .preset(name) }
                        .controlSize(.small)
                }
            }
            Divider()
            Picker("Edit colors for", selection: $editingDark) {
                Text("Light").tag(false); Text("Dark").tag(true)
            }.pickerStyle(.segmented)
            ColorPicker("Accent", selection: color(\.accent), supportsOpacity: false)
            ColorPicker("Page", selection: color(\.paper), supportsOpacity: false)
            ColorPicker("Text", selection: color(\.ink), supportsOpacity: false)
            let colors = editingDark ? state.palette.dark : state.palette.light
            VStack(alignment: .leading, spacing: 6) {
                Text("Romans 8").font(.system(size: 21, design: .serif))
                Text("Your reading colors").font(.callout).foregroundStyle(Color(hex: colors.accent))
            }
            .foregroundStyle(Color(hex: colors.ink)).padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(hex: colors.paper), in: RoundedRectangle(cornerRadius: 6))
            Text("Colors save automatically. Light and dark have separate palettes.")
                .font(.caption).foregroundStyle(.secondary)
            Toggle("Show navigation tips", isOn: $navigationHelpEnabled)
            Button("Reset colors") { state.palette = .standard }
        }
        .padding(20).frame(width: 330).foregroundStyle(.primary).background(Color(nsColor: .windowBackgroundColor))
        .onAppear { editingDark = scheme == .dark }
        .onChange(of: scheme) { _, value in editingDark = value == .dark }
    }
    private func color(_ key: WritableKeyPath<ReadingColors, UInt>) -> Binding<Color> {
        Binding(get: { Color(hex: (editingDark ? state.palette.dark : state.palette.light)[keyPath: key]) }, set: { newColor in
            guard let color = NSColor(newColor).usingColorSpace(.sRGB) else { return }
            func channel(_ value: CGFloat) -> UInt { UInt((min(1, max(0, value)) * 255).rounded()) }
            let rgb = channel(color.redComponent) << 16 | channel(color.greenComponent) << 8 | channel(color.blueComponent)
            var palette = state.palette
            if editingDark { palette.dark[keyPath: key] = rgb } else { palette.light[keyPath: key] = rgb }
            state.palette = palette
        })
    }
}

/// Replaces both rotary controls without changing stored type preferences or pinch gestures.
struct ReadingOptionsPanel: View {
    @EnvironmentObject private var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Reading options").font(.headline)
            Text("Bible").font(.subheadline.weight(.semibold))
            Picker("Typeface", selection: Binding(get: { state.scriptureTypeface }, set: { state.scriptureTypeface = $0 })) {
                ForEach(ReadingTypeface.availableForScripture) { Text($0.displayName).tag($0) }
            }.navigationHelp("Choose the typeface used for Bible text.")
            Stepper("Text size: \(Int(state.fontSize)) pt", value: $state.fontSize, in: 15...30, step: 1)
                .navigationHelp("Adjust Bible text size. The change applies as you read.")
            Stepper("Line spacing: \(Int(state.lineSpacing)) pt", value: $state.lineSpacing, in: 2...16, step: 1)
                .navigationHelp("Adjust the space between Bible text lines.")
            Divider()
            Text("Sources & notes").font(.subheadline.weight(.semibold))
            Picker("Typeface", selection: Binding(get: { state.studyTypeface }, set: { state.studyTypeface = $0 })) {
                ForEach(ReadingTypeface.available) { Text($0.displayName).tag($0) }
            }.navigationHelp("Choose a typeface for sources, commentary, and notes.")
            Stepper("Text size: \(state.studyFontSize, specifier: "%.1f") pt", value: $state.studyFontSize, in: 11...20, step: 0.5)
                .navigationHelp("Adjust text size in sources, commentary, and notes independently of Bible text.")
            Stepper("Line spacing: \(state.studyLineSpacing, specifier: "%.1f") pt", value: $state.studyLineSpacing, in: 1...8, step: 0.5)
                .navigationHelp("Adjust line spacing in sources, commentary, and notes independently of Bible text.")
            Toggle("Section headings", isOn: Binding(get: { state.showSectionHeadings }, set: { state.showSectionHeadings = $0 }))
                .navigationHelp("Show or hide section headings in the Bible text.")
        }.padding(20).frame(width: 340).foregroundStyle(.primary).background(Color(nsColor: .windowBackgroundColor))
    }
}
