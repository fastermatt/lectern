import Foundation

/// Finds bundled resources in both the SwiftPM layout (`swift run`, tests) and the
/// packaged `.app` layout, and the user's writable data folders.
enum AppResources {
    /// Root of the resource bundle, resolved once.
    static let root: URL? = resolveRoot(mainResourceURL: Bundle.main.resourceURL) ?? Bundle.module.resourceURL

    /// Locates `StudyTable_StudyTable.bundle` inside an app's Resources folder. Handles both the
    /// macOS-style nested layout (`…/Contents/Resources`) and a flat bundle directory.
    static func resolveRoot(mainResourceURL: URL?) -> URL? {
        guard let packaged = mainResourceURL?.appendingPathComponent("StudyTable_StudyTable.bundle"),
              FileManager.default.fileExists(atPath: packaged.path) else { return nil }
        let nested = packaged.appendingPathComponent("Contents/Resources")
        return FileManager.default.fileExists(atPath: nested.path) ? nested : packaged
    }

    static func url(_ relativePath: String) -> URL? {
        guard let url = root?.appendingPathComponent(relativePath),
              FileManager.default.fileExists(atPath: url.path) else { return nil }
        return url
    }

    /// `~/Library/Application Support/StudyTable`
    static var supportDirectory: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StudyTable", isDirectory: true)
    }

    /// Licensed translation packs the user has installed (same format as bundled packs).
    static var userTranslationsDirectory: URL {
        supportDirectory.appendingPathComponent("Translations", isDirectory: true)
    }

    /// Reviewer's local Westminster link file, merged over the shipped store.
    static var localConfessionLinks: URL {
        supportDirectory.appendingPathComponent("wcf-links.local.json")
    }

    static var onlineCacheDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("StudyTable/Online", isDirectory: true)
    }
}
