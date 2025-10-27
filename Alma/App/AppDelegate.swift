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

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Alma"
        let menuBarController = MenuBarController(statusItem: statusItem)
        self.statusItem = statusItem
        self.menuBarController = menuBarController

        // Remove MCP; focus on dictation -> server -> paste
        // Show idle mic pill always-on
        menuBarController.beginListening()
        menuBarController.endListening() // ensure window exists then hide; we'll keep it idle and visible

        // Wire hold-to-talk
        hotkey.onHoldStart = { [weak self] in
            guard let self = self else { return }
            self.didPaste = false
            self.menuBarController?.beginListening()
            self.playStartSound()
            self.recorder.start()
        }
        hotkey.onHoldEnd = { [weak self] in
            guard let self = self else { return }
            let url = self.recorder.stop()
            // Keep pill visible and show loading while we transcribe
            self.menuBarController?.showLoading()
            guard let url = url else {
                NSLog("[AppDelegate] no temp file URL")
                self.menuBarController?.endListening()
                return
            }
            let token = AuthManager.shared.accessToken
            TranscribeAPI.shared.transcribe(fileURL: url, token: token) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let text):
                        NSLog("[AppDelegate] pasting text len %d", text.count)
                        if self.isTextInputFocused() {
                            self.pasteToFrontmostApp(text: text)
                        } else {
                            self.showNoFocusPopup()
                        }
                        self.menuBarController?.endListening()
                    case .failure(let error):
                        NSLog("[Transcribe] error: \(error.localizedDescription)")
                        self.menuBarController?.endListening()
                    }
                }
            }
        }
        hotkey.start()

        // Bring main window to front on first launch
        NSApp.activate(ignoringOtherApps: true)
        if let window = NSApp.windows.first(where: { $0.title == "Alma" }) {
            window.makeKeyAndOrderFront(nil)
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

    private func pasteToFrontmostApp(text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        // If we can't post key events yet, at least leave text on clipboard
        if !AccessibilityAuth.isTrusted() {
            NSLog("[AppDelegate] Accessibility not trusted — copied to clipboard only. Will auto-paste if enabled within 15s.")
            // Do not auto-open Accessibility settings or retry; leave text on clipboard
            return
        }
        sendCmdV()
    }

    private func sendCmdV() {
        let src = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false)
        cmdUp?.flags = .maskCommand
        let tap = CGEventTapLocation.cghidEventTap
        cmdDown?.post(tap: tap)
        vDown?.post(tap: tap)
        vUp?.post(tap: tap)
        cmdUp?.post(tap: tap)
        didPaste = true
        NSLog("[AppDelegate] Cmd+V sent")
    }

    private func isTextInputFocused() -> Bool {
        // For simplicity, assume true; improve later with AX API.
        return true
    }

    private func showNoFocusPopup() {
        let alert = NSAlert()
        alert.messageText = "Whoops — no focused input box"
        alert.informativeText = "Click into a text field and try again."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
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


