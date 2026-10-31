import CryptoKit
import SwiftUI
import XCTest
@testable import StudyTable

final class AppUpdaterTests: XCTestCase {
    private var temp: URL!

    override func setUpWithError() throws {
        temp = FileManager.default.temporaryDirectory.appendingPathComponent("tl-updater-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: temp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: temp) }

    func testVersionOrdering() throws {
        let v = { (s: String) in try XCTUnwrap(ReleaseVersion(s)) }
        XCTAssertLessThan(try v("0.21.0"), try v("v0.22.0"))
        XCTAssertLessThan(try v("0.9.9"), try v("0.10.0"))
        XCTAssertLessThan(try v("0.23.0-beta.2"), try v("0.23.0"))
        XCTAssertLessThan(try v("0.23.0-beta.2"), try v("0.23.0-beta.10"))
        XCTAssertEqual(try v("0.22"), try v("0.22.0"))
        XCTAssertNil(ReleaseVersion("latest"))
        XCTAssertEqual(try v("v1.2.3-rc.1").description, "1.2.3-rc.1")
    }

    private func releasesJSON() -> Data {
        func release(_ tag: String, pre: Bool = true, draft: Bool = false, signed: Bool = true, host: String = "github.com") -> String {
            let zip = "Thruline-Bible-\(tag.dropFirst()).zip"
            let base = "https://\(host)/fastermatt/thruline-bible/releases/download/\(tag)/"
            var assets = ["{\"name\":\"\(zip)\",\"size\":109000000,\"browser_download_url\":\"\(base)\(zip)\"}",
                          "{\"name\":\"\(zip).sha256\",\"size\":94,\"browser_download_url\":\"\(base)\(zip).sha256\"}"]
            if signed { assets.append("{\"name\":\"\(zip).sig\",\"size\":89,\"browser_download_url\":\"\(base)\(zip).sig\"}") }
            return """
            {"tag_name":"\(tag)","name":"Thruline \(tag)","body":"**New** things","draft":\(draft),"prerelease":\(pre),
             "html_url":"https://github.com/fastermatt/thruline-bible/releases/tag/\(tag)","published_at":"2026-10-31T04:26:40Z",
             "assets":[\(assets.joined(separator: ","))]}
            """
        }
        return Data("[\(release("v0.24.0", draft: true)),\(release("v0.23.0")),\(release("v0.22.1", pre: false)),\(release("v0.21.0", signed: false))]".utf8)
    }

    @MainActor func testPicksNewestPublishedRelease() throws {
        let current = try XCTUnwrap(ReleaseVersion("0.22.0"))
        let update = try XCTUnwrap(AppUpdater.newest(in: releasesJSON(), newerThan: current, includeBetas: true))
        XCTAssertEqual(update.version, "0.23.0", "drafts are ignored")
        XCTAssertTrue(update.installable)
        XCTAssertEqual(update.signature?.lastPathComponent, "Thruline-Bible-0.23.0.zip.sig")
        let stable = try XCTUnwrap(AppUpdater.newest(in: releasesJSON(), newerThan: current, includeBetas: false))
        XCTAssertEqual(stable.version, "0.22.1", "betas are skipped when the reader turns them off")
        XCTAssertNil(try AppUpdater.newest(in: releasesJSON(), newerThan: try XCTUnwrap(ReleaseVersion("0.23.0")), includeBetas: true))
    }

    @MainActor func testUnsignedReleaseIsManualOnly() throws {
        let update = try XCTUnwrap(AppUpdater.newest(in: releasesJSON(), newerThan: try XCTUnwrap(ReleaseVersion("0.20.0")), includeBetas: true))
        XCTAssertEqual(update.version, "0.23.0")
        let old = """
        [{"tag_name":"v0.21.0","name":null,"body":null,"draft":false,"prerelease":true,"html_url":"https://github.com/x/y","published_at":null,
          "assets":[{"name":"Thruline-Bible-0.21.0.zip","size":1,"browser_download_url":"https://github.com/x/y/a.zip"}]}]
        """
        let manual = try XCTUnwrap(AppUpdater.newest(in: Data(old.utf8), newerThan: try XCTUnwrap(ReleaseVersion("0.20.0")), includeBetas: true))
        XCTAssertFalse(manual.installable, "no .sig asset means the reader is sent to the download page")
    }

    func testOnlyGitHubHostsOverHTTPSAreTrusted() {
        XCTAssertTrue(AppUpdater.isTrusted(URL(string: "https://github.com/fastermatt/thruline-bible/releases/download/v1/a.zip")))
        XCTAssertTrue(AppUpdater.isTrusted(URL(string: "https://release-assets.githubusercontent.com/x")))
        XCTAssertFalse(AppUpdater.isTrusted(URL(string: "http://github.com/a.zip")))
        XCTAssertFalse(AppUpdater.isTrusted(URL(string: "https://github.com.evil.example/a.zip")))
        XCTAssertFalse(AppUpdater.isTrusted(URL(string: "https://example.com/a.zip")))
    }

    func testEmbeddedPublicKeyIsUsable() throws {
        let raw = try XCTUnwrap(Data(base64Encoded: AppUpdater.releasePublicKey))
        XCTAssertNoThrow(try Curve25519.Signing.PublicKey(rawRepresentation: raw))
    }

    /// Builds `Thruline Bible.app` with the given identity, zips it like package-app.sh does, signs the ZIP.
    private func makeRelease(bundleID: String = "com.fastermatt.studytable.beta", version: String = "0.23.0",
                             key: Curve25519.Signing.PrivateKey) throws -> (zip: URL, sig: URL) {
        let root = temp.appendingPathComponent("build-\(UUID().uuidString)")
        let contents = root.appendingPathComponent("Thruline Bible/Thruline Bible.app/Contents")
        try FileManager.default.createDirectory(at: contents.appendingPathComponent("MacOS"), withIntermediateDirectories: true)
        let plist: NSDictionary = ["CFBundleIdentifier": bundleID, "CFBundleShortVersionString": version, "CFBundlePackageType": "APPL"]
        plist.write(to: contents.appendingPathComponent("Info.plist"), atomically: true)
        try Data("notes".utf8).write(to: root.appendingPathComponent("Thruline Bible/Start Here.md"))
        let zip = temp.appendingPathComponent("release-\(UUID().uuidString).zip")
        XCTAssertEqual(AppUpdater.run("/usr/bin/ditto", ["-c", "-k", "--sequesterRsrc", root.appendingPathComponent("Thruline Bible").path, zip.path]), 0)
        let sig = zip.appendingPathExtension("sig")
        try key.signature(for: AppUpdater.sha256(of: zip)).base64EncodedString().write(to: sig, atomically: true, encoding: .utf8)
        return (zip, sig)
    }

    func testPrepareAcceptsSignedMatchingRelease() throws {
        let key = Curve25519.Signing.PrivateKey()
        let release = try makeRelease(key: key)
        XCTAssertTrue(AppUpdater.signatureIsValid(zip: release.zip, signature: try String(contentsOf: release.sig, encoding: .utf8),
                                                  publicKey: key.publicKey.rawRepresentation.base64EncodedString()))
        let app = try AppUpdater.prepare(zip: release.zip, signature: release.sig, stage: temp, bundleID: "com.fastermatt.studytable.beta",
                                         version: "0.23.0", publicKey: key.publicKey.rawRepresentation.base64EncodedString(),
                                         checkCodeSignature: false)
        XCTAssertEqual(app.lastPathComponent, "Thruline Bible.app")
    }

    func testPrepareRejectsWrongKeyTamperingIdentityAndVersion() throws {
        let key = Curve25519.Signing.PrivateKey(), publicKey = key.publicKey.rawRepresentation.base64EncodedString()
        let release = try makeRelease(key: key)
        func prepare(_ zip: URL, _ sig: URL, id: String = "com.fastermatt.studytable.beta", version: String = "0.23.0", key: String) throws {
            _ = try AppUpdater.prepare(zip: zip, signature: sig, stage: temp, bundleID: id, version: version, publicKey: key, checkCodeSignature: false)
        }
        // Signed by someone else.
        XCTAssertThrowsError(try prepare(release.zip, release.sig, key: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()))
        // The embedded production key never accepts a test-signed archive.
        XCTAssertThrowsError(try prepare(release.zip, release.sig, key: AppUpdater.releasePublicKey))
        // One byte changed after signing.
        var bytes = try Data(contentsOf: release.zip); bytes[bytes.count / 2] ^= 0xFF
        let tampered = temp.appendingPathComponent("tampered.zip"); try bytes.write(to: tampered)
        XCTAssertThrowsError(try prepare(tampered, release.sig, key: publicKey))
        // Correctly signed, but not Thruline, or not the advertised version.
        let impostor = try makeRelease(bundleID: "com.example.other", key: key)
        XCTAssertThrowsError(try prepare(impostor.zip, impostor.sig, key: publicKey))
        XCTAssertThrowsError(try prepare(release.zip, release.sig, version: "0.24.0", key: publicKey))
    }

    func testSwapScriptReplacesAppAfterProcessExits() throws {
        let old = temp.appendingPathComponent("Applications/Thruline Bible.app"), stage = temp.appendingPathComponent("stage")
        let new = stage.appendingPathComponent("unpacked/Thruline Bible.app")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        try Data("old".utf8).write(to: old.appendingPathComponent("marker"))
        try Data("new".utf8).write(to: new.appendingPathComponent("marker"))
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep"); sleeper.arguments = ["0.6"]
        try sleeper.run()
        let swap = try AppUpdater.launchSwap(old: old, new: new, stage: stage, waitingFor: sleeper.processIdentifier, reopen: false)
        Thread.sleep(forTimeInterval: 0.2)
        XCTAssertEqual(try String(contentsOf: old.appendingPathComponent("marker"), encoding: .utf8), "old", "waits for the app to quit")
        swap.waitUntilExit()
        XCTAssertEqual(swap.terminationStatus, 0)
        XCTAssertEqual(try String(contentsOf: old.appendingPathComponent("marker"), encoding: .utf8), "new")
        XCTAssertFalse(FileManager.default.fileExists(atPath: stage.path), "staging is cleaned up")
    }

    func testRenamedAppReplacesTheOldThroughlineCopy() throws {
        let apps = temp.appendingPathComponent("Applications"), stage = temp.appendingPathComponent("stage")
        let old = apps.appendingPathComponent("Throughline.app"), new = stage.appendingPathComponent("unpacked/Thruline Bible.app")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: new, withIntermediateDirectories: true)
        try Data("new".utf8).write(to: new.appendingPathComponent("marker"))
        let swap = try AppUpdater.launchSwap(old: old, new: new, stage: stage, waitingFor: 999_999, reopen: false)
        swap.waitUntilExit()
        XCTAssertEqual(swap.terminationStatus, 0)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path), "the old name is gone")
        XCTAssertEqual(try String(contentsOf: apps.appendingPathComponent("Thruline Bible.app/marker"), encoding: .utf8), "new")
        // If something else already has the new name, the update keeps the old location instead.
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        XCTAssertEqual(AppUpdater.destination(replacing: old, with: new), old)
    }

    func testTranslocatedAppIsNotReplacedInPlace() {
        XCTAssertNotNil(AppUpdater.replacementProblem(for: URL(fileURLWithPath: "/private/var/folders/x/AppTranslocation/ABC/d/Thruline Bible.app")))
        XCTAssertNil(AppUpdater.replacementProblem(for: temp.appendingPathComponent("Thruline Bible.app")))
    }

    @MainActor func testDevelopmentBuildNeverChecksOrInstalls() async throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "tl-updater-\(UUID().uuidString)"))
        let updater = AppUpdater(defaults: defaults)
        XCTAssertFalse(updater.canUpdate, "the test runner is not a packaged app")
        XCTAssertTrue(updater.checksAutomatically)
        XCTAssertTrue(updater.includesBetas)
        await updater.check(userInitiated: true)
        guard case .failed = updater.phase else { return XCTFail("expected a plain explanation, got \(updater.phase)") }
        XCTAssertNil(defaults.object(forKey: "updates.lastCheck"), "no network request was made")
    }

    /// STUDYTABLE_SNAPSHOT_DIR=… renders the update sheet and toolbar button in light and dark.
    @MainActor func testSnapshotUpdateSheet() throws {
        guard let output = ProcessInfo.processInfo.environment["STUDYTABLE_SNAPSHOT_DIR"] else { throw XCTSkip("Offscreen capture is opt-in") }
        let defaults = try XCTUnwrap(UserDefaults(suiteName: "tl-updater-\(UUID().uuidString)"))
        let updater = AppUpdater(defaults: defaults)
        let update = AvailableUpdate(version: "0.23.0", title: "Thruline 0.23.0",
            notes: "**Faster search.** Library search now answers in a fraction of a second.\n\n- Detached windows reopen with your layout\n- 19 downloadable Bibles\n- One-click updates",
            page: URL(string: "https://github.com/fastermatt/thruline-bible/releases")!,
            archive: URL(string: "https://github.com/a.zip"), signature: URL(string: "https://github.com/a.zip.sig"), size: 109_708_787)
        for (phase, name) in [(AppUpdater.Phase.available, "available"), (.downloading(0.42), "downloading")] {
            updater.stage(update, phase: phase)
            for dark in [false, true] {
                let view = VStack(spacing: 0) {
                    HStack { Spacer(); UpdateToolbarButton(updater: updater).buttonStyle(WorkspaceActionStyle()).font(.system(size: 12, weight: .medium)) }
                        .padding(12).background(STColor.tileBottom)
                    UpdateSheet(updater: updater)
                }.frame(width: 520).background(Color(nsColor: .windowBackgroundColor))
                let host = NSHostingView(rootView: view)
                host.frame = NSRect(origin: .zero, size: host.fittingSize)
                host.appearance = NSAppearance(named: dark ? .darkAqua : .aqua)
                let window = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
                window.appearance = host.appearance; window.contentView = host
                window.setFrameOrigin(NSPoint(x: -20000, y: -20000)); window.orderBack(nil)
                defer { window.orderOut(nil) }
                RunLoop.main.run(until: Date().addingTimeInterval(0.4))
                let rep = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: rep)
                try XCTUnwrap(rep.representation(using: .png, properties: [:]))
                    .write(to: URL(fileURLWithPath: output).appendingPathComponent("update-\(name)-\(dark ? "dark" : "light").png"))
            }
        }
    }

    /// THRULINE_RELEASE_ZIP=Releases/….zip (with its .sig) runs the real install path into a temp
    /// folder: production key, real code-signature check, the swap helper.
    func testRealReleaseArchiveInstallsIntoTemporaryFolder() throws {
        guard let path = ProcessInfo.processInfo.environment["THRULINE_RELEASE_ZIP"] else { throw XCTSkip("Opt-in release check") }
        let zip = URL(fileURLWithPath: path), sig = URL(fileURLWithPath: path + ".sig")
        let version = zip.deletingPathExtension().lastPathComponent.replacingOccurrences(of: "Thruline-Bible-", with: "")
        let stage = temp.appendingPathComponent("stage")
        try FileManager.default.createDirectory(at: stage, withIntermediateDirectories: true)
        let app = try AppUpdater.prepare(zip: zip, signature: sig, stage: stage, bundleID: "com.fastermatt.studytable.beta", version: version)
        let installed = temp.appendingPathComponent("Applications/Thruline Bible.app")
        try FileManager.default.createDirectory(at: installed, withIntermediateDirectories: true)
        let swap = try AppUpdater.launchSwap(old: installed, new: app, stage: stage, waitingFor: 999_999, reopen: false)
        swap.waitUntilExit()
        XCTAssertEqual(swap.terminationStatus, 0)
        XCTAssertEqual(AppUpdater.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", installed.path]), 0)
        let info = NSDictionary(contentsOf: installed.appendingPathComponent("Contents/Info.plist"))
        XCTAssertEqual(info?["CFBundleShortVersionString"] as? String, version)
    }
}
