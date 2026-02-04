import SwiftUI

struct SignInWindowContent: View {
    @ObservedObject private var auth = AuthManager.shared
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        SignInView()
            .ignoresSafeArea()  // Fill entire window including titlebar area
            .background(
                WindowAccessor { window in
                    configureSignInWindow(window)
                }
            )
            .onReceive(auth.$accessToken) { newToken in
                if let token = newToken, !token.isEmpty {
                    NSLog("[SignInWindowContent] Token received, transitioning to main window")
                    openWindow(id: "main")
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        // Close the sign-in window by finding it by identifier
                        NSApp.windows.first { $0.identifier?.rawValue == "signin" }?.close()
                    }
                }
            }
    }

    private func configureSignInWindow(_ window: NSWindow) {
        // Visual styling
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil

        // Non-resizable
        window.styleMask.remove(.resizable)
        window.collectionBehavior.remove(.fullScreenPrimary)

        // ONLY set frame size, not content size
        // Center on current position
        let targetSize = NSSize(width: 520, height: 390)
        let currentFrame = window.frame
        let newOrigin = NSPoint(
            x: currentFrame.midX - targetSize.width / 2,
            y: currentFrame.midY - targetSize.height / 2
        )
        window.setFrame(NSRect(origin: newOrigin, size: targetSize), display: true, animate: false)

        // Lock size after setting
        window.minSize = targetSize
        window.maxSize = targetSize

        // Traffic lights
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true
        window.standardWindowButton(.closeButton)?.isHidden = false
    }
}

// Simpler window accessor that runs immediately
private struct WindowAccessor: NSViewRepresentable {
    var callback: (NSWindow) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        // Use didMoveToWindow via coordinator for immediate access
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        // Run on every update until we get the window
        if let window = nsView.window {
            callback(window)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(callback: callback)
    }

    class Coordinator: NSObject {
        var callback: (NSWindow) -> Void
        var configured = false

        init(callback: @escaping (NSWindow) -> Void) {
            self.callback = callback
        }
    }
}
