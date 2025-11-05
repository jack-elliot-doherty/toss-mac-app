import Cocoa
import Foundation

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var pillController: PillController!
    private var statusItem: NSStatusItem?
    private let hotkey = HotkeyEventTap()
    private let recorder = AudioRecorder()
    private var didPaste: Bool = false
    private let pasteManager = PasteManager()
    private let historyRepo: InMemoryHistoryRepository = History.shared
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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        self.statusItem = statusItem

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
        hotkey.start()

        // Expose UI intents from pill
        pillViewModel.onRequestStop = { [weak self] in self?.pillController.send(.stopButton) }
        pillViewModel.onRequestCancel = { [weak self] in self?.pillController.send(.cancelButton) }

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
