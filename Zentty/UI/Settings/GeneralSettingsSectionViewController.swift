import AppKit
import os

/// Logs best-effort config-write failures from the settings UI. These persist
/// paths must log and continue rather than crash (see AGENTS.md error handling).
private let settingsLogger = Logger(subsystem: "be.zenjoy.zentty", category: "Settings")

@MainActor
final class GeneralSettingsSectionViewController: SettingsScrollableSectionViewController {
    private let configStore: AppConfigStore
    private var currentConfirmations: AppConfig.Confirmations = .default
    private var currentRestore: AppConfig.Restore = .default
    private var currentClipboard: AppConfig.Clipboard = .default

    private let closePaneSwitch = NSSwitch()
    private let closeWindowSwitch = NSSwitch()
    private let quitSwitch = NSSwitch()
    private let restoreWorkspaceSwitch = NSSwitch()
    private let alwaysCleanCopiesSwitch = NSSwitch()

    init(configStore: AppConfigStore) {
        self.configStore = configStore
        self.currentConfirmations = configStore.current.confirmations
        self.currentRestore = configStore.current.restore
        self.currentClipboard = configStore.current.clipboard
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func assembleContent(in contentView: NSView) {
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        // Confirmations card
        let confirmCard = SettingsCardView()
        let confirmStack = NSStackView()
        confirmStack.orientation = .vertical
        confirmStack.alignment = .leading
        confirmStack.spacing = 0
        confirmStack.translatesAutoresizingMaskIntoConstraints = false
        confirmCard.addSubview(confirmStack)

        let closePaneRow = makeSwitchRow(
            title: "Confirm before closing",
            subtitle: "Show a confirmation dialog when closing a pane.",
            toggle: closePaneSwitch,
            action: #selector(handleClosePaneSwitchChanged(_:))
        )
        confirmStack.addArrangedSubview(closePaneRow)
        closePaneRow.widthAnchor.constraint(equalTo: confirmStack.widthAnchor).isActive = true

        let confirmSeparator1 = NSBox()
        confirmSeparator1.boxType = .separator
        confirmSeparator1.translatesAutoresizingMaskIntoConstraints = false
        confirmStack.addArrangedSubview(confirmSeparator1)
        confirmSeparator1.widthAnchor.constraint(equalTo: confirmStack.widthAnchor).isActive = true

        let closeWindowRow = makeSwitchRow(
            title: "Confirm before closing window",
            subtitle: "Show a confirmation dialog when closing a window with running processes.",
            toggle: closeWindowSwitch,
            action: #selector(handleCloseWindowSwitchChanged(_:))
        )
        confirmStack.addArrangedSubview(closeWindowRow)
        closeWindowRow.widthAnchor.constraint(equalTo: confirmStack.widthAnchor).isActive = true

        let confirmSeparator2 = NSBox()
        confirmSeparator2.boxType = .separator
        confirmSeparator2.translatesAutoresizingMaskIntoConstraints = false
        confirmStack.addArrangedSubview(confirmSeparator2)
        confirmSeparator2.widthAnchor.constraint(equalTo: confirmStack.widthAnchor).isActive = true

        let quitRow = makeSwitchRow(
            title: "Confirm before quitting",
            subtitle: "Show a confirmation dialog when quitting Zentty.",
            toggle: quitSwitch,
            action: #selector(handleQuitSwitchChanged(_:))
        )
        confirmStack.addArrangedSubview(quitRow)
        quitRow.widthAnchor.constraint(equalTo: confirmStack.widthAnchor).isActive = true

        let confirmSeparator3 = NSBox()
        confirmSeparator3.boxType = .separator
        confirmSeparator3.translatesAutoresizingMaskIntoConstraints = false
        confirmStack.addArrangedSubview(confirmSeparator3)
        confirmSeparator3.widthAnchor.constraint(equalTo: confirmStack.widthAnchor).isActive = true

        let restoreRow = makeSwitchRow(
            title: "Restore worklanes on next launch",
            subtitle: "Reopen windows, pane layout, and saved working directories after quitting.",
            toggle: restoreWorkspaceSwitch,
            action: #selector(handleRestoreWorkspaceSwitchChanged(_:))
        )
        confirmStack.addArrangedSubview(restoreRow)
        restoreRow.widthAnchor.constraint(equalTo: confirmStack.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            confirmStack.topAnchor.constraint(equalTo: confirmCard.topAnchor),
            confirmStack.leadingAnchor.constraint(equalTo: confirmCard.leadingAnchor),
            confirmStack.trailingAnchor.constraint(equalTo: confirmCard.trailingAnchor),
            confirmStack.bottomAnchor.constraint(equalTo: confirmCard.bottomAnchor),
        ])

        stackView.addArrangedSubview(confirmCard)
        confirmCard.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        // Clipboard card
        let clipboardCard = SettingsCardView()
        let clipboardStack = NSStackView()
        clipboardStack.orientation = .vertical
        clipboardStack.alignment = .leading
        clipboardStack.spacing = 0
        clipboardStack.translatesAutoresizingMaskIntoConstraints = false
        clipboardCard.addSubview(clipboardStack)

        let cleanCopyRow = makeSwitchRow(
            title: "Always clean copied content",
            subtitle:
                "Remove extra whitespace, color codes, and shell prompts when you copy from the terminal.",
            toggle: alwaysCleanCopiesSwitch,
            action: #selector(handleAlwaysCleanCopiesSwitchChanged(_:))
        )
        clipboardStack.addArrangedSubview(cleanCopyRow)
        cleanCopyRow.widthAnchor.constraint(equalTo: clipboardStack.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            clipboardStack.topAnchor.constraint(equalTo: clipboardCard.topAnchor),
            clipboardStack.leadingAnchor.constraint(equalTo: clipboardCard.leadingAnchor),
            clipboardStack.trailingAnchor.constraint(equalTo: clipboardCard.trailingAnchor),
            clipboardStack.bottomAnchor.constraint(equalTo: clipboardCard.bottomAnchor),
        ])

