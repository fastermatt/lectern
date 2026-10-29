import SwiftUI
import UniformTypeIdentifiers

struct ContributionDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct ContributionView: View {
    @Binding var draft: ContributionDraft
    @State private var document = ContributionDocument(data: Data())
    @State private var exporting = false
    @State private var message: String?
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("Help improve Throughline").font(.system(size: 25, weight: .regular))
                Text("A better reference. A missing resource. A clearer translation. Your experience can help, wherever you study.")
                    .font(.callout).foregroundStyle(STColor.secondary)
                Text("Prepare a suggestion without coding. Export a small file to share with a maintainer. Nothing is sent automatically; public submission channels are still being prepared.")
                    .font(.callout)
                Divider()
                VStack(alignment: .leading, spacing: 14) {
                    Picker("I’d like to", selection: $draft.kind) {
                        ForEach(ContributionDraft.Kind.allCases, id: \.self) { Text($0.title).tag($0) }
                    }
                    field("Title", text: $draft.title, prompt: "A short description of your suggestion")
                    HStack(alignment: .top, spacing: 16) {
                        field("Resource or edition", text: $draft.resource, prompt: "Optional")
                        field("Passage or control", text: $draft.reference, prompt: "Optional")
                    }
                    field("Language", text: $draft.language, prompt: "Write in the language you are comfortable with")
                    field("Source link", text: $draft.sourceURL, prompt: "https://… (optional)")
                    VStack(alignment: .leading, spacing: 6) {
                        Text("What did you notice? What would you change?").font(.callout.weight(.medium))
                        TextEditor(text: $draft.details).font(.body).frame(minHeight: 130)
                            .scrollContentBackground(.hidden).padding(8).background(STColor.tileWell, in: RoundedRectangle(cornerRadius: 4))
                            .accessibilityLabel("Suggestion details")
                    }
                }.textFieldStyle(.roundedBorder)
                Text("Include only what you want to share. Don’t paste private notes, passwords, API keys or entire copyrighted works. Drafts stay in this window and are not saved until you export.")
                    .font(.caption).foregroundStyle(STColor.secondary)
                if let validation = draft.validationMessage { Text(validation).font(.caption).foregroundStyle(STColor.secondary) }
                HStack {
                    Button("Export suggestion…") {
                        do { document = ContributionDocument(data: try draft.encoded()); exporting = true }
                        catch { message = "The draft could not be prepared. Please try again." }
                    }.disabled(draft.validationMessage != nil)
                    if let message { Text(message).font(.callout).accessibilityAddTraits(.updatesFrequently) }
                }
            }.padding(28).frame(maxWidth: 740, alignment: .leading).frame(maxWidth: .infinity, alignment: .leading)
        }.foregroundStyle(STColor.ink).background(STColor.paper)
        .fileExporter(isPresented: $exporting, document: document, contentType: .json, defaultFilename: "throughline-suggestion") { result in
            switch result { case .success: message = "Saved. Review the file before sharing it."; case .failure: message = "The draft wasn’t saved. You can try exporting again." }
        }
    }
    private func field(_ title: String, text: Binding<String>, prompt: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.callout.weight(.medium))
            TextField(title, text: text, prompt: Text(prompt)).labelsHidden().accessibilityLabel(title)
        }
    }
}
