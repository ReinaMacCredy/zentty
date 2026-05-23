import XCTest

@testable import Zentty

final class SettingsNavigationHistoryTests: XCTestCase {
    func test_initial_seed_has_no_back_or_forward() {
        let history = SettingsNavigationHistory(initial: .general)

        XCTAssertEqual(history.current, .general)
        XCTAssertFalse(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
    }

    func test_record_advances_current_and_enables_back() {
        var history = SettingsNavigationHistory(initial: .general)

        history.record(.appearance)

        XCTAssertEqual(history.current, .appearance)
        XCTAssertTrue(history.canGoBack)
        XCTAssertFalse(history.canGoForward)
    }

    func test_record_same_section_is_a_no_op() {
        var history = SettingsNavigationHistory(initial: .general)

        history.record(.general)

        XCTAssertEqual(history.entries, [.general])
        XCTAssertFalse(history.canGoBack)
    }

    func test_back_then_forward_returns_to_tip() {
        var history = SettingsNavigationHistory(initial: .general)
        history.record(.appearance)
        history.record(.shortcuts)

        XCTAssertEqual(history.goBack(), .appearance)
        XCTAssertEqual(history.goBack(), .general)
        XCTAssertFalse(history.canGoBack)
        XCTAssertTrue(history.canGoForward)

        XCTAssertEqual(history.goForward(), .appearance)
        XCTAssertEqual(history.goForward(), .shortcuts)
        XCTAssertFalse(history.canGoForward)
    }

    func test_back_at_start_returns_nil() {
        var history = SettingsNavigationHistory(initial: .general)

        XCTAssertNil(history.goBack())
        XCTAssertEqual(history.current, .general)
    }

    func test_forward_at_tip_returns_nil() {
        var history = SettingsNavigationHistory(initial: .general)
        history.record(.appearance)

        XCTAssertNil(history.goForward())
        XCTAssertEqual(history.current, .appearance)
    }

    func test_recording_after_going_back_truncates_forward_entries() {
        var history = SettingsNavigationHistory(initial: .general)
        history.record(.appearance)
        history.record(.shortcuts)

        _ = history.goBack() // back to appearance

        history.record(.notifications)

        XCTAssertEqual(history.entries, [.general, .appearance, .notifications])
        XCTAssertEqual(history.current, .notifications)
        XCTAssertFalse(history.canGoForward)
        XCTAssertTrue(history.canGoBack)
    }
}
