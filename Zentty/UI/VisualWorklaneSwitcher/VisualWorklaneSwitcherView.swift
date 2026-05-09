import AppKit

/// Overlay rendered above `AppCanvasView` while visual mode is open. Renders
/// the dim layer over non-selected panes, the accent border around the
/// highlighted pane, the HUD (proctitle / folder / branch), and — for multi-
/// worklane windows — peeking neighbor lanes above and below the active band.
@MainActor
final class VisualWorklaneSwitcherView: NSView {

    private let dimLayer = CAShapeLayer()
    private let highlightLayer = CAShapeLayer()
    private let hud = VisualSwitcherHUDView()
    private weak var anchorPaneStripView: PaneStripView?

    /// Neighbor carriers, indexed by relative offset from the active worklane:
    /// −2, −1, +1, +2. The active worklane is rendered by the underlying
    /// `appCanvasView.paneStripView`, not by a carrier.
    private var laneCarriers: [Int: VisualSwitcherLaneView] = [:]

    private struct HUDPlacement {
        let targetZoomScale: CGFloat
        let visibleLeadingInset: CGFloat
    }
    private var hudPlacement: HUDPlacement?

    /// Padding around the highlighted pane's bounds for the accent border.
    private let highlightInset: CGFloat = -2

    /// Vertical gap between the column's top edge and the HUD pill above it.
    private let hudGap: CGFloat = 12

