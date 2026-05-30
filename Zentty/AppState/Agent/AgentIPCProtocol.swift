import Foundation

enum AgentIPCProtocol {
    static let version = 1
    static let selfPIDPlaceholder = "__ZENTTY_SELF_PID__"
    /// Read timeout (seconds) the wrapper uses while blocked on the phase-2
    /// `awaitConsent` response. The app must resolve the consent panel and write
    /// its reply strictly before this elapses; the app-side wait stays below it
    /// by `consentPanelTimeoutMargin`. Shared so the two values can't drift into
    /// an inverted ordering across the app/CLI targets.
    static let awaitConsentTimeoutSeconds = 300
    /// Seconds the app-side consent wait stays below the wrapper timeout.
    static let consentPanelTimeoutMargin = 30
}

enum AgentIPCRequestKind: String, Codable, Equatable {
    case ipc
    case bootstrap
    case pane
    case discover
    case server
    case tmuxCompat = "tmux_compat"
    /// Second phase of the integration-consent handshake. After a `bootstrap`
    /// response carries `consentRequired`, the wrapper re-issues an
    /// `awaitConsent` request (with a long read timeout) that the app holds
    /// open while the consent panel is shown, then answers with the resolved
    /// launch plan. See AgentIntegrationConsent + the IPC handler.
    case awaitConsent = "await_consent"
}

enum AgentBootstrapTool: String, Codable, Equatable, CaseIterable {
    case amp
    case claude
    case codex
    case copilot
    case cursor
    case droid
    case gemini
    case kimi
    case opencode
    case pi
    case grok
    case agy
    case hermes

    /// Names of the real CLI binary (or binaries) this wrapped tool resolves to on PATH.
    /// For most tools this matches `rawValue`, but cursor's CLI is shipped as `cursor-agent`
    /// (with `agent` as a user-facing alias) while `cursor` itself is the IDE launcher.
    var realBinaryNames: [String] {
        switch self {
        case .cursor:
            return ["cursor-agent"]
        case .amp, .claude, .codex, .copilot, .droid, .gemini, .opencode, .pi, .grok, .agy, .hermes:
            return [rawValue]
        case .kimi:
            return [rawValue, "kimi-cli"]
        }
    }

    /// The wrapped agent whose real binary matches the leading token of a shell
    /// command, or `nil` if the command isn't one of our agent CLIs. Mirrors how
    /// the PATH wrapper itself decides a command is an agent (binary-name match),
    /// so a restored pane is treated as an "agent pane" iff its command would
    /// actually trip the wrapper.
    static func wrappedAgent(forCommand command: String) -> AgentBootstrapTool? {
        guard let firstToken = command.split(separator: " ").first else { return nil }
        let binaryName = (String(firstToken) as NSString).lastPathComponent
        return allCases.first { $0.realBinaryNames.contains(binaryName) }
    }
}

struct AgentIPCRequest: Codable, Equatable {
    let version: Int
    let id: String
    let kind: AgentIPCRequestKind
    let arguments: [String]
    let standardInput: String?
    let environment: [String: String]
    let expectsResponse: Bool
    let subcommand: String?
    let tool: AgentBootstrapTool?

    init(
        version: Int = AgentIPCProtocol.version,
        id: String = UUID().uuidString,
        kind: AgentIPCRequestKind,
        arguments: [String],
        standardInput: String?,
        environment: [String: String],
        expectsResponse: Bool,
        subcommand: String? = nil,
        tool: AgentBootstrapTool? = nil
    ) {
        self.version = version
        self.id = id
        self.kind = kind
        self.arguments = arguments
        self.standardInput = standardInput
        self.environment = environment
        self.expectsResponse = expectsResponse
        self.subcommand = subcommand
        self.tool = tool
    }

}

struct AgentLaunchAction: Codable, Equatable {
    let subcommand: String
    let arguments: [String]
    let standardInput: String?
}

struct AgentLaunchPlan: Codable, Equatable {
    let executablePath: String
    let arguments: [String]
    let setEnvironment: [String: String]
    let unsetEnvironment: [String]
    let preLaunchActions: [AgentLaunchAction]
}

