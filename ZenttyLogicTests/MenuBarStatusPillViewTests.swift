import AppKit
import XCTest
@testable import Zentty

@MainActor
final class MenuBarStatusPillViewTests: AppKitTestCase {
    func test_each_kind_resolves_palette_colors_for_light_appearance() {
        let aqua = NSAppearance(named: .aqua)

        for kind in MenuBarStatusKind.allCases {
            let pill = makePill()
            pill.configure(
                kind: kind,
                text: "Running",
                taskProgress: nil,
                appearance: aqua,
                reduceTransparency: false
            )

            let snapshot = pill.debugSnapshotForTesting
            XCTAssertEqual(snapshot.kind, kind)
            XCTAssertEqual(snapshot.labelText, "Running")

            assertColor(
                snapshot.labelColor,
                equals: MenuBarStatusPalette.labelColor(for: kind, isDark: false)
            )
            assertColor(
                snapshot.fillColor,
                equals: MenuBarStatusPalette.fillColor(for: kind, isDark: false, reduceTransparency: false)
            )
            assertColor(
                snapshot.borderColor,
                equals: MenuBarStatusPalette.borderColor(for: kind, isDark: false, reduceTransparency: false)
            )
            assertColor(
                snapshot.dotColor,
                equals: MenuBarStatusPalette.dotColor(for: kind, isDark: false)
            )
        }
    }

    func test_dark_appearance_resolves_dark_label_variant() {
        let darkAqua = NSAppearance(named: .darkAqua)
        let pill = makePill()

        pill.configure(
            kind: .running,
            text: "Running",
            taskProgress: nil,
            appearance: darkAqua,
            reduceTransparency: false
        )

        assertColor(
            pill.debugSnapshotForTesting.labelColor,
            equals: MenuBarStatusPalette.labelColor(for: .running, isDark: true)
        )
    }

    func test_progress_visibility_tracks_task_progress() throws {
        let aqua = NSAppearance(named: .aqua)
        let pill = makePill()

        pill.configure(
            kind: .running,
            text: "Running",
            taskProgress: nil,
            appearance: aqua,
            reduceTransparency: false
        )
        XCTAssertFalse(pill.debugSnapshotForTesting.isProgressVisible)

        let progress = try XCTUnwrap(PaneAgentTaskProgress(doneCount: 2, totalCount: 5))
        pill.configure(
            kind: .running,
            text: "Running",
            taskProgress: progress,
            appearance: aqua,
            reduceTransparency: false
        )
        XCTAssertTrue(pill.debugSnapshotForTesting.isProgressVisible)
    }

    func test_intrinsic_width_grows_with_label_length() {
        let aqua = NSAppearance(named: .aqua)

        let shortPill = makePill()
        shortPill.configure(
            kind: .running,
            text: "Go",
            taskProgress: nil,
            appearance: aqua,
            reduceTransparency: false
        )

        let longPill = makePill()
        longPill.configure(
            kind: .running,
            text: "Running a very long status label",
            taskProgress: nil,
            appearance: aqua,
            reduceTransparency: false
        )

        XCTAssertGreaterThan(shortPill.debugSnapshotForTesting.intrinsicSize.width, 0)
        XCTAssertGreaterThan(
            longPill.debugSnapshotForTesting.intrinsicSize.width,
            shortPill.debugSnapshotForTesting.intrinsicSize.width
        )
    }

    func test_reduce_transparency_bumps_fill_alpha() throws {
        let aqua = NSAppearance(named: .aqua)

        let normalPill = makePill()
        normalPill.configure(
            kind: .running,
            text: "Running",
            taskProgress: nil,
            appearance: aqua,
            reduceTransparency: false
        )

        let reducedPill = makePill()
        reducedPill.configure(
            kind: .running,
            text: "Running",
            taskProgress: nil,
            appearance: aqua,
            reduceTransparency: true
        )

        let normalAlpha = try XCTUnwrap(normalPill.debugSnapshotForTesting.fillColor).srgbClamped.alphaComponent
        let reducedAlpha = try XCTUnwrap(reducedPill.debugSnapshotForTesting.fillColor).srgbClamped.alphaComponent

        XCTAssertGreaterThan(reducedAlpha, normalAlpha)
    }

    // MARK: - Helpers

    private func makePill() -> MenuBarStatusPillView {
        MenuBarStatusPillView(frame: NSRect(x: 0, y: 0, width: 200, height: 18))
    }

    private func assertColor(
        _ actual: NSColor?,
        equals expected: NSColor,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        guard let actual else {
            XCTFail("Expected a color but got nil", file: file, line: line)
            return
        }

        let lhs = actual.srgbClamped
        let rhs = expected.srgbClamped
        XCTAssertEqual(lhs.redComponent, rhs.redComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(lhs.greenComponent, rhs.greenComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(lhs.blueComponent, rhs.blueComponent, accuracy: 0.001, file: file, line: line)
        XCTAssertEqual(lhs.alphaComponent, rhs.alphaComponent, accuracy: 0.001, file: file, line: line)
    }
}
