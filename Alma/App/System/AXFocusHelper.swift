import Cocoa

enum AXFocusHelper {
    
    static func focusedElement() -> AXUIElement? {
        guard AccessibilityAuth.isTrusted() else {return nil}
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        let res = AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused)
        guard res == .success, let el  = focused else {return nil}
        return (el as!  AXUIElement)
    }
    
    static func hasEditableTextTarget() -> Bool {
        guard let el = focusedElement() else {return false}
        
        var isSecure: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, "AXSecure" as CFString, &isSecure) == .success,
           let secure = isSecure as? Bool, secure {return false}
        
        // Role Check
        var role: CFTypeRef?
        if AXUIElementCopyAttributeValue(el, kAXRoleAttribute as CFString, &role) == .success,
           let roleStr = role as? String {
            let editableRoles = [kAXTextFieldRole as String, kAXTextAreaRole as String, "AXSearchField"]
            if editableRoles.contains(roleStr) { return true }
        }
        
        // Editable?
        var editable:CFTypeRef?
        if AXUIElementCopyAttributeValue(el, "AXEditable" as CFString, &editable) == .success,
           let canEdit = editable as? Bool {return canEdit}
        
        return false
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


