import AppKit
import CryptoKit
import Foundation
import SwiftUI

// MARK: - Versions and releases

/// A release version such as `0.22.0` or `0.23.0-beta.2`. A prerelease sorts before its final release.
struct ReleaseVersion: Comparable, CustomStringConvertible, Sendable {
    let numbers: [Int]
    let prerelease: String?

    init?(_ text: String) {
        var raw = text.trimmingCharacters(in: .whitespaces)
        if raw.hasPrefix("v") || raw.hasPrefix("V") { raw.removeFirst() }
        let pieces = raw.split(separator: "-", maxSplits: 1).map(String.init)
        guard let core = pieces.first, !core.isEmpty else { return nil }
        let numbers = core.split(separator: ".").map { Int($0) }
        guard !numbers.isEmpty, numbers.allSatisfy({ $0 != nil }) else { return nil }
        self.numbers = numbers.compactMap { $0 }
        prerelease = pieces.count > 1 ? pieces[1] : nil
    }

    var description: String { numbers.map(String.init).joined(separator: ".") + (prerelease.map { "-\($0)" } ?? "") }

    static func < (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool {
        for index in 0..<max(lhs.numbers.count, rhs.numbers.count) {
            let left = lhs.numbers[safe: index] ?? 0, right = rhs.numbers[safe: index] ?? 0
            if left != right { return left < right }
        }
        switch (lhs.prerelease, rhs.prerelease) {
        case (nil, nil), (nil, _?): return false
        case (_?, nil): return true
        case let (left?, right?): return left.compare(right, options: .numeric) == .orderedAscending
        }
    }
    static func == (lhs: ReleaseVersion, rhs: ReleaseVersion) -> Bool { !(lhs < rhs) && !(rhs < lhs) }
}

struct GitHubRelease: Decodable, Sendable {
    struct Asset: Decodable, Sendable {
        let name: String
        let size: Int
        let browserDownloadURL: URL
        enum CodingKeys: String, CodingKey { case name, size, browserDownloadURL = "browser_download_url" }
    }
    let tagName: String
    let name: String?
    let body: String?
    let draft: Bool
    let prerelease: Bool
    let htmlURL: URL
    let publishedAt: Date?
    let assets: [Asset]
    enum CodingKeys: String, CodingKey {
        case tagName = "tag_name", name, body, draft, prerelease, htmlURL = "html_url", publishedAt = "published_at", assets
    }
}

/// A newer release, ready to show. `archive` and `signature` are nil when the release can only be
/// installed by hand (for example releases published before in-app updates existed).
struct AvailableUpdate: Equatable, Sendable {
    let version: String
    let title: String
    let notes: String
    let page: URL
    let archive: URL?
    let signature: URL?
    let size: Int
    var installable: Bool { archive != nil && signature != nil }
}

enum AppUpdateError: LocalizedError {
    case untrustedLocation(String), download(String), badSignature, badArchive(String), cannotReplace(String)
    var errorDescription: String? {
        switch self {
        case .untrustedLocation(let host): return "The download was redirected somewhere unexpected (\(host)), so it was stopped."
        case .download(let detail): return "The update could not be downloaded. \(detail)"
        case .badSignature: return "The download didn\u{2019}t match Thruline\u{2019}s release signature, so it was not installed."
        case .badArchive(let detail): return "The downloaded app didn\u{2019}t pass its checks: \(detail)"
        case .cannotReplace(let detail): return detail
        }
    }
}

// MARK: - The updater

/// Checks GitHub Releases for a newer Thruline and installs it in one step.
///
/// Trust model: every installable release carries `<zip>.sig`, an Ed25519 signature over the ZIP's
/// SHA-256 made with the maintainer's offline key (`scripts/release-key.swift`). The app only
/// installs archives whose signature matches the public key below, that come from GitHub hosts, and
/// whose app bundle has the same bundle identifier, the advertised version and a valid code signature.
@MainActor
final class AppUpdater: ObservableObject {
    nonisolated static let releasePublicKey = "Qy/VtVyntxWqBTYE5Sg8sVwq4nFx/j5kNIgBIXWl0/A="
    nonisolated static let repository = "fastermatt/thruline-bible"
    nonisolated static let trustedHosts: Set<String> = ["github.com", "api.github.com", "objects.githubusercontent.com",
                                           "release-assets.githubusercontent.com", "codeload.github.com"]

    enum Phase: Equatable {
        case idle, checking, upToDate, available, downloading(Double), verifying, restarting
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var update: AvailableUpdate?
    @Published var showSheet = false
    @Published var checksAutomatically: Bool { didSet { defaults.set(checksAutomatically, forKey: Keys.auto) } }
    @Published var includesBetas: Bool { didSet { defaults.set(includesBetas, forKey: Keys.betas); update = nil } }

