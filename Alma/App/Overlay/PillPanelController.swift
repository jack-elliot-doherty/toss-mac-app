import Cocoa
import SwiftUI

@MainActor
final class PillPanelController {
    private let panel: NSPanel
    private let hostingView: NSHostingView<PillView>
    let viewModel: PillViewModel

    // SINGLE SOURCE OF TRUTH for idle pill size
    // To change idle size: edit ONLY this value, SwiftUI content will auto-adjust
    private static let idleSize = NSSize(width: 64, height: 16)
    
    init(viewModel: PillViewModel) {
        self.viewModel = viewModel
        // Start with idle size centered
        let contentRect = NSRect(x: 0, y: 0, width: Self.idleSize.width, height: Self.idleSize.height)
        self.panel = NSPanel(contentRect: contentRect,
                              styleMask: [.nonactivatingPanel, .borderless],
                              backing: .buffered,
                              defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.ignoresMouseEvents = false

        let root = PillView(viewModel: viewModel)
        self.hostingView = NSHostingView(rootView: root)
        panel.contentView = hostingView
    }

    var frame: NSRect { panel.frame }

    func show(at origin: NSPoint? = nil) {
        if let origin = origin {
            panel.setFrameOrigin(origin)
        } else {
            positionBottomCenter()
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }

    func resize(to size: NSSize, animated: Bool) {
        var frame = panel.frame
        frame.size = size
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    func setState(_ state: PillVisualState) {
        viewModel.visualState = state
        // Resize heuristics for main states and center in one atomic frame update
        let size = sizeForState(state)
        setSizeAndCenter(to: size, animated: true)
        // Ensure panel is visible
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    func positionBottomCenter(margin: CGFloat = 8) {
        let screen = panel.screen ?? NSScreen.main
        guard let screen = screen else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let x = frame.midX - size.width / 2
        let y = frame.minY + margin
        panel.setFrameOrigin(NSPoint(x: x, y: y))
    }

    private func sizeForState(_ state: PillVisualState) -> NSSize {
        switch state {
        case .idle:
            return Self.idleSize  // Use the constant defined above
        case .listening(_):
            return NSSize(width: 240, height: 40)
        case .transcribing(_):
            return NSSize(width: 200, height: 40)
        }
    }

    private func setSizeAndCenter(to size: NSSize, animated: Bool, margin: CGFloat = 8) {
        // Always use main screen for primary display
        guard let screen = NSScreen.main else { return }
        let vf = screen.visibleFrame
        // Center horizontally: midpoint minus half width
        let x = vf.origin.x + (vf.width / 2) - (size.width / 2)
        let y = vf.minY + margin
        let origin = NSPoint(x: x, y: y)
        let target = NSRect(origin: origin, size: size)
        
        NSLog("[PillPanel] Centering: screen.visibleFrame=\(vf), size=\(size), target=\(target)")
        
        if animated {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }
}


