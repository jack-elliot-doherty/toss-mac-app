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
        // RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))

        hostingView.invalidateIntrinsicContentSize()
        hostingView.layoutSubtreeIfNeeded()

        var size = hostingView.fittingSize

        // Optional: make transcribing a hair wider for the dots
        if case .transcribing = state {
            size.width += 6
        }

        if case .hovered = state {
            size.width = ceil(max(size.width, 250))
            size.height = ceil(max(size.height, 32))
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
                ctx.duration = 0.08
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    func setState(_ state: PillVisualState) {
        // For hovered state, we need extra layout time due to the complex button layout
        if case .hovered = state {
            // Temporarily set state to compute size, then revert
            let previousState = viewModel.visualState
            viewModel.visualState = state

            // Force immediate layout to compute the size we'll need
            hostingView.invalidateIntrinsicContentSize()
            hostingView.layoutSubtreeIfNeeded()

            // Compute the target size while in hovered state
            let targetSize = sizeForState(state)

            // Revert to previous state so the view doesn't transition yet
            viewModel.visualState = previousState

            // FIRST: Resize the panel to the target size (without animation)
            // This happens before the visual transition
            setSizeAndCenter(to: targetSize, animated: false)

            // THEN: Set the visual state to trigger the SwiftUI transition
            // The panel is already the right size, so the content just animates in place
            viewModel.visualState = state

        } else {
            viewModel.visualState = state
            // Wait a tick for SwiftUI to begin its layout pass
            DispatchQueue.main.async {
                // Resize heuristics for main states and center in one atomic frame update
                let size = self.sizeForState(state)
                self.setSizeAndCenter(to: size, animated: false)
            }
        }
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