    let currentVersion: ReleaseVersion?
    private let bundleURL: URL
    private let defaults: UserDefaults
    private var dailyTask: Task<Void, Never>?

    private enum Keys {
        static let auto = "updates.checkAutomatically", betas = "updates.includeBetas"
        static let last = "updates.lastCheck", skipped = "updates.skippedVersion"
    }

    init(defaults: UserDefaults, bundle: Bundle = .main) {
        self.defaults = defaults
        bundleURL = bundle.bundleURL
        currentVersion = (bundle.infoDictionary?["CFBundleShortVersionString"] as? String).flatMap(ReleaseVersion.init)
        checksAutomatically = defaults.object(forKey: Keys.auto) as? Bool ?? true
        includesBetas = defaults.object(forKey: Keys.betas) as? Bool ?? true
    }

    /// Only a packaged app (not `swift run` or tests) can update itself.
    var canUpdate: Bool { bundleURL.pathExtension == "app" && currentVersion != nil }
    var hasUpdate: Bool { update != nil && phase != .upToDate }
    var versionText: String { currentVersion?.description ?? "development build" }

    /// Called once at launch: checks now if the last check is a day old, then once a day while open.
    func startAutomaticChecks() {
        guard canUpdate, dailyTask == nil else { return }
        dailyTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(8))
            while !Task.isCancelled {
                guard let self else { return }
                let last = self.defaults.object(forKey: Keys.last) as? Date ?? .distantPast
                if self.checksAutomatically, Date().timeIntervalSince(last) > 20 * 3600 { await self.check(userInitiated: false) }
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    /// "Check for Updates…": always shows the sheet with the answer.
    func checkFromMenu() {
        showSheet = true
        Task { await check(userInitiated: true) }
    }

    func check(userInitiated: Bool) async {
        guard canUpdate, let current = currentVersion else {
            if userInitiated { phase = .failed("Updates are available only in the packaged app.") }
            return
        }
        if case .downloading = phase { return }
        phase = .checking
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/\(Self.repository)/releases?per_page=10")!)
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            request.setValue("Thruline/\(current)", forHTTPHeaderField: "User-Agent")
            request.timeoutInterval = 20
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw AppUpdateError.download("GitHub didn\u{2019}t answer.") }
            defaults.set(Date(), forKey: Keys.last)
            let found = try Self.newest(in: data, newerThan: current, includeBetas: includesBetas)
            if let found, userInitiated || found.version != defaults.string(forKey: Keys.skipped) {
                update = found
                phase = .available
            } else {
                update = nil
                phase = .upToDate
            }
        } catch {
            phase = userInitiated ? .failed(error.localizedDescription) : .idle
        }
    }

    /// For previews and snapshot tests only.
    func stage(_ update: AvailableUpdate?, phase: Phase) {
        self.update = update
        self.phase = phase
    }

    func skipThisVersion() {
        if let update { defaults.set(update.version, forKey: Keys.skipped) }
        update = nil
        phase = .idle
        showSheet = false
    }

    func openReleasePage() {
        NSWorkspace.shared.open(update?.page ?? URL(string: "https://github.com/\(Self.repository)/releases")!)
    }

    /// Downloads, verifies and stages the new app, then quits; a small helper swaps the app in place
    /// and reopens it. Nothing on disk changes until every check has passed.
    func install() async {
        guard let update, let archive = update.archive, let signatureURL = update.signature else { openReleasePage(); return }
        if let problem = Self.replacementProblem(for: bundleURL) { phase = .failed(problem); return }
        phase = .downloading(0)
        do {
            let stage = try FileManager.default.url(for: .itemReplacementDirectory, in: .userDomainMask,
                                                    appropriateFor: bundleURL, create: true)
            let zip = stage.appendingPathComponent("update.zip"), sig = stage.appendingPathComponent("update.zip.sig")
            _ = try await UpdateDownload.fetch(signatureURL, to: sig) { _ in }
            _ = try await UpdateDownload.fetch(archive, to: zip) { fraction in
                Task { @MainActor [weak self] in self?.phase = .downloading(fraction) }
            }
            phase = .verifying
            let expectedID = Bundle.main.bundleIdentifier ?? "com.fastermatt.studytable.beta"
            let version = update.version
            let newApp = try await Task.detached {
                try AppUpdater.prepare(zip: zip, signature: sig, stage: stage, bundleID: expectedID, version: version)
            }.value
            phase = .restarting
            try Self.launchSwap(old: bundleURL, new: newApp, stage: stage, waitingFor: ProcessInfo.processInfo.processIdentifier)
            try? await Task.sleep(for: .milliseconds(300))
            NSApp.terminate(nil)
        } catch {
            phase = .failed(error.localizedDescription)
        }
    }

