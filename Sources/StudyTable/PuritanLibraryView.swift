import SwiftUI

// MARK: - Main View

struct PuritanLibraryView: View {
    @ObservedObject var service: PuritanLibraryService
    @State private var selectedWork: PuritanCatalogueEntry?
    @State private var parsedWork: ParsedPuritanWork?
    @State private var selectedSectionId: String?

    var body: some View {
        if let selectedWork = selectedWork, let parsedWork = parsedWork {
            PuritanReaderView(work: parsedWork, entry: selectedWork, selectedSectionId: $selectedSectionId, onBack: {
                self.selectedWork = nil
                self.parsedWork = nil
                selectedSectionId = nil
            })
        } else {
            PuritanListView(service: service, selectedWork: $selectedWork, parsedWork: $parsedWork)
        }
    }
}

// MARK: - List View

struct PuritanListView: View {
    @ObservedObject var service: PuritanLibraryService
    @Binding var selectedWork: PuritanCatalogueEntry?
    @Binding var parsedWork: ParsedPuritanWork?
    @State private var downloadingTcpId: String?
    @State private var query = ""

    var body: some View {
        VStack(spacing: 0) {
            if let catalogue = service.catalogue {
                TextField("Find a title or author", text: $query).textFieldStyle(.roundedBorder).padding(12)
                VStack(alignment: .leading, spacing: 4) {
                    Text(catalogue.attribution).font(.system(size: 9, design: .rounded)).foregroundStyle(STColor.secondary).lineLimit(2)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(STColor.tileWell)
                .overlay(alignment: .bottom) { Rectangle().fill(STColor.hairline).frame(height: 1) }

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(catalogue.groupedByAuthor.compactMap { group -> (author: String, works: [PuritanCatalogueEntry])? in
                            let works = group.works.filter { query.isEmpty || ($0.author + " " + $0.title).localizedCaseInsensitiveContains(query) }
                            return works.isEmpty ? nil : (group.author, works)
                        }, id: \.author) { author, works in
                            Section {
                                ForEach(works) { work in
                                    PuritanListRow(
                                        work: work,
                                        downloadState: service.downloadStates[work.tcpId] ?? .notDownloaded,
                                        onOpen: { openWork(work) },
                                        onDownload: { downloadWork(work) },
                                        onDelete: { service.delete(work.tcpId) }
                                    )
                                    Rectangle().fill(STColor.hairline).frame(height: 1).padding(.leading, 12)
                                }
                            } header: {
                                Text(author).font(STFont.legend(9)).tracking(0.9).foregroundStyle(STColor.secondary)
                                    .padding(.horizontal, 8).padding(.vertical, 6)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(STColor.tileWell)
                            }
                        }
                    }
                    .padding(.horizontal, 8).padding(.bottom, 8)
                }
            } else {
                VStack(spacing: 8) {
                    ProgressView()
                    Text("Loading catalogue…").font(.system(size: 11, design: .rounded)).foregroundStyle(STColor.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .physicalPaneSurface()
    }

    private func openWork(_ entry: PuritanCatalogueEntry) {
        Task {
            if let work = await service.loadWork(entry) {
                DispatchQueue.main.async {
                    parsedWork = work
                    selectedWork = entry
                }
            }
        }
    }

    private func downloadWork(_ entry: PuritanCatalogueEntry) {
        Task { await service.downloadAndStore(entry) }
    }
}

// MARK: - List Row

struct PuritanListRow: View {
    let work: PuritanCatalogueEntry
    let downloadState: PuritanLibraryService.DownloadState
    let onOpen: () -> Void
    let onDownload: () -> Void
    let onDelete: () -> Void

    @State private var showContextMenu = false

    var body: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(work.title).font(.system(size: 11, weight: .medium)).foregroundStyle(STColor.ink)
                    .accessibilityLabel("Title: \(work.title)")
                if !work.displaySubtitle.isEmpty {
                    Text(work.displaySubtitle).font(.system(size: 9)).foregroundStyle(STColor.secondary)
                        .accessibilityLabel(work.displaySubtitle)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Action button/indicator
            switch downloadState {
            case .notDownloaded:
                Button { onDownload() } label: {
                    Text("Download").font(.system(size: 9, weight: .semibold, design: .rounded))
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(STColor.keyTop, in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(STColor.ink)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Download \(work.title)")
                .help("Download the full text of \(work.title)")

            case .downloading:
                ProgressView()
                    .scaleEffect(0.8, anchor: .center)
                    .accessibilityLabel("Downloading \(work.title)")

            case .downloaded:
                Button { onOpen() } label: {
                    HStack(spacing: 2) {
                        Text("Open").font(.system(size: 9, weight: .semibold, design: .rounded))
                        Image(systemName: "chevron.right").font(.system(size: 8))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 4)
                    .background(STColor.lcd, in: RoundedRectangle(cornerRadius: 3))
                    .foregroundStyle(STColor.lcdInk)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Open \(work.title)")
                .help("Open the reader for \(work.title)")
                .contextMenu {
                    Button("Delete download") {
                        onDelete()
                    }
                    .accessibilityLabel("Remove downloaded text")
                }

            case .failed(let errorMsg):
                VStack(spacing: 2) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 9)).foregroundStyle(STColor.warning)
                    Text("Failed").font(.system(size: 7)).foregroundStyle(STColor.warning)
                }
                .accessibilityLabel("Download failed: \(errorMsg)")
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Reader View

struct PuritanReaderView: View {
    let work: ParsedPuritanWork
    let entry: PuritanCatalogueEntry
    @Binding var selectedSectionId: String?
    let onBack: () -> Void
    @EnvironmentObject private var state: AppState

    var currentSection: PuritanWorkSection? {
        selectedSectionId.flatMap { id in work.sections.first { $0.id == id } }
            ?? work.sections.first
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 2) {
                HStack(spacing: 8) {
                    Button { onBack() } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left").font(.system(size: 9))
                            Text("Back").font(STFont.legend(9)).tracking(0.9)
                        }
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(STColor.keyTop, in: RoundedRectangle(cornerRadius: 3))
                        .foregroundStyle(STColor.ink)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Back to library")
                    .help("Return to the Puritan Library catalogue")
                    .keyboardShortcut(.cancelAction)

                    Spacer()
                }
                .padding(.horizontal, 8).padding(.top, 8)

                Text(work.title).font(STFont.title(14)).foregroundStyle(STColor.ink).lineLimit(1)
                    .accessibilityLabel("Work title: \(work.title)")
                Text(work.author).font(.system(size: 10)).foregroundStyle(STColor.secondary)
                    .accessibilityLabel("Author: \(work.author)")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.bottom, 8)
            .background(STColor.tileWell)
            .overlay(alignment: .bottom) { Rectangle().fill(STColor.hairline).frame(height: 1) }

            if work.isEmpty {
                ContentUnavailableView("Unable to parse work", systemImage: "doc.text",
                                      description: Text("This work could not be parsed from its source file."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                HStack(spacing: 0) {
                    // Table of contents
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(work.sections) { section in
                                Button { selectedSectionId = section.id } label: {
                                    Text(section.heading)
                                        .font(.system(size: 10, weight: currentSection?.id == section.id ? .semibold : .regular))
                                        .foregroundStyle(currentSection?.id == section.id ? STColor.lcdInk : STColor.ink)
                                        .padding(.horizontal, 8).padding(.vertical, 6)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(currentSection?.id == section.id ? STColor.lcd : Color.clear,
                                                   in: RoundedRectangle(cornerRadius: 3))
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .accessibilityLabel("Section: \(section.heading)")
                                .accessibilityAddTraits(currentSection?.id == section.id ? .isSelected : [])
                                .help("Jump to \(section.heading)")
                            }
                        }
                        .padding(.horizontal, 6).padding(.vertical, 6)
                    }
                    .frame(maxWidth: 140)
                    .background(STColor.tileWell)
                    .overlay(alignment: .trailing) { Rectangle().fill(STColor.hairline).frame(width: 1) }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Table of contents")

                    // Reading text
                    if let section = currentSection {
                        ScrollView {
                            Text(section.body)
                                .font(STFont.reading(state.studyFontSize, typeface: state.studyTypeface))
                                .lineSpacing(state.studyLineSpacing)
                                .foregroundStyle(STColor.ink)
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .topLeading)
                                .padding(12)
                        }
                        .pinchToZoomTextSize($state.studyFontSize, in: 11...20)
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Reading text: \(section.heading)")
                    }
                }
            }
        }
        .physicalPaneSurface()
    }
}
