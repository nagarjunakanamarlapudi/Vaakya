#if os(macOS)
import AppKit
import SwiftUI

final class NotchIndicatorWindow: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = .statusBar
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false           // we drive movement manually on drag
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true   // default: passthrough until the controller flips this
        isReleasedWhenClosed = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        animationBehavior = .none    // we drive animations from SwiftUI
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func install<Content: View>(_ view: Content) {
        let host = NSHostingView(rootView: view)
        host.frame = contentLayoutRect
        host.autoresizingMask = [.width, .height]
        contentView = host
    }
}
#endif
