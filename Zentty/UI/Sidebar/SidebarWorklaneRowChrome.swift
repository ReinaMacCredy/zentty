import AppKit
import QuartzCore

@MainActor
final class SidebarWorklaneRowChrome {
    private enum DropTargetHighlightAnimation {
        static let scaleKey = "dropTargetScale"
        static let shadowOpacityKey = "dropTargetShadowOpacity"
        static let scale: CGFloat = 1.025
        static let springMass: CGFloat = 1.0
        static let springStiffness: CGFloat = 300
        static let springDamping: CGFloat = 20
        static let shadowFadeDuration: CFTimeInterval = 0.15
    }

    private struct ShadowStyle {
        let color: CGColor
        let opacity: Float
        let radius: CGFloat
        let offset: CGSize
    }

    let tintLayer = CALayer()
    private var isDropTargetHighlighted = false
    private var normalShadowStyle = ShadowStyle(
        color: NSColor.black.withAlphaComponent(0.02).cgColor,
        opacity: 1,
        radius: 4,
        offset: CGSize(width: 0, height: -1)
    )

    func install(in row: NSButton) {
        row.wantsLayer = true
        row.layer?.cornerRadius = ChromeGeometry.rowRadius
        row.layer?.cornerCurve = .continuous
        row.layer?.masksToBounds = false

        tintLayer.cornerRadius = ChromeGeometry.rowRadius
        tintLayer.cornerCurve = .continuous
        tintLayer.backgroundColor = NSColor.clear.cgColor
        tintLayer.zPosition = -1
        row.layer?.insertSublayer(tintLayer, at: 0)
    }

    func updateTintFrame(_ bounds: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tintLayer.frame = bounds
        CATransaction.commit()
    }

    func setDropTargetHighlighted(
        _ highlighted: Bool,
        layer: CALayer?,
        reducedMotion: Bool
    ) {
        guard let layer else { return }
        guard highlighted != isDropTargetHighlighted else { return }
        isDropTargetHighlighted = highlighted

        let targetTransform = highlighted
            ? CATransform3DMakeScale(
                DropTargetHighlightAnimation.scale,
                DropTargetHighlightAnimation.scale,
                1
            )
            : CATransform3DIdentity
        let targetShadowStyle = highlighted ? highlightedShadowStyle() : normalShadowStyle

        layer.removeAnimation(forKey: DropTargetHighlightAnimation.scaleKey)
        layer.removeAnimation(forKey: DropTargetHighlightAnimation.shadowOpacityKey)

        let currentTransform = layer.presentation()?.transform ?? layer.transform
        let currentShadowOpacity = layer.presentation()?.shadowOpacity ?? layer.shadowOpacity

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.transform = targetTransform
        apply(targetShadowStyle, to: layer)
        CATransaction.commit()

        guard reducedMotion == false else { return }

        let spring = CASpringAnimation(keyPath: "transform")
        spring.mass = DropTargetHighlightAnimation.springMass
        spring.stiffness = DropTargetHighlightAnimation.springStiffness
        spring.damping = DropTargetHighlightAnimation.springDamping
        spring.fromValue = currentTransform
        spring.toValue = targetTransform
        spring.isRemovedOnCompletion = true
        layer.add(spring, forKey: DropTargetHighlightAnimation.scaleKey)

        let fade = CABasicAnimation(keyPath: "shadowOpacity")
        fade.fromValue = currentShadowOpacity
        fade.toValue = targetShadowStyle.opacity
        fade.duration = DropTargetHighlightAnimation.shadowFadeDuration
        fade.isRemovedOnCompletion = true
        layer.add(fade, forKey: DropTargetHighlightAnimation.shadowOpacityKey)
    }

    func apply(
        summary: WorklaneSidebarSummary,
        theme: ZenttyTheme,
        isWorking: Bool,
        isHovered: Bool,
        isPaneRowHovered: Bool,
        isReorderDragActive: Bool,
        animated: Bool,
        layer: CALayer?
    ) {
        let activeBackground = theme.sidebarButtonActiveBackground
        let hoverBackground = theme.sidebarButtonHoverBackground
        let inactiveBackground = theme.sidebarButtonInactiveBackground
        let activeBorder = theme.sidebarButtonActiveBorder
        let inactiveBorder = theme.sidebarButtonInactiveBorder.withAlphaComponent(
            isHovered ? 0.16 : 0.10
        )
        let normalShadowStyle = ShadowStyle(
            color: NSColor.black.withAlphaComponent(summary.isActive ? 0.08 : 0.02).cgColor,
            opacity: 1,
            radius: summary.isActive ? 12 : 4,
            offset: CGSize(width: 0, height: -1)
        )
        self.normalShadowStyle = normalShadowStyle

        performThemeAnimation(animated: animated) {
            layer?.zPosition = summary.isActive ? 10 : 0
            layer?.backgroundColor =
                SidebarWorklaneRowStyleResolver.resolvedBackgroundColor(
                    isActive: summary.isActive,
                    isWorking: isWorking,
                    isHovered: isHovered,
                    isPaneRowHovered: isPaneRowHovered,
                    isReorderDragActive: isReorderDragActive,
                    activeBackground: activeBackground,
                    hoverBackground: hoverBackground,
                    inactiveBackground: inactiveBackground,
                theme: theme
            ).cgColor
            layer?.borderColor = (summary.isActive ? activeBorder : inactiveBorder).cgColor
            layer?.borderWidth = summary.isActive ? 0.8 : 1
            if let layer {
                self.apply(
                    self.isDropTargetHighlighted ? self.highlightedShadowStyle() : normalShadowStyle,
                    to: layer
                )
            }
            self.tintLayer.backgroundColor = SidebarWorklaneRowStyleResolver.tintColor(
                worklaneColor: summary.color,
                isActive: summary.isActive,
                isHovered: isHovered,
                isPaneRowHovered: isPaneRowHovered
            )
        }
    }

    private func highlightedShadowStyle() -> ShadowStyle {
        ShadowStyle(
            color: NSColor.controlAccentColor.cgColor,
            opacity: 0.7,
            radius: 8,
            offset: .zero
        )
    }

    private func apply(_ style: ShadowStyle, to layer: CALayer) {
        layer.shadowColor = style.color
        layer.shadowOpacity = style.opacity
        layer.shadowRadius = style.radius
        layer.shadowOffset = style.offset
    }
}
