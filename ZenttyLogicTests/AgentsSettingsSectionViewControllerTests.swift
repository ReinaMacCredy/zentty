@testable import Zentty
import AppKit
import XCTest

@MainActor
final class AgentsSettingsSectionViewControllerTests: AppKitTestCase {
    private var temporaryDirectoryURL: URL!
    private var defaultsSuiteNames: [String] = []

    override func setUpWithError() throws {
        temporaryDirectoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZenttyTests.AgentsSettings.\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryDirectoryURL, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        defaultsSuiteNames.forEach {
            UserDefaults(suiteName: $0)?.removePersistentDomain(forName: $0)
        }
        defaultsSuiteNames.removeAll()
        if let temporaryDirectoryURL {
            try? FileManager.default.removeItem(at: temporaryDirectoryURL)
        }
        temporaryDirectoryURL = nil
    }

    /// Regression: the Agents section once activated a separator's width
    /// constraint *before* the separator was added to its stack, throwing a
    /// "no common ancestor" exception that aborted `assembleContent` and left the
    /// whole pane blank. Loading the view must assemble the three global switch
    /// rows (menu bar status, agent teams, prevent sleep) plus one switch per
    /// agent in the integrations card, with a non-zero height.
    func test_agents_section_assembles_all_switch_rows() {
        let controller = AgentsSettingsSectionViewController(
            configStore: makeConfigStore(),
            agentTeamsEnableWarningPresenter: { _, completion in completion(.cancel) }
        )

        controller.loadViewIfNeeded()
        controller.view.frame = NSRect(x: 0, y: 0, width: 520, height: 600)
        controller.view.layoutSubtreeIfNeeded()

        // 3 global toggles + one integration toggle per known agent.
        XCTAssertEqual(switches(in: controller.view).count, 3 + AgentIntegrationConsent.allTools.count)
        XCTAssertGreaterThan(controller.measuredContentHeight(), 0)
    }

    func test_menu_bar_status_toggle_persists() {
        let store = makeConfigStore()
        let controller = AgentsSettingsSectionViewController(
            configStore: store,
            agentTeamsEnableWarningPresenter: { _, completion in completion(.cancel) }
        )
        controller.loadViewIfNeeded()

        XCTAssertTrue(controller.isMenuBarStatusSwitchOn)

        controller.setMenuBarStatusEnabledForTesting(false)

        XCTAssertFalse(store.current.menuBar.showStatusItem)
        XCTAssertFalse(controller.isMenuBarStatusSwitchOn)
    }

    func test_integration_disable_uninstallFailure_keepsOff_andSurfacesFailure() {
        struct UninstallError: Error {}
        let store = makeConfigStore()
        var failureTool: AgentBootstrapTool?
        let controller = AgentsSettingsSectionViewController(
            configStore: store,
            agentTeamsEnableWarningPresenter: { _, completion in completion(.cancel) },
            consentPresenter: { _, completion in completion(.on) },
            performUninstall: { _ in throw UninstallError() },
            uninstallFailurePresenter: { _, tool, _ in failureTool = tool }
        )
        controller.loadViewIfNeeded()

        controller.simulateIntegrationToggleForTesting(.cursor, on: true)
        XCTAssertEqual(store.current.agentIntegrations.state(for: .cursor), .on)

        controller.simulateIntegrationToggleForTesting(.cursor, on: false)

        XCTAssertEqual(failureTool, .cursor, "an uninstall failure must be surfaced to the user")
        XCTAssertEqual(
            store.current.agentIntegrations.state(for: .cursor), .off,
            "the user's off choice is recorded even when hook removal fails"
        )
    }

    func test_integration_disable_uninstallSuccess_doesNotSurfaceFailure() {
        let store = makeConfigStore()
        var didPresentFailure = false
        let controller = AgentsSettingsSectionViewController(
            configStore: store,
            agentTeamsEnableWarningPresenter: { _, completion in completion(.cancel) },
            consentPresenter: { _, completion in completion(.on) },
            performUninstall: { _ in },
            uninstallFailurePresenter: { _, _, _ in didPresentFailure = true }
        )
        controller.loadViewIfNeeded()

        controller.simulateIntegrationToggleForTesting(.cursor, on: true)
        controller.simulateIntegrationToggleForTesting(.cursor, on: false)

        XCTAssertFalse(didPresentFailure, "a successful uninstall must not surface a failure")
        XCTAssertEqual(store.current.agentIntegrations.state(for: .cursor), .off)
    }

    // MARK: - Helpers

    private func makeConfigStore() -> AppConfigStore {
        AppConfigStore(
            fileURL: temporaryDirectoryURL.appendingPathComponent("config.toml"),
            sidebarWidthDefaults: makeDefaults(suffix: "sidebarWidth"),
            sidebarVisibilityDefaults: makeDefaults(suffix: "sidebarVisibility"),
            paneLayoutDefaults: makeDefaults(suffix: "paneLayout")
        )
    }

    private func makeDefaults(suffix: String) -> UserDefaults {
        let name = "be.zenjoy.zentty.tests.agentsSettings.\(suffix).\(UUID().uuidString)"
        defaultsSuiteNames.append(name)
        return UserDefaults(suiteName: name)!
    }

    private func switches(in view: NSView) -> [NSSwitch] {
        view.subviews.reduce(into: []) { result, subview in
            if let toggle = subview as? NSSwitch {
                result.append(toggle)
            }
            result.append(contentsOf: switches(in: subview))
        }
    }
}
