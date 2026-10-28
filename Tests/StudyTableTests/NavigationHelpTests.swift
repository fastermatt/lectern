import XCTest
@testable import StudyTable

final class NavigationHelpTests: XCTestCase {
    func testNavigationHelpDefaultsOnAndCanBePersistentlyDisabled() {
        let suiteName = "NavigationHelpTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        XCTAssertTrue(NavigationHelpPreference.defaultValue)
        XCTAssertNil(defaults.object(forKey: NavigationHelpPreference.key))

        defaults.set(false, forKey: NavigationHelpPreference.key)
        XCTAssertFalse(defaults.bool(forKey: NavigationHelpPreference.key))
        XCTAssertFalse(UserDefaults(suiteName: suiteName)!.bool(forKey: NavigationHelpPreference.key))
    }

}
