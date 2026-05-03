import AppKit

@MainActor
final class NotificationChromeCoordinator {
    let store: NotificationStore
    let inboxButton: NotificationInboxButton
    private var notificationPopover: NSPopover?
    private var popoverViewModel: NotificationPopoverViewModel?
    private var popoverObserverToken: NSObjectProtocol?
    private weak var parentView: NSView?
    private var currentTheme: ZenttyTheme?
    private var storeObserverID: UUID?

    var onNavigateToNotification: ((AppNotification) -> Void)?

    init(store: NotificationStore = NotificationStore(), inboxButton: NotificationInboxButton = NotificationInboxButton()) {
        self.store = store
        self.inboxButton = inboxButton
    }

    deinit {
        if let storeObserverID {
            MainActor.assumeIsolated {
                store.removeObserver(storeObserverID)
            }
        }
        MainActor.assumeIsolated {
            removePopoverObserver()
        }
    }

    func setup(parentView: NSView, theme: ZenttyTheme) {
        self.parentView = parentView
        self.currentTheme = theme

        inboxButton.onClick = { [weak self] in
            self?.togglePanel()
        }
        inboxButton.update(count: store.unresolvedCount, theme: theme)
        inboxButton.configure(theme: theme, animated: false)

        if let storeObserverID {
            store.removeObserver(storeObserverID)
        }
        storeObserverID = store.addObserver { [weak self] in
            self?.handleStoreChange()
        }
        handleStoreChange()
    }

    func applyTheme(_ theme: ZenttyTheme, animated: Bool) {
        currentTheme = theme
        inboxButton.configure(theme: theme, animated: animated)
        inboxButton.update(count: store.unresolvedCount, theme: theme)
    }

    func closePanel() {
        guard let popover = notificationPopover else { return }
        popover.performClose(nil)
        clearPopoverState(for: popover)
    }

    var isPopoverShownForTesting: Bool {
        notificationPopover?.isShown == true
    }

    var usesNativePopoverChromeForTesting: Bool {
        notificationPopover != nil
    }

    var isPopoverFullSizeContentForTesting: Bool {
        notificationPopover?.hasFullSizeContent == true
    }

    var popoverAnchorRectForTesting: NSRect? {
        popoverAnchorRectInParent()
    }

    static func popoverPreferredEdge(for positioningView: NSView) -> NSRectEdge {
        positioningView.isFlipped ? .maxY : .minY
    }

    // MARK: - Private

    private func handleStoreChange() {
        guard let theme = currentTheme else { return }
        inboxButton.update(count: store.unresolvedCount, theme: theme)
        popoverViewModel?.update(notifications: store.notifications)
        updatePopoverSize()
        let count = store.unresolvedCount
        NSApp.dockTile.badgeLabel = count > 0 ? "\(count)" : nil
    }

    private func togglePanel() {
        if notificationPopover?.isShown == true {
            closePanel()
        } else {
            showPanel()
        }
    }

    private func showPanel() {
        guard notificationPopover?.isShown != true else { return }
        guard let parentView, let anchorRect = popoverAnchorRectInParent() else { return }

        let viewModel = NotificationPopoverViewModel(
            notifications: store.notifications,
            onJumpToLatest: { [weak self] in
                self?.jumpToLatestNotification()
            },
            onClearAll: { [weak self] in
                self?.store.clearAll()
            },
            onActivate: { [weak self] notification in
                self?.closePanel()
                self?.onNavigateToNotification?(notification)
            },
            onDismiss: { [weak self] id in
                self?.store.dismiss(id: id)
            },
            onClose: { [weak self] in
                self?.closePanel()
            }
        )

        let contentController = NotificationPopoverHostingController(viewModel: viewModel)
        let size = preferredPopoverSize()
        contentController.preferredContentSize = size
        contentController.view.frame = NSRect(origin: .zero, size: size)
        contentController.view.autoresizingMask = [.width, .height]

        let popover = NSPopover()
        popover.behavior = .transient
        popover.animates = true
        popover.contentSize = size
        popover.contentViewController = contentController

        notificationPopover = popover
        self.popoverViewModel = viewModel
        installPopoverObserver(for: popover)
        inboxButton.setPopoverPresented(true)
        popover.show(
            relativeTo: anchorRect,
            of: parentView,
            preferredEdge: Self.popoverPreferredEdge(for: parentView)
        )
    }

    private func jumpToLatestNotification() {
        guard let notification = store.mostUrgentUnresolved() else { return }
        closePanel()
        onNavigateToNotification?(notification)
    }

    private func updatePopoverSize() {
        guard let notificationPopover else { return }

        let nextSize = preferredPopoverSize()
        notificationPopover.contentSize = nextSize
        notificationPopover.contentViewController?.preferredContentSize = nextSize
        notificationPopover.contentViewController?.view.frame = NSRect(origin: .zero, size: nextSize)
    }

    private func preferredPopoverSize() -> NSSize {
        NSSize(
            width: NotificationPopoverMetrics.contentWidth,
            height: NotificationPopoverMetrics.preferredHeight(forEmpty: store.notifications.isEmpty)
        )
    }

    private func popoverAnchorRectInParent() -> NSRect? {
        guard let parentView else {
            return nil
        }

        parentView.layoutSubtreeIfNeeded()
        inboxButton.superview?.layoutSubtreeIfNeeded()
        inboxButton.layoutSubtreeIfNeeded()

        let buttonRect = inboxButton.convert(inboxButton.bounds, to: parentView)
        let visualBottomY = parentView.isFlipped ? buttonRect.maxY : buttonRect.minY
        return NSRect(
            x: buttonRect.midX,
            y: visualBottomY,
            width: 1,
            height: 1
        )
    }

    private func installPopoverObserver(for popover: NSPopover) {
        removePopoverObserver()
        popoverObserverToken = NotificationCenter.default.addObserver(
            forName: NSPopover.didCloseNotification,
            object: popover,
            queue: .main
        ) { [weak self, weak popover] _ in
            guard let popover else { return }
            Task { @MainActor in
                self?.clearPopoverState(for: popover)
            }
        }
    }

    private func clearPopoverState(for closingPopover: NSPopover? = nil) {
        if let closingPopover, let notificationPopover, notificationPopover !== closingPopover {
            return
        }
        removePopoverObserver()
        notificationPopover = nil
        popoverViewModel = nil
        inboxButton.setPopoverPresented(false)
    }

    private func removePopoverObserver() {
        if let popoverObserverToken {
            NotificationCenter.default.removeObserver(popoverObserverToken)
            self.popoverObserverToken = nil
        }
    }
}
