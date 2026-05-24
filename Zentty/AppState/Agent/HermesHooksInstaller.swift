import Foundation

enum HermesHooksInstaller {
    struct Event {
        let name: String
        let cliEvent: String
        let timeout: Int
    }

    static let hookMarker = "# zentty hermes hooks begin"
    private static let hookEndMarker = "# zentty hermes hooks end"

    static let events: [Event] = [
        Event(name: "on_session_start", cliEvent: "on-session-start", timeout: 5),
        Event(name: "on_session_reset", cliEvent: "on-session-reset", timeout: 5),
        Event(name: "pre_llm_call", cliEvent: "pre-llm-call", timeout: 5),
        Event(name: "post_llm_call", cliEvent: "post-llm-call", timeout: 5),
        Event(name: "on_session_end", cliEvent: "on-session-end", timeout: 5),
        Event(name: "on_session_finalize", cliEvent: "on-session-finalize", timeout: 5),
        Event(name: "pre_tool_call", cliEvent: "pre-tool-call", timeout: 5),
        Event(name: "post_tool_call", cliEvent: "post-tool-call", timeout: 5),
        Event(name: "pre_approval_request", cliEvent: "pre-approval-request", timeout: 30),
        Event(name: "post_approval_response", cliEvent: "post-approval-response", timeout: 5),
    ]

    static func defaultHermesHome(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        let home = nonBlank(environment["HOME"]) ?? NSHomeDirectory()
        let configured = nonBlank(environment["HERMES_HOME"]) ?? "~/.hermes"
        if configured == "~" {
            return home
        }
        if configured.hasPrefix("~/") {
            return URL(fileURLWithPath: home, isDirectory: true)
                .appendingPathComponent(String(configured.dropFirst(2)), isDirectory: true)
                .path
        }
        return configured
    }

