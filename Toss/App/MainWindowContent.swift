import SwiftUI

struct MainWindowContent: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var onboarding = OnboardingManager.shared

    var body: some View {
        let _ = NSLog(
            "[MainWindowContent] body evaluated - isAuth=\(auth.isAuthenticated), needsOnboarding=\(onboarding.needsOnboarding)"
        )

        Group {
            if !auth.isAuthenticated {
                // Window is hidden by AppDelegate, but show placeholder just in case
                Color.clear
            } else if onboarding.needsOnboarding {
                OnboardingView()
            } else {
                MainAppView()
            }
        }
        .frame(minWidth: 500, minHeight: 500)
        .background(MainWindowConfigurationView())
        .background(WindowKeyPrevention())
    }
}

/// Prevents the main window from automatically becoming key when the app is activated
/// This stops the focus-stealing behavior when switching desktops
private struct WindowKeyPrevention: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = KeyPreventionView()
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}

    private class KeyPreventionView: NSView {
        private var windowDelegate: WindowKeyDelegate?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window = self.window else { return }

            // Install our custom delegate to control key behavior
            windowDelegate = WindowKeyDelegate(originalDelegate: window.delegate, window: window)
            window.delegate = windowDelegate

            NSLog("[WindowKeyPrevention] Installed key prevention delegate")

            // If the app is already active and authenticated, ensure the window is visible.
            // Never force app activation or key focus here, because this callback can fire
            // during non-user-driven window/lifecycle transitions (e.g. Space switches).
            if AuthManager.shared.isAuthenticated && NSApp.isActive && !window.isVisible {
                window.orderFront(nil)
            }
        }
    }

    /// Custom window delegate that prevents automatic key focus when app activates
    private class WindowKeyDelegate: NSObject, NSWindowDelegate {
        weak var originalDelegate: NSWindowDelegate?
        weak var targetWindow: NSWindow?

        /// Track if user explicitly clicked to activate - only true for a brief moment after click
        private var userClickedOnWindow = false

        /// Event monitor for mouse clicks
        private var clickMonitor: Any?

        init(originalDelegate: NSWindowDelegate?, window: NSWindow) {
            self.originalDelegate = originalDelegate
            self.targetWindow = window
            super.init()

            // Use a LOCAL event monitor to detect clicks ON THIS WINDOW specifically
            clickMonitor = NSEvent.addLocalMonitorForEvents(matching: [
                .leftMouseDown, .rightMouseDown,
            ]) { [weak self] event in
                guard let self = self, let targetWindow = self.targetWindow else { return event }

                // Check if the click was on our window
                if event.window === targetWindow {
                    NSLog("[WindowKeyPrevention] Detected mouse click ON window")
                    self.userClickedOnWindow = true

                    // Reset after a very short delay
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                        self?.userClickedOnWindow = false
                    }
                }
                return event
            }
        }

        deinit {
            if let monitor = clickMonitor {
                NSEvent.removeMonitor(monitor)
            }
        }

        // MARK: - NSWindowDelegate methods that control focus

        func windowShouldClose(_ sender: NSWindow) -> Bool {
            // Only allow user-initiated close (clicking close button), not automatic close
            // This prevents the window from closing when switching to other apps (e.g., during OAuth)
            let isUserClose = userClickedOnWindow || NSApp.currentEvent?.type == .leftMouseUp
            if !isUserClose {
                return false
            }
            return originalDelegate?.windowShouldClose?(sender) ?? true
        }

        func windowDidBecomeKey(_ notification: Notification) {
            guard let window = notification.object as? NSWindow else { return }

            // Allow key focus only for explicit user intent.
            let userInitiated = userClickedOnWindow || WindowFocusIntent.isActive || DeepLinkActivation.isActive

            if !userInitiated {
                NSLog("[WindowKeyPrevention] Preventing unsolicited key focus on main window")
                window.resignKey()
                window.resignMain()
                return
            }

            originalDelegate?.windowDidBecomeKey?(notification)
        }

        func windowDidBecomeMain(_ notification: Notification) {
            originalDelegate?.windowDidBecomeMain?(notification)
        }

        func windowDidResignKey(_ notification: Notification) {
            originalDelegate?.windowDidResignKey?(notification)
        }

        func windowDidResignMain(_ notification: Notification) {
            originalDelegate?.windowDidResignMain?(notification)
        }

        func windowWillMove(_ notification: Notification) {
            originalDelegate?.windowWillMove?(notification)
        }

        func windowDidMove(_ notification: Notification) {
            originalDelegate?.windowDidMove?(notification)
        }

        func windowDidResize(_ notification: Notification) {
            originalDelegate?.windowDidResize?(notification)
        }

        func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
            originalDelegate?.windowWillResize?(sender, to: frameSize) ?? frameSize
        }
    }
}

