import XCTest
@testable import Zentty

final class AppConfigAgentIntegrationsTOMLTests: XCTestCase {

    func test_round_trip_preserves_states_and_flag() {
        var config = AppConfig.default
        config.agentIntegrations.grandfatheredV1 = true
        config.agentIntegrations.states = [
            "agy": .on,
            "grok": .off,
            "claude": .off,
        ]

        let encoded = AppConfigTOML.encode(config)
        let decoded = AppConfigTOML.decode(encoded)

        XCTAssertEqual(decoded?.agentIntegrations.grandfatheredV1, true)
        XCTAssertEqual(decoded?.agentIntegrations.states["agy"], .on)
        XCTAssertEqual(decoded?.agentIntegrations.states["grok"], .off)
        XCTAssertEqual(decoded?.agentIntegrations.states["claude"], .off)
    }

    func test_defaults_round_trip_to_empty_states() {
        let config = AppConfig.default
        let decoded = AppConfigTOML.decode(AppConfigTOML.encode(config))
        XCTAssertEqual(decoded?.agentIntegrations.grandfatheredV1, false)
        XCTAssertTrue(decoded?.agentIntegrations.states.isEmpty ?? false)
    }

    func test_full_default_config_round_trips_unchanged() {
        let decoded = AppConfigTOML.decode(AppConfigTOML.encode(.default))
        XCTAssertEqual(decoded, .default)
    }

    func test_encode_sorts_states_deterministically() {
        var config = AppConfig.default
        config.agentIntegrations.states = ["grok": .off, "agy": .on, "cursor": .on]
        let encoded = AppConfigTOML.encode(config)

        guard
            let agy = encoded.range(of: "agy = "),
            let cursor = encoded.range(of: "cursor = "),
            let grok = encoded.range(of: "grok = ")
        else {
            return XCTFail("expected all three agent state lines in the encoded TOML")
        }
        XCTAssertTrue(agy.lowerBound < cursor.lowerBound)
        XCTAssertTrue(cursor.lowerBound < grok.lowerBound)
    }

    func test_unknown_state_value_is_skipped_not_fatal() {
        let source = """
        [agent_integrations]
        grandfathered_v1 = true

        [agent_integrations.states]
        agy = "on"
        future = "paused"
        """
        let decoded = AppConfigTOML.decode(source)
        XCTAssertNotNil(decoded, "an unknown state value must not discard the whole config")
        XCTAssertEqual(decoded?.agentIntegrations.states["agy"], .on)
        XCTAssertNil(decoded?.agentIntegrations.states["future"])
        XCTAssertEqual(decoded?.agentIntegrations.grandfatheredV1, true)
    }

    func test_unknown_agent_key_with_valid_state_is_preserved() {
        let source = """
        [agent_integrations.states]
        someNewAgent = "on"
        """
        let decoded = AppConfigTOML.decode(source)
        XCTAssertEqual(decoded?.agentIntegrations.states["someNewAgent"], .on)
    }
}
