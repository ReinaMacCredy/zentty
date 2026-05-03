import CoreGraphics

enum BookmarksPopoverMetrics {
    static let contentWidth: CGFloat = 320
    static let emptyStateHeight: CGFloat = 220
    static let populatedDefaultHeight: CGFloat = 320
    static let populatedMaxHeight: CGFloat = 460

    static func preferredHeight(forEmpty isEmpty: Bool) -> CGFloat {
        isEmpty ? emptyStateHeight : populatedDefaultHeight
    }
}
