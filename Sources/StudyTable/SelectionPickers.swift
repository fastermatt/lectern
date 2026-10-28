import SwiftUI

// MARK: - Pointer-free routes to Highlight… / Add to collection… (0.10, S2a)
//
// Modelled on `VerseWordPicker` (Panes.swift): a small popover listing every choice as its own
// button, opened from a VoiceOver custom action or a context-menu item, so the same gesture that
// needs a colour submenu for a mouse has a flat, readable list for keyboard/VoiceOver use.

struct HighlightPickerView: View {
    let current: HighlightColor?
    let choose: (HighlightColor?) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("HIGHLIGHT").legend(STColor.secondary, size: 9)
            ForEach(HighlightColor.allCases, id: \.self) { color in
                Button { choose(color) } label: {
                    HStack(spacing: 8) {
                        Image(systemName: color.glyphName).foregroundStyle(color.tint)
                        Text(color.displayName).font(STFont.reading(13)).foregroundStyle(STColor.ink)
                        Spacer(minLength: 8)
                        if current == color { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)) }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(current == color ? "\(color.displayName), selected" : color.displayName)
            }
            if current != nil {
                Divider()
                Button { choose(nil) } label: {
                    Text("Remove Highlight").font(.system(size: 12, design: .rounded)).foregroundStyle(STColor.secondary)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(width: 200)
    }
}

struct CollectionPickerView: View {
    let collections: [StudyCollection]
    let selected: Set<UUID>
    let choose: (StudyCollection) -> Void
    let createNew: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ADD TO COLLECTION").legend(STColor.secondary, size: 9)
            if collections.isEmpty {
                Text("No collections yet.").font(.system(size: 12, design: .rounded)).foregroundStyle(STColor.secondary)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(collections) { collection in
                            let inCollection = selected.contains(collection.id)
                            Button { choose(collection) } label: {
                                HStack(spacing: 8) {
                                    Text(collection.name).font(STFont.reading(13)).foregroundStyle(STColor.ink)
                                    Spacer(minLength: 8)
                                    if inCollection { Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold)) }
                                }
                                .padding(.horizontal, 8).padding(.vertical, 5)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(inCollection ? "\(collection.name), already added" : "Add to \(collection.name)")
                        }
                    }
                }
                .frame(maxHeight: 180)
            }
            Divider()
            Button { createNew() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "plus.circle")
                    Text("New Collection\u{2026}").font(.system(size: 12, weight: .medium, design: .rounded))
                }
                .foregroundStyle(STColor.ink)
                .padding(.horizontal, 8).padding(.vertical, 5)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(10)
        .frame(width: 220)
    }
}
