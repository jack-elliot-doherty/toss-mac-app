import Cocoa
import SwiftUI

@MainActor
final class AgentPanelController {
    private let panel: NSPanel
    private let viewModel: AgentViewModel
    private let anchorFrameProvider: () -> NSRect?
    private let anchorOffset: CGFloat = 12
    private let hostingView: NSHostingView<AgentView>

    init(viewModel: AgentViewModel, anchorFrameProvider: @escaping () -> NSRect?) {
        self.viewModel = viewModel
        self.anchorFrameProvider = anchorFrameProvider

        let contentRect = NSRect(x: 0, y: 0, width: 400, height: 200)
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
        // panel.sharingType = .none  // Exclude from screen recording and screenshots

        let root = AgentView(viewModel: viewModel)
        self.hostingView = NSHostingView(rootView: root)

        // CRITICAL: Tell the hosting view to size itself based on SwiftUI content
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        panel.contentView = hostingView

        // Observe view model changes to trigger resize
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("AgentMessagesChanged"),
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.resizePanelToFitContent()
        }

        // ESC key handler
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {  // ESC
                self?.hide()
                return nil
            }
            return event
        }
    }

    func show(with initialMessage: String) {
        viewModel.startConversation(with: initialMessage)

        // Initial sizing
        resizePanelToFitContent()
        positionAboveAnchor()

        // Fade in animation
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1.0
        }
    }

    private func resizePanelToFitContent() {
        let maxHeight: CGFloat = 500
        let width: CGFloat = 400

        // Ask the hosting view for its fitting size
        let fittingSize = hostingView.fittingSize

        // Cap at max height
        let finalHeight = min(fittingSize.height, maxHeight)
        let finalSize = NSSize(width: width, height: finalHeight)

        if let anchor = anchorFrameProvider() {
            let x = anchor.midX - width / 2
            let y = anchor.maxY + anchorOffset
            let newFrame = NSRect(x: x, y: y, width: finalSize.width, height: finalSize.height)
            panel.setFrame(newFrame, display: true, animate: true)
        } else if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - width / 2
            let y = frame.minY + 80
            let newFrame = NSRect(x: x, y: y, width: finalSize.width, height: finalSize.height)
            panel.setFrame(newFrame, display: true, animate: true)
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

    private func positionAboveAnchor() {
        if let anchor = anchorFrameProvider() {
            let x = anchor.midX - panel.frame.width / 2
            let y = anchor.maxY + anchorOffset
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - panel.frame.width / 2
            let y = frame.minY + 80
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}
