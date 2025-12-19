import Cocoa
import Combine
import SwiftUI

// Custom NSPanel that can become key for text input
private class KeyablePanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

@MainActor
final class AgentPanelController {
    private let panel: KeyablePanel
    private let viewModel: AgentViewModel
    private let anchorFrameProvider: () -> NSRect?
    private let anchorOffset: CGFloat = 12
    private let hostingView: NSHostingView<AgentView>
    private var cancellables = Set<AnyCancellable>()
    private var initialXPosition: CGFloat?  // NEW: Store the X position once
    private(set) var isMinimized = false  // Track if we have a minimized session

    // Callback for when minimize/restore happens (to update pill state)
    var onShow: (() -> Void)?
    var onMinimize: (() -> Void)?
    var onRestore: (() -> Void)?
    var onSessionEnd: (() -> Void)?

    init(viewModel: AgentViewModel, anchorFrameProvider: @escaping () -> NSRect?) {
        self.viewModel = viewModel
        self.anchorFrameProvider = anchorFrameProvider

        let contentRect = NSRect(x: 0, y: 0, width: 650, height: 200)
        self.panel = KeyablePanel(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        panel.titleVisibility = .hidden
        panel.titlebarAppearsTransparent = true
        panel.styleMask.insert(.fullSizeContentView)
        panel.isMovableByWindowBackground = false

        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.ignoresMouseEvents = false
        panel.becomesKeyOnlyIfNeeded = true  // Allow becoming key for text input

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

        // Resize when compact mode changes
        viewModel.$isCompactMode
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
        ) { [weak self] (_: Notification) in
            Task { @MainActor in
                self?.resizePanelToFitContent()
            }
        }

        // ESC key handler
        NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if event.keyCode == 53 {  // ESC
                self?.hide()
                return nil
            }
            return event
        }

        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("HideAgentPanel"),
            object: nil,
            queue: .main
        ) { [weak self] (_: Notification) in
            Task { @MainActor in
                self?.hide()
            }
        }

        // Listen for minimize requests (e.g., during OAuth flow)
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("MinimizeAgentPanel"),
            object: nil,
            queue: .main
        ) { [weak self] (_: Notification) in
            Task { @MainActor in
                self?.minimize()
            }
        }

        // Listen for restore requests (e.g., after OAuth completes)
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("RestoreAgentPanel"),
            object: nil,
            queue: .main
        ) { [weak self] (_: Notification) in
            Task { @MainActor in
                self?.restore()
            }
        }

        // Listen for show requests with initial message
        NotificationCenter.default.addObserver(
            forName: NSNotification.Name("ShowAgentPanel"),
            object: nil,
            queue: .main
        ) { [weak self] (notification: Notification) in
            Task { @MainActor in
                if let message = notification.userInfo?["message"] as? String {
                    self?.show(with: message)
                }
            }
        }
    }

    /// Whether the panel is currently visible with an active session
    var isVisible: Bool {
        panel.isVisible && !viewModel.messages.isEmpty
    }

    /// Show empty agent panel for text-based chat (no initial message)
    func showEmpty() {
        if isVisible { return }

        NSLog("[AgentPanelController] Showing empty agent panel for text chat")
        initialXPosition = nil

        // Clear first, then set compact mode (clearConversation resets it)
        viewModel.clearConversation()
        viewModel.isCompactMode = true

        // Initial sizing and positioning for compact mode
        resizePanelToFitContent()

        // Notify that panel is showing (to disable pill hover)
        onShow?()

        // Fade in animation
        panel.alphaValue = 0
        panel.makeKeyAndOrderFront(nil)  // Make key AND order front for text input

        NSAnimationContext.runAnimationGroup(
            { ctx in
                ctx.duration = 0.2
                panel.animator().alphaValue = 1.0
            },
            completionHandler: { [weak self] in
                // Force focus on the text field after animation
                self?.panel.makeFirstResponder(self?.hostingView)
                // Notify SwiftUI to focus the text field (more reliable)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    NotificationCenter.default.post(
                        name: NSNotification.Name("FocusAgentInput"), object: nil)
                }
            })
    }

    func show(with initialMessage: String) {
        // Check if we already have an active session
        if isVisible {
            // Panel is already showing with a conversation - add this as a follow-up message
            NSLog("[AgentPanelController] Adding follow-up message to existing session")
            viewModel.sendMessage(initialMessage)
            return
        }

        // New session - reset everything and start in full mode (we have a message)
        NSLog("[AgentPanelController] Starting new agent session")
        viewModel.isCompactMode = false
        initialXPosition = nil

        viewModel.startConversation(with: initialMessage)

        // Initial sizing and positioning
        resizePanelToFitContent()

        // Notify that panel is showing (to disable pill hover)
        onShow?()

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
        let fixedWidth: CGFloat = 650
        let verticalPadding: CGFloat = 24

        hostingView.layoutSubtreeIfNeeded()
        let fittingSize = hostingView.fittingSize
        let finalHeight = min(fittingSize.height + verticalPadding, maxHeight)

        let targetSize = NSSize(width: fixedWidth, height: finalHeight)

        // Calculate X position only once, then reuse it
        let x: CGFloat
        let y: CGFloat

        if let storedX = initialXPosition {
            // Reuse the initial X position
            x = storedX
            if let anchor = anchorFrameProvider() {
                y = anchor.maxY + anchorOffset
            } else if let screen = NSScreen.main {
                y = screen.visibleFrame.minY + 80
            } else {
                y = panel.frame.origin.y
            }
        } else {
            // First time: calculate and store X position
            if let anchor = anchorFrameProvider() {
                x = anchor.midX - fixedWidth / 2
                y = anchor.maxY + anchorOffset
            } else if let screen = NSScreen.main {
                let frame = screen.visibleFrame
                x = frame.midX - fixedWidth / 2
                y = frame.minY + 80
            } else {
                x = panel.frame.origin.x
                y = panel.frame.origin.y
            }
            initialXPosition = x  // Store for future resizes
        }

        let targetFrame = NSRect(origin: NSPoint(x: x, y: y), size: targetSize)

        let currentFrame = panel.frame
        if abs(currentFrame.height - targetFrame.height) < 1
            && abs(currentFrame.origin.y - targetFrame.origin.y) < 1
        {
            return
        }

        let delta = abs(panel.frame.height - targetFrame.height)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        if delta > 5 && !reduceMotion {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.2
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().setFrame(targetFrame, display: true)
            }
        } else {
            panel.setFrame(targetFrame, display: true)
        }
    }

    func hide() {
        isMinimized = false
        NSAnimationContext.runAnimationGroup(
            { ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = 0
            },
            completionHandler: {
                self.panel.orderOut(nil)
                self.viewModel.clearConversation()
                self.onSessionEnd?()
            })
    }

    /// Minimize the panel but keep the session active
    func minimize() {
        guard panel.isVisible else { return }
        isMinimized = true

        NSAnimationContext.runAnimationGroup(
            { ctx in
                ctx.duration = 0.15
                panel.animator().alphaValue = 0
            },
            completionHandler: {
                self.panel.orderOut(nil)
                self.onMinimize?()
            })
    }

    /// Restore a minimized panel
    func restore() {
        guard isMinimized else { return }
        isMinimized = false

        // Recalculate position and size
        resizePanelToFitContent()

        // Fade in animation
        panel.alphaValue = 0
        panel.orderFrontRegardless()

        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.2
            panel.animator().alphaValue = 1.0
        }

        onRestore?()
    }

    /// Check if there's an active (possibly minimized) session
    var hasActiveSession: Bool {
        !viewModel.messages.isEmpty
    }
}
