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
    private var pendingWindowWorkItem: DispatchWorkItem?

    // Menu bar upcoming meetings
    private var todaysMeetings: [UpcomingMeeting] = []
    private var menuBarUpdateTimer: Timer?
    private var meetingsSubscription: AnyCancellable?

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Disable window restoration to prevent stale windows from previous sessions
        NSWindow.allowsAutomaticWindowTabbing = false
        UserDefaults.standard.set(false, forKey: "NSQuitAlwaysKeepsWindows")

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
            // Use menu bar icon if available, otherwise fall back to "T"
            if let menuBarIcon = NSImage(named: "MenuBarIcon") {
                menuBarIcon.isTemplate = true  // Adapts to light/dark mode
                button.image = menuBarIcon
                button.imagePosition = .imageLeading
            } else {
                let font = NSFont.systemFont(ofSize: 20, weight: .bold)
                let attributes: [NSAttributedString.Key: Any] = [
                    .font: font,
                    .baselineOffset: -3,
                ]
                let attributedTitle = NSAttributedString(string: "T", attributes: attributes)
                button.attributedTitle = attributedTitle
            }
        }

        // Build initial menu (will be rebuilt dynamically with meetings)
        rebuildMenu()

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
            // Post notification so command palette can dismiss
            NotificationCenter.default.post(name: NSNotification.Name("GlobalEscapePressed"), object: nil)
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
        pillViewModel.onPillClicked = { [weak self] in
            self?.pillController.send(.pillClicked)
        }

        // Wire agent panel show/minimize/restore to disable/enable pill hover
        agentPanel.onShow = { [weak self] in
            self?.pillViewModel.isHoverDisabled = true
        }
        agentPanel.onMinimize = { [weak self] in
            self?.pillViewModel.isHoverDisabled = false  // Re-enable hover when minimized
            self?.pillController.send(.agentSessionMinimized)
        }
        agentPanel.onRestore = { [weak self] in
            self?.pillViewModel.isHoverDisabled = true  // Disable hover when restored
            self?.pillController.send(.agentSessionEnded)
        }
        agentPanel.onSessionEnd = { [weak self] in
            self?.pillViewModel.isHoverDisabled = false  // Re-enable hover when session ends
            self?.pillController.send(.agentSessionEnded)
        }
        pillViewModel.onQuickActionRecordMeeting = { [weak self] in
            self?.pillController.send(.quickActionRecordMeeting)
        }
        pillViewModel.onQuickActionDictation = { [weak self] in
            self?.pillController.send(.quickActionDictation)
        }
        pillViewModel.onQuickActionAgentChat = { [weak self] in
            self?.pillController.send(.quickActionAgentChat)
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

        // Configure update manager for in-app update notifications
        UpdateManager.shared.configure(with: updaterController)

        NSLog("[AppDelegate] Meeting detection enabled")

        // Observe when a different user signs in (to clear previous user's data)
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleUserAccountChanged),
            name: .userAccountChanged, object: nil)

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

                // Cancel any pending window operations to prevent race conditions
                self.pendingWindowWorkItem?.cancel()
                self.pendingWindowWorkItem = nil

                // Only react to actual state transitions, not token refreshes
                if isAuthenticated && !wasAuthenticated {
                    // User just signed in - fetch their meetings from server
                    Task {
                        await self.fetchMeetingsFromServer()
                    }

                    // Start menu bar meetings feature
                    self.startMenuBarMeetingsFeature()

                    self.closeSignInWindow()
                    // Small delay to let window fully close
                    let workItem = DispatchWorkItem { [weak self] in
                        self?.showMainWindow()
                    }
                    self.pendingWindowWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
                } else if !isAuthenticated && wasAuthenticated {
                    // Stop menu bar meetings feature
                    self.stopMenuBarMeetingsFeature()

                    self.closeMainWindow()
                    let workItem = DispatchWorkItem { [weak self] in
                        self?.showSignInWindow()
                    }
                    self.pendingWindowWorkItem = workItem
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05, execute: workItem)
                }
            }

        // Initial window state
        // IMMEDIATELY hide main window if not authenticated to prevent flash
        if !AuthManager.shared.isAuthenticated {
            NSLog("[AppDelegate] Not authenticated on launch, hiding main window immediately")
            closeMainWindow()
        }

        // Then show the appropriate window after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            if AuthManager.shared.isAuthenticated {
                self?.showMainWindow()
                // Start menu bar meetings feature on launch
                self?.startMenuBarMeetingsFeature()
            } else {
                // Hide main window again in case SwiftUI made it visible after our initial hide
                self?.closeMainWindow()
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

    @objc private func handleUserAccountChanged() {
        // When a different user signs in, clear local data and fetch their meetings from the server
        NSLog("[AppDelegate] User account changed - clearing local data and fetching from server")
        meetingRepository.clearAllData()
        History.shared.clear()

        // Fetch meetings from server for the new user
        Task {
            await fetchMeetingsFromServer()
        }
    }

    private func fetchMeetingsFromServer() async {
        NSLog("[AppDelegate] Fetching meetings from server...")
        do {
            let serverMeetings = try await MeetingsApi.shared.fetchRecordedMeetings()
            await MainActor.run {
                meetingRepository.importFromServer(serverMeetings)
            }
            NSLog(
                "[AppDelegate] Successfully fetched and imported \(serverMeetings.count) meetings")
        } catch {
            NSLog(
                "[AppDelegate] Failed to fetch meetings from server: \(error.localizedDescription)")
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        // End any active meeting recording gracefully
        pillController.endActiveRecordingIfNeeded()

        hotkey.stop()
        _ = recorder.stop()
        meetingDetector.stop()
        stopMenuBarMeetingsFeature()
        NSLog("[AppDelegate] Meeting detection disabled")
    }

    @objc private func runPlannerDemo() {}

    @objc private func handleRecordMeetingRequest() {
        pillController.send(.startMeetingRecording)
    }

    func showSignInWindow() {
        NSLog("[AppDelegate] showSignInWindow START")

        // Reuse existing sign-in window if it exists
        if let existing = signInWindow {
            NSLog(
                "[AppDelegate] showSignInWindow - reusing existing window (visible=\(existing.isVisible))"
            )
            existing.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            NSLog("[AppDelegate] showSignInWindow END (reused)")
            return
        }

        NSLog("[AppDelegate] showSignInWindow - creating new window")

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
        NSLog("[AppDelegate] showSignInWindow END")
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
            let isPillPanel = window.level == .floating || window.level == .statusBar
            let isSignIn = window === signInWindow
            let isMainWindow = window.title == "Toss" || window.identifier?.rawValue == "main"

            NSLog(
                "[AppDelegate] Checking window \(index): title='\(window.title)', isSignIn=\(isSignIn), isPill=\(isPillPanel), isMain=\(isMainWindow), visible=\(window.isVisible)"
            )

            // Hide main window or any non-pill, non-signin window
            // Force hide regardless of current visibility state to catch windows that will become visible
            if isMainWindow || (!isSignIn && !isPillPanel) {
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
            NSLog("[AppDelegate] closeSignInWindow - no signInWindow reference")
            return
        }

        NSLog(
            "[AppDelegate] closeSignInWindow - hiding window (visible=\(window.isVisible), title='\(window.title)')"
        )

        // Just hide the window, don't close it
        // Closing can cause crashes if tracking areas are still active
        window.orderOut(nil)

        NSLog("[AppDelegate] closeSignInWindow END (visible=\(window.isVisible))")
    }

    // MARK: - Menu Bar Upcoming Meetings

    private func startMenuBarMeetingsFeature() {
        // Subscribe to MeetingsManager's upcoming meetings
        meetingsSubscription = MeetingsManager.shared.$upcomingMeetings
            .receive(on: DispatchQueue.main)
            .sink { [weak self] allUpcoming in
                self?.updateTodaysMeetings(from: allUpcoming)
            }

        // Trigger initial fetch from MeetingsManager
        Task {
            await MeetingsManager.shared.fetchUpcoming()
        }

        // Schedule first update aligned to the next minute boundary
        scheduleNextMenuBarUpdate()
    }

    private func scheduleNextMenuBarUpdate() {
        menuBarUpdateTimer?.invalidate()

        // Calculate seconds until the next minute boundary
        let now = Date()
        let calendar = Calendar.current
        let seconds = calendar.component(.second, from: now)
        let secondsUntilNextMinute = 60 - seconds

        // Schedule timer to fire at the next minute boundary
        menuBarUpdateTimer = Timer.scheduledTimer(
            withTimeInterval: TimeInterval(secondsUntilNextMinute), repeats: false
        ) {
            [weak self] _ in
            Task { @MainActor in
                self?.updateMenuBarButton()
                self?.rebuildMenu()  // Also rebuild menu so dropdown times stay in sync

                // Now schedule recurring updates every 60 seconds (aligned to minute)
                self?.menuBarUpdateTimer?.invalidate()
                self?.menuBarUpdateTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true)
                {
                    [weak self] _ in
                    Task { @MainActor in
                        self?.updateMenuBarButton()
                        self?.rebuildMenu()  // Keep dropdown times in sync
                    }
                }
            }
        }
    }

    private func stopMenuBarMeetingsFeature() {
        menuBarUpdateTimer?.invalidate()
        menuBarUpdateTimer = nil
        meetingsSubscription?.cancel()
        meetingsSubscription = nil
        todaysMeetings = []
        updateMenuBarButton()
        rebuildMenu()
    }

    private func updateTodaysMeetings(from allUpcoming: [UpcomingMeeting]) {
        // Filter to only today's meetings
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: today)!

        todaysMeetings = allUpcoming.filter { meeting in
            meeting.startedAt >= today && meeting.startedAt < tomorrow
        }.sorted { $0.startedAt < $1.startedAt }

        NSLog("[AppDelegate] Updated menu bar with \(todaysMeetings.count) meetings for today")
        updateMenuBarButton()
        rebuildMenu()
    }

    private func updateMenuBarButton() {
        guard let button = statusItem?.button else { return }

        // Set up menu bar icon
        let hasMenuBarIcon = NSImage(named: "MenuBarIcon") != nil
        if let menuBarIcon = NSImage(named: "MenuBarIcon") {
            menuBarIcon.isTemplate = true
            button.image = menuBarIcon
            button.imagePosition = .imageLeading
        }

        // Find the next upcoming meeting (hasn't started yet)
        let now = Date()
        let nextMeeting = todaysMeetings.first { $0.startedAt > now }

        if let meeting = nextMeeting {
            // Build the attributed string: "title • in Xm"
            let title = truncateTitle(meeting.displayTitle, maxWidth: 80)
            let timeString = formatRelativeTime(meeting.startedAt)

            let fullString = NSMutableAttributedString()

            // If no icon, add "T" as fallback
            if !hasMenuBarIcon {
                let logoFont = NSFont.systemFont(ofSize: 20, weight: .bold)
                let logoAttrs: [NSAttributedString.Key: Any] = [
                    .font: logoFont,
                    .baselineOffset: -3,
                ]
                fullString.append(NSAttributedString(string: "T", attributes: logoAttrs))

                let spaceAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12)
                ]
                fullString.append(NSAttributedString(string: "  ", attributes: spaceAttrs))
            } else {
                // Add spacing after icon
                let spaceAttrs: [NSAttributedString.Key: Any] = [
                    .font: NSFont.systemFont(ofSize: 12)
                ]
                fullString.append(NSAttributedString(string: " ", attributes: spaceAttrs))
            }

            // Meeting title
            let titleFont = NSFont.systemFont(ofSize: 12, weight: .medium)
            let titleAttrs: [NSAttributedString.Key: Any] = [
                .font: titleFont,
                .baselineOffset: 0,
            ]
            fullString.append(NSAttributedString(string: title, attributes: titleAttrs))

            // Separator and time
            let timeFont = NSFont.systemFont(ofSize: 12, weight: .regular)
            let timeAttrs: [NSAttributedString.Key: Any] = [
                .font: timeFont,
                .baselineOffset: 0,
            ]
            fullString.append(NSAttributedString(string: " • \(timeString)", attributes: timeAttrs))

            button.attributedTitle = fullString
        } else {
            // No meeting today - just show logo (or "T" fallback)
            if hasMenuBarIcon {
                button.attributedTitle = NSAttributedString(string: "")
            } else {
                let logoFont = NSFont.systemFont(ofSize: 20, weight: .bold)
                let logoAttrs: [NSAttributedString.Key: Any] = [
                    .font: logoFont,
                    .baselineOffset: -3,
                ]
                button.attributedTitle = NSAttributedString(string: "T", attributes: logoAttrs)
            }
        }
    }

    private func truncateTitle(_ title: String, maxWidth: CGFloat) -> String {
        let font = NSFont.systemFont(ofSize: 12, weight: .medium)
        let attributes: [NSAttributedString.Key: Any] = [.font: font]

        var truncated = title
        var size = (truncated as NSString).size(withAttributes: attributes)

        while size.width > maxWidth && truncated.count > 1 {
            truncated = String(truncated.dropLast(2)) + "…"
            size = (truncated as NSString).size(withAttributes: attributes)
        }

        return truncated
    }

    private func formatRelativeTime(_ date: Date) -> String {
        let now = Date()
        let seconds = date.timeIntervalSince(now)

        guard seconds > 0 else { return "now" }

        let minutes = Int(ceil(seconds / 60))

        if minutes < 60 {
            return "in \(minutes)m"
        } else {
            let hours = minutes / 60
            let remainingMins = minutes % 60
            if remainingMins == 0 {
                return "in \(hours)h"
            } else {
                return "in \(hours)h \(remainingMins)m"
            }
        }
    }

    private func rebuildMenu() {
        let menu = NSMenu()

        // Add today's meetings section if there are any
        let now = Date()
        let upcomingToday = todaysMeetings.filter { $0.startedAt > now }

        if !upcomingToday.isEmpty {
            // Header
            if let nextMeeting = upcomingToday.first {
                let headerItem = NSMenuItem(
                    title: "Starts \(formatRelativeTime(nextMeeting.startedAt))", action: nil,
                    keyEquivalent: "")
                headerItem.isEnabled = false
                menu.addItem(headerItem)
            }

            // Meeting items
            for meeting in upcomingToday {
                let meetingItem = createMeetingMenuItem(meeting)
                menu.addItem(meetingItem)
            }

            menu.addItem(NSMenuItem.separator())
        }

        // Add "Open Toss" menu item
        let openItem = NSMenuItem(
            title: "Open Toss", action: #selector(openMainWindow), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

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

        statusItem?.menu = menu
    }

    private func createMeetingMenuItem(_ meeting: UpcomingMeeting) -> NSMenuItem {
        // Format: "Meeting Title\n10:30 - 11:00"
        let timeFormatter = DateFormatter()
        timeFormatter.dateFormat = "HH:mm"

        let startTime = timeFormatter.string(from: meeting.startedAt)
        let endTime = meeting.endedAt.map { timeFormatter.string(from: $0) } ?? ""
        let timeRange = endTime.isEmpty ? startTime : "\(startTime) - \(endTime)"

        // Create a custom hoverable view for the menu item
        let menuItem = NSMenuItem()

        // Match native menu item dimensions
        let containerView = HoverableMenuItemView(frame: NSRect(x: 0, y: 0, width: 250, height: 42))

        let titleLabel = NSTextField(labelWithString: meeting.displayTitle)
        titleLabel.font = NSFont.systemFont(ofSize: 13, weight: .medium)
        titleLabel.textColor = .labelColor
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: 19, y: 22, width: 212, height: 16)
        titleLabel.drawsBackground = false
        titleLabel.isBordered = false

        let timeLabel = NSTextField(labelWithString: timeRange)
        timeLabel.font = NSFont.systemFont(ofSize: 11)
        timeLabel.textColor = .secondaryLabelColor
        timeLabel.frame = NSRect(x: 19, y: 5, width: 212, height: 14)
        timeLabel.drawsBackground = false
        timeLabel.isBordered = false

        containerView.addSubview(titleLabel)
        containerView.addSubview(timeLabel)
        containerView.setLabels(title: titleLabel, time: timeLabel)

        // Store meeting ID and set click handler
        let upcomingId = meeting.id
        containerView.onClick = { [weak self] in
            self?.statusItem?.menu?.cancelTracking()
            self?.openUpcomingMeeting(upcomingId: upcomingId)
        }

        menuItem.view = containerView

        return menuItem
    }

    private func openUpcomingMeeting(upcomingId: UUID) {
        // Find the upcoming meeting from our cached list
        guard let upcoming = todaysMeetings.first(where: { $0.id == upcomingId }) else {
            NSLog("[AppDelegate] Could not find upcoming meeting with ID: \(upcomingId)")
            return
        }

        // Create or find the local meeting
        let localMeeting = meetingRepository.getOrCreateFromUpcoming(upcoming)

        NSLog(
            "[AppDelegate] Opening meeting page for \(localMeeting.id) (from upcoming: \(upcomingId))"
        )

        // Activate the app
        NSApp.activate(ignoringOtherApps: true)

        // Post notification to navigate to meeting
        NotificationCenter.default.post(
            name: NSNotification.Name("OpenMeetingView"),
            object: nil,
            userInfo: ["meetingId": localMeeting.id]
        )
    }
}