struct PaneListEntry: Codable, Equatable {
    let index: Int
    let id: String
    let column: Int
    let title: String
    let workingDirectory: String?
    let isFocused: Bool
    let agentTool: String?
    let agentStatus: String?
}

struct DiscoveredWindow: Codable, Equatable {
    let id: String
    let order: Int
    let isFocused: Bool
    let worklaneCount: Int
    let paneCount: Int
}

struct DiscoveredWorklane: Codable, Equatable {
    let id: String
    let windowID: String
    let order: Int
    let title: String?
    let isFocused: Bool
    let paneCount: Int
    let columnCount: Int
    let focusedPaneID: String?
}

struct DiscoveredPane: Codable, Equatable {
    let id: String
    let windowID: String
    let worklaneID: String
    let index: Int
    let column: Int
    let title: String
    let workingDirectory: String?
    let isFocused: Bool
    let agentTool: String?
    let agentStatus: String?
    let controlToken: String?
}

struct ServerListEntry: Codable, Equatable {
    let id: String
    let origin: String
    let url: String
    let display: String
    let worklaneID: String
    let paneID: String?
    let source: String
    let ports: [Int]
    let confidence: String
    let updatedAt: String
    /// Relevance tier: "primary", "shown", or "hidden". Optional for decode
    /// tolerance across version-skewed app/CLI pairs (added in response v2).
    let tier: String?
    /// Relevance reasons, e.g. ["ignored_port:9229", "running_pane"] (v2).
    let reasons: [String]?
}

struct ServerListResult: Codable, Equatable {
    let version: Int
    let primaryServerID: String?
    let servers: [ServerListEntry]
}

struct AgentIPCResponseResult: Codable, Equatable {
    let launchPlan: AgentLaunchPlan?
    let paneList: [PaneListEntry]?
    let discoveredWindows: [DiscoveredWindow]?
    let discoveredWorklanes: [DiscoveredWorklane]?
    let discoveredPanes: [DiscoveredPane]?
    let serverState: ServerListResult?
    /// Optional text payload returned from tmux-compat subcommands like
    /// `capture-pane`, `list-panes`, `display-message`. The CLI writes this
    /// directly to stdout.
    let stdout: String?
    /// Set on a `bootstrap` response when the agent's integration needs
    /// first-run consent before its hooks may be written to the user's config.
    /// The wrapper, on seeing this, re-issues an `awaitConsent` request that
    /// blocks (long timeout) until the user answers the consent panel. Optional
    /// for decode tolerance across version-skewed app/CLI pairs.
    let consentRequired: Bool?

    init(
        launchPlan: AgentLaunchPlan? = nil,
        paneList: [PaneListEntry]? = nil,
        discoveredWindows: [DiscoveredWindow]? = nil,
        discoveredWorklanes: [DiscoveredWorklane]? = nil,
        discoveredPanes: [DiscoveredPane]? = nil,
        serverState: ServerListResult? = nil,
        stdout: String? = nil,
        consentRequired: Bool? = nil
    ) {
        self.launchPlan = launchPlan
        self.paneList = paneList
        self.discoveredWindows = discoveredWindows
        self.discoveredWorklanes = discoveredWorklanes
        self.discoveredPanes = discoveredPanes
        self.serverState = serverState
        self.stdout = stdout
        self.consentRequired = consentRequired
    }
}

struct AgentIPCResponseError: Codable, Equatable {
    let code: String
    let message: String
}

struct AgentIPCResponse: Codable, Equatable {
    let version: Int
    let id: String
    let ok: Bool
    let result: AgentIPCResponseResult?
    let error: AgentIPCResponseError?

    init(
        version: Int = AgentIPCProtocol.version,
        id: String,
        ok: Bool,
        result: AgentIPCResponseResult? = nil,
        error: AgentIPCResponseError? = nil
    ) {
        self.version = version
        self.id = id
        self.ok = ok
        self.result = result
        self.error = error
    }
}
