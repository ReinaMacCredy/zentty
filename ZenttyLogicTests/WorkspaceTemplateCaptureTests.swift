import XCTest
@testable import Zentty

final class WorkspaceTemplateCaptureTests: XCTestCase {
    func test_lca_returns_common_ancestor_for_sibling_paths() {
        let lca = WorkspaceTemplateCapture.longestCommonAncestor(of: [
            "/Users/peter/proj/api/src",
            "/Users/peter/proj/web/src",
        ])
        XCTAssertEqual(lca, "/Users/peter/proj")
    }

    func test_lca_returns_full_path_for_single_input() {
        let lca = WorkspaceTemplateCapture.longestCommonAncestor(of: ["/Users/peter/proj"])
        XCTAssertEqual(lca, "/Users/peter/proj")
    }

    func test_lca_returns_nil_for_unrelated_paths() {
        let lca = WorkspaceTemplateCapture.longestCommonAncestor(of: [
            "/Users/peter/proj",
            "/var/log",
        ])
        XCTAssertNil(lca)
    }

    func test_lca_returns_nil_for_empty_input() {
        XCTAssertNil(WorkspaceTemplateCapture.longestCommonAncestor(of: []))
    }

    func test_capture_bookmark_records_per_pane_cwd_and_project_root() {
        let worklane = makeWorklane(
            panes: [
                paneFixture(id: "p1", cwd: "/Users/peter/proj/api", processName: "claude"),
                paneFixture(id: "p2", cwd: "/Users/peter/proj/web", processName: "zsh"),
            ],
            color: .blue
        )

        let template = WorkspaceTemplateCapture.capture(
            worklane: worklane,
            kind: .bookmark,
            name: "Demo"
        )

        XCTAssertEqual(template.kind, .bookmark)
        XCTAssertEqual(template.projectRoot, "/Users/peter/proj")
        XCTAssertEqual(template.color, "blue")
        XCTAssertEqual(template.allPanes.map(\.workingDirectory), [
            "/Users/peter/proj/api",
            "/Users/peter/proj/web",
        ])
        XCTAssertEqual(template.allPanes.map(\.command), ["claude", nil])
        XCTAssertEqual(template.allPanes.map(\.wasUserEdited), [false, false])
    }

    func test_capture_preset_strips_working_directories_and_project_root() {
        let worklane = makeWorklane(
            panes: [
                paneFixture(id: "p1", cwd: "/Users/peter/proj/api", processName: "claude"),
            ],
            color: nil
        )

        let template = WorkspaceTemplateCapture.capture(
            worklane: worklane,
            kind: .preset,
            name: "Claude pane"
        )

        XCTAssertEqual(template.kind, .preset)
        XCTAssertNil(template.projectRoot)
        XCTAssertEqual(template.allPanes.first?.workingDirectory, nil)
        XCTAssertEqual(template.allPanes.first?.command, "claude")
    }

    func test_capture_skips_shell_process_names() {
        for shell in ["zsh", "-zsh", "bash", "-bash", "fish"] {
            let worklane = makeWorklane(
                panes: [
                    paneFixture(id: "p1", cwd: "/Users/peter", processName: shell),
                ],
                color: nil
            )
            let template = WorkspaceTemplateCapture.capture(
                worklane: worklane,
                kind: .bookmark,
                name: "Test"
            )
            XCTAssertNil(template.allPanes.first?.command, "shell name '\(shell)' should not be captured as command")
        }
    }

    func test_capture_uses_remembered_title_as_title_seed_when_present() {
        let pane = paneFixture(id: "p1", cwd: "/Users/peter", processName: nil, rememberedTitle: "My favourite shell")
        let worklane = makeWorklane(panes: [pane], color: nil)
        let template = WorkspaceTemplateCapture.capture(worklane: worklane, kind: .bookmark, name: "Test")
        XCTAssertEqual(template.allPanes.first?.titleSeed, "My favourite shell")
    }

    private struct PaneFixture {
        let pane: PaneState
        let auxiliary: PaneAuxiliaryState
    }

    private func paneFixture(
        id: String,
        cwd: String,
        processName: String?,
        rememberedTitle: String? = nil
    ) -> PaneFixture {
        let paneID = PaneID(id)
        let pane = PaneState(
            id: paneID,
            title: "shell",
            sessionRequest: TerminalSessionRequest(workingDirectory: cwd)
        )
        let metadata = TerminalMetadata(
            title: nil,
            currentWorkingDirectory: cwd,
            processName: processName,
            gitBranch: nil
        )
        var presentation = PanePresentationState()
        presentation.cwd = cwd
        presentation.rememberedTitle = rememberedTitle
        let auxiliary = PaneAuxiliaryState(
            metadata: metadata,
            presentation: presentation
        )
        return PaneFixture(pane: pane, auxiliary: auxiliary)
    }

    private func makeWorklane(
        panes: [PaneFixture],
        color: WorklaneColor?
    ) -> WorklaneState {
        let columns = panes.enumerated().map { index, fixture in
            PaneColumnState(
                id: PaneColumnID("c\(index)"),
                panes: [fixture.pane],
                width: fixture.pane.width,
                focusedPaneID: fixture.pane.id,
                lastFocusedPaneID: fixture.pane.id
            )
        }
        let auxiliary = Dictionary(uniqueKeysWithValues: panes.map { fixture in
            (fixture.pane.id, fixture.auxiliary)
        })
        return WorklaneState(
            id: WorklaneID("w1"),
            title: "",
            paneStripState: PaneStripState(columns: columns),
            nextPaneNumber: 1,
            auxiliaryStateByPaneID: auxiliary,
            color: color
        )
    }
}
