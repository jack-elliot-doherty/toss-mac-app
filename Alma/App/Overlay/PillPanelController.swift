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
        let contentRect = NSRect(
            x: 0, y: 0, width: Self.idleSize.width, height: Self.idleSize.height)
        self.panel = NSPanel(
            contentRect: contentRect,
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

    private func intrinsicPillSize(for state: PillVisualState) -> NSSize {
        // For idle state, use exact hardcoded size to avoid SwiftUI layout quirks
        if case .idle = state {
            // The idle ring is 32px wide (idleWidth - 8), plus we need to account
            // for the capsule stroke and any container padding
            // Match exactly what PillStyle defines
            return NSSize(width: 32, height: 8)  // Using PillStyle.idleWidth and idleHeight directly
        }

        // For other states, compute from SwiftUI
        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()

        // Give SwiftUI a moment to compute layout
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))

        var size = hostingView.fittingSize

        // Optional: make transcribing a hair wider for the dots
        if case .transcribing = state {
            size.width += 6
        }

        // Round to whole pixels
        size.width = ceil(max(size.width, Self.idleSize.width))
        size.height = ceil(max(size.height, Self.idleSize.height))

        NSLog("[PillPanel] Computed size for \(state): \(size)")

        return size
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

    func recenter() {
        // Force recenter the pill at current size
        let currentSize = panel.frame.size
        setSizeAndCenter(to: currentSize, animated: false)
    }

    private func sizeForState(_ state: PillVisualState) -> NSSize {
        intrinsicPillSize(for: state)
    }

    private func screenUnderMouse() -> NSScreen? {
        let mouse = NSEvent.mouseLocation  // global coords
        // Use .frame (not .visibleFrame) for containment checks
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    private func setSizeAndCenter(
        to size: NSSize,
        on screen: NSScreen? = nil,
        animated: Bool,
        margin: CGFloat = 8
    ) {
        let screen = screen ?? screenUnderMouse() ?? panel.screen ?? NSScreen.main
        guard let screen else { return }

        let vf = screen.visibleFrame

        // Calculate center position with explicit rounding to prevent sub-pixel offsets
        let centerX = vf.origin.x + (vf.width / 2)
        let x = round(centerX - (size.width / 2))
        let y = vf.minY + margin

        let target = NSRect(x: x, y: y, width: size.width, height: size.height)

        NSLog("[PillPanel] Centering at x=\(x), screen center=\(centerX), width=\(size.width)")

        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let shouldAnimate = animated && !reducedMotion

        if shouldAnimate {
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
