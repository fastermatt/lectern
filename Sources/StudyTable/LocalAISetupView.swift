import SwiftUI

struct LocalAISetupView: View {
    @ObservedObject var manager: LocalAIManager
    @Environment(\.dismiss) private var dismiss
    @State private var removing: LocalAIModel?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("AI on your Mac").font(STFont.reading(26, weight: .semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Choose a free, optional model. No account or separate app is needed. After the download, questions and attached passages stay on this Mac.")
                .font(.system(size: 13)).fixedSize(horizontal: false, vertical: true)
            Text("This Mac: \(manager.memoryGB) GB memory · Apple Silicon required · Internet needed for downloads")
                .font(.system(size: 11)).foregroundStyle(STColor.secondary)
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(LocalAIModel.catalog) { model in card(model) }
                }.padding(1)
            }
            if manager.busy {
                HStack { ProgressView().controlSize(.small); Text(manager.status); Spacer(); Button("Cancel") { manager.cancel() } }
                    .font(.system(size: 12))
            } else { Text(manager.status).font(.system(size: 12)) }
            if let error = manager.error { Text(error).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true) }
            Text("Memory figures are guidance; other apps need room too. Models can make factual and theological errors. Check replies against Scripture and cited sources. Installing a model does not make its answers reviewed or approved.")
                .font(.system(size: 11)).foregroundStyle(STColor.secondary).fixedSize(horizontal: false, vertical: true)
        }
        .padding(24).frame(width: 620, height: 690)
        .foregroundStyle(STColor.ink).background(STColor.paper)
        .confirmationDialog("Remove \(removing?.name ?? "model") from this Mac?", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } })) {
            if let model = removing { Button("Remove download", role: .destructive) { manager.remove(model); removing = nil } }
            Button("Cancel", role: .cancel) { removing = nil }
        } message: { Text("You can download it again. Your notes and library are kept.") }
    }
    private func card(_ model: LocalAIModel) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(model.name).font(.system(size: 17, weight: .semibold))
                if model.id == LocalAIModel.recommended(memory: ProcessInfo.processInfo.physicalMemory) {
                    Text("Suggested start").font(.system(size: 10, weight: .medium)).padding(5).background(STColor.hairline, in: Capsule())
                }
                Spacer()
                if manager.activeID == model.id { Label("In use", systemImage: "checkmark.circle.fill").font(.system(size: 11)) }
            }
            Text(model.size).font(.system(size: 11)).foregroundStyle(STColor.secondary)
            Text(model.detail).font(.system(size: 12)).fixedSize(horizontal: false, vertical: true)
            HStack {
                Text("\(model.downloadSize) download · \(model.recommendedRAM) GB+ memory suggested").font(.system(size: 11))
                Spacer()
                Link("Source · Apache 2.0", destination: model.sourceURL).font(.system(size: 10))
            }
            if manager.workingID == model.id { ProgressView(value: manager.progress).accessibilityLabel("Model download progress") }
            HStack {
                if manager.installed.contains(model.id) {
                    Button(manager.activeID == model.id ? "Stop & free memory" : "Use model") {
                        if manager.activeID == model.id { manager.stop() } else { manager.start(model) }
                    }
                    Button("Remove…") { removing = model }
                } else { Button("Download · \(model.downloadSize)") { manager.download(model) } }
                if manager.memoryGB < model.recommendedRAM { Text("May be slow on this Mac").font(.system(size: 10)).foregroundStyle(STColor.secondary) }
                Spacer()
            }.disabled(manager.busy || !manager.supported).controlSize(.small)
        }.padding(16).background(STColor.tileWell, in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).stroke(STColor.hairline))
    }
}
