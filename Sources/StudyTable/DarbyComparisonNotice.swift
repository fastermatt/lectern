import SwiftUI

/// Resource context, separate from optional navigation help and confessional approval badges.
enum DarbyComparisonContext {
    static let label = "Darby · Dispensational background"
    static let summary = "Retained for comparison with historic orthodox Christian teaching. Darby's Israel–Church distinction and pre-tribulation interpretation are disputed and should not be assumed to represent historic Christian consensus. Evaluate his translation separately from his explanatory writings; Lectern's download omits footnotes."
    static let discovery = "Darby · Dispensational background. Available for comparison with historic orthodox Christian teaching. Read and search offline; explanatory footnotes are not included."
}

struct DarbyComparisonNotice: View {
    let translationID: String

    var body: some View {
        if translationID == "DBY" {
            DisclosureGroup {
                VStack(alignment: .leading, spacing: 8) {
                    Text(DarbyComparisonContext.summary)
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                    Link("Darby's explanation of the rapture and Israel ↗",
                         destination: URL(string: "https://www.stempublishing.com/authors/darby/PROPHET/11007E.html")!)
                    Link("Early Christian comparison: Didache 16 ↗",
                         destination: URL(string: "https://www.newadvent.org/fathers/0714.htm")!)
                    Text("These sources support comparison; the Didache is one early witness, not a statement of every Christian tradition.")
                        .foregroundStyle(STColor.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 6)
            } label: {
                Label(DarbyComparisonContext.label, systemImage: "info.circle")
                    .fontWeight(.medium)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.system(size: 12))
            .foregroundStyle(STColor.ink)
            .tint(STColor.ink)
        }
    }
}
