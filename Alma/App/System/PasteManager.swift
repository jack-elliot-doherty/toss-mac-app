import Cocoa

final class PasteManager {
    func pasteOrCopy(text: String, hasFocus: Bool, axTrusted: Bool, delay: TimeInterval = 0.1, completion: @escaping (PasteResult) -> Void) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)

        guard hasFocus, axTrusted else {
            completion(.copiedNoFocus)
            return
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.sendCmdV()
            completion(.pasted)
        }
    }

    func sendCmdV() {
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
    }

    func sendCmdZ() {
        let src = CGEventSource(stateID: .hidSystemState)
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand
        let zDown = CGEvent(keyboardEventSource: src, virtualKey: 0x06, keyDown: true)
        zDown?.flags = .maskCommand
        let zUp = CGEvent(keyboardEventSource: src, virtualKey: 0x06, keyDown: false)
        zUp?.flags = .maskCommand
        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false)
        cmdUp?.flags = .maskCommand
        let tap = CGEventTapLocation.cghidEventTap
        cmdDown?.post(tap: tap)
        zDown?.post(tap: tap)
        zUp?.post(tap: tap)
        cmdUp?.post(tap: tap)
    }
}


