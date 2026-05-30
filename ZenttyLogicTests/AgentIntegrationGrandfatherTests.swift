import XCTest
@testable import Zentty

final class AgentIntegrationGrandfatherTests: XCTestCase {
    private var tempDirs: [URL] = []
    private var suiteNames: [String] = []

    override func tearDownWithError() throws {
        for dir in tempDirs {
            try? FileManager.default.removeItem(at: dir)
        }
        for name in suiteNames {
            UserDefaults.standard.removePersistentDomain(forName: name)
        }
        tempDirs = []
        suiteNames = []
        try super.tearDownWithError()
    }

    // MARK: - Migration behavior (injected detector)

    func test_migration_marks_installed_persistent_agents_on_and_sets_flag() throws {
        let store = try makeConfigStore()
        XCTAssertFalse(store.current.agentIntegrations.grandfatheredV1)

        AgentIntegrationGrandfather.migrateIfNeeded(configStore: store) { tool in
            tool == .grok || tool == .agy
        }

        XCTAssertEqual(store.current.agentIntegrations.states["grok"], .on)
        XCTAssertEqual(store.current.agentIntegrations.states["agy"], .on)
        XCTAssertNil(store.current.agentIntegrations.states["cursor"], "uninstalled agents stay at their ask default")
        XCTAssertTrue(store.current.agentIntegrations.grandfatheredV1)
    }

    func test_migration_runs_only_once() throws {
        let store = try makeConfigStore()
        AgentIntegrationGrandfather.migrateIfNeeded(configStore: store) { _ in true }
        XCTAssertTrue(store.current.agentIntegrations.grandfatheredV1)

        // User later turns grok off; a second migration must NOT re-add it.
        try store.update { $0.agentIntegrations.states["grok"] = .off }
        AgentIntegrationGrandfather.migrateIfNeeded(configStore: store) { _ in true }
        XCTAssertEqual(store.current.agentIntegrations.states["grok"], .off)
    }

    func test_migration_does_not_clobber_explicit_state() throws {
        let store = try makeConfigStore()
        // User explicitly disabled grok before the migration runs.
        try store.update { $0.agentIntegrations.states["grok"] = .off }

        AgentIntegrationGrandfather.migrateIfNeeded(configStore: store) { _ in true }

        XCTAssertEqual(store.current.agentIntegrations.states["grok"], .off, "explicit choice preserved")
        XCTAssertEqual(store.current.agentIntegrations.states["agy"], .on, "others still grandfathered")
    }

    func test_migration_with_nothing_installed_only_sets_flag() throws {
        let store = try makeConfigStore()
        AgentIntegrationGrandfather.migrateIfNeeded(configStore: store) { _ in false }
        XCTAssertTrue(store.current.agentIntegrations.grandfatheredV1)
        XCTAssertTrue(store.current.agentIntegrations.states.isEmpty)
    }

    // MARK: - isInstalled round-trips (install → detected → uninstall → gone)

    func test_cursor_isInstalled_round_trip() throws {
        let home = try makeTempDir()
        let url = CursorHooksInstaller.defaultUserHooksURL(home: home.path)
        XCTAssertFalse(CursorHooksInstaller.isInstalled(at: url))
        try CursorHooksInstaller.install(at: url, cliPath: "/bin/zentty")
        XCTAssertTrue(CursorHooksInstaller.isInstalled(at: url))
        try CursorHooksInstaller.uninstall(at: url)
        XCTAssertFalse(CursorHooksInstaller.isInstalled(at: url))
    }

    func test_droid_isInstalled_round_trip() throws {
        let home = try makeTempDir()
        let url = DroidHooksInstaller.defaultUserSettingsURL(home: home.path)
        XCTAssertFalse(DroidHooksInstaller.isInstalled(at: url))
        try DroidHooksInstaller.install(at: url, cliPath: "/bin/zentty")
        XCTAssertTrue(DroidHooksInstaller.isInstalled(at: url))
        try DroidHooksInstaller.uninstall(at: url)
        XCTAssertFalse(DroidHooksInstaller.isInstalled(at: url))
    }

    func test_grok_isInstalled_round_trip() throws {
        let home = try makeTempDir()
        let root = GrokHooksInstaller.defaultUserHooksURL(home: home.path)
        XCTAssertFalse(GrokHooksInstaller.isInstalled(hooksRoot: root))
        try GrokHooksInstaller.install(at: root, cliPath: "/bin/zentty")
        XCTAssertTrue(GrokHooksInstaller.isInstalled(hooksRoot: root))
        try GrokHooksInstaller.uninstall(at: root)
        XCTAssertFalse(GrokHooksInstaller.isInstalled(hooksRoot: root))
    }

    func test_agy_isInstalled_round_trip() throws {
        let home = try makeTempDir()
        let url = AgyHooksInstaller.defaultUserHooksFileURL(home: home.path)
        XCTAssertFalse(AgyHooksInstaller.isInstalled(hooksFileURL: url))
        _ = try AgyHooksInstaller.install(hooksFileURL: url, cliPath: "/bin/zentty", home: home.path)
        XCTAssertTrue(AgyHooksInstaller.isInstalled(hooksFileURL: url))
        try AgyHooksInstaller.uninstall(hooksFileURL: url, home: home.path)
        XCTAssertFalse(AgyHooksInstaller.isInstalled(hooksFileURL: url))
    }

