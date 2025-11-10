import Cocoa
import Foundation
import Sparkle

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {

    let updaterController: SPUStandardUpdaterController
    private let meetingDetector = MeetingDetector()

    private var pillController: PillController!
    private var statusItem: NSStatusItem?
    private let hotkey = HotkeyEventTap()
    private let recorder = AudioRecorder()
    private var didPaste: Bool = false
    private let pasteManager = PasteManager()
    private let historyRepo: PersistentHistoryRepository = History.shared
    private let pillViewModel = PillViewModel()
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

    override init() {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        super.init()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
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
            agentPanel: agentPanel

        )

        // Wire hold-to-talk
        hotkey.onFnDown = { [weak self] in
            self?.pillController.send(.fnDown)
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

        // Observe planner demo trigger
        NotificationCenter.default.addObserver(
            self, selector: #selector(runPlannerDemo),
            name: Notification.Name("plannerDemoRequested"), object: nil)

        // Setup meeting detection
        meetingDetector.onMeetingDetected = { [weak self] in
            self?.pillController.send(.meetingDetected)
        }
        meetingDetector.start()

        NSLog("[AppDelegate] Meeting detection enabled")
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
        for url in urls { _ = AuthManager.shared.handleDeepLink(url: url) }
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
        hotkey.stop()
        _ = recorder.stop()
        meetingDetector.stop()
        NSLog("[AppDelegate] Meeting detection disabled")
    }

    @objc private func runPlannerDemo() {}
}

extension Notification.Name {
    static let plannerDemoRequested = Notification.Name("plannerDemoRequested")
}
