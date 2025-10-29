import Cocoa
import Foundation

@MainActor
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var menuBarController: MenuBarController?
    private let hotkey = HotkeyEventTap()
    private let recorder = AudioRecorder()
    private var didPaste: Bool = false
    private var pasteRetryTimer: Timer?
    private var pasteRetryCount: Int = 0
    private var startSound: NSSound?
    private let pasteManager = PasteManager()
    private let historyRepo: InMemoryHistoryRepository = InMemoryHistoryRepository()
    private let pillViewModel = PillViewModel()
    private lazy var pillPanel = PillPanelController(viewModel: pillViewModel)
    private lazy var toastPanel = ToastPanelController(anchorFrameProvider: { [weak self] in self?.pillPanel.frame })
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

        // Wire hold-to-talk
        hotkey.onHoldStart = { [weak self] in
            guard let self = self else { return }
            self.didPaste = false
            // Double-tap detection (~300ms)
            let now = Date()
            if let last = self.lastTapAt, now.timeIntervalSince(last) < 0.3 {
                self.pillViewModel.toggleAlwaysOn()
                let msg = self.pillViewModel.isAlwaysOn ? "Always-On enabled" : "Always-On disabled"
                self.toastPanel.show(message: msg, duration: 1.6)
            }
            self.pillPanel.setState(.listening)
            self.playStartSound()
            self.recorder.start()
            self.recorder.onLevelUpdate = { [weak self] rms in
                self?.pillViewModel.updateLevelRMS(rms)
            }
        }
        hotkey.onHoldEnd = { [weak self] in
            guard let self = self else { return }
            self.lastTapAt = Date()
            if self.pillViewModel.isAlwaysOn {
                // Do not stop; user will press Stop
                return
            }
            self.finishRecordingAndTranscribe()
        }
        hotkey.start()

        // Expose UI intents from pill
        pillViewModel.onRequestStop = { [weak self] in self?.finishRecordingAndTranscribe() }
        pillViewModel.onRequestCancel = { [weak self] in
            guard let self = self else { return }
            _ = self.recorder.stop()
            self.pillPanel.setState(.idle)
        }

        // Observe planner demo trigger
        NotificationCenter.default.addObserver(self, selector: #selector(runPlannerDemo), name: Notification.Name("plannerDemoRequested"), object: nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
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

    private func playStartSound() {
        // Prefer bundled asset
        if let url = Bundle.main.url(forResource: "digital-click-357350", withExtension: "mp3") {
            let sound = NSSound(contentsOf: url, byReference: true)
            self.startSound = sound
            if sound?.play() == true { return }
        }
        // Dev fallback: play from repository path if running locally
        let devPath = "/Users/jackdoherty/code/alma/alma-server/digital-click-357350.mp3"
        if FileManager.default.fileExists(atPath: devPath) {
            let url = URL(fileURLWithPath: devPath)
            let sound = NSSound(contentsOf: url, byReference: true)
            self.startSound = sound
            if sound?.play() == true { return }
        }
        // Final fallback
        NSSound.beep()
    }

    private func finishRecordingAndTranscribe() {
        let url = self.recorder.stop()
        self.pillPanel.setState(.transcribing)
        guard let url = url else {
            NSLog("[AppDelegate] no temp file URL")
            self.pillPanel.setState(.idle)
            return
        }
        let token = AuthManager.shared.accessToken
        TranscribeAPI.shared.transcribe(fileURL: url, token: token) { result in
            DispatchQueue.main.async {
                switch result {
                case .success(let text):
                    NSLog("[AppDelegate] received text len %d", text.count)
                    if self.pillViewModel.agentModeEnabled {
                        let thread = self.cacheTranscript(text)
                        self.toastPanel.show(message: "Sent to Agent", duration: 1.8)
                        self.agentPanel.show(for: thread)
                        self.pillPanel.setState(.idle)
                    } else {
                        let hasFocus = AXFocusHelper.hasFocusedTextInput()
                        let axTrusted = AccessibilityAuth.isTrusted()
                        self.pasteManager.pasteOrCopy(text: text, hasFocus: hasFocus, axTrusted: axTrusted, delay: 0.1) { pasteResult in
                            self.pillPanel.setState(.done(pasteResult))
                            switch pasteResult {
                            case .pasted:
                                self.toastPanel.show(message: "Pasted • Undo", duration: 2.2, onTap: { [weak self] in self?.pasteManager.sendCmdZ() })
                            case .copiedNoFocus:
                                self.toastPanel.show(message: "No input detected — text copied to clipboard", duration: 2.4)
                            case .error(let err):
                                self.toastPanel.show(message: "Error: \(err)", duration: 2.4)
                            }
                            _ = self.cacheTranscript(text)
                            self.pillPanel.setState(.idle)
                        }
                    }
                case .failure(let error):
                    NSLog("[Transcribe] error: \(error.localizedDescription)")
                    self.toastPanel.show(message: "Transcription failed: \(error.localizedDescription)", duration: 2.4)
                    self.pillPanel.setState(.idle)
                }
            }
        }
    }

    private func cacheTranscript(_ text: String) -> ThreadModel {
        let thread = historyRepo.upsertThread(title: "Quick Dictations")
        _ = historyRepo.appendMessage(threadId: thread.id, role: .user, content: text, status: .final)
        return thread
    }

    func applicationWillTerminate(_ notification: Notification) {
        hotkey.stop()
        _ = recorder.stop()
    }

    @objc private func runPlannerDemo() { }
}

extension Notification.Name {
    static let plannerDemoRequested = Notification.Name("plannerDemoRequested")
}