    static func defaultConfigURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        URL(fileURLWithPath: defaultHermesHome(environment: environment), isDirectory: true)
            .appendingPathComponent("config.yaml", isDirectory: false)
    }

    static func defaultAllowlistURL(environment: [String: String] = ProcessInfo.processInfo.environment) -> URL {
        URL(fileURLWithPath: defaultHermesHome(environment: environment), isDirectory: true)
            .appendingPathComponent("shell-hooks-allowlist.json", isDirectory: false)
    }

    @discardableResult
    static func install(
        configURL: URL = defaultConfigURL(),
        allowlistURL: URL = defaultAllowlistURL(),
        cliPath: String,
        fileManager: FileManager = .default
    ) throws -> Bool {
        try fileManager.createDirectory(at: configURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fileManager.createDirectory(at: allowlistURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let existingConfig = (try? String(contentsOf: configURL, encoding: .utf8)) ?? ""
        let nextConfig = installManagedBlock(in: existingConfig, cliPath: cliPath)
        let wroteConfig = existingConfig != nextConfig || !fileManager.fileExists(atPath: configURL.path)
        if wroteConfig {
            try nextConfig.write(to: configURL, atomically: true, encoding: .utf8)
        }

        let existingAllowlist = readAllowlist(at: allowlistURL)
        let nextAllowlist = mergedAllowlist(existingAllowlist, cliPath: cliPath)
        let existingAllowlistData = try? JSONSerialization.data(
            withJSONObject: existingAllowlist,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        let nextAllowlistData = try JSONSerialization.data(
            withJSONObject: nextAllowlist,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        let wroteAllowlist = existingAllowlistData != nextAllowlistData || !fileManager.fileExists(atPath: allowlistURL.path)
        if wroteAllowlist {
            try nextAllowlistData.write(to: allowlistURL, options: .atomic)
        }

        return wroteConfig || wroteAllowlist
    }

    static func uninstall(
        configURL: URL = defaultConfigURL(),
        allowlistURL: URL = defaultAllowlistURL(),
        fileManager: FileManager = .default
    ) throws {
        if let existingConfig = try? String(contentsOf: configURL, encoding: .utf8) {
            let nextConfig = removeManagedBlock(from: existingConfig)
            if nextConfig != existingConfig {
                try nextConfig.write(to: configURL, atomically: true, encoding: .utf8)
            }
        }

        guard fileManager.fileExists(atPath: allowlistURL.path) else {
            return
        }

        let existingAllowlist = readAllowlist(at: allowlistURL)
        let nextAllowlist = removeManagedApprovals(from: existingAllowlist)
        let existingAllowlistData = try? JSONSerialization.data(
            withJSONObject: existingAllowlist,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        let nextAllowlistData = try JSONSerialization.data(
            withJSONObject: nextAllowlist,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
        if existingAllowlistData != nextAllowlistData {
            try nextAllowlistData.write(to: allowlistURL, options: .atomic)
        }
    }

    @discardableResult
    static func ensureInstalledForCurrentUser(
        cliPath: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        fileManager: FileManager = .default
    ) throws -> Bool {
        try install(
            configURL: defaultConfigURL(environment: environment),
            allowlistURL: defaultAllowlistURL(environment: environment),
            cliPath: cliPath,
            fileManager: fileManager
        )
    }

    private static func installManagedBlock(in source: String, cliPath: String) -> String {
        var text = removeManagedBlock(from: source)
        if text.isEmpty {
            text = "hooks:\n"
        }

        if let range = text.range(of: #"(?m)^hooks:\s*\{\}\s*$"#, options: .regularExpression) {
            text.replaceSubrange(range, with: "hooks:")
        } else if let range = text.range(of: #"(?m)^hooks:\s*\[\]\s*$"#, options: .regularExpression) {
            text.replaceSubrange(range, with: "hooks:")
        }

        let block = managedHookBlock(cliPath: cliPath)
        guard let hooksRange = text.range(of: #"(?m)^hooks:\s*$"#, options: .regularExpression) else {
            if !text.hasSuffix("\n") { text += "\n" }
            return text + "\nhooks:\n" + block
        }

        var insertionIndex = hooksRange.upperBound
        if insertionIndex < text.endIndex, text[insertionIndex] == "\n" {
            insertionIndex = text.index(after: insertionIndex)
        } else {
            text.insert("\n", at: insertionIndex)
            insertionIndex = text.index(after: insertionIndex)
        }
        text.insert(contentsOf: block, at: insertionIndex)
        return text
    }

    private static func managedHookBlock(cliPath: String) -> String {
        var lines = ["  \(hookMarker)"]
        for event in events {
            lines.append("  \(event.name):")
            lines.append("    - command: \"\(yamlDoubleQuoted(hookCommand(cliPath: cliPath, event: event)))\"")
            lines.append("      timeout: \(event.timeout)")
        }
        lines.append("  \(hookEndMarker)")
        return lines.joined(separator: "\n") + "\n"
    }

    private static func removeManagedBlock(from source: String) -> String {
        var lines = source.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == hookMarker }),
              let end = lines[start...].firstIndex(where: { $0.trimmingCharacters(in: .whitespacesAndNewlines) == hookEndMarker }) else {
            return source
        }
        lines.removeSubrange(start...end)
        return lines.joined(separator: "\n")
    }

    private static func hookCommand(cliPath: String, event: Event) -> String {
        let script = #"if [ "$ZENTTY_HERMES_HOOKS_DISABLED" = "1" ]; then echo "{}"; exit 0; fi; "#
            + "\(shellQuotedIfNeeded(cliPath)) hermes-hook \(event.cliEvent) || echo '{}'"
        return "sh -c \(shellQuotedArgument(script))"
    }

    private static func readAllowlist(at url: URL) -> [String: Any] {
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return ["approvals": []]
        }
        return object
    }

    private static func mergedAllowlist(_ allowlist: [String: Any], cliPath: String) -> [String: Any] {
        var next = allowlist
        var approvals = (next["approvals"] as? [[String: Any]]) ?? []
        approvals.removeAll { approval in
            guard let command = approval["command"] as? String else { return false }
            return command.contains("zentty hermes-hook")
        }
        let timestamp = ISO8601DateFormatter().string(from: Date())
        approvals.append(contentsOf: events.map { event in
            [
                "event": event.name,
                "command": hookCommand(cliPath: cliPath, event: event),
                "approved_at": timestamp,
            ]
        })
        next["approvals"] = approvals
        return next
    }

    private static func removeManagedApprovals(from allowlist: [String: Any]) -> [String: Any] {
        var next = allowlist
        let approvals = (next["approvals"] as? [[String: Any]]) ?? []
        next["approvals"] = approvals.filter { approval in
            guard let command = approval["command"] as? String else { return true }
            return !command.contains("zentty hermes-hook")
        }
        return next
    }

    private static func yamlDoubleQuoted(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func shellQuotedIfNeeded(_ value: String) -> String {
        if value.range(of: #"^[A-Za-z0-9_./:=+-]+$"#, options: .regularExpression) != nil {
            return value
        }
        return shellQuotedArgument(value)
    }

    private static func shellQuotedArgument(_ value: String) -> String {
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private static func nonBlank(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
    }
}
