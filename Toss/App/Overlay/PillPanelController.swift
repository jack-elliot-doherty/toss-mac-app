import Cocoa
import Combine
import SwiftUI

@MainActor
final class PillPanelController {
    private let panel: NSPanel
    private let hostingView: NSHostingView<PillView>
    let viewModel: PillViewModel
    private var cancellables = Set<AnyCancellable>()

    // Drag state
    private var customPosition: NSPoint? = nil
    private var globalDragMonitor: Any? = nil
    private var localDragMonitor: Any? = nil
    private var dragOffset: NSPoint? = nil  // Offset from mouse to panel origin at drag start

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
        // no shadow this was causing a square window around the pill
        panel.hasShadow = false
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.ignoresMouseEvents = false

        // Apply initial screen capture visibility setting
        if PreferencesManager.shared.hideFromScreenCapture {
            panel.sharingType = .none
        }

        let root = PillView(viewModel: viewModel)
        self.hostingView = NSHostingView(rootView: root)
        // Make hosting view fill the window - it will resize with the panel
        hostingView.autoresizingMask = [.width, .height]
        panel.contentView = hostingView

        // Listen for preference changes
        NotificationCenter.default.addObserver(
            forName: .hideFromScreenCaptureChanged,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.updateScreenCaptureVisibility()
            }
        }

        viewModel.$isMeetingRecordingHovered
            .debounce(for: .milliseconds(50), scheduler: DispatchQueue.main)
            .sink { [weak self] (isHovered: Bool) in
                Task { @MainActor in
                    guard let self = self else { return }
                    if case .meetingRecording = self.viewModel.visualState {
                        // Window is always the expanded size (122px) - no resizing needed
                        // Just toggle stop button visibility, SwiftUI animates within the fixed frame
                        self.viewModel.showMeetingRecordingStopButton = isHovered
                    }
                }
            }
            .store(in: &cancellables)

        // Handle drag events from the pill using AppKit mouse monitoring
        viewModel.onDragStart = { [weak self] in
            self?.startDragging()
        }
        viewModel.onDragEnd = { [weak self] in
            self?.stopDragging()
        }
    }

    private func intrinsicPillSize(for state: PillVisualState) -> NSSize {
        // For idle state, use exact hardcoded size to avoid SwiftUI layout quirks
        if case .idle = state {
            // The idle ring is 32px wide (idleWidth - 8), plus we need to account
            // for the capsule stroke and any container padding
            // Match exactly what PillStyle defines
            return NSSize(width: 32, height: 8)  // Using PillStyle.idleWidth and idleHeight directly
        }

        // For meeting recording, always use expanded size (content animates within)
        if case .meetingRecording = state {
            return NSSize(width: 36, height: 122)
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
        // Meeting recording: vertical pill snapped to right edge
        if case .meetingRecording = state {
            let targetSize = knownSizeForState(state)
            panel.setFrame(NSRect(origin: panel.frame.origin, size: targetSize), display: true)
            positionRightEdge()  // Snap to right edge immediately
            viewModel.visualState = state
            if !panel.isVisible {
                panel.orderFrontRegardless()
            }
            return
        }

        // Use known sizes to avoid reentrant layout issues
        let targetSize = knownSizeForState(state)

        // Start the panel resize animation
        animatePanelToSize(targetSize)

        // Set the visual state on next tick to let panel animation start first
        DispatchQueue.main.async {
            self.viewModel.visualState = state
        }

        // Handle visibility based on idle state + preference
        if case .idle = state {
            if PreferencesManager.shared.hideIdlePill {
                panel.orderOut(nil)
                return
            }
        }

        // Ensure panel is visible for non-idle states (or idle when preference is off)
        if !panel.isVisible {
            panel.orderFrontRegardless()
        }
    }

    /// Updates pill visibility when preference changes while in idle state
    func updateIdleVisibility() {
        if case .idle = viewModel.visualState {
            if PreferencesManager.shared.hideIdlePill {
                panel.orderOut(nil)
            } else {
                panel.orderFrontRegardless()
            }
        }
    }

    /// Returns known sizes for each state to avoid dynamic layout calculations
    /// that cause reentrant layout issues
    private func knownSizeForState(_ state: PillVisualState) -> NSSize {
        switch state {
        case .idle:
            return NSSize(width: 32, height: 8)
        case .hovered:
            return NSSize(width: 300, height: 48)  // 3 labeled buttons with padding
        case .listening:
            return NSSize(width: 175, height: 32)  // Waveform + AgentChip in command mode
        case .transcribing:
            return NSSize(width: 185, height: 32)  // Waveform + spinner + AgentChip in command mode
        case .meetingDetected:
            return NSSize(width: 380, height: 48)
        case .upcomingMeeting:
            return NSSize(width: 400, height: 48)
        case .meetingRecording:
            // Always use expanded size - SwiftUI content animates within fixed frame
            return NSSize(width: 36, height: 122)
        case .agentSessionActive:
            return NSSize(width: 100, height: 28)
        }
    }

    /// Animates the panel to a new size while keeping it anchored at bottom-center
    private func animatePanelToSize(_ size: NSSize) {
        let screen = screenUnderMouse() ?? panel.screen ?? NSScreen.main
        guard let screen = screen else { return }

        let vf = screen.visibleFrame
        let margin: CGFloat = 8

        // Calculate new frame anchored at bottom-center
        let centerX = vf.origin.x + (vf.width / 2)
        let x = round(centerX - (size.width / 2))
        let y = vf.minY + margin

        let target = NSRect(x: x, y: y, width: round(size.width), height: round(size.height))

        let reducedMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        if !reducedMotion {
            NSAnimationContext.runAnimationGroup { ctx in
                // Match SwiftUI spring timing more closely
                ctx.duration = 0.22
                ctx.timingFunction = CAMediaTimingFunction(
                    controlPoints: 0.25, 0.1, 0.25, 1.0  // Ease-out curve
                )
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }

    private func setSizeKeepingCurrentOrigin(to size: NSSize, animated: Bool) {
        var frame = panel.frame
        frame.size = size

        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.18
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
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

    /// Position pill at the right edge of the screen, vertically centered
    func positionRightEdge(margin: CGFloat = 8) {
        let screen = screenUnderMouse() ?? panel.screen ?? NSScreen.main
        guard let screen = screen else { return }
        let frame = screen.visibleFrame
        let size = panel.frame.size
        let x = frame.maxX - size.width - margin
        let y = frame.midY - size.height / 2  // Vertically centered
        let origin = NSPoint(x: x, y: y)
        panel.setFrameOrigin(origin)
        customPosition = origin  // Store as custom position so resizing keeps it here
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

    private func resizeKeepingCenter(to size: NSSize, animated: Bool) {
        // Always recenter on screen to prevent drift
        let screen = screenUnderMouse() ?? panel.screen ?? NSScreen.main
        guard let screen = screen else { return }

        let vf = screen.visibleFrame
        let centerX = vf.origin.x + (vf.width / 2)
        let x = round(centerX - (size.width / 2))
        let y = round(vf.minY + 8)  // Same margin as setSizeAndCenter

        let target = NSRect(x: x, y: y, width: round(size.width), height: round(size.height))

        if animated && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.15
                ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(target, display: true)
            }
        } else {
            panel.setFrame(target, display: true)
        }
    }

    private func updateScreenCaptureVisibility() {
        if PreferencesManager.shared.hideFromScreenCapture {
            panel.sharingType = .none
        } else {
            panel.sharingType = .readOnly
        }
    }

    // MARK: - Drag handling

    private func startDragging() {
        // Calculate offset from mouse position to panel origin
        let mouseLocation = NSEvent.mouseLocation
        let panelOrigin = panel.frame.origin
        dragOffset = NSPoint(
            x: mouseLocation.x - panelOrigin.x,
            y: mouseLocation.y - panelOrigin.y
        )

        // Global monitor - for when mouse is outside our app's windows
        globalDragMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] _ in
            DispatchQueue.main.async {
                self?.handleMouseDragged()
            }
        }

        // Local monitor - for when mouse is over our app's windows (including the pill panel)
        localDragMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDragged]) { [weak self] event in
            self?.handleMouseDragged()
            return event
        }
    }

    private func handleMouseDragged() {
        guard let offset = dragOffset else { return }

        let mouseLocation = NSEvent.mouseLocation

        // Calculate new panel origin: mouse position minus the offset
        let newOrigin = NSPoint(
            x: mouseLocation.x - offset.x,
            y: mouseLocation.y - offset.y
        )

        // Constrain to screen bounds
        let constrainedOrigin = constrainToScreen(origin: newOrigin, size: panel.frame.size)

        // Update panel position immediately
        panel.setFrameOrigin(constrainedOrigin)

        // Store as custom position
        customPosition = constrainedOrigin
        viewModel.customPillPosition = constrainedOrigin
    }

    private func stopDragging() {
        if let monitor = globalDragMonitor {
            NSEvent.removeMonitor(monitor)
            globalDragMonitor = nil
        }
        if let monitor = localDragMonitor {
            NSEvent.removeMonitor(monitor)
            localDragMonitor = nil
        }
        dragOffset = nil
    }

    /// Resets custom position and returns pill to bottom-center
    func resetCustomPosition() {
        stopDragging()
        customPosition = nil
        viewModel.customPillPosition = nil
        positionBottomCenter()
    }

    private func constrainToScreen(origin: NSPoint, size: NSSize) -> NSPoint {
        // Find the screen that contains the mouse cursor
        let mouseLocation = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouseLocation) } ?? panel.screen ?? NSScreen.main
        guard let screen = screen else { return origin }

        let visibleFrame = screen.visibleFrame
        let margin: CGFloat = 8

        var constrained = origin

        // Constrain horizontally
        constrained.x = max(visibleFrame.minX + margin, constrained.x)
        constrained.x = min(visibleFrame.maxX - size.width - margin, constrained.x)

        // Constrain vertically
        constrained.y = max(visibleFrame.minY + margin, constrained.y)
        constrained.y = min(visibleFrame.maxY - size.height - margin, constrained.y)

        return constrained
    }
}
