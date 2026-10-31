import SwiftUI

/// Pick a source first; read its actual indexed text below. Never substitute an AI summary
/// for the author's words. Existing SourceCard retains citations and reception context.
struct PassageSourceBrowser: View {
    @EnvironmentObject private var state: AppState
    @Environment(\.openWindow) private var openWindow
    let sources: [ResolvedSource]
    var compact = false
    @State private var selectedID: String?
    private var ordered: [ResolvedSource] {
        let traditions = state.deskSectionOrder.compactMap(\.tradition)
        return sources.sorted {
            let left = traditions.firstIndex(of: $0.entry.tradition) ?? 99
            let right = traditions.firstIndex(of: $1.entry.tradition) ?? 99
            return left == right ? $0.entry.author.localizedStandardCompare($1.entry.author) == .orderedAscending : left < right
        }
    }

    private var selection: ResolvedSource? { ordered.first(where: { $0.id == selectedID }) ?? ordered.first }
    var body: some View {
        VStack(spacing: 0) {
            if compact {
                Menu {
                    ForEach(ordered) { source in
                        Button { selectedID = source.id } label: {
                            if selection?.id == source.id { Label(source.entry.author + " — " + source.entry.work, systemImage: "checkmark") }
                            else { Text(source.entry.author + " — " + source.entry.work) }
                        }
                    }
                } label: {
                    Label(selection?.entry.author ?? "Choose a source", systemImage: "book")
                        .font(.system(size: 13, weight: .semibold)).lineLimit(1)
                }.menuStyle(.borderlessButton).padding(.horizontal, 18).padding(.vertical, 10)
            } else {
            ScrollView {
                LazyVStack(spacing: 2) {
                    ForEach(ordered) { source in
                        Button { selectedID = source.id } label: {
                            HStack(spacing: 12) {
                                Image(systemName: source.entry.tradition == .crossReferences ? "link" : "book")
                                    .font(.system(size: 19)).frame(width: 24)
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(source.entry.author).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                                    Text(source.entry.work).font(.system(size: 11)).foregroundStyle(STColor.secondary).lineLimit(1)
                                }
                                Spacer(minLength: 0)
                                Image(systemName: selection?.id == source.id ? "checkmark" : "chevron.right").font(.system(size: 11))
                            }
                            .foregroundStyle(STColor.ink).padding(12).frame(maxWidth: .infinity, alignment: .leading)
                            .background(selection?.id == source.id ? STColor.navy.opacity(0.10) : .clear,
                                        in: RoundedRectangle(cornerRadius: 5))
                            .contentShape(Rectangle())
                        }.buttonStyle(.plain)
                            .accessibilityAddTraits(selection?.id == source.id ? .isSelected : [])
                    }
                }.padding(.horizontal, 10)
            }.frame(height: min(154, CGFloat(ordered.count) * 64))
            }
            HStack {
                Text("\(ordered.count) linked entries").font(.caption).foregroundStyle(STColor.secondary)
                Spacer()
                Button("Add resources…") {
                    if let action = state.openSceneWindow { action("add-resources") }
                    else { openWindow(id: "add-resources") }
                }.font(.caption)
            }.padding(.horizontal, 20).padding(.vertical, 10)
            Divider()
            if let selection {
                SourceCard(resolved: selection, bookName: state.bookName, startExpanded: false) { ref in
                    state.navigate(bookCode: ref.code, chapter: ref.chapter, verse: ref.start)
                }.id(selection.id).padding(.horizontal, 6)
            }
        }
    }
}
