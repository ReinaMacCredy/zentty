import XCTest
@testable import Zentty

final class WorkspaceTemplateExporterTests: XCTestCase {
    func test_round_trips_preset_through_data() throws {
        let original = WorkspaceTemplate(
            name: "Editor + tests",
            kind: .preset,
            columns: [
                WorkspaceTemplate.Column(
                    id: "c0",
                    width: 600,
                    focusedPaneID: "p1",
                    lastFocusedPaneID: "p1",
                    paneHeights: [1.0],
                    panes: [
                        WorkspaceTemplate.Pane(
                            id: "p1",
                            titleSeed: "Editor",
                            workingDirectory: nil,
                            command: "vim",
                            environment: ["TERM": "xterm-256color"],
                            wasUserEdited: true
                        ),
                    ]
                ),
            ]
        )

        let data = try WorkspaceTemplateExporter.export(original)
        let restored = try WorkspaceTemplateExporter.importTemplate(from: data)

        XCTAssertEqual(restored.name, original.name)
        XCTAssertEqual(restored.kind, .preset)
        XCTAssertEqual(restored.allPanes.first?.command, "vim")
        XCTAssertEqual(restored.allPanes.first?.environment["TERM"], "xterm-256color")
        XCTAssertNotEqual(restored.id, original.id, "Imported templates must be assigned a fresh ID")
    }

    func test_export_strips_working_directories_when_source_is_a_bookmark() throws {
        let bookmark = WorkspaceTemplate(
            name: "Zentty / main",
            kind: .bookmark,
            projectRoot: "/Users/peter/proj",
            columns: [
                WorkspaceTemplate.Column(
                    id: "c0",
                    width: 600,
                    focusedPaneID: "p1",
                    lastFocusedPaneID: "p1",
                    paneHeights: [1.0],
                    panes: [
                        WorkspaceTemplate.Pane(
                            id: "p1",
                            workingDirectory: "/Users/peter/proj/zentty",
                            command: "claude --yolo"
                        ),
                    ]
                ),
            ]
        )

        let data = try WorkspaceTemplateExporter.export(bookmark)
        let restored = try WorkspaceTemplateExporter.importTemplate(from: data)

        XCTAssertEqual(restored.kind, .preset)
        XCTAssertNil(restored.projectRoot)
        XCTAssertNil(restored.allPanes.first?.workingDirectory, "Bookmark export must strip per-pane cwds")
        XCTAssertEqual(restored.allPanes.first?.command, "claude --yolo")
    }

    func test_export_strips_reserved_environment_keys() throws {
        let original = WorkspaceTemplate(
            name: "Env",
            kind: .preset,
            columns: [
                WorkspaceTemplate.Column(
                    id: "c0",
                    width: 600,
                    focusedPaneID: "p1",
                    lastFocusedPaneID: "p1",
                    paneHeights: [1.0],
                    panes: [
                        WorkspaceTemplate.Pane(
                            id: "p1",
                            environment: [
                                "TERM": "xterm-256color",
                                "NODE_ENV": "production",
                                "ZENTTY_WINDOW_ID": "stale-window",
                                "ZENTTY_PANE_TOKEN": "stale-token",
                                "PATH": "/tmp/stale-bin",
                                "ZDOTDIR": "/tmp/stale-zdotdir",
                            ]
                        ),
                    ]
                ),
            ]
        )

        let data = try WorkspaceTemplateExporter.export(original)
        let restored = try WorkspaceTemplateExporter.importTemplate(from: data)

        XCTAssertEqual(restored.allPanes.first?.environment, [
            "NODE_ENV": "production",
            "TERM": "xterm-256color",
        ])
    }

    func test_import_strips_reserved_environment_keys_from_external_files() throws {
        let original = WorkspaceTemplate(
            name: "Imported Env",
            kind: .preset,
            columns: [
                WorkspaceTemplate.Column(
                    id: "c0",
                    width: 600,
                    focusedPaneID: "p1",
                    lastFocusedPaneID: "p1",
                    paneHeights: [1.0],
                    panes: [
                        WorkspaceTemplate.Pane(
                            id: "p1",
                            environment: [
                                "NODE_ENV": "production",
                                "ZENTTY_PANE_TOKEN": "stale-token",
                                "PATH": "/tmp/stale-bin",
                            ]
                        ),
                    ]
                ),
            ]
        )
        let envelope = WorkspaceTemplateExporter.ExportEnvelope(template: original)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)

        let restored = try WorkspaceTemplateExporter.importTemplate(from: data)

        XCTAssertEqual(restored.allPanes.first?.environment, ["NODE_ENV": "production"])
    }

    func test_imported_template_resets_pinned_and_lastUsedAt() throws {
        let original = WorkspaceTemplate(
            name: "Pinned demo",
            kind: .preset,
            pinned: true,
            lastUsedAt: Date()
        )
        let data = try WorkspaceTemplateExporter.export(original)
        let restored = try WorkspaceTemplateExporter.importTemplate(from: data)
        XCTAssertFalse(restored.pinned)
        XCTAssertNil(restored.lastUsedAt)
    }

    func test_import_throws_when_schema_version_is_newer_than_supported() throws {
        let envelope = WorkspaceTemplateExporter.ExportEnvelope(
            schemaVersion: WorkspaceTemplateExporter.ExportEnvelope.currentSchemaVersion + 1,
            template: WorkspaceTemplate(name: "Future", kind: .preset)
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(envelope)

        XCTAssertThrowsError(try WorkspaceTemplateExporter.importTemplate(from: data)) { error in
            guard case WorkspaceTemplateExporter.ImportError.schemaVersionTooNew = error else {
                XCTFail("Expected schemaVersionTooNew, got \(error)")
                return
            }
        }
    }

    func test_write_and_read_round_trips_via_disk() throws {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZenttyTests.WorkspaceTemplateExporter.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }

        let url = dir.appendingPathComponent("preset.\(WorkspaceTemplateExporter.fileExtension)")
        let original = WorkspaceTemplate(name: "Disk test", kind: .preset)
        try WorkspaceTemplateExporter.write(original, to: url)
        let restored = try WorkspaceTemplateExporter.read(from: url)
        XCTAssertEqual(restored.name, "Disk test")
    }
}
