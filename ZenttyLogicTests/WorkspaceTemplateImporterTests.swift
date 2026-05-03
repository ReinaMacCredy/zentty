import XCTest
@testable import Zentty

final class WorkspaceTemplateImporterTests: XCTestCase {
    private var temporaryDirectoryURL: URL!

    override func setUpWithError() throws {
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZenttyTests.WorkspaceTemplateImporter.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
    }

    func test_imports_bookmark_with_runnable_command_as_command_field() {
        let template = makeTemplate(
            kind: .bookmark,
            panes: [
                makePane(id: "p1", workingDirectory: temporaryDirectoryURL.path, command: "yes-this-runs"),
            ]
        )

        let result = WorkspaceTemplateImporter.makeWorklane(
            from: template,
            worklaneID: WorklaneID("w1"),
            fallbackWorkingDirectory: nil,
            windowID: WindowID("win1"),
            layoutContext: layoutContext(),
            processEnvironment: ["HOME": NSHomeDirectory()],
            commandResolver: { _ in true }
        )

        XCTAssertTrue(result.fallbacks.isEmpty)
        let pane = result.worklane.paneStripState.panes.first!
        XCTAssertEqual(pane.sessionRequest.command, "yes-this-runs")
        XCTAssertNil(pane.sessionRequest.prefillText)
        XCTAssertEqual(pane.sessionRequest.workingDirectory, temporaryDirectoryURL.path)
    }

    func test_imports_missing_command_as_prefillText_and_reports_fallback() {
        let template = makeTemplate(
            kind: .bookmark,
            panes: [
                makePane(id: "p1", workingDirectory: temporaryDirectoryURL.path, command: "definitely-not-installed"),
            ]
        )

        let result = WorkspaceTemplateImporter.makeWorklane(
            from: template,
            worklaneID: WorklaneID("w1"),
            fallbackWorkingDirectory: nil,
            windowID: WindowID("win1"),
            layoutContext: layoutContext(),
            processEnvironment: ["HOME": NSHomeDirectory()],
            commandResolver: { _ in false }
        )

        XCTAssertEqual(result.fallbacks.count, 1)
        switch result.fallbacks.first?.kind {
        case .missingCommand(let command):
            XCTAssertEqual(command, "definitely-not-installed")
        default:
            XCTFail("Expected missingCommand fallback, got \(String(describing: result.fallbacks.first))")
        }

        let pane = result.worklane.paneStripState.panes.first!
        XCTAssertNil(pane.sessionRequest.command, "Missing command must NOT be set as auto-Enter command")
        XCTAssertEqual(pane.sessionRequest.prefillText, "definitely-not-installed", "Missing command should fall back to prefillText (no auto-Enter)")
    }

    func test_imports_bookmark_with_missing_cwd_falls_back_to_home_and_reports() {
        let bogusPath = "/this/path/does/not/exist/\(UUID().uuidString)"
        let template = makeTemplate(
            kind: .bookmark,
            panes: [
                makePane(id: "p1", workingDirectory: bogusPath, command: nil),
            ]
        )

        let result = WorkspaceTemplateImporter.makeWorklane(
            from: template,
            worklaneID: WorklaneID("w1"),
            fallbackWorkingDirectory: nil,
            windowID: WindowID("win1"),
            layoutContext: layoutContext(),
            processEnvironment: ["HOME": NSHomeDirectory()],
            commandResolver: { _ in true }
        )

        XCTAssertEqual(result.fallbacks.count, 1)
        switch result.fallbacks.first?.kind {
        case .missingWorkingDirectory(let requested, _):
            XCTAssertEqual(requested, bogusPath)
        default:
            XCTFail("Expected missingWorkingDirectory fallback")
        }

        let pane = result.worklane.paneStripState.panes.first!
        XCTAssertNotEqual(pane.sessionRequest.workingDirectory, bogusPath)
    }

