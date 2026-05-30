import AppKit

/// First-run consent prompt for a persistent-config agent. Shown the first time
/// such an agent launches, or when enabling one from Settings. Explains what
/// Zentty will write to the user's config and offers Enable / Not Now.
///
/// The panel floats centered above the app; it does not run a nested modal loop,
/// so the rest of Zentty stays usable while the agent itself stays halted (its
/// launch is blocked on the IPC handshake until this resolves). `completion`
/// fires exactly once with `.on` (install hooks) or `.off` (skip).
@MainActor
enum AgentIntegrationConsentPanel {
    static func present(
        tool: AgentBootstrapTool,
        completion: @escaping (AgentIntegrationState) -> Void
    ) {
        AgentIntegrationConsentWindowController.present(tool: tool, completion: completion)
    }
}

@MainActor
private final class AgentIntegrationConsentWindowController: NSWindowController, NSWindowDelegate {
    /// Live controller per tool. Concurrent prompts for the same agent (e.g. a
    /// launch-time prompt and a Settings toggle) coalesce onto one window
    /// instead of stacking; all queued completions fire once on resolve. The
    /// dictionary also keeps the controller alive until its window closes.
    private static var live: [AgentBootstrapTool: AgentIntegrationConsentWindowController] = [:]

    /// Open the panel for `tool`, or attach `completion` to the one already
    /// open for it.
    static func present(
        tool: AgentBootstrapTool,
        completion: @escaping (AgentIntegrationState) -> Void
    ) {
        if let existing = live[tool] {
            existing.completions.append(completion)
            existing.bringToFront()
            return
        }
        let controller = AgentIntegrationConsentWindowController(tool: tool, completion: completion)
        live[tool] = controller
        controller.bringToFront()
    }

    private let tool: AgentBootstrapTool
    private var completions: [(AgentIntegrationState) -> Void]
    private var hasResolved = false
    private let detailsLabel = NSTextField(wrappingLabelWithString: "")
    private var detailsVisible = false

    init(tool: AgentBootstrapTool, completion: @escaping (AgentIntegrationState) -> Void) {
        self.tool = tool
        self.completions = [completion]
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.level = .floating
        window.titlebarAppearsTransparent = true
        window.title = ""
        super.init(window: window)
        window.delegate = self
        window.contentView = makeContentView()
        window.setContentSize(window.contentView?.fittingSize ?? NSSize(width: 460, height: 240))
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    private func bringToFront() {
        window?.center()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    // MARK: - Content

    private func makeContentView() -> NSView {
        let name = tool.integrationDisplayName

        let icon = NSImageView()
        icon.image = MenuBarStatusIconRenderer.agentIconTemplateImage(for: tool.agentTool)
        icon.image?.isTemplate = true
        icon.contentTintColor = .controlAccentColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 38),
            icon.heightAnchor.constraint(equalToConstant: 38),
        ])

        let title = NSTextField(labelWithString: "Enable \(name) status in Zentty?")
        title.font = .systemFont(ofSize: 15, weight: .semibold)
        title.lineBreakMode = .byWordWrapping
        title.maximumNumberOfLines = 0

        let header = NSStackView(views: [icon, title])
        header.orientation = .horizontal
        header.alignment = .centerY
        header.spacing = 12

        let body = NSTextField(wrappingLabelWithString:
            "Zentty can show \(name)'s live status in the sidebar and notify you when it needs input. "
            + "This requires installing status hooks in your \(name) configuration.")
        body.font = .systemFont(ofSize: 13)
        body.textColor = .secondaryLabelColor

        let stack = NSStackView(views: [header, body])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false

        if let path = tool.integrationConfigPathDisplay {
            stack.addArrangedSubview(makePathBox(path: path))

            let disclosure = NSButton(title: "Show what changes", target: self, action: #selector(toggleDetails))
            disclosure.bezelStyle = .inline
            disclosure.isBordered = false
            disclosure.contentTintColor = .controlAccentColor
            disclosure.font = .systemFont(ofSize: 12)
            stack.addArrangedSubview(disclosure)

            detailsLabel.stringValue =
                "Zentty adds its status-hook entries to the file above (marked so they can be found again) "
                + "and changes nothing else. They are removed when you turn this off, or via `zentty uninstall`."
            detailsLabel.font = .systemFont(ofSize: 12)
            detailsLabel.textColor = .secondaryLabelColor
            detailsLabel.isHidden = true
            stack.addArrangedSubview(detailsLabel)
        }

        let reversibility = NSTextField(wrappingLabelWithString: "You can turn this off anytime in Settings › Agents.")
        reversibility.font = .systemFont(ofSize: 12)
        reversibility.textColor = .tertiaryLabelColor
        stack.addArrangedSubview(reversibility)

        let notNow = NSButton(title: "Not Now", target: self, action: #selector(declineTapped))
        notNow.bezelStyle = .rounded
        notNow.keyEquivalent = "\u{1b}" // Escape
        let enable = NSButton(title: "Enable", target: self, action: #selector(enableTapped))
        enable.bezelStyle = .rounded
        enable.keyEquivalent = "\r" // Return — default button
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let buttons = NSStackView(views: [spacer, notNow, enable])
        buttons.orientation = .horizontal
        buttons.spacing = 10
        stack.addArrangedSubview(buttons)
        buttons.leadingAnchor.constraint(equalTo: stack.leadingAnchor).isActive = true
        buttons.trailingAnchor.constraint(equalTo: stack.trailingAnchor).isActive = true

        let container = NSView()
        container.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: container.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalToConstant: 412),
        ])
        return container
    }

    private func makePathBox(path: String) -> NSView {
        let label = NSTextField(labelWithString: path)
        label.font = .monospacedSystemFont(ofSize: 12, weight: .regular)
        label.textColor = .labelColor
        label.lineBreakMode = .byTruncatingMiddle
        label.translatesAutoresizingMaskIntoConstraints = false

        let box = NSView()
        box.wantsLayer = true
        box.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.12).cgColor
        box.layer?.cornerRadius = 6
        box.translatesAutoresizingMaskIntoConstraints = false
        box.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: box.leadingAnchor, constant: 10),
            label.trailingAnchor.constraint(equalTo: box.trailingAnchor, constant: -10),
            label.topAnchor.constraint(equalTo: box.topAnchor, constant: 7),
            label.bottomAnchor.constraint(equalTo: box.bottomAnchor, constant: -7),
        ])
        return box
    }

    // MARK: - Actions

    @objc private func toggleDetails() {
        detailsVisible.toggle()
        detailsLabel.isHidden = !detailsVisible
        if let window, let content = window.contentView {
            window.setContentSize(content.fittingSize)
            window.center()
        }
    }

    @objc private func enableTapped() { finish(.on) }
    @objc private func declineTapped() { finish(.off) }

    private func finish(_ state: AgentIntegrationState) {
        deliver(state)
        window?.close()
    }

    /// Fire all queued completions once and drop the per-tool registration.
    /// Idempotent: `finish` calls this then `window.close()`, which re-enters
    /// through `windowWillClose`.
    private func deliver(_ state: AgentIntegrationState) {
        guard !hasResolved else { return }
        hasResolved = true
        if Self.live[tool] === self { Self.live[tool] = nil }
        let pending = completions
        completions = []
        for completion in pending { completion(state) }
    }

    // MARK: - NSWindowDelegate

    func windowWillClose(_ notification: Notification) {
        // Closing without choosing is a decline.
        deliver(.off)
    }
}
