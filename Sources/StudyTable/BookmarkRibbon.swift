import SwiftUI

/// The icon's notched ribbon denotes an actual saved note, never a decorative bookmark.
struct BookmarkRibbon: Shape {
    func path(in rect: CGRect) -> Path {
        Path { path in
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY - rect.height * 0.25))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
        }
    }
}

struct SavedNoteRibbon: View {
    @ObservedObject var notes: NotesStore
    let passage: String
    /// 0.10, S2a: when set, the ribbon is range-aware — it shows for a verse covered by ANY note
    /// whose anchor overlaps this one (`notes(overlapping:)`), not only a note stored under this
    /// exact display string. `NotesPane.swift`'s existing string-keyed calls leave this `nil` and
    /// keep their old exact-match behavior unchanged.
    var overlapAnchor: Anchor?
    var width: CGFloat = 8
    var height: CGFloat = 15

    private var hasNote: Bool {
        if let overlapAnchor { return !notes.notes(overlapping: overlapAnchor).isEmpty }
        guard let note = notes.note(for: passage) else { return false }
        return !note.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        if hasNote {
            BookmarkRibbon()
                .fill(LinearGradient(colors: [STColor.orange, Color(hex: 0xA94416)], startPoint: .leading, endPoint: .trailing))
                .frame(width: width, height: height)
                .overlay(alignment: .leading) { Rectangle().fill(.white.opacity(0.25)).frame(width: 1).padding(.bottom, height * 0.25) }
                .shadow(color: .black.opacity(0.18), radius: 1, x: 1, y: 1)
                .help("Saved note for \(passage)")
                .accessibilityLabel("Has saved note")
        }
    }
}
