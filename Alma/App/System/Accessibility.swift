import Cocoa

enum AccessibilityAuth {
    static func isTrusted() -> Bool {
        let trusted = AXIsProcessTrusted()
        NSLog("[Accessibility] AXIsProcessTrusted = %@", trusted ? "true" : "false")
        return trusted
    }

    @discardableResult
    static func ensureAccess(prompt: Bool) -> Bool {
        if AXIsProcessTrusted() { return true }
        if prompt {
            let options: CFDictionary = [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        let trusted = AXIsProcessTrusted()
        NSLog("[Accessibility] ensureAccess -> %@", trusted ? "granted" : "denied")
        return trusted
    }
}


