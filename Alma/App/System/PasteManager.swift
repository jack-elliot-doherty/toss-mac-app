import Cocoa

final class PasteManager {
    
    private let pb = NSPasteboard.general
    
    // Mark: Public Api
    func pasteOrCopy(
        text: String,
        hasFocus: Bool,
        axTrusted: Bool,
        delay: TimeInterval = 0.08,
        completion: @escaping (PasteResult) -> Void
    ) {
        
        // Direct insert for Cocoa text inputs (No AX needed)
        if directInsertIntoCocao(text) {
            completion(.pasted)
            return
        }
        
        // if we dont have an editable target  or AX trust, just copy
        guard hasFocus, axTrusted, AXFocusHelper.hasEditableTextTarget() else {
            copyToClipboard(text)
            completion(.copiedNoFocus)
            return
        }
        
        // Use clipboard + ⌘V but restore previous clipboard after
        let snapshot = pb.pasteboardItems // preserve
        copyToClipboard(text)
        
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            self.sendCmdV()
            
            // Restore the clipboard shortly after the paste is dispatched
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1 ) {
                self.restoreClipboard(snapshot)
                completion(|.pasted)
        }
        
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

    // MARK: Clipboard helpers
    func copyToClipboard(_ text: String) {
        pb.clearContents()
        pb.setString(text, forType: .string)
    }
        
        func restoreClipboard(_ items: [NSPasteboardItem]?) {
               guard let items, !items.isEmpty else { return }
               pb.clearContents()
               pb.writeObjects(items)
           }
        
    func sendCmdV() {
        let src = CGEventSource(stateID: .hidSystemState)
        
        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand
        cmdDown?.post(tap: .cghidEventTap)
        
        let vDown = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: true)
        vDown?.flags = .maskCommand
        vDown?.post(tap: .cghidEventTap)
        
        let vUp = CGEvent(keyboardEventSource: src, virtualKey: 0x09, keyDown: false)
        vUp?.flags = .maskCommand
        vUp?.post(tap: .cghidEventTap)
        
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


