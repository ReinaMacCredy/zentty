import Foundation

enum SidebarBookmarkRowAction: Equatable {
    case bookmark
    case saveAsPreset
    case updateBookmark(UUID)
    case editBookmark(UUID)
    case saveAsNewBookmark
    case unlink
}

final class SidebarBookmarkRowActionBox {
    let action: SidebarBookmarkRowAction

    init(action: SidebarBookmarkRowAction) {
        self.action = action
    }
}