    func test_hermes_isInstalled_round_trip() throws {
        let home = try makeTempDir()
        let configURL = home.appendingPathComponent("config.yaml")
        let allowlistURL = home.appendingPathComponent("shell-hooks-allowlist.json")
        XCTAssertFalse(HermesHooksInstaller.isInstalled(configURL: configURL))
        _ = try HermesHooksInstaller.install(configURL: configURL, allowlistURL: allowlistURL, cliPath: "/bin/zentty")
        XCTAssertTrue(HermesHooksInstaller.isInstalled(configURL: configURL))
        try HermesHooksInstaller.uninstall(configURL: configURL, allowlistURL: allowlistURL)
        XCTAssertFalse(HermesHooksInstaller.isInstalled(configURL: configURL))
    }

    func test_amp_isInstalled_round_trip() throws {
        let home = try makeTempDir()
        let source = home.appendingPathComponent("source.ts")
        try "// \(AmpPluginInstaller.ownershipMarker)\nexport default {}".write(to: source, atomically: true, encoding: .utf8)
        let destination = home
            .appendingPathComponent("amp", isDirectory: true)
            .appendingPathComponent("plugins", isDirectory: true)
            .appendingPathComponent(AmpPluginInstaller.pluginFileName, isDirectory: false)

        XCTAssertFalse(AmpPluginInstaller.isInstalled(destinationConfigHomeURL: home))
        _ = try AmpPluginInstaller.install(sourceURL: source, destinationURL: destination)
        XCTAssertTrue(AmpPluginInstaller.isInstalled(destinationConfigHomeURL: home))
        try AmpPluginInstaller.uninstall(destinationURL: destination)
        XCTAssertFalse(AmpPluginInstaller.isInstalled(destinationConfigHomeURL: home))
    }

    func test_amp_unmarked_plugin_is_not_detected() throws {
        let home = try makeTempDir()
        let destination = home
            .appendingPathComponent("amp", isDirectory: true)
            .appendingPathComponent("plugins", isDirectory: true)
            .appendingPathComponent(AmpPluginInstaller.pluginFileName, isDirectory: false)
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "export default {}".write(to: destination, atomically: true, encoding: .utf8)
        XCTAssertFalse(
            AmpPluginInstaller.isInstalled(destinationConfigHomeURL: home),
            "a plugin file without our ownership marker must not count as installed"
        )
    }

    // MARK: - Ownership-predicate divergence guards

    func test_hermes_half_written_block_is_not_detected() throws {
        let home = try makeTempDir()
        let configURL = home.appendingPathComponent("config.yaml")
        // Begin marker present but end marker missing (corrupted/hand-edited):
        // uninstall would be a no-op, so isInstalled must NOT claim it.
        try """
        hooks:
          # zentty hermes hooks begin
          - event: foo
        """.write(to: configURL, atomically: true, encoding: .utf8)
        XCTAssertFalse(
            HermesHooksInstaller.isInstalled(configURL: configURL),
            "a begin marker without a matching end marker must not count as installed"
        )
    }

    func test_agy_foreign_zentty_group_is_not_detected() throws {
        let home = try makeTempDir()
        let url = AgyHooksInstaller.defaultUserHooksFileURL(home: home.path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        // A top-level "zentty" group that is NOT one of ours (no agy marker in
        // its commands): uninstall would refuse to touch it, so isInstalled
        // must return false.
        try #"{"zentty":{"SessionStart":[{"command":"echo hi"}]}}"#
            .write(to: url, atomically: true, encoding: .utf8)
        XCTAssertFalse(
            AgyHooksInstaller.isInstalled(hooksFileURL: url),
            "a foreign top-level zentty group must not count as a Zentty install"
        )
    }

    func test_cursor_foreign_entry_is_not_detected() throws {
        let home = try makeTempDir()
        let url = CursorHooksInstaller.defaultUserHooksURL(home: home.path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"version":1,"hooks":{"stop":[{"command":"/some/other/tool run"}]}}"#
            .write(to: url, atomically: true, encoding: .utf8)
        XCTAssertFalse(
            CursorHooksInstaller.isInstalled(at: url),
            "an entry without our adapter marker must not count as a Zentty install"
        )
    }

    // MARK: - Helpers

    private func makeTempDir() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentIntegrationGrandfatherTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        tempDirs.append(url)
        return url
    }

    private func makeConfigStore() throws -> AppConfigStore {
        let dir = try makeTempDir()
        func defaults(_ suffix: String) -> UserDefaults {
            let name = "ZenttyTests.Grandfather.\(suffix).\(UUID().uuidString)"
            suiteNames.append(name)
            return UserDefaults(suiteName: name) ?? .standard
        }
        return AppConfigStore(
            fileURL: dir.appendingPathComponent("config.toml"),
            sidebarWidthDefaults: defaults("width"),
            sidebarVisibilityDefaults: defaults("visibility"),
            paneLayoutDefaults: defaults("paneLayout")
        )
    }
}