private struct MainWindowConfigurationView: NSViewRepresentable {
    @ObservedObject private var auth = AuthManager.shared

    // Track which windows have been configured to avoid repeated configuration
    // Using a static set since this is a struct and we need state across instances
    private static var configuredWindows = Set<ObjectIdentifier>()

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            configureMainWindow(window, isAuthenticated: auth.isAuthenticated, isInitial: true)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        // Hide window if user signed out
        if !auth.isAuthenticated && window.isVisible {
            window.orderOut(nil)
        }
    }

    private func configureMainWindow(_ window: NSWindow, isAuthenticated: Bool, isInitial: Bool) {
        // Hide window if not authenticated
        if !isAuthenticated {
            window.orderOut(nil)
            return
        }

        // Only configure window properties once to prevent focus stealing
        let windowId = ObjectIdentifier(window)
        guard isInitial || !Self.configuredWindows.contains(windowId) else {
            return
        }
        Self.configuredWindows.insert(windowId)

        // Visual styling (same frosted glass look)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        // Note: Do NOT set isMovableByWindowBackground = true here!
        // It interferes with resize cursor detection at window edges.
        // The sidebar and title bar areas can handle window dragging instead.
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil

        // Apply corner radius to window's contentView to eliminate corner peaks
        // NOTE: Do NOT set masksToBounds = true here! It breaks hit testing for the sidebar
        // because the sidebar uses .ultraThinMaterial (NSVisualEffectView) and layered
        // masksToBounds causes hit testing to fail for views with visual effects.
        if let contentView = window.contentView {
            contentView.wantsLayer = true
            contentView.layer?.cornerRadius = 18  // Match SwiftUI clipShape radius
            contentView.layer?.cornerCurve = .continuous
            // contentView.layer?.masksToBounds = true  // REMOVED - breaks sidebar hit testing
        }

        // Resizable
        window.styleMask.insert(.resizable)
        window.collectionBehavior.formUnion([.fullScreenPrimary, .moveToActiveSpace])

        // Size constraints
        // Note: minWidth must be less than sidebar collapse threshold (700) in MainAppView
        // to allow the window to legitimately reach collapsed-sidebar widths
        window.minSize = NSSize(width: 500, height: 500)
        window.maxSize = NSSize(width: 10_000, height: 10_000)
        window.contentMinSize = NSSize(width: 500, height: 500)
        window.contentMaxSize = NSSize(width: 10_000, height: 10_000)

        // Hide all traffic lights (you draw custom ones)
        window.standardWindowButton(.closeButton)?.isHidden = true
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        if let titlebarView = window.standardWindowButton(.closeButton)?.superview {
            titlebarView.isHidden = true
        }
    }
}

// MARK: - Deep Link Activation Helper

/// Static helper to track deep link activations synchronously.
/// This allows WindowKeyPrevention to recognize deep link activations as user-initiated.
enum DeepLinkActivation {
    private static var _isActive = false

    /// Whether a deep link activation is currently in progress
    static var isActive: Bool { _isActive }

    /// Call this before activating the app from a deep link (OAuth callback, etc.)
    /// The flag will automatically reset after a short delay.
    static func markActivation() {
        _isActive = true

        // Reset after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            _isActive = false
        }
    }
}
