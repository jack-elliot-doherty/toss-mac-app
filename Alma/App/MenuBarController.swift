import Cocoa
import SwiftUI

private let plannerDemoNotification = Notification.Name("plannerDemoRequested")

final class MenuBarController {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var overlayWindow: NSWindow?
    private let pillModel = MicPillModel()
    private var overlayKeepAliveTimer: Timer?
    private let toolsSummaryItem = NSMenuItem(title: "Tools: —", action: nil, keyEquivalent: "")
    private lazy var plannerItem: NSMenuItem = {
        let item = NSMenuItem(title: "Test Planner (Demo)", action: #selector(runPlannerDemo), keyEquivalent: "p")
        item.target = self
        return item
    }()
    private lazy var updateItem: NSMenuItem = {
        let item = NSMenuItem(title: "Check for Updates…", action: #selector(checkUpdates), keyEquivalent: "u")
        item.target = self
        return item
    }()

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        configureMenu()
        // Keep pill correctly placed when Space or screen parameters change
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.positionOverlay()
            self?.overlayWindow?.orderFrontRegardless()
        }
        NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            self?.positionOverlay()
            self?.overlayWindow?.orderFrontRegardless()
        }
    }

    private func configureMenu() {
        let listenItem = NSMenuItem(title: "Hold-to-talk (Fn)", action: nil, keyEquivalent: "")
        listenItem.isEnabled = false
        menu.addItem(listenItem)

        toolsSummaryItem.isEnabled = false
        menu.addItem(toolsSummaryItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(plannerItem)
        menu.addItem(updateItem)

        let quitItem = NSMenuItem(title: "Quit Alma", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func beginListening() {
        pillModel.state = .listening
        showOverlay()
        updateWindowSize()
        applyWindowInteractionMode()
    }

    func endListening() {
        hideOverlay()
    }

    func showLoading() {
        pillModel.state = .loading
        showOverlay()
        updateWindowSize()
        applyWindowInteractionMode()
    }

    private func showOverlay() {
        if overlayWindow == nil {
            let hosting = NSHostingView(rootView: MicPillView(model: pillModel))
        let initialSize = currentPillSize()
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: initialSize.width, height: initialSize.height),
                              styleMask: [.borderless],
                              backing: .buffered, defer: false)
        // Keep the pill visible across Spaces and over fullscreen content
        window.level = .screenSaver
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        window.contentView = hosting
            overlayWindow = window
        }
        updateWindowSize()
        applyWindowInteractionMode()
        overlayWindow?.orderFrontRegardless()
    }

    private func hideOverlay() {
        // Keep a minimal idle pill visible at all times
        pillModel.state = .idle
        showOverlay()
        updateWindowSize()
        applyWindowInteractionMode()
    }

    private func positionOverlay() {
        guard let window = overlayWindow else { return }
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            // Center horizontally, flush to very bottom with a small margin above the screen edge
            let currentSize = window.frame.size
            let x = frame.midX - currentSize.width / 2
            let margin: CGFloat = 8
            let y = frame.minY + margin
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }

    private func updateWindowSize() {
        guard let window = overlayWindow else { return }
        let size = currentPillSize()
        // Compute target frame centered at bottom with margin
        let margin: CGFloat = 8
        var targetOrigin = window.frame.origin
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - size.width / 2
            let y = frame.minY + margin
            targetOrigin = NSPoint(x: x, y: y)
        }
        let targetFrame = NSRect(origin: targetOrigin, size: size)
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(targetFrame, display: true)
        }
    }

    private func applyWindowInteractionMode() {
        guard let window = overlayWindow else { return }
        // When idle, pass mouse through so we never block video/player controls
        // When active (listening/loading), allow hover/interactions if needed
        switch pillModel.state {
        case .idle:
            window.ignoresMouseEvents = true
            startOverlayKeepAlive()
        case .listening, .loading:
            window.ignoresMouseEvents = false
            stopOverlayKeepAlive()
        }
    }

    private func startOverlayKeepAlive() {
        overlayKeepAliveTimer?.invalidate()
        overlayKeepAliveTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let window = self.overlayWindow else { return }
            // Reassert z-order and position in case fullscreen video created a new Space/layer
            self.positionOverlay()
            window.level = .screenSaver
            window.orderFrontRegardless()
        }
    }

    private func stopOverlayKeepAlive() {
        overlayKeepAliveTimer?.invalidate()
        overlayKeepAliveTimer = nil
    }

    private func currentPillSize() -> NSSize {
        switch pillModel.state {
        case .idle:
            return NSSize(width: 40, height: 16)
        case .listening, .loading:
            return NSSize(width: 180, height: 36)
        }
    }

    func setToolsSummary(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.toolsSummaryItem.title = text
        }
    }

    @objc private func runPlannerDemo() {
        NotificationCenter.default.post(name: plannerDemoNotification, object: nil)
    }

    @objc private func checkUpdates() {
        UpdateManager.shared.checkForUpdates()
    }
}

private struct LocalMicPillView: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Color.black.opacity(0.7))
            .frame(width: 180, height: 36)
            .overlay(
                HStack(spacing: 8) {
                    Image(systemName: "waveform")
                        .foregroundColor(.white)
                    Text("Listening…")
                        .foregroundColor(.white)
                        .font(.system(size: 13, weight: .medium))
                }
                .padding(.horizontal, 12)
            )
    }
}