extension Notification.Name {
    static let plannerDemoRequested = Notification.Name("plannerDemoRequested")
    static let requestMeetingRecording = Notification.Name("requestMeetingRecording")
}

// MARK: - Hoverable Menu Item View

class HoverableMenuItemView: NSView {
    private var trackingArea: NSTrackingArea?
    private var isHovered = false {
        didSet {
            needsDisplay = true
            updateTextColors()
        }
    }

    var onClick: (() -> Void)?
    private var titleLabel: NSTextField?
    private var timeLabel: NSTextField?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = false  // Use draw() instead
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func setLabels(title: NSTextField, time: NSTextField) {
        self.titleLabel = title
        self.timeLabel = time
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Ensure tracking area is set up when added to window
        updateTrackingAreas()
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()

        if let existingArea = trackingArea {
            removeTrackingArea(existingArea)
        }

        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        )
        addTrackingArea(trackingArea!)
    }

    override func mouseEntered(with event: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with event: NSEvent) {
        isHovered = false
    }

    override func mouseUp(with event: NSEvent) {
        if bounds.contains(convert(event.locationInWindow, from: nil)) {
            onClick?()
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)

        if isHovered {
            // Draw rounded rect background with 5px inset from edges
            let highlightRect = bounds.insetBy(dx: 5, dy: 1)
            let path = NSBezierPath(roundedRect: highlightRect, xRadius: 5, yRadius: 5)
            NSColor.selectedContentBackgroundColor.setFill()
            path.fill()
        }
    }

    private func updateTextColors() {
        if isHovered {
            titleLabel?.textColor = .white
            timeLabel?.textColor = .white.withAlphaComponent(0.85)
        } else {
            titleLabel?.textColor = .labelColor
            timeLabel?.textColor = .secondaryLabelColor
        }
    }
}
