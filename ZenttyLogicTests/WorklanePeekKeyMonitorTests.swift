import XCTest
@testable import Zentty

@MainActor
final class WorklanePeekKeyMonitorTests: XCTestCase {

    private func makeInstalledMonitor() -> WorklanePeekKeyMonitor {
        let monitor = WorklanePeekKeyMonitor()
        monitor.install()
        return monitor
    }

    func test_processFlagsChanged_emits_release_only_on_down_to_up_transition() {
        let monitor = makeInstalledMonitor()
        defer { monitor.uninstall() }

        // Right after install, Ctrl is presumed down. Letting it go fires.
        let release = monitor.processFlagsChanged(.init(containsControl: false))
        XCTAssertEqual(release, .ctrlReleased)

        // Subsequent flagsChanged events without Ctrl re-down don't refire.
        XCTAssertNil(monitor.processFlagsChanged(.init(containsControl: false)))
    }

    func test_processFlagsChanged_does_not_fire_for_other_modifier_changes_while_ctrl_held() {
        let monitor = makeInstalledMonitor()
        defer { monitor.uninstall() }

        // Shift goes up/down with Ctrl still held — no release should fire.
        XCTAssertNil(monitor.processFlagsChanged(.init(containsControl: true)))
        XCTAssertNil(monitor.processFlagsChanged(.init(containsControl: true)))
    }

    func test_processFlagsChanged_redown_then_release_fires_again() {
        let monitor = makeInstalledMonitor()
        defer { monitor.uninstall() }

        XCTAssertEqual(
            monitor.processFlagsChanged(.init(containsControl: false)),
            .ctrlReleased
        )
        // Ctrl pressed again
        XCTAssertNil(monitor.processFlagsChanged(.init(containsControl: true)))
        // ...and released again
        XCTAssertEqual(
            monitor.processFlagsChanged(.init(containsControl: false)),
            .ctrlReleased
        )
    }

    func test_install_seeds_ctrl_down_so_first_release_fires() {
        let monitor = WorklanePeekKeyMonitor()
        monitor.install()
        defer { monitor.uninstall() }

        // No prior call — first flagsChanged with no Ctrl should fire.
        XCTAssertEqual(
            monitor.processFlagsChanged(.init(containsControl: false)),
            .ctrlReleased
        )
    }

    func test_uninstall_then_reinstall_resets_state() {
        let monitor = WorklanePeekKeyMonitor()
        monitor.install()
        _ = monitor.processFlagsChanged(.init(containsControl: false))
        monitor.uninstall()

        // Re-install for a fresh gesture.
        monitor.install()
        defer { monitor.uninstall() }
        XCTAssertEqual(
            monitor.processFlagsChanged(.init(containsControl: false)),
            .ctrlReleased
        )
    }

    func test_mouse_down_is_emitted_and_consumed_while_monitor_is_installed() {
        let monitor = makeInstalledMonitor()
        defer { monitor.uninstall() }

        let event = monitor.processMouseEvent(
            .init(kind: .down, locationInWindow: CGPoint(x: 42, y: 24))
        )

        XCTAssertEqual(event, .mouseDown(locationInWindow: CGPoint(x: 42, y: 24)))
    }

    func test_mouse_drag_and_up_are_consumed_without_selecting_pane() {
        let monitor = makeInstalledMonitor()
        defer { monitor.uninstall() }

        XCTAssertEqual(
            monitor.processMouseEvent(.init(kind: .dragged, locationInWindow: .zero)),
            .mouseDragged
        )
        XCTAssertEqual(
            monitor.processMouseEvent(.init(kind: .up, locationInWindow: .zero)),
            .mouseUp
        )
    }

    func test_precise_scroll_emits_spatial_swipe_after_threshold() {
        let monitor = makeInstalledMonitor()
        defer { monitor.uninstall() }

        let partial = MockPeekScrollEvent(
            scrollingDeltaX: 20,
            scrollingDeltaY: 0,
            phase: .began
        )
        XCTAssertNil(monitor.processScrollEvent(partial.asNSEvent))

        let threshold = MockPeekScrollEvent(
            scrollingDeltaX: 45,
            scrollingDeltaY: 0,
            phase: .changed
        )
        XCTAssertEqual(monitor.processScrollEvent(threshold.asNSEvent), .spatialSwipe(.right))
    }

    func test_precise_scroll_requires_fresh_begin_after_triggered_gesture_ends() {
        let monitor = makeInstalledMonitor()
        defer { monitor.uninstall() }

        XCTAssertEqual(
            monitor.processScrollEvent(MockPeekScrollEvent(
                scrollingDeltaX: 45,
                scrollingDeltaY: 0,
                phase: .began
            ).asNSEvent),
            .spatialSwipe(.right)
        )
        XCTAssertNil(monitor.processScrollEvent(MockPeekScrollEvent(
            scrollingDeltaX: 0,
            scrollingDeltaY: 0,
            phase: .ended
        ).asNSEvent))

        XCTAssertNil(monitor.processScrollEvent(MockPeekScrollEvent(
            scrollingDeltaX: 80,
            scrollingDeltaY: 0,
            phase: .changed
        ).asNSEvent))
    }

    func test_processKeyDown_emits_arrow_only_while_ctrl_is_held_and_peeking() {
        let monitor = WorklanePeekKeyMonitor()

        XCTAssertEqual(
            monitor.processKeyDown(.init(keyCode: 123, containsControl: true, containsShift: false, isPeeking: true)),
            .spatialSwipe(.left)
        )
        XCTAssertEqual(
            monitor.processKeyDown(.init(keyCode: 124, containsControl: true, containsShift: false, isPeeking: true)),
            .spatialSwipe(.right)
        )
        XCTAssertEqual(
            monitor.processKeyDown(.init(keyCode: 126, containsControl: true, containsShift: false, isPeeking: true)),
            .spatialSwipe(.up)
        )
        XCTAssertEqual(
            monitor.processKeyDown(.init(keyCode: 125, containsControl: true, containsShift: false, isPeeking: true)),
            .spatialSwipe(.down)
        )
    }

    func test_processKeyDown_passes_arrows_outside_peek_or_without_ctrl() {
        let monitor = WorklanePeekKeyMonitor()

        XCTAssertNil(monitor.processKeyDown(.init(keyCode: 123, containsControl: false, containsShift: false, isPeeking: true)))
        XCTAssertNil(monitor.processKeyDown(.init(keyCode: 123, containsControl: true, containsShift: false, isPeeking: false)))
    }
}

private struct MockPeekScrollEvent {
    let scrollingDeltaX: CGFloat
    let scrollingDeltaY: CGFloat
    let phase: NSEvent.Phase
    var momentumPhase: NSEvent.Phase = []

    var asNSEvent: NSEvent {
        let cgEvent = CGEvent(
            scrollWheelEvent2Source: nil,
            units: .pixel,
            wheelCount: 2,
            wheel1: Int32(scrollingDeltaY),
            wheel2: Int32(scrollingDeltaX),
            wheel3: 0
        )!
        cgEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis2, value: Double(scrollingDeltaX))
        cgEvent.setDoubleValueField(.scrollWheelEventPointDeltaAxis1, value: Double(scrollingDeltaY))
        cgEvent.setIntegerValueField(.scrollWheelEventScrollPhase, value: Int64(phase.rawValue))
        cgEvent.setIntegerValueField(.scrollWheelEventMomentumPhase, value: Int64(momentumPhase.rawValue))
        return NSEvent(cgEvent: cgEvent)!
    }
}
