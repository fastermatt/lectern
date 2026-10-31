import SwiftUI

/// Recessed status glass. The readout selector never takes over passage navigation.
struct ConsoleStatusBar: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.colorScheme) private var colorScheme
    @AppStorage("console.display") private var display = "passage"

    private var status: String {
        switch state.chapterLoad {
        case .loading: return "LOADING"
        case .unavailable: return "UNAVAILABLE"
        case .loaded(let content):
            switch content.origin {
            case .offline: return "OFFLINE"
            case .onlineLive: return "ONLINE"
            case .onlineCached: return "CACHED"
            }
        }
    }

    var body: some View {
        HStack(spacing: 16) {
            Text("THRULINE BIBLE").font(.system(size: 11, weight: .medium)).tracking(3)
                .foregroundStyle(STColor.lcdInk).padding(.leading, 8)
            Spacer(minLength: 6)
            if display == "original" {
                Text(state.passage).font(STFont.lcd(10)).foregroundStyle(STColor.lcdDim)
                InterlinearStrip().frame(maxWidth: 420, maxHeight: 32)
            } else {
                Text(display == "resources"
                     ? "\(state.passage)   |   \(state.sourcesForPassage().count) LINKED SOURCES"
                     : "\(state.passage)   |   \(state.translationID)   |   \(status)")
                    .font(.system(size: 11, weight: .medium)).tracking(1.2)
                    .foregroundStyle(STColor.lcdInk).lineLimit(1)
            }
            Spacer(minLength: 6)
            Menu {
                Picker("Display", selection: $display) {
                    Text("Passage and connection").tag("passage")
                    Text("Original-language words").tag("original")
                    Text("Linked resource count").tag("resources")
                }
            } label: {
                Image(systemName: "chevron.down").font(.system(size: 11))
                    .foregroundStyle(STColor.lcdInk).frame(width: 22, height: 30)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
            .colorScheme(.dark)
            .accessibilityLabel("Choose display information").navigationHelp("Choose whether this readout shows passage status, original-language words, or linked resources.")
            Rectangle().fill(Color.white.opacity(0.3)).frame(width: 1, height: 20)
            Button { state.switchAppearance(from: colorScheme) } label: {
                HStack(spacing: 7) {
                    Image(systemName: colorScheme == .dark ? "sun.max" : "moon")
                    Text(colorScheme == .dark ? "LIGHT" : "DARK").font(.system(size: 8, weight: .medium))
                }
                .foregroundStyle(STColor.lcdInk).frame(width: 65, height: 28)
                .background(Capsule().fill(LinearGradient(colors: [.white.opacity(0.17), .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)))
                .overlay(Capsule().strokeBorder(.white.opacity(0.3), lineWidth: 0.7))
            }
            .buttonStyle(.plain).navigationHelp("Switch between light and dark appearance.")
            .accessibilityLabel(colorScheme == .dark ? "Switch to Light appearance" : "Switch to Dark appearance")
        }
        .padding(.horizontal, 18)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Color(hex: 0x303333), Color(hex: 0x111414), Color(hex: 0x242727)], startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .fill(LinearGradient(stops: [.init(color: .white.opacity(0.09), location: 0), .init(color: .clear, location: 0.48), .init(color: .black.opacity(0.16), location: 1)], startPoint: .top, endPoint: .bottom))
                .allowsHitTesting(false)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(LinearGradient(colors: [.black.opacity(0.85), .white.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 2))
        .shadow(color: .black.opacity(0.3), radius: 2, x: 0, y: 1)
    }
}
