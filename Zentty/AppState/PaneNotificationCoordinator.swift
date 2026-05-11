import Foundation

struct PaneNotificationRequest: Equatable, Sendable {
    let title: String
    let subtitle: String?
    let includeInbox: Bool
    let isSilent: Bool
    let windowID: WindowID
    let worklaneID: WorklaneID
    let paneID: PaneID
}

@MainActor
final class PaneNotificationCoordinator {
    private let center: any WorklaneAttentionUserNotificationCenter
    private let notificationStore: NotificationStore
    private let configStore: AppConfigStore?

    init(
        center: (any WorklaneAttentionUserNotificationCenter)? = nil,
        notificationStore: NotificationStore,
        configStore: AppConfigStore?
    ) {
        self.center = center ?? WorklaneAttentionUNCenter()
        self.notificationStore = notificationStore
        self.configStore = configStore
        self.center.requestAuthorizationIfNeeded()
    }

    func deliver(_ request: PaneNotificationRequest) {
        center.add(
            identifier: "pane-notification-\(UUID().uuidString)",
            title: request.title,
            subtitle: request.subtitle,
            body: "",
            windowID: request.windowID.rawValue,
            worklaneID: request.worklaneID.rawValue,
            paneID: request.paneID.rawValue,
            soundName: request.isSilent ? nil : (configStore?.current.notifications.soundName ?? "")
        )

        guard request.includeInbox else {
            return
        }

        notificationStore.add(
            windowID: request.windowID,
            worklaneID: request.worklaneID,
            paneID: request.paneID,
            state: .ready,
            tool: .zentty,
            interactionKind: nil,
            interactionSymbolName: "bell.fill",
            statusText: request.title,
            primaryText: request.subtitle ?? "Notification from pane.",
            locationText: nil,
            isDebounced: false,
            coalescesByPane: false
        )
    }
}