        stackView.addArrangedSubview(clipboardCard)
        clipboardCard.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        closePaneSwitch.state = currentConfirmations.confirmBeforeClosingPane ? .on : .off
        closeWindowSwitch.state = currentConfirmations.confirmBeforeClosingWindow ? .on : .off
        quitSwitch.state = currentConfirmations.confirmBeforeQuitting ? .on : .off
        restoreWorkspaceSwitch.state = currentRestore.restoreWorkspaceOnLaunch ? .on : .off
        alwaysCleanCopiesSwitch.state = currentClipboard.alwaysCleanCopies ? .on : .off
    }

    func apply(confirmations: AppConfig.Confirmations) {
        currentConfirmations = confirmations
        guard isViewLoaded else { return }
        closePaneSwitch.state = confirmations.confirmBeforeClosingPane ? .on : .off
        closeWindowSwitch.state = confirmations.confirmBeforeClosingWindow ? .on : .off
        quitSwitch.state = confirmations.confirmBeforeQuitting ? .on : .off
    }

    func apply(restore: AppConfig.Restore) {
        currentRestore = restore
        guard isViewLoaded else { return }
        restoreWorkspaceSwitch.state = restore.restoreWorkspaceOnLaunch ? .on : .off
    }

    func apply(clipboard: AppConfig.Clipboard) {
        currentClipboard = clipboard
        guard isViewLoaded else { return }
        alwaysCleanCopiesSwitch.state = clipboard.alwaysCleanCopies ? .on : .off
    }

    // MARK: - Actions

    @objc
    private func handleClosePaneSwitchChanged(_ sender: NSSwitch) {
        try? configStore.update { config in
            config.confirmations.confirmBeforeClosingPane = sender.state == .on
        }
        currentConfirmations = configStore.current.confirmations
    }

    @objc
    private func handleCloseWindowSwitchChanged(_ sender: NSSwitch) {
        try? configStore.update { config in
            config.confirmations.confirmBeforeClosingWindow = sender.state == .on
        }
        currentConfirmations = configStore.current.confirmations
    }

    @objc
    private func handleQuitSwitchChanged(_ sender: NSSwitch) {
        try? configStore.update { config in
            config.confirmations.confirmBeforeQuitting = sender.state == .on
        }
        currentConfirmations = configStore.current.confirmations
    }

    @objc
    private func handleRestoreWorkspaceSwitchChanged(_ sender: NSSwitch) {
        try? configStore.update { config in
            config.restore.restoreWorkspaceOnLaunch = sender.state == .on
        }
        currentRestore = configStore.current.restore
    }

    @objc
    private func handleAlwaysCleanCopiesSwitchChanged(_ sender: NSSwitch) {
        try? configStore.update { config in
            config.clipboard.alwaysCleanCopies = sender.state == .on
        }
        currentClipboard = configStore.current.clipboard
        CleanCopyPipeline.isAutoCleanEnabled = currentClipboard.alwaysCleanCopies
    }

    // MARK: - Helpers

    private func makeSwitchRow(
        title: String,
        subtitle: String,
        toggle: NSSwitch,
        action: Selector
    ) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let leftStack = NSStackView()
        leftStack.orientation = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 2
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = makeLabel(
            text: title,
            font: .systemFont(ofSize: 13, weight: .semibold)
        )
        leftStack.addArrangedSubview(titleLabel)

        let subtitleLabel = makeLabel(
            text: subtitle,
            font: .systemFont(ofSize: 12, weight: .regular)
        )
        subtitleLabel.textColor = .secondaryLabelColor
        leftStack.addArrangedSubview(subtitleLabel)

        toggle.target = self
        toggle.action = action

        container.addSubview(leftStack)
        container.addSubview(toggle)
        toggle.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            leftStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            leftStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            leftStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),

            toggle.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            toggle.leadingAnchor.constraint(
                greaterThanOrEqualTo: leftStack.trailingAnchor, constant: 12),
            toggle.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        ])

        return container
    }

    private func makeLabel(text: String, font: NSFont) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }

    // MARK: - For Testing

    var isClosePaneSwitchOn: Bool {
        closePaneSwitch.state == .on
    }

    var isQuitSwitchOn: Bool {
        quitSwitch.state == .on
    }

    var isRestoreWorkspaceSwitchOn: Bool {
        restoreWorkspaceSwitch.state == .on
    }

    func setRestoreWorkspaceEnabledForTesting(_ enabled: Bool) {
        restoreWorkspaceSwitch.state = enabled ? .on : .off
        handleRestoreWorkspaceSwitchChanged(restoreWorkspaceSwitch)
    }
}

