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
    }
}

private struct MainWindowConfigurationView: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            configureMainWindow(window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let window = nsView.window else { return }
        configureMainWindow(window)
    }

    private func configureMainWindow(_ window: NSWindow) {
        // Visual styling (same frosted glass look)
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.styleMask.insert(.fullSizeContentView)
        window.isMovableByWindowBackground = true
        window.isOpaque = false
        window.backgroundColor = .clear
        window.titlebarSeparatorStyle = .none
        window.toolbar = nil

        // Resizable
        window.styleMask.insert(.resizable)
        window.collectionBehavior.insert(.fullScreenPrimary)

        // Size constraints
        window.minSize = NSSize(width: 820, height: 600)
        window.maxSize = NSSize(width: 10_000, height: 10_000)
        window.contentMinSize = NSSize(width: 820, height: 600)
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