    // MARK: Pure steps (tested)

    static func newest(in data: Data, newerThan current: ReleaseVersion, includeBetas: Bool) throws -> AvailableUpdate? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let releases = try decoder.decode([GitHubRelease].self, from: data)
        let candidates = releases.compactMap { release -> (ReleaseVersion, GitHubRelease)? in
            guard !release.draft, includeBetas || !release.prerelease, let version = ReleaseVersion(release.tagName),
                  version > current else { return nil }
            return (version, release)
        }
        guard let (version, release) = candidates.max(by: { $0.0 < $1.0 }) else { return nil }
        let zip = release.assets.first { $0.name.hasSuffix(".zip") && !$0.name.contains("overnight") }
        let signature = zip.flatMap { zip in release.assets.first { $0.name == zip.name + ".sig" } }
        let trusted = zip.map { isTrusted($0.browserDownloadURL) } ?? false
            && signature.map { isTrusted($0.browserDownloadURL) } ?? false
        return AvailableUpdate(version: version.description, title: release.name ?? "Thruline Bible \(version)",
                               notes: release.body ?? "", page: release.htmlURL,
                               archive: trusted ? zip?.browserDownloadURL : nil,
                               signature: trusted ? signature?.browserDownloadURL : nil, size: zip?.size ?? 0)
    }

    nonisolated static func isTrusted(_ url: URL?) -> Bool {
        guard let url, url.scheme == "https", let host = url.host?.lowercased() else { return false }
        return trustedHosts.contains(host)
    }

    nonisolated static func sha256(of file: URL) throws -> Data {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty { hasher.update(data: chunk) }
        return Data(hasher.finalize())
    }

    nonisolated static func signatureIsValid(zip: URL, signature: String, publicKey: String = releasePublicKey) -> Bool {
        guard let raw = Data(base64Encoded: publicKey), let key = try? Curve25519.Signing.PublicKey(rawRepresentation: raw),
              let sig = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines)),
              let digest = try? sha256(of: zip) else { return false }
        return key.isValidSignature(sig, for: digest)
    }

    /// Why the running copy can't be replaced in place, or nil if it can.
    nonisolated static func replacementProblem(for app: URL) -> String? {
        if app.path.contains("/AppTranslocation/") {
            return "macOS is running Thruline from a temporary location. Drag Thruline into Applications, open it from there, and try again."
        }
        if !FileManager.default.isWritableFile(atPath: app.deletingLastPathComponent().path) {
            return "Thruline can\u{2019}t write to \(app.deletingLastPathComponent().path). Download the update from the release page instead."
        }
        return nil
    }

    /// Verifies the signature, unpacks, and checks the app inside. Returns the staged `.app`.
    nonisolated static func prepare(zip: URL, signature sigFile: URL, stage: URL, bundleID: String, version: String,
                                    publicKey: String = releasePublicKey, checkCodeSignature: Bool = true) throws -> URL {
        let signature = (try? String(contentsOf: sigFile, encoding: .utf8)) ?? ""
        guard signatureIsValid(zip: zip, signature: signature, publicKey: publicKey) else { throw AppUpdateError.badSignature }
        let unpacked = stage.appendingPathComponent("unpacked", isDirectory: true)
        try? FileManager.default.removeItem(at: unpacked)
        guard run("/usr/bin/ditto", ["-x", "-k", zip.path, unpacked.path]) == 0 else { throw AppUpdateError.badArchive("it could not be unpacked") }
        let apps = (FileManager.default.enumerator(at: unpacked, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])?
            .compactMap { $0 as? URL } ?? []).filter { $0.pathExtension == "app" && !$0.path.dropLast(4).contains(".app/") }
        guard apps.count == 1, let app = apps.first else { throw AppUpdateError.badArchive("expected one app in the download") }
        let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist"))
        guard info?["CFBundleIdentifier"] as? String == bundleID else { throw AppUpdateError.badArchive("it isn\u{2019}t Thruline") }
        guard let shipped = (info?["CFBundleShortVersionString"] as? String).flatMap(ReleaseVersion.init),
              let expected = ReleaseVersion(version), shipped == expected else {
            throw AppUpdateError.badArchive("its version doesn\u{2019}t match the release")
        }
        if checkCodeSignature, run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path]) != 0 {
            throw AppUpdateError.badArchive("its code signature is broken")
        }
        _ = run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", app.path])
        return app
    }

    /// Waits for this process to quit, moves the old app aside, moves the new one in under its own
    /// name (restoring the old one if that fails), reopens Thruline Bible and cleans up.
    nonisolated static let swapScript = """
    #!/bin/bash
    pid="$1"; old="$2"; new="$3"; stage="$4"; reopen="${5:-1}"; dest="${6:-$2}"
    for _ in $(seq 1 600); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
    if kill -0 "$pid" 2>/dev/null; then exit 2; fi
    backup="$stage/previous.app"
    if ! mv "$old" "$backup"; then [[ "$reopen" == 1 ]] && open "$old"; exit 3; fi
    if mv "$new" "$dest"; then rm -rf "$backup"; status=0; else mv "$backup" "$old"; dest="$old"; status=4; fi
    [[ "$reopen" == 1 ]] && open "$dest"
    rm -rf "$stage"
    exit $status
    """

    /// Where the new app goes: under its own (possibly renamed) bundle name next to the old one,
    /// unless something else already uses that name.
    nonisolated static func destination(replacing old: URL, with new: URL) -> URL {
        let renamed = old.deletingLastPathComponent().appendingPathComponent(new.lastPathComponent)
        return renamed == old || !FileManager.default.fileExists(atPath: renamed.path) ? renamed : old
    }

    @discardableResult
    nonisolated static func launchSwap(old: URL, new: URL, stage: URL, waitingFor pid: Int32, reopen: Bool = true) throws -> Process {
        let destination = destination(replacing: old, with: new)
        let script = stage.appendingPathComponent("swap.sh")
        try swapScript.write(to: script, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [script.path, String(pid), old.path, new.path, stage.path, reopen ? "1" : "0", destination.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try process.run()
        return process
    }

    @discardableResult
    nonisolated static func run(_ tool: String, _ arguments: [String]) -> Int32 {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return -1 }
        process.waitUntilExit()
        return process.terminationStatus
    }
}

