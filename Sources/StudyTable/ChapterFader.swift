import SwiftUI

enum ChapterFaderScale {
    static func chapter(at fraction: Double, count: Int) -> Int {
        guard count > 1 else { return 1 }
        return 1 + Int((min(1, max(0, fraction)) * Double(count - 1)).rounded())
    }
    static func fraction(chapter: Int, count: Int) -> Double {
        guard count > 1 else { return 0 }
        return min(1, max(0, Double(chapter - 1) / Double(count - 1)))
    }
}

/// Chapter 1 is at the top, like the chapter order in a book—not an audio volume control.
/// Dragging previews locally. Only release commits a chapter/network request.
struct ChapterFader: View {
    @EnvironmentObject private var state: AppState
    @State private var preview: Int?
    @FocusState private var focused: Bool
    private var count: Int { max(1, state.book?.chapterCount ?? 1) }
    private var chapter: Int { preview ?? state.selectedChapter }

    var body: some View {
        VStack(spacing: 8) {
            Text("CHAPTER").font(.system(size: 7, weight: .semibold)).tracking(1)
            Text("\(chapter)").font(.system(size: 13, weight: .medium, design: .monospaced))
                .monospacedDigit().foregroundStyle(STColor.ink)
                .frame(width: 32, height: 20)
            Text("1").font(.system(size: 9, design: .monospaced))
            GeometryReader { geometry in
                let travel = max(1, geometry.size.height - 30)
                let position = ChapterFaderScale.fraction(chapter: chapter, count: count) * travel
                ZStack(alignment: .top) {
                    Capsule()
                        .fill(LinearGradient(colors: [STColor.chassisEdge, STColor.highlight], startPoint: .topLeading, endPoint: .bottomTrailing))
                        .frame(width: 21)
                        .overlay(Capsule().stroke(STColor.highlight.opacity(0.55), lineWidth: 1))
                        .overlay {
                            Capsule().fill(LinearGradient(colors: [STColor.socket, STColor.chassisEdge, STColor.socket], startPoint: .leading, endPoint: .trailing)).frame(width: 13)
                                .overlay(Capsule().stroke(STColor.keyRim.opacity(0.75), lineWidth: 1))
                                .shadow(color: .black.opacity(0.32), radius: 2, x: 1, y: 1)
                        }
                    RoundedRectangle(cornerRadius: 5)
                        .fill(LinearGradient(colors: [STColor.highlight, STColor.metalRim, STColor.keyTop, STColor.keyBottom], startPoint: .top, endPoint: .bottom))
                        .frame(width: 23, height: 30)
                        .overlay(RoundedRectangle(cornerRadius: 5).stroke(STColor.metalRim, lineWidth: 1.2))
                        .overlay(alignment: .top) {
                            RoundedRectangle(cornerRadius: 3).fill(STColor.highlight.opacity(0.72))
                                .frame(width: 23, height: 1).padding(.top, 2)
                        }
                        .overlay {
                            VStack(spacing: 2) {
                                ForEach(0..<3, id: \.self) { _ in
                                    Rectangle().fill(STColor.chassisEdge.opacity(0.65)).frame(width: 16, height: 0.7)
                                        .shadow(color: STColor.highlight, radius: 0, y: 0.7)
                                }
                            }
                        }
                        .shadow(color: .black.opacity(0.48), radius: 3, x: 3, y: 4)
                        .offset(y: position)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 0)
                    .onChanged { gesture in
                        guard count > 1 else { return }
                        focused = true
                        preview = ChapterFaderScale.chapter(at: (gesture.location.y - 15) / travel, count: count)
                    }
                    .onEnded { _ in
                        if let preview, preview != state.selectedChapter { state.selectedChapter = preview }
                        preview = nil
                    })
            }
            Text("\(count)").font(.system(size: 9, design: .monospaced))
        }
        .padding(.vertical, 10).frame(width: 50)
        .foregroundStyle(STColor.secondary)
        .background(LinearGradient(colors: [STColor.tileTop, STColor.tileWell], startPoint: .leading, endPoint: .trailing))
        .overlay(alignment: .leading) { Rectangle().fill(STColor.hairline).frame(width: 1) }
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(focused ? STColor.secondary : .clear, lineWidth: 1))
        .opacity(count > 1 ? 1 : 0.5)
        .focusable(count > 1).focused($focused)
        .onKeyPress(.downArrow) { adjust(1); return .handled }
        .onKeyPress(.upArrow) { adjust(-1); return .handled }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(state.bookName) chapter")
        .accessibilityValue("\(chapter) of \(count)")
        .accessibilityHint("Drag down for later chapters. Release to open. Arrow keys change one chapter.")
        .accessibilityAdjustableAction { direction in
            if direction == .increment { adjust(1) } else if direction == .decrement { adjust(-1) }
        }
        .help("\(state.bookName): chapter \(chapter) of \(count). Drag to preview, release to open.")
        .onChange(of: state.selectedChapter) { _, _ in preview = nil }
    }

    private func adjust(_ delta: Int) {
        let next = min(count, max(1, state.selectedChapter + delta))
        if next != state.selectedChapter { state.selectedChapter = next }
    }
}

struct StudyStatusLCD: View {
    @EnvironmentObject private var state: AppState
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
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 6) {
                Text(state.passage).lineLimit(1)
                Spacer(minLength: 0)
                Text("\(state.translationID) · \(status)").lineLimit(1).fixedSize()
            }
            .font(.system(size: 10, weight: .medium, design: .monospaced))
            .foregroundStyle(Color(red: 0.79, green: 0.91, blue: 0.83))
            .shadow(color: .green.opacity(0.12), radius: 2, y: 1)
            if InterlinearStore.shared.words(bookCode: state.selectedBookCode, chapter: state.selectedChapter,
                                            verse: state.selectedVerse ?? 0).isEmpty {
                Text("No original-language entry for this selection")
                    .font(.system(size: 10, design: .monospaced)).foregroundStyle(STColor.lcdDim)
                    .lineLimit(2).frame(height: 32)
            } else {
                InterlinearStrip().frame(height: 32)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(LinearGradient(colors: [Color(red: 0.06, green: 0.09, blue: 0.08), STColor.lcd], startPoint: .top, endPoint: .bottom))
        .overlay(RoundedRectangle(cornerRadius: 3).stroke(STColor.lcdRim, lineWidth: 1))
        .clipped()
        .help("Selected passage and text connection status. Original-language words below open their Study tools entry.")
    }
}
