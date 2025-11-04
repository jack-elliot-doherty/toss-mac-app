import Cocoa
import SwiftUI

@MainActor
final class AgentPanelController {
    private let panel: NSPanel
    private let viewModel: AgentViewModel
    private let anchorFrameProvider: () -> NSRect?

    init(viewModel: AgentViewModel, anchorFrameProvider: @escaping () -> NSRect?) {
        self.viewModel = viewModel
        self.anchorFrameProvider = anchorFrameProvider

        let contentRect = NSRect(x: 0, y: 0, width: 400, height: 500)
        self.panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.ignoresMouseEvents = false

        let root = AgentView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: root)
        panel.contentView = hostingView
    }

    func show(with initialMessage: String) {
        viewModel.startConversation(with: initialMessage)
        positionAboveAnchor()

        // Fade in animation
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1.0
        }
    }

    func hide() {
        NSAnimationContext.runAnimationGroup(
            { ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = 0
            },
            completionHandler: {
                self.panel.orderOut(nil)
                self.viewModel.clearConversation()
            })
    }

    private func positionAboveAnchor(offset: CGFloat = 12) {
        if let anchor = anchorFrameProvider() {
            let x = anchor.midX - panel.frame.width / 2
            let y = anchor.maxY + offset
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - panel.frame.width / 2
            let y = frame.minY + 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}