// MARK: - Download with progress and a host allowlist

final class UpdateDownload: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    private let destination: URL
    private let progress: @Sendable (Double) -> Void
    private let lock = NSLock()
    private var continuation: CheckedContinuation<URL, Error>?
    private var failure: Error?
    private var finished = false

    private init(destination: URL, progress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.progress = progress
    }

    static func fetch(_ url: URL, to destination: URL, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        guard AppUpdater.isTrusted(url) else { throw AppUpdateError.untrustedLocation(url.host ?? url.absoluteString) }
        let delegate = UpdateDownload(destination: destination, progress: progress)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.timeoutIntervalForRequest = 60
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
        defer { session.finishTasksAndInvalidate() }
        return try await withCheckedThrowingContinuation { continuation in
            delegate.lock.withLock { delegate.continuation = continuation }
            session.downloadTask(with: url).resume()
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest) async -> URLRequest? {
        if AppUpdater.isTrusted(request.url) { return request }
        lock.withLock { failure = AppUpdateError.untrustedLocation(request.url?.host ?? "unknown") }
        return nil
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
                    totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64) {
        if totalBytesExpectedToWrite > 0 { progress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)) }
    }

    func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL) {
        let status = (downloadTask.response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200, AppUpdater.isTrusted(downloadTask.response?.url) else {
            lock.withLock { if failure == nil { failure = AppUpdateError.download("The server answered \(status).") } }
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
        } catch {
            lock.withLock { failure = error }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        let (continuation, failure) = lock.withLock { () -> (CheckedContinuation<URL, Error>?, Error?) in
            defer { self.continuation = nil; finished = true }
            return (self.continuation, self.failure ?? error)
        }
        if let failure { continuation?.resume(throwing: failure) } else { continuation?.resume(returning: destination) }
    }
}

// MARK: - Interface

/// The toolbar capsule that appears only when a newer version is waiting.
struct UpdateToolbarButton: View {
    @ObservedObject var updater: AppUpdater
    var body: some View {
        if updater.hasUpdate, let update = updater.update {
            Button { updater.showSheet = true } label: {
                Label("Update to \(update.version)", systemImage: "arrow.down.circle.fill")
                    .foregroundStyle(STColor.navy)
            }
            .navigationHelp("A newer Thruline Bible is available. Review what\u{2019}s new and update in one click.")
            .accessibilityLabel("Update available: version \(update.version)")
        }
    }
}

struct UpdateSheetModifier: ViewModifier {
    @ObservedObject var updater: AppUpdater
    func body(content: Content) -> some View {
        content.sheet(isPresented: $updater.showSheet) { UpdateSheet(updater: updater) }
    }
}

extension View {
    func updateSheet(_ updater: AppUpdater) -> some View { modifier(UpdateSheetModifier(updater: updater)) }
}

struct UpdateSheet: View {
    @ObservedObject var updater: AppUpdater
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 52, height: 52)
                VStack(alignment: .leading, spacing: 3) {
                    Text(headline).font(.system(size: 18, weight: .semibold))
                    Text(subhead).font(.callout).foregroundStyle(.secondary)
                }
            }
            if let update = updater.update, showsNotes {
                ScrollView {
                    Text(Self.notes(update.notes)).font(.callout).textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }
                .frame(minHeight: 140, maxHeight: 260)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 6))
            }
            progressArea
            HStack {
                if updater.phase == .available, updater.update != nil {
                    Button("Skip This Version") { updater.skipThisVersion() }
                }
                Spacer()
                buttons
            }
        }
        .padding(22)
        .frame(width: 520)
    }

    private var showsNotes: Bool {
        switch updater.phase { case .available, .downloading, .verifying, .failed: return true; default: return false }
    }

    private var headline: String {
        switch updater.phase {
        case .checking: return "Checking for updates\u{2026}"
        case .upToDate: return "Thruline Bible is up to date"
        case .restarting: return "Restarting Thruline Bible\u{2026}"
        case .failed: return updater.update == nil ? "Couldn\u{2019}t check for updates" : "The update didn\u{2019}t finish"
        default: return updater.update.map { "Thruline Bible \($0.version) is available" } ?? "Updates"
        }
    }

    private var subhead: String {
        switch updater.phase {
        case .upToDate: return "You have \(updater.versionText), the newest release."
        case .failed(let message): return message
        default:
            guard let update = updater.update else { return "You have \(updater.versionText)." }
            let size = update.size > 0 ? " \u{00B7} \(ByteCountFormatter.string(fromByteCount: Int64(update.size), countStyle: .file)) download" : ""
            return "You have \(updater.versionText)\(size). Your notes, layouts and downloads stay as they are."
        }
    }

    @ViewBuilder private var progressArea: some View {
        switch updater.phase {
        case .checking: ProgressView().controlSize(.small)
        case .downloading(let fraction):
            ProgressView(value: fraction) { Text("Downloading\u{2026} \(Int(fraction * 100))%").font(.caption) }
        case .verifying: ProgressView { Text("Checking the release signature\u{2026}").font(.caption) }
        case .restarting: ProgressView { Text("Thruline Bible will reopen in a moment.").font(.caption) }
        default:
            if let update = updater.update, !update.installable, updater.phase == .available {
                Text("This release was published without an update signature, so it has to be installed from the download page.")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder private var buttons: some View {
        switch updater.phase {
        case .available:
            Button("Later") { dismiss() }.keyboardShortcut(.cancelAction)
            if updater.update?.installable == true {
                Button("Update Now") { Task { await updater.install() } }.keyboardShortcut(.defaultAction)
            } else {
                Button("Open Download Page") { updater.openReleasePage() }.keyboardShortcut(.defaultAction)
            }
        case .failed:
            if updater.update != nil { Button("Open Download Page") { updater.openReleasePage() } }
            Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            Button("Try Again") { Task { updater.update == nil ? await updater.check(userInitiated: true) : await updater.install() } }
                .keyboardShortcut(.defaultAction)
        case .downloading, .verifying, .restarting:
            EmptyView()
        default:
            Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
        }
    }

    static func notes(_ markdown: String) -> AttributedString {
        let trimmed = markdown.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return AttributedString("No release notes were published for this version.") }
        return (try? AttributedString(markdown: trimmed, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(trimmed)
    }
}

/// The Updates section in Settings › About.
struct UpdateSettingsSection: View {
    @ObservedObject var updater: AppUpdater
    var body: some View {
        Section("Updates") {
            LabeledContent("Installed version", value: updater.versionText)
            Toggle("Check for updates automatically", isOn: $updater.checksAutomatically)
            Toggle("Include beta releases", isOn: $updater.includesBetas)
            HStack {
                Button("Check Now") { updater.checkFromMenu() }.disabled(!updater.canUpdate)
                Spacer()
                Link("All releases", destination: URL(string: "https://github.com/\(AppUpdater.repository)/releases")!)
            }
            Text("Thruline asks GitHub once a day whether a newer release exists. Updates are installed only after their signature matches Thruline\u{2019}s release key; nothing about your study is sent.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}
