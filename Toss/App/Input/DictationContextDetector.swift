import AppKit
import Foundation

/// Represents the context in which dictation is happening
enum DictationMode: String {
    case plain  // Default, light cleanup only
    case email  // Email composition (Mail, Gmail, Outlook)
    case slack  // Slack message
    case notes  // Note-taking apps

    var displayName: String {
        switch self {
        case .plain: return "Plain"
        case .email: return "Email"
        case .slack: return "Slack"
        case .notes: return "Notes"
        }
    }
}

/// Detects the current dictation context based on the focused application and element
final class DictationContextDetector {
    static let shared = DictationContextDetector()

    // Bundle identifiers for email apps
    private let emailAppBundleIds: Set<String> = [
        "com.apple.mail",  // Apple Mail
        "com.microsoft.Outlook",  // Microsoft Outlook
        "com.readdle.smartemail-Mac",  // Spark
        "com.freron.MailMate",  // MailMate
        "com.postbox-inc.postbox",  // Postbox
        "com.superhuman.Superhuman",  // Superhuman
        "com.mimestream.Mimestream",  // Mimestream
        "com.GyazMail.GyazMail",  // GyazMail
        "com.canary-mail.Canary-Mail",  // Canary Mail
    ]

    // Bundle identifiers for note-taking apps
    private let notesAppBundleIds: Set<String> = [
        "com.apple.Notes",  // Apple Notes
        "notion.id",  // Notion
        "md.obsidian",  // Obsidian
        "com.evernote.Evernote",  // Evernote
        "com.craft.craft",  // Craft
        "com.logseq.logseq",  // Logseq
        "com.electron.replit",  // Bear
        "net.shinyfrog.bear",  // Bear (actual bundle ID)
        "com.ulysses.ulysses",  // Ulysses
    ]

    // Bundle identifiers for Slack
    private let slackBundleIds: Set<String> = [
        "com.tinyspeck.slackmacgap"  // Slack
    ]

    // Browser bundle identifiers
    private let browserBundleIds: Set<String> = [
        "com.google.Chrome",
        "com.apple.Safari",
        "org.mozilla.firefox",
        "com.microsoft.edgemac",
        "company.thebrowser.Browser",  // Arc browser
        "com.brave.Browser",  // Brave
        "com.vivaldi.Vivaldi",  // Vivaldi
    ]

    private init() {}

    /// Detects the current dictation context
    func detectContext() -> DictationMode {
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
            let bundleId = frontApp.bundleIdentifier
        else {
            return .plain
        }

        NSLog(
            "[DictationContextDetector] Front app: \(frontApp.localizedName ?? "unknown") (\(bundleId))"
        )

        // Check native apps first
        if emailAppBundleIds.contains(bundleId) {
            NSLog("[DictationContextDetector] Detected email app")
            return .email
        }

        if slackBundleIds.contains(bundleId) {
            NSLog("[DictationContextDetector] Detected Slack")
            return .slack
        }

        if notesAppBundleIds.contains(bundleId) {
            NSLog("[DictationContextDetector] Detected notes app")
            return .notes
        }

        // Check browsers for web-based apps
        if browserBundleIds.contains(bundleId) {
            return detectBrowserContext(app: frontApp)
        }

        return .plain
    }

    /// Detects context when the user is in a browser
    private func detectBrowserContext(app: NSRunningApplication) -> DictationMode {
        // Try to get the browser's active tab title/URL using accessibility
        let browserElement = AXUIElementCreateApplication(app.processIdentifier)

        // Get the focused window's title which often contains the page title
        var windowsRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                browserElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
            let windows = windowsRef as? [AXUIElement],
            let firstWindow = windows.first
        else {
            return .plain
        }

        var titleRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(firstWindow, kAXTitleAttribute as CFString, &titleRef)
                == .success,
            let windowTitle = titleRef as? String
        else {
            return .plain
        }

        let lowercaseTitle = windowTitle.lowercased()
        NSLog("[DictationContextDetector] Browser window title: \(windowTitle)")

        // Check for email web apps
        if lowercaseTitle.contains("gmail") || lowercaseTitle.contains("mail")
            || lowercaseTitle.contains("outlook") || lowercaseTitle.contains("yahoo mail")
            || lowercaseTitle.contains("protonmail") || lowercaseTitle.contains("fastmail")
            || lowercaseTitle.contains("hey.com") || lowercaseTitle.contains("inbox")
            || lowercaseTitle.contains("compose")
        {
            NSLog("[DictationContextDetector] Detected email in browser")
            return .email
        }

        // Check for Slack web
        if lowercaseTitle.contains("slack") {
            NSLog("[DictationContextDetector] Detected Slack in browser")
            return .slack
        }

        // Check for note-taking web apps
        if lowercaseTitle.contains("notion") || lowercaseTitle.contains("evernote")
            || lowercaseTitle.contains("google docs") || lowercaseTitle.contains("roam")
            || lowercaseTitle.contains("obsidian")
        {
            NSLog("[DictationContextDetector] Detected notes in browser")
            return .notes
        }

        return .plain
    }

