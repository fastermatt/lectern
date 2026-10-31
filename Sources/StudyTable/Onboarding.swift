import SwiftUI

/// A one-time explanation of the instrument, shown on first launch only. The deck is dense by
/// design (it's a reproduction of a physical control surface, not a generic dashboard), so the
/// lever for "not complicated" is teaching it once rather than stripping it down.
struct WelcomeSheet: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var state: AppState

    // Internal (not private) so `AlignmentTests` can assert these strings never carry the banned
    // fixed-identity phrasing the 2026-09-24 decision rules out, the same way it checks PRODUCT.md.
    let points: [(String, String)] = [
        ("PASSAGE", "Choose a book and chapter in the Bible sidebar, or click the passage title to jump to a reference. Click a verse to link your sources and notes to it."),
        ("READING OPTIONS", "Use Reading options below the Bible to change typeface, text size and line spacing. Bible and study text have separate controls. You can also pinch to resize text."),
        ("APPEARANCE", "The half-filled circle at the top right opens System, Light and Dark modes. Choose a palette or edit accent, page and text colors independently for light and dark."),
        ("LAYOUTS", "Save your workspace from Layouts in the toolbar. Choose a preset, favorite a layout, or set a startup layout. Drag dividers to resize panes. Reading focus hides surrounding panes (⇧⌘F)."),
        ("SOURCES", "Choose a linked resource to read its actual indexed text. The filter above the list controls source banks. Citations, coverage and historical context remain attached to each entry."),
        ("HISTORICAL CONTEXT", "Church Fathers are historical witnesses, not automatically Reformed authorities. Author profiles give sourced context where available. Council-condemned authors are separately labelled and opt-in under View. No source's inclusion means theological endorsement."),
        ("TOOLS & GUIDE", "Tools opens original languages, definitions, cross-references, topics, people and places, and translation comparison. Guide gives an overview for a selected or entered passage. Historical resources have gaps."),
        ("STUDY A WORD", "Double-click a Bible word, or right-click its verse and choose Study a word. Thruline shows the original-language match and its confidence; some translated words have no single original word."),
        ("RESOURCES", "Library shows included and personal resources. Add resources offers free Bible downloads, Tyndale study notes and dictionary, historic works, and publisher links. Import your own unencrypted EPUB or text books. Purchases happen on the publisher's website."),
        ("SEARCH", "Search in the top toolbar (⌘F) finds Bible text, library material and notes, or original-language matches. The sidebar field finds a book or reference."),
        ("NOTES", "Notes stay linked to your passage. Use the plus button to start another note, choose a template, or browse your saved notes. Everything saves locally."),
        ("YOUR AI", "Connect your own local model or provider in Your AI. You choose which passage or cited material to attach. Core Bible study works offline without an AI account."),
        ("ALIGNMENT LENS", "Settings → About offers Westminster Standards, Three Forms of Unity, ecumenical creeds, or none. Documented alignment labels never imply a fixed doctrinal identity for Thruline.")
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text("THRULINE BIBLE").font(STFont.legend(11)).tracking(1.6)
                Text("Welcome to Thruline Bible").font(STFont.title(20))
            }
            .padding(20)
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(points, id: \.0) { point in
                        VStack(alignment: .leading, spacing: 3) {
                            // Orange fails WCAG AA as text (reserved for selected/active/LED per
                            // DESIGN.md's One Accent rule) -- ink plus the legend's own tracked
                            // small caps already carries the label emphasis these need.
                            Text(point.0).legend(STColor.ink, size: 10)
                            Text(point.1).font(.system(size: 13, design: .rounded)).foregroundStyle(STColor.ink)
                        }
                    }
                }
                .padding(20)
            }
            // These items don't fit the visible area at once; without this, a reader who never
            // scrolls misses exactly the items explaining the least-guessable features.
            .overlay(alignment: .bottom) {
                LinearGradient(colors: [STColor.tileTop.opacity(0), STColor.tileTop.opacity(0.95)], startPoint: .top, endPoint: .bottom)
                    .frame(height: 22)
                    .allowsHitTesting(false)
                    .overlay(alignment: .bottom) {
                        Image(systemName: "chevron.compact.down")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(STColor.secondary)
                            .padding(.bottom, 2)
                    }
                    .accessibilityHidden(true)
            }
            Divider()
            HStack {
                Spacer()
                Button("Got it") { state.hasSeenIntro = true; dismiss() }
                    .buttonStyle(.borderedProminent).keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 420, height: 480)
        .background(STColor.tileTop)
    }
}
