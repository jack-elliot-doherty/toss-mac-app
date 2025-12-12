import Cocoa
import Combine
import Foundation
import PostHog
import Sentry
import Sparkle
import SwiftUI

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    let updaterController: SPUStandardUpdaterController
    private let meetingDetector = MeetingDetector()
    let meetingRepository = PersistentMeetingRepository()

    private var pillController: PillController!
    private var statusItem: NSStatusItem?
    private let hotkey = HotkeyEventTap()
    private let recorder = AudioRecorder()
    private var didPaste: Bool = false
    private let historyRepo: PersistentHistoryRepository = History.shared
    private let pillViewModel = PillViewModel()
    private lazy var pasteManager = PasteManager(hotkeyTap: hotkey)
    private lazy var pillPanel = PillPanelController(viewModel: pillViewModel)
    private lazy var toastPanel = ToastPanelController(anchorFrameProvider: { [weak self] in
        self?.pillPanel.frame
    })
    private lazy var agentViewModel = AgentViewModel(auth: AuthManager.shared)
    private lazy var agentPanel = AgentPanelController(
        viewModel: agentViewModel,
        anchorFrameProvider: { [weak self] in
            self?.pillPanel.frame
        })
    private var lastTapAt: Date?
    private var signInWindow: NSWindow?
    private var authCancellable: AnyCancellable?
    private var wasAuthenticated = false

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Clean up any orphaned meetings from previous crash/force quit
        meetingRepository.cleanupOrphanedMeetings()

        MeetingSyncManager.shared.configure(repository: meetingRepository)

        // Process any pending meeting syncs from previous sessions
        Task { @MainActor in
            // First, sync any meetings that were updated but not synced
            let unsyncedMeetings = meetingRepository.getUnsyncedMeetings()
            if !unsyncedMeetings.isEmpty {
                NSLog(
                    "[AppDelegate] Found \(unsyncedMeetings.count) unsynced meetings, queueing for sync"
                )
                for meeting in unsyncedMeetings {
                    await MeetingSyncManager.shared.syncMeeting(meeting.id)
                }
            }

            // Process any failed syncs from the retry queue
            await MeetingSyncManager.shared.processQueue()

            // Start the periodic retry timer
            MeetingSyncManager.shared.startRetryTimer()
        }

        SentrySDK.start { options in
            options.dsn =
                "https://a26dd5e1ec6aac34508dc372eae29c87@o4510456233197568.ingest.us.sentry.io/4510456234442752"
            options.debug = false

            // Adds IP for users.
            // For more information, visit: https://docs.sentry.io/platforms/apple/data-management/data-collected/
            options.sendDefaultPii = true
        }

        let POSTHOG_API_KEY = "phc_eclzkTVIbtcxa3WAXBLAP6OUzytVyTzoJPF6tMKmskH"
        let POSTHOG_HOST = "https://us.i.posthog.com"

        let config = PostHogConfig(apiKey: POSTHOG_API_KEY, host: POSTHOG_HOST)

        PostHogSDK.shared.setup(config)
        PostHogSDK.shared.capture("Test Event")

        NSApp.setActivationPolicy(.regular)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

        if let button = statusItem.button {
            let font = NSFont.systemFont(ofSize: 20, weight: .bold)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: font,
                .baselineOffset: -3,
            ]
            let attributedTitle = NSAttributedString(string: "T", attributes: attributes)
            button.attributedTitle = attributedTitle
            button.image = nil
        }
        // Create the menu
        let menu = NSMenu()

        // Add "Open Toss" menu item
        let openItem = NSMenuItem(
            title: "Open Toss", action: #selector(openMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(NSMenuItem.separator())

        menu.addItem(NSMenuItem.separator())

        // Add "Settings" menu item
        let settingsItem = NSMenuItem(
            title: "Settings", action: #selector(openSettings), keyEquivalent: ",")
        settingsItem.target = self
        menu.addItem(settingsItem)

        menu.addItem(NSMenuItem.separator())

        // Add version info (non-clickable)
        let versionString =
            Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
        let versionItem = NSMenuItem(
            title: "Toss v\(versionString)", action: nil, keyEquivalent: "")
        versionItem.isEnabled = false
        menu.addItem(versionItem)

        // Add "Check for updates" menu item
        let updateItem = NSMenuItem(
            title: "Check for updates", action: #selector(checkForUpdates), keyEquivalent: "")
        updateItem.target = self
        menu.addItem(updateItem)

        menu.addItem(NSMenuItem.separator())

        // Add "Quit Toss Completely" menu item
        let quitItem = NSMenuItem(
            title: "Quit Toss Completely", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        statusItem.menu = menu

        // Pill panel idle and visible (non-activating)
        // Small delay to ensure window system is ready
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            self?.pillPanel.setState(.idle)

            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.pillPanel.recenter()
            }
        }
        // No need to call show() separately - setState already positions and shows

        pillController = PillController(
            audio: recorder,
            transcriber: TranscribeAPI.shared,
            paste: pasteManager,
            pillPanel: pillPanel,
            toast: toastPanel,
            viewModel: pillViewModel,
            history: History.shared,
            auth: AuthManager.shared,
            agentPanel: agentPanel,
            meetingRepository: meetingRepository,
            meetingDetector: meetingDetector

        )

        // Wire hold-to-talk
        hotkey.onFnDown = { [weak self] isCmdHeld in
            self?.pillController.send(.fnDown(isCmdHeld: isCmdHeld))
        }
        hotkey.onFnUp = { [weak self] in
            self?.pillController.send(.fnUp)
        }
        hotkey.onCmdDown = { [weak self] in
            self?.pillController.send(.cmdDown)
        }
        hotkey.onCmdUp = { [weak self] in
            self?.pillController.send(.cmdUp)
        }
        hotkey.onDoubleTapFn = { [weak self] in
            self?.pillController.send(.doubleTapFn)
        }
        hotkey.onEscapePressed = { [weak self] in
            self?.pillController.send(.escapePressed)
        }
        hotkey.start()

        // Expose UI intents from pill
        pillViewModel.onRequestStop = { [weak self] in self?.pillController.send(.stopButton) }
        pillViewModel.onRequestCancel = { [weak self] in self?.pillController.send(.cancelButton) }

        pillViewModel.onJoinAndRecordUpcoming = { [weak pillController] meeting in
            pillController?.send(.joinAndRecordUpcoming(meeting))
        }
        pillViewModel.onDismissUpcomingMeeting = { [weak pillController] in
            pillController?.send(.dismissUpcomingMeeting)
        }

        pillViewModel.onHoverEnter = { [weak self] in self?.pillController.send(.pillHoverEnter) }
        pillViewModel.onHoverExit = { [weak self] in self?.pillController.send(.pillHoverExit) }
        pillViewModel.onPillClicked = { [weak self] in self?.pillController.send(.pillClicked) }
        pillViewModel.onQuickActionRecordMeeting = { [weak self] in
            self?.pillController.send(.quickActionRecordMeeting)
        }
        pillViewModel.onQuickActionDictation = { [weak self] in
            self?.pillController.send(.quickActionDictation)
        }
        pillViewModel.onStopMeetingRecording = { [weak self] in
            self?.pillController.send(.stopMeetingRecording)
        }
        pillViewModel.onPauseMeetingRecording = { [weak self] in
            self?.pillController.send(.pauseMeetingRecording)
        }
        pillViewModel.onResumeMeetingRecording = { [weak self] in
            self?.pillController.send(.resumeMeetingRecording)
        }

        // Add this somewhere in your app initialization (e.g., AppDelegate)
        DistributedNotificationCenter.default().addObserver(
            forName: nil,
            object: nil,
            queue: .main
        ) { notification in
            let name = notification.name.rawValue
            // Filter for audio-related notifications
            if name.lowercased().contains("audio") || name.lowercased().contains("session")
                || name.lowercased().contains("media")
            {
                NSLog("[DistNotification] \(name) - object: \(notification.object ?? "nil")")
            }
        }

        // Observe planner demo trigger
        NotificationCenter.default.addObserver(
            self, selector: #selector(runPlannerDemo),
            name: Notification.Name("plannerDemoRequested"), object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleRecordMeetingRequest),
            name: .requestMeetingRecording, object: nil)

        // Setup meeting detection
        meetingDetector.onMeetingDetected = { [weak self] in
            self?.pillController.send(.meetingDetected)
        }
        meetingDetector.onMeetingEnded = { [weak self] in
            self?.pillController.send(.meetingEnded)
        }
        meetingDetector.start()

        MeetingsManager.shared.pillController = pillController

        NSLog("[AppDelegate] Meeting detection enabled")

        // Observe auth state changes to manage windows
        // Initialize wasAuthenticated based on current state
        wasAuthenticated = AuthManager.shared.isAuthenticated

        authCancellable = AuthManager.shared.$accessToken
            .dropFirst()  // Skip initial value to avoid duplicate on launch
            .receive(on: DispatchQueue.main)
            .sink { [weak self] token in
                guard let self = self else { return }

                let isAuthenticated = token?.isEmpty == false
                let wasAuthenticated = self.wasAuthenticated
                self.wasAuthenticated = isAuthenticated

                NSLog(
                    "[AppDelegate] Auth state changed: \(isAuthenticated) (was: \(wasAuthenticated))"
                )

                // Only react to actual state transitions, not token refreshes
                if isAuthenticated && !wasAuthenticated {
                    self.closeSignInWindow()
                    // Small delay to let window fully close
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.showMainWindow()
                    }
                } else if !isAuthenticated && wasAuthenticated {
                    self.closeMainWindow()
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        self.showSignInWindow()
                    }
                }
            }

        // Initial window state
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            if AuthManager.shared.isAuthenticated {
                self?.showMainWindow()
            } else {
                self?.showSignInWindow()
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool
    {
        // When user clicks dock icon, show the main window
        if !flag {
            // No visible windows, create/show the main window
            if let window = NSApp.windows.first(where: {
                $0.title == "Toss" || $0.identifier?.rawValue == "main"
            }) {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            } else {
                // If window doesn't exist, activate app (SwiftUI will recreate it)
                NSApp.activate(ignoringOtherApps: true)
            }
        }
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        // we want to pill to always be persistent even if the main app screen is closed
        return false
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            // Handle integration callbacks (Slack OAuth)
            if IntegrationsManager.shared.handleDeepLink(url: url) {
                continue
            }
            // Handle auth callbacks
            _ = AuthManager.shared.handleDeepLink(url: url)
        }

    }

    private func cacheTranscript(_ text: String) -> ThreadModel {
        let thread = historyRepo.upsertThread(title: "Quick Dictations")
        _ = historyRepo.appendMessage(
            threadId: thread.id, role: .user, content: text, status: .final)
        return thread
    }

    @objc private func openMainWindow() {
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Toss" }) {
            window.makeKeyAndOrderFront(nil)
        }
    }

    @objc private func openSettings() {
        // Open the main window and show settings
        openMainWindow()
        // Post notification to show settings
        NotificationCenter.default.post(name: NSNotification.Name("ShowSettings"), object: nil)
    }

    @objc private func checkForUpdates() {
        NSLog("[AppDelegate] Check for updates")
        updaterController.updater.checkForUpdates()
    }

    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        // End any active meeting recording gracefully
        pillController.endActiveRecordingIfNeeded()

        hotkey.stop()
        _ = recorder.stop()
        meetingDetector.stop()
        NSLog("[AppDelegate] Meeting detection disabled")
    }

    @objc private func runPlannerDemo() {}

    @objc private func handleRecordMeetingRequest() {
        pillController.send(.startMeetingRecording)
    }

    func showSignInWindow() {
        // Reuse existing sign-in window if it exists
        if let existing = signInWindow {
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 390),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )

        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.backgroundColor = .clear
        window.isOpaque = false
        window.titlebarSeparatorStyle = .none

        // Create hosting view that fills the ENTIRE window
        let contentView = SignInView()
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false

        // Create a container view that fills the window
        let containerView = NSView(frame: window.contentView?.bounds ?? .zero)
        containerView.wantsLayer = true
        containerView.addSubview(hostingView)

        // Pin hosting view to all edges of container
        NSLayoutConstraint.activate([
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor),
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
        ])

        window.contentView = containerView
        window.center()

        // Lock size
        window.minSize = NSSize(width: 520, height: 390)
        window.maxSize = NSSize(width: 520, height: 390)

        // Hide minimize/zoom buttons
        window.standardWindowButton(.miniaturizeButton)?.isHidden = true
        window.standardWindowButton(.zoomButton)?.isHidden = true

        self.signInWindow = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func showMainWindow() {
        NSLog("[AppDelegate] showMainWindow START")
        // Find existing main window
        for window in NSApp.windows {
            if window.title == "Toss" && window !== signInWindow {
                window.makeKeyAndOrderFront(nil)
                NSApp.activate(ignoringOtherApps: true)
                NSLog("[AppDelegate] showMainWindow END (found)")
                return
            }
        }
        // No existing window - SwiftUI should create it, just activate
        NSApp.activate(ignoringOtherApps: true)
        NSLog("[AppDelegate] showMainWindow END (not found)")
    }

    func closeMainWindow() {
        NSLog("[AppDelegate] closeMainWindow START")

        for (index, window) in NSApp.windows.enumerated() {
            NSLog(
                "[AppDelegate] Checking window \(index): title='\(window.title)', isSignIn=\(window === signInWindow)"
            )

            if window.title == "Toss" && window !== signInWindow {
                NSLog("[AppDelegate] closeMainWindow - HIDING window \(index)")
                window.orderOut(nil)
                // DON'T call window.close() - this tears down SwiftUI views
                // but leaves NSTrackingAreas active, causing crashes on mouse move
            }
        }

        NSLog("[AppDelegate] closeMainWindow END")
    }

    func closeSignInWindow() {
        NSLog("[AppDelegate] closeSignInWindow START")

        guard let window = signInWindow else {
            NSLog("[AppDelegate] closeSignInWindow - no window to close")
            return
        }

        // Just hide the window, don't close it
        // Closing can cause crashes if tracking areas are still active
        window.orderOut(nil)

        NSLog("[AppDelegate] closeSignInWindow END")
    }
}

extension Notification.Name {
    static let plannerDemoRequested = Notification.Name("plannerDemoRequested")
    static let requestMeetingRecording = Notification.Name("requestMeetingRecording")
}
