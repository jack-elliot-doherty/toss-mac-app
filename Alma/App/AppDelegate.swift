import Cocoa
import Foundation

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var pillController: PillController!
    private var statusItem: NSStatusItem?
    private var menuBarController: MenuBarController?
    private let hotkey = HotkeyEventTap()
    private let recorder = AudioRecorder()
    private var didPaste: Bool = false
    private let pasteManager = PasteManager()
    private let historyRepo: InMemoryHistoryRepository = InMemoryHistoryRepository()
    private let pillViewModel = PillViewModel()
    private lazy var pillPanel = PillPanelController(viewModel: pillViewModel)
    private lazy var toastPanel = ToastPanelController(anchorFrameProvider: { [weak self] in
        self?.pillPanel.frame
    })
    private lazy var agentPanel = AgentPanelController(historyRepo: historyRepo)
    private var lastTapAt: Date?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Alma"
        let menuBarController = MenuBarController(statusItem: statusItem)
        self.statusItem = statusItem
        self.menuBarController = menuBarController

        // Pill panel idle and visible (non-activating)
        pillPanel.setState(.idle)
        // No need to call show() separately - setState already positions and shows

        pillController = PillController(
            audio: <#T##AudioRecorder#>,
            transcriber: <#T##TranscribeAPI#>,
            paste: <#T##PasteManager#>,
            pillPanel: <#T##PillPanelController#>,
            toast: <#T##ToastPanelController#>,
            viewModel: <#T##PillViewModel#>,
            auth: <#T##AuthManager#>
        )

        // Wire hold-to-talk
        hotkey.onHoldStart = { [weak self] in
            self?.pillController.send(.fnDown)
        }
        hotkey.onHoldEnd = { [weak self] in
            self?.pillController.send(.fnUp)
        }
        hotkey.start()

        // Expose UI intents from pill
        pillViewModel.onRequestStop = { [weak self] in self?.pillController.send(.stopButton)}
        pillViewModel.onRequestCancel = { [weak self] in self?.pillController.send(.cancelButton)}

        // Observe planner demo trigger
        NotificationCenter.default.addObserver(
            self, selector: #selector(runPlannerDemo),
            name: Notification.Name("plannerDemoRequested"), object: nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool)
        -> Bool
    {
        if !flag {
            if let window = NSApp.windows.first(where: { $0.title == "Alma" }) {
                NSApp.activate(ignoringOtherApps: true)
                window.makeKeyAndOrderFront(nil)
            }
        }
        return true
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

    func applicationWillTerminate(_ notification: Notification) {
        hotkey.stop()
        _ = recorder.stop()
    }

    @objc private func runPlannerDemo() {}
}

extension Notification.Name {
    static let plannerDemoRequested = Notification.Name("plannerDemoRequested")
}
