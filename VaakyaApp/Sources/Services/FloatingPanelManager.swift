#if os(macOS)
import AppKit
import SwiftUI

@MainActor
class FloatingPanelManager {
    static let shared = FloatingPanelManager()

    private var panel: NSPanel?
    private(set) var isMinimized = false

    /// Remembers where the user dragged the pill/notepad so it survives close/reopen.
    private var lastOrigin: NSPoint?

    // MARK: - Panel Sizes

    private let pillSize   = NSSize(width: 220, height: 40)
    private let notepadSize = NSSize(width: 400, height: 300)

    // MARK: - Show Expanded (initial open)

    func showExpanded(content: NSView) {
        closePanel()
        let panel = createPanel(size: notepadSize)
        panel.contentView = content
        positionPanel(panel, size: notepadSize)
        panel.orderFront(nil)
        self.panel = panel
        isMinimized = false
    }

    // MARK: - Minimize → Pill

    func showMinimized(content: NSView) {
        guard let panel = panel else { return }
        saveOrigin()
        let currentTopRight = NSPoint(
            x: panel.frame.maxX,
            y: panel.frame.maxY
        )
        panel.contentView = content
        // Anchor to top-right corner so the pill stays near the same spot
        let newOrigin = NSPoint(
            x: currentTopRight.x - pillSize.width,
            y: currentTopRight.y - pillSize.height
        )
        panel.setContentSize(pillSize)
        panel.setFrameOrigin(newOrigin)
        isMinimized = true
    }

    // MARK: - Expand from Pill → Notepad

    func expandFromPill(content: NSView) {
        guard let panel = panel else { return }
        saveOrigin()
        let currentTopRight = NSPoint(
            x: panel.frame.maxX,
            y: panel.frame.maxY
        )
        panel.contentView = content
        let newOrigin = NSPoint(
            x: currentTopRight.x - notepadSize.width,
            y: currentTopRight.y - notepadSize.height
        )
        panel.setContentSize(notepadSize)
        panel.setFrameOrigin(newOrigin)
        isMinimized = false
    }

    // MARK: - Toggle (Cmd+Shift+V support)

    func toggle(expandedContent: NSView, minimizedContent: NSView) {
        if isMinimized {
            expandFromPill(content: expandedContent)
        } else {
            showMinimized(content: minimizedContent)
        }
    }

    // MARK: - Close

    func closePanel() {
        saveOrigin()
        panel?.close()
        panel = nil
        isMinimized = false
    }

    var isVisible: Bool { panel != nil }

    // MARK: - Private Helpers

    /// Creates a properly-configured borderless NSPanel that floats above all apps
    /// including fullscreen windows. No toolbar, no title bar, no tab bar — just a
    /// transparent container for SwiftUI content.
    private func createPanel(size: NSSize) -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .floating
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isMovableByWindowBackground = true
        panel.tabbingMode = .disallowed
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = true
        return panel
    }

    /// Sets the initial position — restores the saved origin if available, otherwise
    /// places the panel in the top-right corner of the main screen.
    private func positionPanel(_ panel: NSPanel, size: NSSize) {
        if let saved = lastOrigin {
            panel.setFrameOrigin(saved)
        } else if let screen = NSScreen.main {
            let x = screen.visibleFrame.maxX - size.width - 20
            let y = screen.visibleFrame.maxY - size.height - 20
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    private func saveOrigin() {
        if let panel = panel {
            lastOrigin = panel.frame.origin
        }
    }
}
#endif
