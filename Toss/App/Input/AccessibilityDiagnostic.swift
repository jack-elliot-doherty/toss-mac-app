import AppKit
import Foundation

/// Utility for extracting participant names from Slack huddles via Accessibility API
final class AccessibilityDiagnostic {
    
    /// Extract participant names from a Slack huddle window
    /// Returns an array of participant names (e.g., ["jack", "alice", "bob"])
    static func extractSlackHuddleParticipants() -> [String] {
        guard let slackApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.tinyspeck.slackmacgap"
        }) else {
            NSLog("[AXDiagnostic] Slack is not running")
            return []
        }
        
        let appElement = AXUIElementCreateApplication(slackApp.processIdentifier)
        
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            NSLog("[AXDiagnostic] Failed to get Slack windows")
            return []
        }
        
        NSLog("[AXDiagnostic] Searching \(windows.count) windows for huddle...")
        
        // Find the huddle window
        for (index, window) in windows.enumerated() {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            let title = (titleRef as? String) ?? ""
            
            NSLog("[AXDiagnostic] Window \(index): '\(title)'")
            
            if title.contains("Huddle") {
                NSLog("[AXDiagnostic] Found huddle window, searching for participants...")
                let participants = findParticipantsInElement(window, depth: 0)
                NSLog("[AXDiagnostic] Found \(participants.count) participant(s): \(participants)")
                return participants
            }
        }
        
        NSLog("[AXDiagnostic] No huddle window found")
        return []
    }
    
    /// Recursively search for AXRow elements with "View X's profile" titles
    private static func findParticipantsInElement(_ element: AXUIElement, depth: Int = 0, maxDepth: Int = 20) -> [String] {
        // Prevent infinite recursion
        guard depth < maxDepth else { return [] }
        
        var participants: [String] = []
        
        let role = getStringAttribute(element, kAXRoleAttribute as CFString)
        let title = getStringAttribute(element, kAXTitleAttribute as CFString)
        let desc = getStringAttribute(element, kAXDescriptionAttribute as CFString)
        
        // Log first few levels to see tree structure
        if depth <= 3 {
            NSLog("[AXDiagnostic] Depth \(depth): role='\(role ?? "nil")' title='\(title ?? "")' desc='\(desc ?? "")'")
        }
        
        // Log AXRow elements we find for debugging
        if role == "AXRow" {
            NSLog("[AXDiagnostic] Found AXRow at depth \(depth): title='\(title ?? "nil")'")
        }
        
        // Also check AXCell and AXButton - Slack might use different elements
        if let title = title, title.hasPrefix("View ") && title.contains("profile") {
            NSLog("[AXDiagnostic] Found potential participant element: role='\(role ?? "?")' title='\(title)'")
        }
        
        // Participant rows have title like "View jack's profile"
        // Note: Slack uses RIGHT SINGLE QUOTATION MARK ' (U+2019) not straight apostrophe ' (U+0027)
        if let title = title, title.hasPrefix("View ") && title.hasSuffix(" profile") {
            // Use regex to extract name between "View " and "'s profile" or similar
            // This handles various apostrophe characters
            let pattern = "^View (.+?)['']s profile$"
            if let regex = try? NSRegularExpression(pattern: pattern, options: []),
               let match = regex.firstMatch(in: title, options: [], range: NSRange(title.startIndex..., in: title)),
               let nameRange = Range(match.range(at: 1), in: title) {
                let name = String(title[nameRange])
                NSLog("[AXDiagnostic] Extracted participant: '\(name)' from role='\(role ?? "?")'")
                participants.append(name)
            } else {
                // Debug: log the actual Unicode code points in the title
                let codePoints = title.unicodeScalars.map { String(format: "U+%04X", $0.value) }.joined(separator: " ")
                NSLog("[AXDiagnostic] Failed to extract name from title. Unicode: \(codePoints)")
            }
        }
        
        // Recurse into children
        var childrenRef: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
        
        if result != .success {
            if depth <= 2 {
                NSLog("[AXDiagnostic] Depth \(depth): No children (result=\(result.rawValue))")
            }
            return participants
        }
        
        guard let children = childrenRef as? [AXUIElement] else {
            if depth <= 2 {
                NSLog("[AXDiagnostic] Depth \(depth): Children not castable to [AXUIElement]")
            }
            return participants
        }
        
        if depth <= 2 {
            NSLog("[AXDiagnostic] Depth \(depth): Found \(children.count) children")
        }
        
        for child in children {
            participants.append(contentsOf: findParticipantsInElement(child, depth: depth + 1, maxDepth: maxDepth))
        }
        
        return participants
    }
    
    /// Dump the full accessibility tree for Slack (for debugging)
    static func dumpSlackAccessibilityTree() {
        NSLog("[AXDiagnostic] === Starting Slack Accessibility Tree Dump ===")
        
        guard let slackApp = NSWorkspace.shared.runningApplications.first(where: {
            $0.bundleIdentifier == "com.tinyspeck.slackmacgap"
        }) else {
            NSLog("[AXDiagnostic] Slack is not running")
            return
        }
        
        let slackPID = slackApp.processIdentifier
        NSLog("[AXDiagnostic] Found Slack with PID: \(slackPID)")
        
        let appElement = AXUIElementCreateApplication(slackPID)
        
        var windowsRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(appElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
              let windows = windowsRef as? [AXUIElement] else {
            NSLog("[AXDiagnostic] Failed to get Slack windows")
            return
        }
        
        NSLog("[AXDiagnostic] Found \(windows.count) window(s)")
        
        for (windowIndex, window) in windows.enumerated() {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            let title = (titleRef as? String) ?? "<no title>"
            
            guard title.contains("Huddle") else {
                NSLog("[AXDiagnostic] Skipping non-huddle window: '\(title)'")
                continue
            }
            
            NSLog("[AXDiagnostic] ")
            NSLog("[AXDiagnostic] ========== Window \(windowIndex): '\(title)' ==========")
            dumpElementFull(window, depth: 0)
        }
        
        NSLog("[AXDiagnostic] === End of Slack Accessibility Tree Dump ===")
    }
    
    private static func dumpElementFull(_ element: AXUIElement, depth: Int) {
        let role = getStringAttribute(element, kAXRoleAttribute as CFString)
        let roleDescription = getStringAttribute(element, kAXRoleDescriptionAttribute as CFString)
        let title = getStringAttribute(element, kAXTitleAttribute as CFString)
        let value = getStringAttribute(element, kAXValueAttribute as CFString)
        let label = getStringAttribute(element, kAXDescriptionAttribute as CFString)
        let identifier = getStringAttribute(element, "AXIdentifier" as CFString)
        
        var desc = "\(indent(depth))[\(role ?? "?")]"
        if let roleDescription = roleDescription, !roleDescription.isEmpty { desc += " (\(roleDescription))" }
        if let identifier = identifier, !identifier.isEmpty { desc += " id='\(identifier)'" }
        if let title = title, !title.isEmpty { desc += " title='\(title)'" }
        if let value = value, !value.isEmpty { desc += " value='\(value)'" }
        if let label = label, !label.isEmpty { desc += " desc='\(label)'" }
        
        NSLog("[AXDiagnostic] \(desc)")
        
        var childrenRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef) == .success,
              let children = childrenRef as? [AXUIElement] else { return }
        
        for child in children {
            dumpElementFull(child, depth: depth + 1)
        }
    }
    
    private static func getStringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var valueRef: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &valueRef) == .success else { return nil }
        return valueRef as? String
    }
    
    private static func indent(_ depth: Int) -> String {
        String(repeating: "  ", count: depth)
    }
}