    func test_imports_preset_uses_fallback_working_directory() {
        let template = makeTemplate(
            kind: .preset,
            panes: [
                makePane(id: "p1", workingDirectory: nil, command: nil),
            ]
        )

        let result = WorkspaceTemplateImporter.makeWorklane(
            from: template,
            worklaneID: WorklaneID("w1"),
            fallbackWorkingDirectory: temporaryDirectoryURL.path,
            windowID: WindowID("win1"),
            layoutContext: layoutContext(),
            processEnvironment: ["HOME": NSHomeDirectory()],
            commandResolver: { _ in true }
        )

        XCTAssertTrue(result.fallbacks.isEmpty)
        XCTAssertEqual(result.worklane.paneStripState.panes.first?.sessionRequest.workingDirectory, temporaryDirectoryURL.path)
    }

    func test_imported_worklane_carries_template_id_as_origin() {
        let template = makeTemplate(
            kind: .bookmark,
            panes: [makePane(id: "p1", workingDirectory: temporaryDirectoryURL.path, command: nil)]
        )

        let result = WorkspaceTemplateImporter.makeWorklane(
            from: template,
            worklaneID: WorklaneID("w1"),
            fallbackWorkingDirectory: nil,
            windowID: WindowID("win1"),
            layoutContext: layoutContext(),
            processEnvironment: ["HOME": NSHomeDirectory()],
            commandResolver: { _ in true }
        )

        XCTAssertEqual(result.worklane.bookmarkOriginID, template.id)
    }

    func test_environment_overrides_are_merged_into_session_environment() {
        let template = makeTemplate(
            kind: .bookmark,
            panes: [
                makePane(
                    id: "p1",
                    workingDirectory: temporaryDirectoryURL.path,
                    command: nil,
                    environment: ["NODE_ENV": "production"]
                ),
            ]
        )

        let result = WorkspaceTemplateImporter.makeWorklane(
            from: template,
            worklaneID: WorklaneID("w1"),
            fallbackWorkingDirectory: nil,
            windowID: WindowID("win1"),
            layoutContext: layoutContext(),
            processEnvironment: ["HOME": NSHomeDirectory()],
            commandResolver: { _ in true }
        )

        XCTAssertEqual(
            result.worklane.paneStripState.panes.first?.sessionRequest.environmentVariables["NODE_ENV"],
            "production"
        )
    }

    func test_isCommandOnPath_resolves_first_token_against_PATH() {
        let helperDir = temporaryDirectoryURL.appendingPathComponent("bin", isDirectory: true)
        try? FileManager.default.createDirectory(at: helperDir, withIntermediateDirectories: true)
        let executableURL = helperDir.appendingPathComponent("zen-test-cmd")
        FileManager.default.createFile(
            atPath: executableURL.path,
            contents: Data("#!/bin/sh\nexit 0\n".utf8),
            attributes: [.posixPermissions: 0o755]
        )

        XCTAssertTrue(
            WorkspaceTemplateImporter.isCommandOnPath(
                "zen-test-cmd --flag",
                processEnvironment: ["PATH": helperDir.path]
            )
        )

        XCTAssertFalse(
            WorkspaceTemplateImporter.isCommandOnPath(
                "definitely-not-an-installed-thing-xyz",
                processEnvironment: ["PATH": helperDir.path]
            )
        )
    }

    private func layoutContext() -> PaneLayoutContext {
        PaneLayoutContext(
            displayClass: .largeDisplay,
            preset: .balanced,
            viewportWidth: 1280,
            leadingVisibleInset: 0,
            sizing: .balanced
        )
    }

    private func makeTemplate(
        kind: WorkspaceTemplate.Kind,
        panes: [WorkspaceTemplate.Pane]
    ) -> WorkspaceTemplate {
        let column = WorkspaceTemplate.Column(
            id: "c0",
            width: 600,
            focusedPaneID: panes.first?.id,
            lastFocusedPaneID: panes.first?.id,
            paneHeights: panes.map { _ in 1.0 },
            panes: panes
        )
        return WorkspaceTemplate(
            name: "Test",
            kind: kind,
            focusedColumnID: "c0",
            columns: [column]
        )
    }

    private func makePane(
        id: String,
        workingDirectory: String?,
        command: String?,
        environment: [String: String] = [:]
    ) -> WorkspaceTemplate.Pane {
        WorkspaceTemplate.Pane(
            id: id,
            titleSeed: nil,
            workingDirectory: workingDirectory,
            command: command,
            environment: environment,
            wasUserEdited: false
        )
    }
}
