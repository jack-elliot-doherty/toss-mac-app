import Cocoa

enum AXFocusHelper {
    
    static func focusedElement() -> AXUIElement? {
        guard AccessibilityAuth.isTrusted() else {return nil}
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let res = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
        guard res == .success, let el  = focused else {return nil}
        return (el! as  AXUIElement)
    }
    
    static func hasEditableTextTarget() -> Bool {
        guard let el = focusedElement() else {return false}
        
        var isSecure: CFTypeRef
        
    }
    
    static func hasFocusedTextInput() -> Bool {
        guard AccessibilityAuth.isTrusted() else { return false }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let res = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
        guard res == .success, let el = focused else { return false }
        let elem = el as! AXUIElement

        var roleValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(elem, kAXRoleAttribute as CFString, &roleValue) == .success, let roleStr = roleValue as? String {
            if roleStr == kAXTextFieldRole as String || roleStr == kAXTextAreaRole as String || roleStr.contains("Text") {
                return true
            }
        }
        // Fallback: check for editable attribute if present
        var editableValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(elem, "AXEditable" as CFString, &editableValue) == .success, let editable = editableValue as? Bool {
            return editable
        }
        return false
    }
}


