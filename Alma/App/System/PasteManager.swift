import Cocoa

final class PasteManager {

    private let pb = NSPasteboard.general
    
    // reentry guard
    private var isPasting = false
    
    typealias PasteSnapshot = [[NSPasteboard.PasteboardType: Data]]

    // Mark: Public Api
    func pasteOrCopy(
        text: String,
        hasFocus: Bool,
        axTrusted: Bool,
        delay: TimeInterval = 0.2,
        completion: @escaping (PasteResult) -> Void
    ) {

        // Prevent overlapping paste cycles
               guard !isPasting else { completion(.error("busy")); return }
               isPasting = true
        
        // Snapshot current clipboard first
               let snapshot = snapshotClipboard()
        
        // Replace clipboard with our text
               NSPasteboard.general.clearContents()
               NSPasteboard.general.setString(text, forType: .string)
        
        // Give the focused app a beat, then ⌘V, then restore clipboard
               DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                   self.sendCmdV()
                   DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                       self.restoreClipboard(snapshot)
                       self.isPasting = false
                       completion(.pasted)
                   }
               }
        
//        // Direct insert for Cocoa text inputs (No AX needed)
//        if directInsertIntoCocoa(text) {
//            completion(.pasted)
//            return
//        }
//
//        // if we dont have an editable target  or AX trust, just copy
//        guard hasFocus, axTrusted, AXFocusHelper.hasEditableTextTarget() else {
//            copyToClipboard(text)
//            completion(.copiedNoFocus)
//            return
//        }
//
//        // Use clipboard + ⌘V but restore previous clipboard after
//        let snapshot = pb.pasteboardItems  // preserve
//        copyToClipboard(text)
//
//        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
//            self.sendCmdV()
//
//            // Restore the clipboard shortly after the paste is dispatched
//            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
//                self.restoreClipboard(snapshot)
//                completion(.pasted)
//            }
//
//            NSPasteboard.general.clearContents()
//            NSPasteboard.general.setString(text, forType: .string)
//
//            guard hasFocus, axTrusted else {
//                completion(.copiedNoFocus)
//                return
//            }
//
//            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
//                self.sendCmdV()
//                completion(.pasted)
//            }
//        }
    }

    // MARK: Cocoa fast-path
    private func directInsertIntoCocoa(_ text: String) -> Bool {

        // Don’t try to insert if AX says the target is secure/non-editable.
        guard AXFocusHelper.hasEditableTextTarget() else { return false }

        // Must run on main thread because we’re touching AppKit responders.
        if !Thread.isMainThread {
            var ok = false
            DispatchQueue.main.sync { ok = self.directInsertIntoCocoa(text) }
            return ok
        }

        let responders: [NSResponder?] = [
            NSApp.keyWindow?.firstResponder,
            NSApp.mainWindow?.firstResponder,
        ]

        for r in responders.compactMap({ $0 }) {
            // NSTextView path (editable text views & field editors)
            if let tv = r as? NSTextView, tv.window != nil, tv.isEditable {
                tv.insertText(text, replacementRange: tv.selectedRange())
                return true
            }

            // Generic NSTextInputClient path (covers some custom controls)
            if let tic = r as? NSTextInputClient {
                let attr = NSAttributedString(string: text)
                tic.insertText(attr, replacementRange: NSRange(location: NSNotFound, length: 0))
                return true
            }
        }
        return false

    }

    // MARK: Clipboard helpers
    func copyToClipboard(_ text: String) {
        pb.clearContents()
        pb.setString(text, forType: .string)
    }

    private func restoreClipboard(_ snap: PasteSnapshot?) {
        guard let snap, !snap.isEmpty else { return }
        let board = NSPasteboard.general
        board.clearContents()
        
        // Recreate brand-new NSPasteboardItem instances
               var newItems: [NSPasteboardItem] = []
               for itemDict in snap {
                   let newItem = NSPasteboardItem()
                   for (type, data) in itemDict {
                       newItem.setData(data, forType: type)
                   }
                   newItems.append(newItem)
               }
               board.writeObjects(newItems)
    }
    
    private func snapshotClipboard() -> PasteSnapshot {
        let board = NSPasteboard.general
               let items = board.pasteboardItems ?? []
               return items.map { item in
                   var dict: [NSPasteboard.PasteboardType: Data] = [:]
                   for type in item.types {
                       if let data = item.data(forType: type) {
                           dict[type] = data
                       }
                   }
                   return dict
               }
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
        cmdUp?.post(tap: .cghidEventTap)
    }

    func sendCmdZ() {
        let src = CGEventSource(stateID: .hidSystemState)
        let tap = CGEventTapLocation.cghidEventTap

        let cmdDown = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: true)
        cmdDown?.flags = .maskCommand
        cmdDown?.post(tap: tap)

        let zDown = CGEvent(keyboardEventSource: src, virtualKey: 0x06, keyDown: true)
        zDown?.flags = .maskCommand
        zDown?.post(tap: tap)

        let zUp = CGEvent(keyboardEventSource: src, virtualKey: 0x06, keyDown: false)
        zUp?.flags = .maskCommand
        zUp?.post(tap: tap)

        let cmdUp = CGEvent(keyboardEventSource: src, virtualKey: 0x37, keyDown: false)
        cmdUp?.flags = .maskCommand
        cmdUp?.post(tap: tap)
    }
}
