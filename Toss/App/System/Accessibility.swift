import Cocoa

enum AccessibilityAuth {
    // Cache the last known state to reduce log spam
    private static var lastKnownState: Bool?

    static func isTrusted() -> Bool {
        let trusted = AXIsProcessTrusted()
        // Only log when the state changes to reduce noise
        if lastKnownState != trusted {
            NSLog("[Accessibility] AXIsProcessTrusted changed: %@", trusted ? "true" : "false")
            lastKnownState = trusted
        }
        return trusted
    }

    @discardableResult
    static func ensureAccess(prompt: Bool) -> Bool {
        if AXIsProcessTrusted() { return true }
        if prompt {
            let options: CFDictionary =
                [kAXTrustedCheckOptionPrompt.takeRetainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(options)
        }
        let trusted = AXIsProcessTrusted()
        NSLog("[Accessibility] ensureAccess -> %@", trusted ? "granted" : "denied")
        return trusted
    }
}