@MainActor
final class AgentsSettingsSectionViewController: SettingsScrollableSectionViewController {
    private let configStore: AppConfigStore
    private let agentTeamsEnableWarningPresenter: AgentTeamsEnableWarningPresenter
    private var currentAgentTeams: AppConfig.AgentTeams
    private var currentAgentCaffeination: AppConfig.AgentCaffeination
    private var currentMenuBar: AppConfig.MenuBar

    private let menuBarStatusSwitch = NSSwitch()
    private let agentTeamsSwitch = NSSwitch()
    private let agentCaffeinationSwitch = NSSwitch()
    private let experimentalBadgeLabel = NSTextField(labelWithString: "EXPERIMENTAL")
    private weak var agentTeamsTitleLabel: NSTextField?

    /// Live controls for one agent-integration row, so toggles and status can
    /// be refreshed when config changes (or a toggle is reverted).
    private struct IntegrationRow {
        let tool: AgentBootstrapTool
        let toggle: NSSwitch
        let statusLabel: NSTextField
        let askPill: NSView?
    }

    private var integrationRows: [IntegrationRow] = []
    private var toolForToggle: [NSSwitch: AgentBootstrapTool] = [:]
    /// Presents the consent panel; injectable for tests. Mirrors the launch-time
    /// consent panel so enabling here is gated by the same prompt.
    private let consentPresenter: @MainActor (AgentBootstrapTool, @escaping (AgentIntegrationState) -> Void) -> Void
    /// Removes a persistent agent's on-disk hooks; injectable so tests can force a
    /// failure without touching disk. Defaults to the real remover.
    private let performUninstall: (AgentBootstrapTool) throws -> Void
    /// Surfaces an uninstall failure (default: a warning NSAlert); injectable for
    /// tests. Receives the host window (nil in headless tests), the tool, and the error.
    private let uninstallFailurePresenter: @MainActor (NSWindow?, AgentBootstrapTool, Error) -> Void

    init(
        configStore: AppConfigStore,
        agentTeamsEnableWarningPresenter: @escaping AgentTeamsEnableWarningPresenter =
            AgentTeamsEnableWarning.present,
        consentPresenter: @escaping @MainActor (AgentBootstrapTool, @escaping (AgentIntegrationState) -> Void) -> Void =
            AgentIntegrationConsentPanel.present,
        performUninstall: @escaping (AgentBootstrapTool) throws -> Void = AgentIntegrationHooks.uninstall,
        uninstallFailurePresenter: @escaping @MainActor (NSWindow?, AgentBootstrapTool, Error) -> Void =
            AgentIntegrationUninstallFailureAlert.present
    ) {
        self.configStore = configStore
        self.agentTeamsEnableWarningPresenter = agentTeamsEnableWarningPresenter
        self.consentPresenter = consentPresenter
        self.performUninstall = performUninstall
        self.uninstallFailurePresenter = uninstallFailurePresenter
        self.currentAgentTeams = configStore.current.agentTeams
        self.currentAgentCaffeination = configStore.current.agentCaffeination
        self.currentMenuBar = configStore.current.menuBar
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func assembleContent(in contentView: NSView) {
        let stackView = NSStackView()
        stackView.orientation = .vertical
        stackView.alignment = .leading
        stackView.spacing = 16
        stackView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stackView)

        let card = SettingsCardView()
        let cardStack = NSStackView()
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 0
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)

