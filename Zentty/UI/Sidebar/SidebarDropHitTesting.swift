import CoreGraphics

/// Hit testing for pane transfer/duplicate drops onto the sidebar.
///
/// This intentionally excludes the active worklane because dropping a pane
/// onto its own worklane is a no-op. Worklane reordering uses
/// `SidebarWorklaneReorderModel` instead.
enum SidebarPaneDropTarget: Equatable {
    case existingWorklane(WorklaneID)
    case newWorklane
    case none
}

enum SidebarPaneDropHitTesting {
    static func target(
        cursorInStrip: CGPoint,
        worklaneFrames: [(WorklaneID, CGRect)],
        activeWorklaneID: WorklaneID?,
        sidebarBottomY: CGFloat
    ) -> SidebarPaneDropTarget {
        for (worklaneID, frame) in worklaneFrames {
            guard worklaneID != activeWorklaneID else { continue }
            if frame.contains(cursorInStrip) {
                return .existingWorklane(worklaneID)
            }
        }

        let lastRowBottomY: CGFloat
        if let lastFrame = worklaneFrames.last?.1 {
            lastRowBottomY = lastFrame.minY
        } else {
            lastRowBottomY = sidebarBottomY + 1000
        }

        let effectiveSidebarBottom = min(sidebarBottomY, lastRowBottomY - 40)
        if cursorInStrip.y < lastRowBottomY && cursorInStrip.y >= effectiveSidebarBottom {
            return .newWorklane
        }

        return .none
    }
}
