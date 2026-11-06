import AppKit
import SwiftUI

@MainActor
final class WindowSnapPreviewController {
    private final class Panel: NSPanel {
        init() {
            super.init(
                contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false)
            isOpaque = false
            backgroundColor = .clear
            hasShadow = false
            level = .paletteDropGuide
            ignoresMouseEvents = true
            hidesOnDeactivate = false
            animationBehavior = .none
            collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            isReleasedWhenClosed = false

            let host = NSHostingView(rootView: WindowSnapPreviewView())
            host.sizingOptions = []
            contentView = host
        }

        override var canBecomeKey: Bool { false }
        override var canBecomeMain: Bool { false }
    }

    private let panel = Panel()

    func show(frame: CGRect) {
        let inset = Theme.Size.windowSnapPreviewInset
        panel.setFrame(frame.insetBy(dx: inset, dy: inset), display: true)
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}
