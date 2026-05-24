import Foundation
import XCTest
@testable import Zentty

final class HermesHooksInstallerTests: XCTestCase {
    private var temporaryHomeURL: URL!
    private var hermesHomeURL: URL!
    private var configURL: URL!
    private var allowlistURL: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        temporaryHomeURL = try makeTemporaryDirectory()
        hermesHomeURL = temporaryHomeURL.appendingPathComponent(".hermes", isDirectory: true)
        try FileManager.default.createDirectory(at: hermesHomeURL, withIntermediateDirectories: true)
        configURL = hermesHomeURL.appendingPathComponent("config.yaml", isDirectory: false)
        allowlistURL = hermesHomeURL.appendingPathComponent("shell-hooks-allowlist.json", isDirectory: false)
    }

    override func tearDownWithError() throws {
        if let temporaryHomeURL {
            try? FileManager.default.removeItem(at: temporaryHomeURL)
        }
        try super.tearDownWithError()
    }

    func test_install_inserts_managed_hooks_and_allowlist_entries() throws {
        try """
        model: anthropic/claude-sonnet-4.6
        hooks: {}
        """.write(to: configURL, atomically: true, encoding: .utf8)

        let wrote = try HermesHooksInstaller.install(
            configURL: configURL,
            allowlistURL: allowlistURL,
            cliPath: "/opt/zentty/bin/zentty"
        )

        XCTAssertTrue(wrote)
        let config = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertTrue(config.contains(HermesHooksInstaller.hookMarker))
        XCTAssertTrue(config.contains("on_session_start:"))
        XCTAssertTrue(config.contains("pre_approval_request:"))
        XCTAssertTrue(config.contains("/opt/zentty/bin/zentty hermes-hook on-session-start"))
        XCTAssertTrue(config.contains("|| echo"))
        XCTAssertFalse(config.contains("hooks: {}"))

        let allowlistData = try Data(contentsOf: allowlistURL)
        let allowlist = try XCTUnwrap(JSONSerialization.jsonObject(with: allowlistData) as? [String: Any])
        let approvals = try XCTUnwrap(allowlist["approvals"] as? [[String: Any]])
        XCTAssertEqual(Set(approvals.compactMap { $0["event"] as? String }), Set(HermesHooksInstaller.events.map(\.name)))
        XCTAssertTrue(approvals.allSatisfy { ($0["command"] as? String)?.contains("zentty hermes-hook") == true })
    }

    func test_install_preserves_foreign_hooks_and_is_idempotent() throws {
        try """
        hooks:
          pre_tool_call:
            - command: "echo existing"
              timeout: 9
        """.write(to: configURL, atomically: true, encoding: .utf8)

        XCTAssertTrue(try HermesHooksInstaller.install(
            configURL: configURL,
            allowlistURL: allowlistURL,
            cliPath: "/opt/zentty/bin/zentty"
        ))
        let first = try String(contentsOf: configURL, encoding: .utf8)

        XCTAssertFalse(try HermesHooksInstaller.install(
            configURL: configURL,
            allowlistURL: allowlistURL,
            cliPath: "/opt/zentty/bin/zentty"
        ))
        let second = try String(contentsOf: configURL, encoding: .utf8)

        XCTAssertEqual(first, second)
        XCTAssertTrue(second.contains(#"- command: "echo existing""#))
        XCTAssertEqual(second.components(separatedBy: HermesHooksInstaller.hookMarker).count - 1, 1)
    }

    func test_uninstall_removes_only_managed_content() throws {
        try """
        hooks:
          pre_tool_call:
            - command: "echo existing"
              timeout: 9
        """.write(to: configURL, atomically: true, encoding: .utf8)
        _ = try HermesHooksInstaller.install(
            configURL: configURL,
            allowlistURL: allowlistURL,
            cliPath: "/opt/zentty/bin/zentty"
        )

        try HermesHooksInstaller.uninstall(configURL: configURL, allowlistURL: allowlistURL)

        let config = try String(contentsOf: configURL, encoding: .utf8)
        XCTAssertFalse(config.contains(HermesHooksInstaller.hookMarker))
        XCTAssertTrue(config.contains(#"- command: "echo existing""#))

        let allowlistData = try Data(contentsOf: allowlistURL)
        let allowlist = try XCTUnwrap(JSONSerialization.jsonObject(with: allowlistData) as? [String: Any])
        XCTAssertEqual((allowlist["approvals"] as? [[String: Any]])?.count, 0)
    }

    func test_uninstall_does_not_create_allowlist_when_none_exists() throws {
        try """
        model: anthropic/claude-sonnet-4.6
        """.write(to: configURL, atomically: true, encoding: .utf8)

        XCTAssertFalse(FileManager.default.fileExists(atPath: allowlistURL.path))

        try HermesHooksInstaller.uninstall(configURL: configURL, allowlistURL: allowlistURL)

        XCTAssertFalse(FileManager.default.fileExists(atPath: allowlistURL.path))
    }

    func test_default_paths_respect_hermes_home() {
        let env = [
            "HOME": temporaryHomeURL.path,
            "HERMES_HOME": "~/custom-hermes",
        ]

        XCTAssertEqual(
            HermesHooksInstaller.defaultHermesHome(environment: env),
            temporaryHomeURL.appendingPathComponent("custom-hermes", isDirectory: true).path
        )
        XCTAssertEqual(
            HermesHooksInstaller.defaultConfigURL(environment: env).path,
            temporaryHomeURL.appendingPathComponent("custom-hermes/config.yaml").path
        )
    }

    private func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("HermesHooksInstallerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