        let menuBarStatusRow = makeMenuBarStatusRow()
        cardStack.addArrangedSubview(menuBarStatusRow)
        menuBarStatusRow.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true

        addSeparator(to: cardStack)

        let agentTeamsRow = makeAgentTeamsRow()
        cardStack.addArrangedSubview(agentTeamsRow)
        agentTeamsRow.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true

        addSeparator(to: cardStack)

        let agentCaffeinationRow = makeAgentCaffeinationRow()
        cardStack.addArrangedSubview(agentCaffeinationRow)
        agentCaffeinationRow.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: card.topAnchor),
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])

        stackView.addArrangedSubview(card)
        card.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        let integrationsHeader = makeIntegrationsSectionHeader()
        stackView.addArrangedSubview(integrationsHeader)
        integrationsHeader.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        let integrationsCard = makeIntegrationsCard()
        stackView.addArrangedSubview(integrationsCard)
        integrationsCard.widthAnchor.constraint(equalTo: stackView.widthAnchor).isActive = true

        NSLayoutConstraint.activate([
            stackView.topAnchor.constraint(equalTo: contentView.topAnchor),
            stackView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            stackView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            stackView.bottomAnchor.constraint(lessThanOrEqualTo: contentView.bottomAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        menuBarStatusSwitch.state = currentMenuBar.showStatusItem ? .on : .off
        agentTeamsSwitch.state = currentAgentTeams.enabled ? .on : .off
        agentCaffeinationSwitch.state = currentAgentCaffeination.enabled ? .on : .off
        refreshIntegrationControls()
    }

    func apply(
        agentTeams: AppConfig.AgentTeams,
        agentCaffeination: AppConfig.AgentCaffeination,
        menuBar: AppConfig.MenuBar
    ) {
        currentAgentTeams = agentTeams
        currentAgentCaffeination = agentCaffeination
        currentMenuBar = menuBar
        guard isViewLoaded else { return }
        menuBarStatusSwitch.state = menuBar.showStatusItem ? .on : .off
        agentTeamsSwitch.state = agentTeams.enabled ? .on : .off
        agentCaffeinationSwitch.state = agentCaffeination.enabled ? .on : .off
        refreshIntegrationControls()
    }

    private func makeMenuBarStatusRow() -> NSView {
        let row = makeAgentSwitchRow(
            title: "Show agent status in menu bar",
            subtitle: "Display a Zentty menu bar icon with live waiting, running, and idle agent panes.",
            toggle: menuBarStatusSwitch,
            action: #selector(handleMenuBarStatusSwitchChanged(_:))
        )
        return row
    }

    private func makeAgentTeamsRow() -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let leftStack = NSStackView()
        leftStack.orientation = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 4
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        let titleRow = NSView()
        titleRow.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = makeLabel(
            text: "Claude Code agent teams",
            font: .systemFont(ofSize: 13, weight: .semibold)
        )
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        agentTeamsTitleLabel = titleLabel
        configureExperimentalBadge()
        experimentalBadgeLabel.translatesAutoresizingMaskIntoConstraints = false

        titleRow.addSubview(titleLabel)
        titleRow.addSubview(experimentalBadgeLabel)
        NSLayoutConstraint.activate([
            titleLabel.topAnchor.constraint(equalTo: titleRow.topAnchor),
            titleLabel.leadingAnchor.constraint(equalTo: titleRow.leadingAnchor),
            titleLabel.bottomAnchor.constraint(equalTo: titleRow.bottomAnchor),

            experimentalBadgeLabel.leadingAnchor.constraint(equalTo: titleLabel.trailingAnchor, constant: 8),
            experimentalBadgeLabel.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor, constant: 1),
            experimentalBadgeLabel.trailingAnchor.constraint(lessThanOrEqualTo: titleRow.trailingAnchor),
        ])
        leftStack.addArrangedSubview(titleRow)

        let subtitleLabel = makeLabel(
            text:
                "Render Claude Code's subagents as native Zentty panes when team mode is enabled.",
            font: .systemFont(ofSize: 12, weight: .regular)
        )
        subtitleLabel.textColor = .secondaryLabelColor
        leftStack.addArrangedSubview(subtitleLabel)

        agentTeamsSwitch.target = self
        agentTeamsSwitch.action = #selector(handleAgentTeamsSwitchChanged(_:))

        container.addSubview(leftStack)
        container.addSubview(agentTeamsSwitch)
        agentTeamsSwitch.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            leftStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            leftStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            leftStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),

            agentTeamsSwitch.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            agentTeamsSwitch.leadingAnchor.constraint(
                greaterThanOrEqualTo: leftStack.trailingAnchor,
                constant: 12
            ),
            agentTeamsSwitch.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        ])

        return container
    }

    private func makeAgentCaffeinationRow() -> NSView {
        makeAgentSwitchRow(
            title: "Prevent sleep while agents run",
            subtitle: "Keep the Mac awake while an agent pane is running. The display can still sleep.",
            toggle: agentCaffeinationSwitch,
            action: #selector(handleAgentCaffeinationSwitchChanged(_:))
        )
    }

    private func makeAgentSwitchRow(
        title: String,
        subtitle: String,
        toggle: NSSwitch,
        action: Selector
    ) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let leftStack = NSStackView()
        leftStack.orientation = .vertical
        leftStack.alignment = .leading
        leftStack.spacing = 4
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        let titleLabel = makeLabel(
            text: title,
            font: .systemFont(ofSize: 13, weight: .semibold)
        )
        leftStack.addArrangedSubview(titleLabel)

        let subtitleLabel = makeLabel(
            text: subtitle,
            font: .systemFont(ofSize: 12, weight: .regular)
        )
        subtitleLabel.textColor = .secondaryLabelColor
        leftStack.addArrangedSubview(subtitleLabel)

        toggle.target = self
        toggle.action = action

        container.addSubview(leftStack)
        container.addSubview(toggle)
        toggle.translatesAutoresizingMaskIntoConstraints = false

        NSLayoutConstraint.activate([
            leftStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 14),
            leftStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            leftStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -14),

            toggle.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            toggle.leadingAnchor.constraint(
                greaterThanOrEqualTo: leftStack.trailingAnchor,
                constant: 12
            ),
            toggle.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        ])

        return container
    }

    @discardableResult
    private func addSeparator(to stack: NSStackView) -> NSView {
        let separator = NSBox()
        separator.boxType = .separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        // Add to the stack before activating the width constraint: the anchor
        // pair needs a common ancestor at activation time, otherwise AppKit
        // throws and aborts assembleContent (leaving the pane blank).
        stack.addArrangedSubview(separator)
        separator.widthAnchor.constraint(equalTo: stack.widthAnchor).isActive = true
        return separator
    }

    private func configureExperimentalBadge() {
        experimentalBadgeLabel.font = .systemFont(ofSize: 10, weight: .bold)
        experimentalBadgeLabel.textColor = .secondaryLabelColor
        experimentalBadgeLabel.alignment = .center
        experimentalBadgeLabel.wantsLayer = true
        experimentalBadgeLabel.layer?.cornerRadius = 5
        experimentalBadgeLabel.layer?.cornerCurve = .continuous
        experimentalBadgeLabel.layer?.backgroundColor = NSColor.systemOrange
            .withAlphaComponent(0.16)
            .cgColor
        experimentalBadgeLabel.layer?.borderColor = NSColor.systemOrange
            .withAlphaComponent(0.35)
            .cgColor
        experimentalBadgeLabel.layer?.borderWidth = 1
        experimentalBadgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        experimentalBadgeLabel.widthAnchor.constraint(greaterThanOrEqualToConstant: 84).isActive = true
        experimentalBadgeLabel.heightAnchor.constraint(equalToConstant: 16).isActive = true
    }

    @objc
    private func handleMenuBarStatusSwitchChanged(_ sender: NSSwitch) {
        do {
            try configStore.update { config in
                config.menuBar.showStatusItem = sender.state == .on
            }
        } catch {
            settingsLogger.error(
                "Failed to persist menu-bar status-item visibility: \(error.localizedDescription, privacy: .public)")
        }
        currentMenuBar = configStore.current.menuBar
        menuBarStatusSwitch.state = currentMenuBar.showStatusItem ? .on : .off
    }

    @objc
    private func handleAgentTeamsSwitchChanged(_ sender: NSSwitch) {
        requestAgentTeamsChange(to: sender.state == .on)
    }

    @objc
    private func handleAgentCaffeinationSwitchChanged(_ sender: NSSwitch) {
        persistAgentCaffeinationEnabled(sender.state == .on)
    }

    private func requestAgentTeamsChange(to requestedValue: Bool) {
        guard requestedValue != currentAgentTeams.enabled else {
            agentTeamsSwitch.state = currentAgentTeams.enabled ? .on : .off
            return
        }

        if requestedValue == false {
            persistAgentTeamsEnabled(false)
            return
        }

        guard let window = view.window else {
            agentTeamsSwitch.state = currentAgentTeams.enabled ? .on : .off
            return
        }

        agentTeamsSwitch.state = .off
        agentTeamsEnableWarningPresenter(window) { [weak self] decision in
            guard let self else { return }
            if decision == .enable {
                self.persistAgentTeamsEnabled(true)
            } else {
                self.agentTeamsSwitch.state = self.currentAgentTeams.enabled ? .on : .off
            }
        }
    }

    private func persistAgentTeamsEnabled(_ enabled: Bool) {
        do {
            try configStore.update { config in
                config.agentTeams.enabled = enabled
            }
        } catch {
            settingsLogger.error(
                "Failed to persist agent-teams enabled state: \(error.localizedDescription, privacy: .public)")
        }
        currentAgentTeams = configStore.current.agentTeams
        agentTeamsSwitch.state = currentAgentTeams.enabled ? .on : .off
    }

    private func persistAgentCaffeinationEnabled(_ enabled: Bool) {
        do {
            try configStore.update { config in
                config.agentCaffeination.enabled = enabled
            }
        } catch {
            settingsLogger.error(
                "Failed to persist agent-caffeination enabled state: \(error.localizedDescription, privacy: .public)")
        }
        currentAgentCaffeination = configStore.current.agentCaffeination
        agentCaffeinationSwitch.state = currentAgentCaffeination.enabled ? .on : .off
    }

    private func makeLabel(text: String, font: NSFont) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = font
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        return label
    }

    // MARK: - Agent integrations

    private func makeIntegrationsSectionHeader() -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 4
        stack.translatesAutoresizingMaskIntoConstraints = false

        let title = makeLabel(text: "Agent integrations", font: .systemFont(ofSize: 13, weight: .semibold))
        let subtitle = makeLabel(
            text: "Enable or disable each agent's Zentty integration. Agents that modify your "
                + "configuration ask before installing hooks; turn any integration off if it misbehaves.",
            font: .systemFont(ofSize: 12)
        )
        subtitle.textColor = .secondaryLabelColor
        stack.addArrangedSubview(title)
        stack.addArrangedSubview(subtitle)
        return stack
    }

    private func makeIntegrationsCard() -> NSView {
        integrationRows = []
        toolForToggle = [:]

        let card = SettingsCardView()
        let cardStack = NSStackView()
        cardStack.orientation = .vertical
        cardStack.alignment = .leading
        cardStack.spacing = 0
        cardStack.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(cardStack)

        func appendRow(_ view: NSView, separatorBefore: Bool) {
            if separatorBefore {
                addSeparator(to: cardStack)
            }
            cardStack.addArrangedSubview(view)
            view.widthAnchor.constraint(equalTo: cardStack.widthAnchor).isActive = true
        }

        appendRow(makeIntegrationGroupHeader("MODIFIES YOUR CONFIG"), separatorBefore: false)
        for tool in AgentIntegrationConsent.persistentTools {
            appendRow(makeIntegrationRow(tool: tool), separatorBefore: true)
        }

        appendRow(makeIntegrationGroupHeader("BUILT-IN"), separatorBefore: true)
        for tool in AgentIntegrationConsent.ephemeralTools {
            appendRow(makeIntegrationRow(tool: tool), separatorBefore: true)
        }

        NSLayoutConstraint.activate([
            cardStack.topAnchor.constraint(equalTo: card.topAnchor),
            cardStack.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardStack.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            cardStack.bottomAnchor.constraint(equalTo: card.bottomAnchor),
        ])
        return card
    }

    private func makeIntegrationGroupHeader(_ title: String) -> NSView {
        let container = NSView()
        let label = makeLabel(text: title, font: .systemFont(ofSize: 11, weight: .semibold))
        label.textColor = .tertiaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(label)
        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(lessThanOrEqualTo: container.trailingAnchor, constant: -16),
            label.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            label.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -6),
        ])
        return container
    }

    private func makeIntegrationRow(tool: AgentBootstrapTool) -> NSView {
        let container = NSView()
        container.translatesAutoresizingMaskIntoConstraints = false

        let icon = NSImageView()
        icon.image = MenuBarStatusIconRenderer.agentIconTemplateImage(for: tool.agentTool)
        icon.image?.isTemplate = true
        icon.contentTintColor = .secondaryLabelColor
        icon.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 18),
            icon.heightAnchor.constraint(equalToConstant: 18),
        ])

        let nameLabel = makeLabel(text: tool.integrationDisplayName, font: .systemFont(ofSize: 13, weight: .semibold))

        let nameRow = NSStackView(views: [nameLabel])
        nameRow.orientation = .horizontal
        nameRow.alignment = .centerY
        nameRow.spacing = 8
        if tool.integrationClass == .persistent {
            nameRow.addArrangedSubview(makeIntegrationBadge("Modifies config"))
        }

        let statusLabel = makeLabel(text: "", font: .systemFont(ofSize: 12))
        statusLabel.textColor = .secondaryLabelColor

        let askPill: NSView? = tool.integrationClass == .persistent ? makeAskPill() : nil

        let infoStack = NSStackView(views: [nameRow, statusLabel])
        if let askPill {
            infoStack.addArrangedSubview(askPill)
        }
        infoStack.orientation = .vertical
        infoStack.alignment = .leading
        infoStack.spacing = 3

        let toggle = NSSwitch()
        toggle.target = self
        toggle.action = #selector(handleIntegrationToggle(_:))
        toggle.translatesAutoresizingMaskIntoConstraints = false
        toolForToggle[toggle] = tool

        let leftStack = NSStackView(views: [icon, infoStack])
        leftStack.orientation = .horizontal
        leftStack.alignment = .centerY
        leftStack.spacing = 10
        leftStack.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(leftStack)
        container.addSubview(toggle)
        NSLayoutConstraint.activate([
            leftStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 12),
            leftStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 16),
            leftStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -12),

            toggle.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            toggle.leadingAnchor.constraint(greaterThanOrEqualTo: leftStack.trailingAnchor, constant: 12),
            toggle.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -16),
        ])

        integrationRows.append(
            IntegrationRow(tool: tool, toggle: toggle, statusLabel: statusLabel, askPill: askPill)
        )
        return container
    }

    private func makeIntegrationBadge(_ text: String) -> NSView {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 10, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.cornerRadius = 5
        label.layer?.cornerCurve = .continuous
        label.layer?.backgroundColor = NSColor.quaternaryLabelColor.withAlphaComponent(0.18).cgColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.heightAnchor.constraint(equalToConstant: 16).isActive = true
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: CGFloat(text.count) * 7 + 12).isActive = true
        return label
    }

    private func makeAskPill() -> NSView {
        let label = NSTextField(labelWithString: "Asks on first launch")
        label.font = .systemFont(ofSize: 11, weight: .medium)
        label.textColor = .systemOrange
        label.alignment = .center
        label.wantsLayer = true
        label.layer?.cornerRadius = 6
        label.layer?.cornerCurve = .continuous
        label.layer?.backgroundColor = NSColor.systemOrange.withAlphaComponent(0.14).cgColor
        label.translatesAutoresizingMaskIntoConstraints = false
        label.setContentHuggingPriority(.required, for: .horizontal)
        label.heightAnchor.constraint(equalToConstant: 18).isActive = true
        label.widthAnchor.constraint(greaterThanOrEqualToConstant: 150).isActive = true
        return label
    }

    func refreshIntegrationControls() {
        guard isViewLoaded else { return }
        let integrations = configStore.current.agentIntegrations
        for row in integrationRows {
            let state = integrations.state(for: row.tool)
            row.toggle.state = (state == .on) ? .on : .off
            let isAsk = (state == .ask)
            row.askPill?.isHidden = !isAsk
            row.statusLabel.isHidden = isAsk
            let status = statusDisplay(for: state, tool: row.tool)
            row.statusLabel.stringValue = status.text
            row.statusLabel.textColor = status.color
        }
    }

    private struct IntegrationStatus {
        let text: String
        let color: NSColor
    }

    /// Resolves the status line's text and color together so they never drift.
    /// For an `.on` persistent agent we read disk once: hooks the user expects
    /// can be removed outside Zentty (manual edit of the agent's config), and a
    /// missing install must read as a warning, not as a pristine fresh state.
    private func statusDisplay(for state: AgentIntegrationState, tool: AgentBootstrapTool) -> IntegrationStatus {
        switch state {
        case .ask:
            return IntegrationStatus(text: "Asks on first launch", color: .systemOrange)
        case .off:
            return IntegrationStatus(text: "Disabled", color: .tertiaryLabelColor)
        case .on:
            guard tool.integrationClass == .persistent else {
                return IntegrationStatus(text: "Enabled", color: .secondaryLabelColor)
            }
            if AgentIntegrationHooks.isInstalled(tool) {
                return IntegrationStatus(text: "Hooks installed", color: .secondaryLabelColor)
            }
            return IntegrationStatus(
                text: "Hooks missing — reinstalls on next launch",
                color: .systemOrange
            )
        }
    }

    @objc
    private func handleIntegrationToggle(_ sender: NSSwitch) {
        guard let tool = toolForToggle[sender] else { return }
        let wantsOn = sender.state == .on

        if tool.integrationClass == .ephemeral {
            setIntegrationState(tool, wantsOn ? .on : .off)
            return
        }

        if wantsOn {
            // Any disk write is gated by the same consent panel as first launch;
            // only persist On if the user confirms, otherwise revert the switch.
            consentPresenter(tool) { [weak self] decision in
                guard let self else { return }
                if decision == .on {
                    self.setIntegrationState(tool, .on)
                } else {
                    self.refreshIntegrationControls()
                }
            }
        } else {
            // Turning off removes our hooks from disk (parity with `zentty
            // uninstall`), then records the choice. The state is recorded as off
            // regardless of the disk outcome — but if removal fails we log and
            // warn the user, so stale hooks don't keep reporting status silently.
            do {
                try performUninstall(tool)
            } catch {
                settingsLogger.error(
                    "Failed to uninstall \(tool.rawValue, privacy: .public) hooks: \(error.localizedDescription, privacy: .public)")
                uninstallFailurePresenter(view.window, tool, error)
            }
            setIntegrationState(tool, .off)
        }
    }

    private func setIntegrationState(_ tool: AgentBootstrapTool, _ state: AgentIntegrationState) {
        do {
            try configStore.update { config in
                config.agentIntegrations.states[tool.rawValue] = state
            }
        } catch {
            settingsLogger.error(
                "Failed to persist \(tool.rawValue, privacy: .public) integration state: \(error.localizedDescription, privacy: .public)")
        }
        refreshIntegrationControls()
    }

    var isAgentTeamsSwitchOn: Bool {
        agentTeamsSwitch.state == .on
    }

    var isMenuBarStatusSwitchOn: Bool {
        menuBarStatusSwitch.state == .on
    }

    var isAgentCaffeinationSwitchOn: Bool {
        agentCaffeinationSwitch.state == .on
    }

    var experimentalBadgeText: String {
        experimentalBadgeLabel.stringValue
    }

    var experimentalBadgeTitleCenterYOffset: CGFloat? {
        guard let titleLabel = agentTeamsTitleLabel else { return nil }
        return titleLabel.frame.midY - experimentalBadgeLabel.frame.midY
    }

    func setAgentTeamsEnabledForTesting(_ enabled: Bool) {
        agentTeamsSwitch.state = enabled ? .on : .off
        requestAgentTeamsChange(to: enabled)
    }

    func setMenuBarStatusEnabledForTesting(_ enabled: Bool) {
        menuBarStatusSwitch.state = enabled ? .on : .off
        handleMenuBarStatusSwitchChanged(menuBarStatusSwitch)
    }

    func setAgentCaffeinationEnabledForTesting(_ enabled: Bool) {
        agentCaffeinationSwitch.state = enabled ? .on : .off
        persistAgentCaffeinationEnabled(enabled)
    }

    /// Drives an integration row's toggle and runs the same handler the real
    /// switch would, so tests can exercise enable/disable + consent/uninstall.
    func simulateIntegrationToggleForTesting(_ tool: AgentBootstrapTool, on: Bool) {
        guard let row = integrationRows.first(where: { $0.tool == tool }) else { return }
        row.toggle.state = on ? .on : .off
        handleIntegrationToggle(row.toggle)
    }
}
