import AppKit

/// Renders a macOS System Settings–style icon badge: a white SF Symbol centred
/// on a rounded square filled with a subtle vertical gradient derived from the
/// section's base color (lighter at the top, darker at the bottom).
enum SettingsSidebarIconBadge {
    @MainActor private static var cache: [String: NSImage] = [:]

    @MainActor
    static func cachedImage(for section: SettingsSection, diameter: CGFloat) -> NSImage {
        let key = "\(section.rawValue)-\(Int(diameter.rounded()))"
        if let cached = cache[key] {
            return cached
        }
        let image = self.image(
            symbolName: section.symbolName,
            color: section.badgeColor,
            diameter: diameter,
            symbolScale: section.badgeSymbolScale
        )
        cache[key] = image
        return image
    }

    static func image(
        symbolName: String,
        color: NSColor,
        diameter: CGFloat,
        symbolScale: CGFloat = 1
    ) -> NSImage {
        NSImage(size: NSSize(width: diameter, height: diameter), flipped: false) { rect in
            let cornerRadius = diameter * 0.26
            let badgePath = NSBezierPath(
                roundedRect: rect,
                xRadius: cornerRadius,
                yRadius: cornerRadius
            )
            badgePath.addClip()

            let topColor = blend(color, toward: .white, fraction: 0.14)
            let bottomColor = blend(color, toward: .black, fraction: 0.12)
            if let gradient = NSGradient(starting: topColor, ending: bottomColor) {
                // angle -90° fills top → bottom, so the lighter color sits on top.
                gradient.draw(in: rect, angle: -90)
            } else {
                color.setFill()
                rect.fill()
            }

            let symbolConfiguration = NSImage.SymbolConfiguration(
                pointSize: diameter * 0.56 * symbolScale,
                weight: .semibold
            )
            .applying(NSImage.SymbolConfiguration(paletteColors: [.white]))

            if let symbol = NSImage(systemSymbolName: symbolName, accessibilityDescription: nil)?
                .withSymbolConfiguration(symbolConfiguration)
            {
                let symbolSize = symbol.size
                let symbolRect = NSRect(
                    x: rect.midX - symbolSize.width / 2,
                    y: rect.midY - symbolSize.height / 2,
                    width: symbolSize.width,
                    height: symbolSize.height
                )
                symbol.draw(
                    in: symbolRect,
                    from: .zero,
                    operation: .sourceOver,
                    fraction: 1.0
                )
            }

            return true
        }
    }

    private static func blend(
        _ color: NSColor,
        toward other: NSColor,
        fraction: CGFloat
    ) -> NSColor {
        let base = color.usingColorSpace(.sRGB) ?? color
        let mix = other.usingColorSpace(.sRGB) ?? other
        return base.blended(withFraction: fraction, of: mix) ?? color
    }
}
