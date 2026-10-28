import SwiftUI
import XCTest
@testable import StudyTable

@MainActor
final class CustomizationTests: XCTestCase {
    private func state(_ defaults: UserDefaults) -> AppState {
        AppState(online: OnlineTranslationService(
            cache: OnlineChapterCache(directory: temporaryDirectory("custom-cache")),
            transport: { _ in throw URLError(.notConnectedToInternet) },
            idStore: BibleIDStore(defaultsKey: "test.ids.\(UUID().uuidString)"),
            keyReader: { _ in nil }), defaults: defaults, notes: ephemeralNotes())
    }

    func testOrderSurvivesRelaunchAndMovesWithinItsTab() {
        let defaults = ephemeralDefaults()
        let original = state(defaults)
        original.moveDeskSection(.compare, by: -1)
        original.moveDeskSection(.crossReferences, by: -1)
        let restored = state(defaults)
        XCTAssertEqual(original.deskSectionOrder, restored.deskSectionOrder)
        XCTAssertEqual(restored.deskSectionOrder.filter(\.isSourceBank), [.fathers, .reformed, .crossReferences, .exegetes])
        XCTAssertEqual(restored.deskSectionOrder.last, .peoplePlaces)
    }

    func testBankKeysAndCustomizationHaveOneVisibilityState() {
        let defaults = ephemeralDefaults()
        let original = state(defaults)
        original.setDeskSectionVisible(.fathers, false)
        XCTAssertFalse(original.selectedTraditions.contains(.fathers))
        original.toggleTradition(.fathers)
        XCTAssertTrue(original.isDeskSectionVisible(.fathers))
        original.setDeskSectionVisible(.originalLanguage, false)
        original.setDeskSectionVisible(.reformed, false)
        let restored = state(defaults)
        XCTAssertFalse(restored.visibleDeskSections.contains(.originalLanguage))
        XCTAssertFalse(restored.visibleDeskSections.contains(.reformed))
        restored.setDeskSectionVisible(.originalLanguage, true)
        XCTAssertTrue(restored.visibleDeskSections.contains(.originalLanguage))
    }

    func testOrderRepairsUnknownAndDuplicateSavedValues() {
        let defaults = ephemeralDefaults()
        defaults.set(["compare", "removedFeature", "compare", "fathers"], forKey: "desk.sectionOrder")
        let restored = state(defaults)
        XCTAssertEqual(restored.deskSectionOrder.first, .compare)
        XCTAssertEqual(Set(restored.deskSectionOrder), Set(StudyDeskSection.allCases))
        XCTAssertEqual(restored.deskSectionOrder.count, StudyDeskSection.allCases.count)
    }

    func testResetPreservesReadingPreferencesAndNotes() {
        let original = state(ephemeralDefaults())
        original.fontSize = 26
        original.lineSpacing = 12
        original.showLibrary = false
        original.setDeskSectionVisible(.compare, false)
        original.setDeskSectionVisible(.reformed, false)
        original.moveDeskSection(.dictionary, by: -1)
        original.resetDeskCustomization()
        XCTAssertEqual(original.visibleDeskSections, StudyDeskSection.allCases)
        XCTAssertEqual(original.fontSize, 26)
        XCTAssertEqual(original.lineSpacing, 12)
        XCTAssertFalse(original.showLibrary)
    }

    func testInjectedDefaultsIsolateAllWorkspacePreferences() {
        let firstDefaults = ephemeralDefaults()
        let first = state(firstDefaults)
        let second = state(ephemeralDefaults())
        first.theme = .dark
        first.fontSize = 29
        first.showLibrary = false
        first.showResearchTier = true
        XCTAssertEqual(firstDefaults.string(forKey: "theme"), AppTheme.dark.rawValue)
        XCTAssertEqual(firstDefaults.double(forKey: "fontSize"), 29)
        XCTAssertEqual(second.theme, .system)
        XCTAssertEqual(second.fontSize, 20)
        XCTAssertTrue(second.showLibrary)
        XCTAssertFalse(second.showResearchTier)
    }

    func testAppearanceKeySwitchesFromVisibleFinishAndPersists() {
        let defaults = ephemeralDefaults()
        let current = state(defaults)
        XCTAssertEqual(current.theme, .system)

        current.switchAppearance(from: .dark)
        XCTAssertEqual(current.theme, .light)
        XCTAssertEqual(current.colorScheme, .light)
        XCTAssertEqual(defaults.string(forKey: "theme"), AppTheme.light.rawValue)

        current.switchAppearance(from: .light)
        XCTAssertEqual(current.theme, .dark)
        XCTAssertEqual(current.colorScheme, .dark)
        XCTAssertEqual(state(defaults).theme, .dark)
    }
}