    /// Layout constants for neighbor lanes. Sizes are expressed as fractions
    /// of the **active band** size so neighbors share its aspect ratio
    /// exactly — prevents the carrier-vs-band aspect mismatch that would
    /// cause letterboxing inside the carrier.
    private enum NeighborLayout {
        /// ±1 lanes — fully visible, ~55% of the active band area.
        static let primaryFraction: CGFloat = 0.55
        /// ±2 lanes — peeking, ~30% of the active band area.
        static let peekingFraction: CGFloat = 0.30
        /// Vertical gap between adjacent bands.
        static let bandGap: CGFloat = 10
    }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        configure()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func configure() {
        wantsLayer = true

        dimLayer.fillColor = NSColor.black.withAlphaComponent(0.18).cgColor
        dimLayer.fillRule = .evenOdd
        layer?.addSublayer(dimLayer)

        highlightLayer.fillColor = NSColor.clear.cgColor
        highlightLayer.strokeColor = NSColor.controlAccentColor.cgColor
        highlightLayer.lineWidth = 2.5
        highlightLayer.shadowColor = NSColor.controlAccentColor.cgColor
        highlightLayer.shadowOpacity = 0.6
        highlightLayer.shadowRadius = 6
        highlightLayer.shadowOffset = .zero
        layer?.addSublayer(highlightLayer)

        hud.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hud)
    }

    // MARK: - Public API

    func attach(paneStripView: PaneStripView) {
        anchorPaneStripView = paneStripView
    }

    func detach() {
        anchorPaneStripView = nil
        dimLayer.path = nil
        highlightLayer.path = nil
        hud.content = .init()
        hudPlacement = nil
        teardownNeighborLanes()
    }

    /// Set up the neighbor carriers for one visual-mode session.
    /// `worklanes` is in the same order as `WorklaneStore.worklanes`. The
    /// active worklane is identified by `activeIndex` and is *not* rendered
    /// here (the existing pane strip handles it). Carriers are positioned
    /// once and don't reflow during the session.
    func configureNeighborLanes(
        worklanes: [WorklaneState],
        activeIndex: Int,
        canvasSize: CGSize,
        runtimeRegistry: PaneRuntimeRegistry,
        theme: ZenttyTheme
    ) {
        teardownNeighborLanes()

        let neighborOffsets: [Int] = [-2, -1, 1, 2]
        for offset in neighborOffsets {
            let neighborIndex = activeIndex + offset
            guard worklanes.indices.contains(neighborIndex) else { continue }

            let ring: VisualSwitcherLaneView.Ring = abs(offset) == 1 ? .primary : .peeking
            let carrier = VisualSwitcherLaneView(runtimeRegistry: runtimeRegistry, ring: ring)
            // Carrier is positioned via direct frame assignment in
            // layoutNeighborCarriers — keep autoresizing translation on so
            // the explicit frames stick instead of being clobbered by AL.
            carrier.translatesAutoresizingMaskIntoConstraints = true
            insertNeighborSubview(carrier)
            laneCarriers[offset] = carrier
        }
        // Size carriers BEFORE binding state so each carrier's bounds is
        // known when its layer-scale math runs.
        layoutNeighborCarriers()

        for (offset, carrier) in laneCarriers {
            let neighborIndex = activeIndex + offset
            guard worklanes.indices.contains(neighborIndex) else { continue }
            carrier.bind(
                worklane: worklanes[neighborIndex],
                theme: theme,
                canvasSize: canvasSize
            )
            // Stagger: ±1 fades in immediately, ±2 a beat later as a hint.
            let delay: TimeInterval = abs(offset) == 1 ? 0.10 : 0.25
            carrier.appear(after: delay)
        }
    }

    private func insertNeighborSubview(_ carrier: VisualSwitcherLaneView) {
        if hud.superview === self {
            addSubview(carrier, positioned: .below, relativeTo: hud)
        } else {
            addSubview(carrier)
        }
    }

    private func teardownNeighborLanes() {
        for (_, carrier) in laneCarriers {
            carrier.detach()
            carrier.removeFromSuperview()
        }
        laneCarriers.removeAll()
    }

    /// Update the highlight to point at `paneID` (in any visible lane),
    /// refresh HUD content, and recompute the HUD frame so the box stays
    /// centered on its x-axis midpoint as content widths change. The HUD's
    /// *center* is the stable beacon — content can grow or shrink and the
    /// box widens/narrows symmetrically around the visible-canvas center.
    func update(highlightedPaneID: PaneID, hudContent: VisualSwitcherHUDView.Content) {
        guard let highlightRect = highlightRectFor(paneID: highlightedPaneID) else { return }
        let cornerRadius: CGFloat = 8

        let outer = CGMutablePath()
        outer.addRect(bounds)
        outer.addPath(CGPath(roundedRect: highlightRect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil))
        dimLayer.path = outer

        highlightLayer.path = CGPath(
            roundedRect: highlightRect,
            cornerWidth: cornerRadius,
            cornerHeight: cornerRadius,
            transform: nil
        )

        hud.content = hudContent
        applyHUDPlacement()
    }

    /// Resolve the on-screen rect for a pane that may live in the active
    /// strip or in any of the visible neighbor carriers. Returns the rect
    /// in this overlay's coordinate space, padded by `highlightInset`.
    private func highlightRectFor(paneID: PaneID) -> CGRect? {
        if let anchor = anchorPaneStripView,
           let rect = anchor.convertPaneFrame(paneID, to: self) {
            return rect.insetBy(dx: highlightInset, dy: highlightInset)
        }
        for carrier in laneCarriers.values {
            if let rectInCarrier = carrier.paneFrameInCarrier(paneID) {
                let rect = convert(rectInCarrier, from: carrier)
                return rect.insetBy(dx: highlightInset, dy: highlightInset)
            }
        }
        return nil
    }

    /// Cache the placement parameters; the actual frame is computed lazily
    /// inside `applyHUDPlacement()` once the HUD has real content (so its
    /// fitting size is correct).
    func placeHUDStably(targetZoomScale: CGFloat, visibleLeadingInset: CGFloat = 0) {
        hudPlacement = HUDPlacement(
            targetZoomScale: targetZoomScale,
            visibleLeadingInset: visibleLeadingInset
        )
        applyHUDPlacement()
    }

    private func applyHUDPlacement() {
        guard let placement = hudPlacement else { return }
        hud.layoutSubtreeIfNeeded()
        let size = hud.fittingSize
        guard size.width > 0, size.height > 0 else { return }

        let visibleCenterX = (placement.visibleLeadingInset + bounds.width) / 2
        let originX = visibleCenterX - size.width / 2

        // After the zoom + centering animation settles, columns occupy a
        // vertical band centered on the canvas, with height ≈ bounds.height
        // × targetZoomScale (assuming full-height columns — the typical
        // Zentty layout). The column's top edge in non-flipped coords sits
        // at ~ midY + (band height / 2). Anchor HUD just above that edge.
        let bandHeight = bounds.height * placement.targetZoomScale
        let columnTopY = bounds.midY + bandHeight / 2
        let originY = min(columnTopY + hudGap, bounds.height - size.height - 8)
        let clampedX = max(8, min(originX, bounds.width - size.width - 8))
        hud.frame = CGRect(x: clampedX, y: originY, width: size.width, height: size.height)
    }

    private func layoutNeighborCarriers() {
        guard let placement = hudPlacement else {
            // Without a known active band height we can't position neighbors
            // sensibly. They'll be placed on the next placeHUDStably call.
            return
        }
        let activeBandWidth = bounds.width * placement.targetZoomScale
        let activeBandHeight = bounds.height * placement.targetZoomScale
        let activeBandTop = bounds.midY + activeBandHeight / 2
        let activeBandBottom = bounds.midY - activeBandHeight / 2

        let visibleCenterX = (placement.visibleLeadingInset + bounds.width) / 2

        // Neighbor carriers share the active band's aspect ratio so their
        // internal layer-scale fills cleanly without letterboxing.
        let primaryW = activeBandWidth * NeighborLayout.primaryFraction
        let primaryH = activeBandHeight * NeighborLayout.primaryFraction
        let peekingW = activeBandWidth * NeighborLayout.peekingFraction
        let peekingH = activeBandHeight * NeighborLayout.peekingFraction

        if let above = laneCarriers[-1] {
            above.frame = CGRect(
                x: visibleCenterX - primaryW / 2,
                y: activeBandTop + NeighborLayout.bandGap,
                width: primaryW,
                height: primaryH
            )
        }
        if let below = laneCarriers[1] {
            below.frame = CGRect(
                x: visibleCenterX - primaryW / 2,
                y: activeBandBottom - NeighborLayout.bandGap - primaryH,
                width: primaryW,
                height: primaryH
            )
        }
        if let farAbove = laneCarriers[-2] {
            let primaryTop = activeBandTop + NeighborLayout.bandGap + primaryH
            farAbove.frame = CGRect(
                x: visibleCenterX - peekingW / 2,
                y: primaryTop + NeighborLayout.bandGap,
                width: peekingW,
                height: peekingH
            )
        }
        if let farBelow = laneCarriers[2] {
            let primaryBottom = activeBandBottom - NeighborLayout.bandGap - primaryH
            farBelow.frame = CGRect(
                x: visibleCenterX - peekingW / 2,
                y: primaryBottom - NeighborLayout.bandGap - peekingH,
                width: peekingW,
                height: peekingH
            )
        }
    }

    // MARK: - Layout

    override func layout() {
        super.layout()
        layoutNeighborCarriers()
        if let anchor = anchorPaneStripView,
           let path = highlightLayer.path,
           !path.isEmpty {
            let outer = CGMutablePath()
            outer.addRect(bounds)
            outer.addPath(path)
            dimLayer.path = outer
            _ = anchor // silence weak-ref warning
        }
    }

    // MARK: - Hit testing

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Defense-in-depth: if no anchor PaneStripView is attached, visual
        // mode is not active — let clicks fall through so drag-zones,
        // dividers, and pane focus continue working normally even if
        // `isHidden` somehow drifts out of sync.
        guard anchorPaneStripView != nil else { return nil }

        if hud.frame.contains(point), !hud.isHidden {
            return hud.hitTest(point)
        }
        return self
    }
}
