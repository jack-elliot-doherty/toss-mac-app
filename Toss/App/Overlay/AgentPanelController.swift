import Cocoa
import Combine
import SwiftUI

@MainActor
final class AgentPanelController {
    private let panel: NSPanel
    private let viewModel: AgentViewModel
    private let anchorFrameProvider: () -> NSRect?
    private let anchorOffset: CGFloat = 12
    private let hostingView: NSHostingView<AgentView>
    private var cancellables = Set<AnyCancellable>()

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

        let root = AgentView(viewModel: viewModel)
        self.hostingView = NSHostingView(rootView: root)

        // CRITICAL: Tell the hosting view to size itself based on SwiftUI content
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        panel.contentView = hostingView

        // Keep panel size in sync with SwiftUI content
        viewModel.$messages
            .combineLatest(
                viewModel.$pendingToolCalls,
                viewModel.$isProcessing,
                viewModel.$errorMessage
            )
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in
                self?.resizePanelToFitContent()
            }
            .store(in: &cancellables)

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
        let fixedWidth: CGFloat = 400
        let verticalPadding: CGFloat = 24

        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let finalHeight = min(fittingSize.height + verticalPadding, maxHeight)

        let targetSize = NSSize(width: fixedWidth, height: finalHeight)

        let targetFrame: NSRect
        if let anchor = anchorFrameProvider() {
            let x = anchor.midX - fixedWidth / 2
            let y = anchor.maxY + anchorOffset
            targetFrame = NSRect(origin: NSPoint(x: x, y: y), size: targetSize)
        } else if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - fixedWidth / 2
            let y = frame.minY + 80
            targetFrame = NSRect(origin: NSPoint(x: x, y: y), size: targetSize)
        } else {
            targetFrame = panel.frame
        }

        let delta = abs(panel.frame.height - targetFrame.height)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if delta > 1 && !reduceMotion {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
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
