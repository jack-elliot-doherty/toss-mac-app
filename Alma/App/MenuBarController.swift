import Cocoa
import SwiftUI

private let plannerDemoNotification = Notification.Name("plannerDemoRequested")

final class MenuBarController {
    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private var overlayWindow: NSWindow?
    private let toolsSummaryItem = NSMenuItem(title: "Tools: —", action: nil, keyEquivalent: "")
    private lazy var plannerItem: NSMenuItem = {
        let item = NSMenuItem(title: "Test Planner (Demo)", action: #selector(runPlannerDemo), keyEquivalent: "p")
        item.target = self
        return item
    }()

    init(statusItem: NSStatusItem) {
        self.statusItem = statusItem
        configureMenu()
    }

    private func configureMenu() {
        let listenItem = NSMenuItem(title: "Hold-to-talk (Fn)", action: nil, keyEquivalent: "")
        listenItem.isEnabled = false
        menu.addItem(listenItem)

        toolsSummaryItem.isEnabled = false
        menu.addItem(toolsSummaryItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(plannerItem)

        let quitItem = NSMenuItem(title: "Quit Alma", action: #selector(quit), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    func beginListening() {
        showOverlay()
    }

    func endListening() {
        hideOverlay()
    }

    private func showOverlay() {
        guard overlayWindow == nil else { return }
        let hosting = NSHostingView(rootView: LocalMicPillView())
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 200, height: 48),
                              styleMask: [.borderless],
                              backing: .buffered, defer: false)
        window.level = .statusBar
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.contentView = hosting

        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - 100
            let y = frame.minY + 120
            window.setFrameOrigin(NSPoint(x: x, y: y))
        }

        window.orderFrontRegardless()
        overlayWindow = window
    }

    private func hideOverlay() {
        overlayWindow?.orderOut(nil)
        overlayWindow = nil
    }

    func setToolsSummary(_ text: String) {
        DispatchQueue.main.async { [weak self] in
            self?.toolsSummaryItem.title = text
        }
    }

    @objc private func runPlannerDemo() {
        NotificationCenter.default.post(name: plannerDemoNotification, object: nil)
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


