import XCTest
@testable import Zentty

@MainActor
final class AgentConsentCoordinatorTests: XCTestCase {
    private var tempDirs: [URL] = []
    private var suiteNames: [String] = []

    override func tearDown() {
        for dir in tempDirs { try? FileManager.default.removeItem(at: dir) }
        for name in suiteNames { UserDefaults.standard.removePersistentDomain(forName: name) }
        tempDirs = []
        suiteNames = []
        super.tearDown()
    }

    func test_concurrent_requests_for_same_tool_coalesce_to_one_panel() throws {
        let store = try makeConfigStore()
        let coordinator = AgentConsentCoordinator()
        var presenterCalls = 0
        var capturedCompletion: ((AgentIntegrationState) -> Void)?
        coordinator.configure(configStore: store) { _, completion in
            presenterCalls += 1
            capturedCompletion = completion
        }

        var results: [AgentIntegrationState] = []
        coordinator.requestDecision(tool: .agy) { results.append($0) }
        coordinator.requestDecision(tool: .agy) { results.append($0) }

        XCTAssertEqual(presenterCalls, 1, "the second request must join the first panel, not open another")

        capturedCompletion?(.on)
        XCTAssertEqual(results, [.on, .on], "both waiters resolve with the same decision")
        XCTAssertEqual(store.current.agentIntegrations.states["agy"], .on, "the decision is persisted")
    }

    func test_resolve_clears_waiters_so_a_later_request_opens_a_fresh_panel() throws {
        let store = try makeConfigStore()
        let coordinator = AgentConsentCoordinator()
        var presenterCalls = 0
        var capturedCompletion: ((AgentIntegrationState) -> Void)?
        coordinator.configure(configStore: store) { _, completion in
            presenterCalls += 1
            capturedCompletion = completion
        }

        coordinator.requestDecision(tool: .grok) { _ in }
        capturedCompletion?(.off)
        XCTAssertEqual(store.current.agentIntegrations.states["grok"], .off)

        coordinator.requestDecision(tool: .grok) { _ in }
        XCTAssertEqual(presenterCalls, 2, "after a decision resolves, a new request opens a fresh panel")
    }

    func test_without_presenter_declines_without_persisting() throws {
        let store = try makeConfigStore()
        let coordinator = AgentConsentCoordinator()
        // Not configured: no presenter.
        var result: AgentIntegrationState?
        coordinator.requestDecision(tool: .agy) { result = $0 }
        XCTAssertEqual(result, .off, "an unconfigured coordinator declines")
        XCTAssertNil(store.current.agentIntegrations.states["agy"], "but does not persist, so state stays ask")
    }

    private func makeConfigStore() throws -> AppConfigStore {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AgentConsentCoordinatorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        tempDirs.append(dir)
        func defaults(_ suffix: String) -> UserDefaults {
            let name = "ZenttyTests.ConsentCoordinator.\(suffix).\(UUID().uuidString)"
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
