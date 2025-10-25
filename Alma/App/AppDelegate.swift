import Cocoa
import Foundation

class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem?
    private var menuBarController: MenuBarController?
    private let hotkey = HotkeyEventTap()
    private let recorder = AudioRecorder()
    private var didPaste: Bool = false
    private var pasteRetryTimer: Timer?
    private var pasteRetryCount: Int = 0

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "Alma"
        let menuBarController = MenuBarController(statusItem: statusItem)
        self.statusItem = statusItem
        self.menuBarController = menuBarController

        // Remove MCP; focus on dictation -> server -> paste

        // Wire hold-to-talk
        hotkey.onHoldStart = { [weak self] in
            guard let self = self else { return }
            self.didPaste = false
            self.menuBarController?.beginListening()
            self.recorder.start()
        }
        hotkey.onHoldEnd = { [weak self] in
            guard let self = self else { return }
            let url = self.recorder.stop()
            self.menuBarController?.endListening()
            guard let url = url else { NSLog("[AppDelegate] no temp file URL"); return }
            TranscribeAPI.shared.transcribe(fileURL: url) { result in
                DispatchQueue.main.async {
                    switch result {
                    case .success(let text):
                        NSLog("[AppDelegate] pasting text len %d", text.count)
                        if self.isTextInputFocused() {
                            self.pasteToFrontmostApp(text: text)
                        } else {
                            self.showNoFocusPopup()
                        }
                    case .failure(let error):
                        NSLog("[Transcribe] error: \(error.localizedDescription)")
                    }
                }
            }
        }
        hotkey.start()

        // Observe planner demo trigger
        NotificationCenter.default.addObserver(self, selector: #selector(runPlannerDemo), name: Notification.Name("plannerDemoRequested"), object: nil)
    }

    private func pasteToFrontmostApp(text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        // If we can't post key events yet, at least leave text on clipboard
        if !AccessibilityAuth.isTrusted() {
            NSLog("[AppDelegate] Accessibility not trusted — copied to clipboard only. Will auto-paste if enabled within 15s.")
            // Open Accessibility pane to make it easy to enable
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
            // Start a short-lived retry loop that will paste once trust becomes true
            pasteRetryTimer?.invalidate()
            pasteRetryCount = 0
            pasteRetryTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
                guard let self = self else { timer.invalidate(); return }
                self.pasteRetryCount += 1
                if AccessibilityAuth.isTrusted() {
                    self.sendCmdV()
                    timer.invalidate()
                    NSLog("[AppDelegate] Auto-paste succeeded after Accessibility granted")
                } else if self.pasteRetryCount > 30 { // ~15s
                    timer.invalidate()
                    NSLog("[AppDelegate] Auto-paste retry window elapsed; user can press Cmd+V")
                }
            }
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


