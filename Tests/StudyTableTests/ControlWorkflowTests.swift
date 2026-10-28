import SwiftUI
import XCTest
@testable import StudyTable

@MainActor
final class ControlWorkflowTests: XCTestCase {
    func testConsoleKeysRevealPanelsFromFocusAndToggleWithoutChangingPassage() {
        let state = makeOfflineState()
        let passage = state.passage
        state.focusMode = true
        state.showLibrary = false
        state.toggleConsoleLibrary()
        XCTAssertFalse(state.focusMode)
        XCTAssertTrue(state.showLibrary)
        state.toggleConsoleLibrary()
        XCTAssertFalse(state.showLibrary)
        state.focusMode = true
        state.showStudyDesk = false
        state.showNotes = false
        state.toggleConsoleNotes()
        XCTAssertFalse(state.focusMode)
        XCTAssertTrue(state.showStudyDesk)
        XCTAssertTrue(state.showNotes)
        state.toggleConsoleNotes()
        XCTAssertFalse(state.showNotes)
        state.focusMode = true
        state.toggleConsoleSources()
        XCTAssertFalse(state.focusMode)
        XCTAssertTrue(state.showStudyDesk)
        state.toggleConsoleSources()
        XCTAssertFalse(state.showStudyDesk)
        XCTAssertEqual(state.passage, passage)
    }

    func testWorkspacePresetsDoNotResetReadingOrTheme() {
        let state = makeOfflineState()
        state.fontSize = 24
        state.lineSpacing = 10
        state.theme = .dark
        state.focusMode = true
        state.applyPreset(.reading)
        XCTAssertFalse(state.focusMode)
        XCTAssertFalse(state.showLibrary)
        XCTAssertFalse(state.showStudyDesk)
        state.applyPreset(.study)
        XCTAssertTrue(state.showLibrary)
        XCTAssertTrue(state.showStudyDesk)
        XCTAssertTrue(state.showNotes)
        state.applyPreset(.research)
        XCTAssertTrue(state.showLibrary)
        XCTAssertTrue(state.showStudyDesk)
        XCTAssertFalse(state.showNotes)
        XCTAssertEqual(state.fontSize, 24)
        XCTAssertEqual(state.lineSpacing, 10)
        XCTAssertEqual(state.theme, .dark)
    }

    func testEverySourceBankCanBeDisabledAndRestoredWithoutChangingPassage() {
        let state = makeOfflineState()
        let passage = state.passage
        for bank in SourceTradition.allCases {
            state.selectedTraditions.insert(bank)
            state.toggleTradition(bank)
            XCTAssertFalse(state.selectedTraditions.contains(bank))
            state.toggleTradition(bank)
            XCTAssertTrue(state.selectedTraditions.contains(bank))
        }
        XCTAssertEqual(state.passage, passage)
    }

    func testReturningToSystemAppearanceRestoresDynamicScheme() {
        let state = makeOfflineState()
        state.switchAppearance(from: .dark)
        XCTAssertEqual(state.colorScheme, .light)
        state.theme = .system
        XCTAssertNil(state.colorScheme)
        state.switchAppearance(from: .light)
        XCTAssertEqual(state.colorScheme, .dark)
    }
}