    /// Check if we're specifically in an email compose context
    /// This is more precise but requires accessibility access
    func isInEmailComposeContext() -> Bool {
        guard AccessibilityAuth.isTrusted() else { return false }

        guard let focusedElement = AXFocusHelper.focusedElement() else {
            return false
        }

        // Check if we're in a text area that might be email compose
        var roleRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(focusedElement, kAXRoleAttribute as CFString, &roleRef)
                == .success,
            let role = roleRef as? String
        else {
            return false
        }

        // Email compose fields are typically text areas or text fields
        let isTextInput = role == kAXTextAreaRole as String || role == kAXTextFieldRole as String

        if !isTextInput {
            return false
        }

        // Try to get the description or identifier of the element
        var descriptionRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            focusedElement, kAXDescriptionAttribute as CFString, &descriptionRef) == .success,
            let description = descriptionRef as? String
        {
            let lowerDesc = description.lowercased()
            if lowerDesc.contains("message") || lowerDesc.contains("compose")
                || lowerDesc.contains("body") || lowerDesc.contains("email")
            {
                return true
            }
        }

        return false
    }

    /// Checks if a string is specifically a "To" field label (not just containing "to")
    private func isToFieldLabel(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased()
        // Match: "to", "to:", "to ", but NOT "skip to content", "go to", etc.
        return trimmed == "to" || trimmed == "to:" || trimmed.hasPrefix("to ")
            || trimmed.hasPrefix("to:") || trimmed == "recipients" || trimmed == "to recipients"
    }

    /// Extracts vocabulary hints for speech-to-text based on current context
    /// For email mode, this tries to extract recipient names from the "To:" field
    func getContextVocabularyHints() -> String? {
        guard AccessibilityAuth.isTrusted() else { return nil }

        guard let frontApp = NSWorkspace.shared.frontmostApplication,
            let bundleId = frontApp.bundleIdentifier
        else {
            return nil
        }

        // Only extract hints for email apps
        let isEmailApp =
            emailAppBundleIds.contains(bundleId)
            || (browserBundleIds.contains(bundleId)
                && detectBrowserContext(app: frontApp) == .email)

        guard isEmailApp else { return nil }

        NSLog("[DictationContextDetector] Extracting email recipient hints...")

        // Try to find recipient names from the app's UI
        let appElement = AXUIElementCreateApplication(frontApp.processIdentifier)

        // First, try to get the focused window for more targeted search
        var focusedWindowRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            appElement, kAXFocusedWindowAttribute as CFString, &focusedWindowRef) == .success,
            let focusedWindow = focusedWindowRef
        {
            let windowElement = focusedWindow as! AXUIElement

            // Try Gmail-specific detection first (look for compose window)
            if let gmailRecipient = findGmailComposeRecipients(in: windowElement) {
                NSLog(
                    "[DictationContextDetector] Found Gmail compose recipients: \(gmailRecipient)")
                return gmailRecipient
            }

            // Search within the focused window for traditional To: fields
            if let recipientText = findEmailRecipients(in: windowElement) {
                NSLog("[DictationContextDetector] Found recipients in window: \(recipientText)")
                return recipientText
            }
        }

        // Fallback: Search the entire app
        if let recipientText = findEmailRecipients(in: appElement) {
            NSLog("[DictationContextDetector] Found recipients: \(recipientText)")
            return recipientText
        }

        NSLog("[DictationContextDetector] No recipient hints found")
        return nil
    }

    /// Gmail-specific: Find recipients in a Gmail compose window
    /// Gmail compose windows have title like "Compose: <subject>" and contain email addresses
    private func findGmailComposeRecipients(in element: AXUIElement, depth: Int = 0) -> String? {
        guard depth < 25 else { return nil }

        // Check if this is a compose window
        var titleRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        let title = (titleRef as? String) ?? ""

        // Gmail compose windows have "Compose:" in title
        if title.lowercased().hasPrefix("compose:") || title.lowercased().contains("compose:") {
            NSLog("[DictationContextDetector] Found Gmail compose window: \(title)")

            // Search for email addresses within this compose window
            if let emails = findEmailAddressesInDescendants(element, maxDepth: 10) {
                return emails
            }
        }

        // Recurse into children
        var childrenRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
                == .success,
            let children = childrenRef as? [AXUIElement]
        else {
            return nil
        }

        for child in children {
            if let result = findGmailComposeRecipients(in: child, depth: depth + 1) {
                return result
            }
        }

        return nil
    }

    /// Find email addresses in descendants and extract name hints from them
    private func findEmailAddressesInDescendants(
        _ element: AXUIElement, maxDepth: Int, currentDepth: Int = 0
    ) -> String? {
        guard currentDepth < maxDepth else { return nil }

        var names: [String] = []

        // Check this element for email address
        var valueRef: CFTypeRef?
        var roleRef: CFTypeRef?

        _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        _ = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)

        let role = (roleRef as? String) ?? ""
        let value = (valueRef as? String) ?? ""

        // Look for static text elements containing email addresses
        if role == kAXStaticTextRole as String && value.contains("@") && value.contains(".") {
            // This looks like an email address - extract name from it
            if let name = extractNameFromEmail(value) {
                NSLog("[DictationContextDetector] Found email '\(value)' -> name hint '\(name)'")
                names.append(name)
            }
        }

        // Recurse into children
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
            == .success,
            let children = childrenRef as? [AXUIElement]
        {
            for child in children {
                if let childNames = findEmailAddressesInDescendants(
                    child, maxDepth: maxDepth, currentDepth: currentDepth + 1)
                {
                    names.append(childNames)
                }
            }
        }

        guard !names.isEmpty else { return nil }
        return names.joined(separator: ", ")
    }

    /// Extract a name hint from an email address
    /// "bryan.smith@gmail.com" -> "Bryan Smith"
    /// "bryan@gmail.com" -> "Bryan"
    /// "b.smith@company.com" -> "B Smith"
    private func extractNameFromEmail(_ email: String) -> String? {
        // Get the username part before @
        guard let atIndex = email.firstIndex(of: "@") else { return nil }
        let username = String(email[..<atIndex])

        // Skip very short usernames or generic ones
        if username.count < 2 { return nil }
        let genericUsernames = [
            "info", "hello", "contact", "support", "admin", "noreply", "no-reply", "notifications",
            "team",
        ]
        if genericUsernames.contains(username.lowercased()) { return nil }

        // Split by common separators (., _, -)
        let parts =
            username
            .replacingOccurrences(of: ".", with: " ")
            .replacingOccurrences(of: "_", with: " ")
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: " ")
            .filter { !$0.isEmpty }

        // Capitalize each part
        let capitalizedParts = parts.map { part -> String in
            // Handle all caps or all lowercase
            if part.count == 1 {
                return part.uppercased()
            }
            return part.prefix(1).uppercased() + part.dropFirst().lowercased()
        }

        return capitalizedParts.joined(separator: " ")
    }

    /// Debug function to dump the accessibility tree structure
    private func dumpAccessibilityTree(element: AXUIElement, depth: Int, maxDepth: Int) {
        guard depth < maxDepth else { return }

        let indent = String(repeating: "  ", count: depth)

        // Get key attributes
        var roleRef: CFTypeRef?
        var titleRef: CFTypeRef?
        var descriptionRef: CFTypeRef?
        var valueRef: CFTypeRef?
        var labelRef: CFTypeRef?
        var placeholderRef: CFTypeRef?
        var identifierRef: CFTypeRef?

        _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        _ = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        _ = AXUIElementCopyAttributeValue(
            element, kAXDescriptionAttribute as CFString, &descriptionRef)
        _ = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
        _ = AXUIElementCopyAttributeValue(element, "AXLabel" as CFString, &labelRef)
        _ = AXUIElementCopyAttributeValue(
            element, "AXPlaceholderValue" as CFString, &placeholderRef)
        _ = AXUIElementCopyAttributeValue(
            element, kAXIdentifierAttribute as CFString, &identifierRef)

        let role = (roleRef as? String) ?? "?"
        let title = (titleRef as? String) ?? ""
        let desc = (descriptionRef as? String) ?? ""
        let value = (valueRef as? String) ?? ""
        let label = (labelRef as? String) ?? ""
        let placeholder = (placeholderRef as? String) ?? ""
        let identifier = (identifierRef as? String) ?? ""

        // Only log elements that have some interesting content
        let hasContent =
            !title.isEmpty || !desc.isEmpty || !value.isEmpty || !label.isEmpty
            || !placeholder.isEmpty

        // Always log the structure, but truncate long values
        let truncatedValue = value.count > 50 ? String(value.prefix(50)) + "..." : value
        let truncatedTitle = title.count > 50 ? String(title.prefix(50)) + "..." : title

        // Log this element
        var parts: [String] = [role]
        if !truncatedTitle.isEmpty { parts.append("title=\"\(truncatedTitle)\"") }
        if !desc.isEmpty { parts.append("desc=\"\(desc)\"") }
        if !truncatedValue.isEmpty { parts.append("value=\"\(truncatedValue)\"") }
        if !label.isEmpty { parts.append("label=\"\(label)\"") }
        if !placeholder.isEmpty { parts.append("placeholder=\"\(placeholder)\"") }
        if !identifier.isEmpty { parts.append("id=\"\(identifier)\"") }

        // Only log if there's something interesting or it's a container
        if hasContent || depth < 5 {
            NSLog("%@%@", indent, parts.joined(separator: " | "))
        }

        // Get children and recurse
        var childrenRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
                == .success,
            let children = childrenRef as? [AXUIElement]
        else {
            return
        }

        for child in children {
            dumpAccessibilityTree(element: child, depth: depth + 1, maxDepth: maxDepth)
        }
    }

    /// Recursively searches for email recipient fields in the accessibility tree
    private func findEmailRecipients(in element: AXUIElement, depth: Int = 0) -> String? {
        // Limit recursion depth to avoid performance issues (Gmail has deep nesting)
        guard depth < 20 else { return nil }

        // Get various attributes that might identify a recipient field
        var descriptionRef: CFTypeRef?
        var labelRef: CFTypeRef?
        var valueRef: CFTypeRef?
        var roleRef: CFTypeRef?
        var titleRef: CFTypeRef?
        var roleDescRef: CFTypeRef?
        var placeholderRef: CFTypeRef?
        var identifierRef: CFTypeRef?

        _ = AXUIElementCopyAttributeValue(
            element, kAXDescriptionAttribute as CFString, &descriptionRef)
        _ = AXUIElementCopyAttributeValue(
            element, "AXLabel" as CFString, &labelRef)
        _ = AXUIElementCopyAttributeValue(
            element, kAXRoleAttribute as CFString, &roleRef)
        _ = AXUIElementCopyAttributeValue(
            element, kAXTitleAttribute as CFString, &titleRef)
        _ = AXUIElementCopyAttributeValue(
            element, kAXRoleDescriptionAttribute as CFString, &roleDescRef)
        _ = AXUIElementCopyAttributeValue(
            element, "AXPlaceholderValue" as CFString, &placeholderRef)
        _ = AXUIElementCopyAttributeValue(
            element, kAXIdentifierAttribute as CFString, &identifierRef)

        let description = (descriptionRef as? String)?.lowercased() ?? ""
        let label = (labelRef as? String)?.lowercased() ?? ""
        let title = (titleRef as? String)?.lowercased() ?? ""
        let roleDesc = (roleDescRef as? String)?.lowercased() ?? ""
        let placeholder = (placeholderRef as? String)?.lowercased() ?? ""
        let identifier = (identifierRef as? String)?.lowercased() ?? ""

        // Check if this is a "To" field - various apps use different labels
        // Be careful to match "To" as a field label, not just any text containing "to"
        let isToField =
            isToFieldLabel(description) || isToFieldLabel(label)
            || isToFieldLabel(title) || isToFieldLabel(placeholder)
            || description.contains("recipient") || label.contains("recipient")
            || roleDesc.contains("recipient") || placeholder.contains("recipient")
            || (identifier.contains("to")
                && (identifier.contains("input") || identifier.contains("field")
                    || identifier.contains("recipient")))

        if isToField {
            NSLog(
                "[DictationContextDetector] Found potential To field (desc: '\(description)', label: '\(label)', placeholder: '\(placeholder)')"
            )

            // Try to get the value of this field directly
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
                == .success,
                let value = valueRef as? String, !value.isEmpty
            {
                NSLog("[DictationContextDetector] Found To field with value: \(value)")
                return extractNamesFromRecipientField(value)
            }

            // Gmail uses "chips" for recipients - look for child text elements
            if let chipText = extractTextFromChildren(element) {
                NSLog("[DictationContextDetector] Found recipient chips: \(chipText)")
                return chipText
            }

            // Try deeper extraction for Gmail's complex structure
            if let deepText = extractAllTextFromDescendants(element, maxDepth: 5) {
                NSLog("[DictationContextDetector] Found text in descendants: \(deepText)")
                return deepText
            }
        }

        // Check children
        var childrenRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
                == .success,
            let children = childrenRef as? [AXUIElement]
        else {
            return nil
        }

        for child in children {
            if let result = findEmailRecipients(in: child, depth: depth + 1) {
                return result
            }
        }

        return nil
    }

    /// Extracts text content from child elements (for Gmail's recipient "chips")
    private func extractTextFromChildren(_ element: AXUIElement) -> String? {
        var childrenRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
                == .success,
            let children = childrenRef as? [AXUIElement]
        else {
            return nil
        }

        var texts: [String] = []

        for child in children {
            // Try to get value or title from each child
            var valueRef: CFTypeRef?
            var titleRef: CFTypeRef?

            if AXUIElementCopyAttributeValue(child, kAXValueAttribute as CFString, &valueRef)
                == .success,
                let value = valueRef as? String, !value.isEmpty
            {
                let extracted = extractNamesFromRecipientField(value)
                if !extracted.isEmpty {
                    texts.append(extracted)
                }
            } else if AXUIElementCopyAttributeValue(child, kAXTitleAttribute as CFString, &titleRef)
                == .success,
                let title = titleRef as? String, !title.isEmpty, !title.contains("@")
            {
                texts.append(title)
            }
        }

        guard !texts.isEmpty else { return nil }
        return texts.joined(separator: ", ")
    }

    /// Recursively extracts all text from descendants (for deeply nested structures like Gmail)
    private func extractAllTextFromDescendants(
        _ element: AXUIElement, maxDepth: Int, currentDepth: Int = 0
    ) -> String? {
        guard currentDepth < maxDepth else { return nil }

        var texts: [String] = []

        // Get this element's text content
        var valueRef: CFTypeRef?
        var titleRef: CFTypeRef?
        var roleRef: CFTypeRef?

        _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        let role = roleRef as? String ?? ""

        // Only extract from static text or text fields
        if role == kAXStaticTextRole as String || role == kAXTextFieldRole as String {
            if AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)
                == .success,
                let value = valueRef as? String, !value.isEmpty
            {
                let extracted = extractNamesFromRecipientField(value)
                if !extracted.isEmpty && !extracted.contains("@") {
                    texts.append(extracted)
                }
            }
            if AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
                == .success,
                let title = titleRef as? String, !title.isEmpty, !title.contains("@")
            {
                texts.append(title)
            }
        }

        // Recurse into children
        var childrenRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &childrenRef)
            == .success,
            let children = childrenRef as? [AXUIElement]
        {
            for child in children {
                if let childText = extractAllTextFromDescendants(
                    child, maxDepth: maxDepth, currentDepth: currentDepth + 1)
                {
                    texts.append(childText)
                }
            }
        }

        guard !texts.isEmpty else { return nil }

        // Deduplicate and join
        let unique = Array(Set(texts))
        return unique.joined(separator: ", ")
    }

    /// Extracts clean name spellings from email recipient field value
    /// Input: "Ondrej Brothanek <ondrej@vercel.com>, John Smith <john@example.com>"
    /// Output: "Ondrej Brothanek, John Smith"
    private func extractNamesFromRecipientField(_ fieldValue: String) -> String {
        // Split by comma for multiple recipients
        let recipients = fieldValue.components(separatedBy: ",")

        var names: [String] = []
        for recipient in recipients {
            let trimmed = recipient.trimmingCharacters(in: .whitespaces)

            // Handle "Name <email>" format
            if let angleBracketRange = trimmed.range(of: "<") {
                let namePart = String(trimmed[..<angleBracketRange.lowerBound])
                    .trimmingCharacters(in: .whitespaces)
                if !namePart.isEmpty && !namePart.contains("@") {
                    names.append(namePart)
                }
            } else if !trimmed.contains("@") {
                // Just a name without email
                names.append(trimmed)
            }
        }

        guard !names.isEmpty else { return fieldValue }

        return names.joined(separator: ", ")
    }
}
