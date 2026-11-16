#if os(macOS)
import AppKit

enum NotchGeometry {
    static let virtualNotchWidth: CGFloat = 180
    static let pillHeight: CGFloat = 32        // matches typical notch; never grows vertically
    static let expandedWidth: CGFloat = 360    // 180 (notch) + 90 (left ext) + 90 (right ext)
    static var sideExtensionWidth: CGFloat {   // visible content area on each side of the notch
        (expandedWidth - virtualNotchWidth) / 2
    }
    static let windowHeight: CGFloat = 44      // small top buffer for the borderless panel

    static func hasPhysicalNotch(_ screen: NSScreen) -> Bool {
        screen.safeAreaInsets.top > 0
    }

    static func screenForIndicator() -> NSScreen? {
        NSScreen.screens.first(where: hasPhysicalNotch) ?? NSScreen.main ?? NSScreen.screens.first
    }

    /// Default top-edge frame for the indicator window (collapsed width).
    /// Origin uses AppKit conventions (bottom-left origin per screen).
    static func defaultFrame(on screen: NSScreen, savedX: CGFloat? = nil) -> NSRect {
        let centerX = savedX ?? (screen.frame.midX - virtualNotchWidth / 2)
        let y = screen.frame.maxY - windowHeight
        return NSRect(x: centerX, y: y, width: virtualNotchWidth, height: windowHeight)
    }

    /// Hot zone at the top edge used to summon the floating pill on non-notch screens.
    static func summonHotZone(on screen: NSScreen) -> NSRect {
        NSRect(
            x: screen.frame.minX,
            y: screen.frame.maxY - 10,
            width: screen.frame.width,
            height: 10
        )
    }
}
#endif
