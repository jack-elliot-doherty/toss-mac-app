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

            // DEBUG: Uncomment to dump AX tree
            // NSLog("[DictationContextDetector] ========== DUMPING AX TREE ==========")
            // dumpAccessibilityTree(element: windowElement, depth: 0, maxDepth: 30)
            // NSLog("[DictationContextDetector] ========== END AX TREE DUMP ==========")

            // Try Gmail-specific detection first (look for compose window)
            if let gmailRecipient = findGmailComposeRecipients(in: windowElement) {
                NSLog(
                    "[DictationContextDetector] Found Gmail compose recipients: \(gmailRecipient)")
                return gmailRecipient
            }

            // For Gmail replies - check if browser window indicates a reply and search more broadly
            var windowTitleRef: CFTypeRef?
            if AXUIElementCopyAttributeValue(
                windowElement, kAXTitleAttribute as CFString, &windowTitleRef) == .success,
                let windowTitle = windowTitleRef as? String
            {
                let lowerTitle = windowTitle.lowercased()

                // If this is a Gmail reply/forward, search for email addresses broadly
                if lowerTitle.contains("gmail")
                    && (lowerTitle.hasPrefix("re:") || lowerTitle.hasPrefix("fwd:"))
                {
                    NSLog(
                        "[DictationContextDetector] Detected Gmail reply/forward, searching broadly"
                    )
                    if let emails = findEmailAddressesInDescendants(windowElement, maxDepth: 15) {
                        NSLog("[DictationContextDetector] Found emails in reply context: \(emails)")
                        return emails
                    }
                }
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

    /// Gmail-specific: Find recipients in a Gmail compose or reply window
    /// - New emails: title like "Compose: <subject>"
    /// - Replies: title like "RE: <subject>" or contains reply indicators
    /// - Forwards: title like "Fwd: <subject>"
    private func findGmailComposeRecipients(in element: AXUIElement, depth: Int = 0) -> String? {
        guard depth < 25 else { return nil }

        // Check if this is a compose/reply window
        var titleRef: CFTypeRef?
        var descRef: CFTypeRef?
        _ = AXUIElementCopyAttributeValue(element, kAXTitleAttribute as CFString, &titleRef)
        _ = AXUIElementCopyAttributeValue(element, kAXDescriptionAttribute as CFString, &descRef)
        let title = (titleRef as? String)?.lowercased() ?? ""
        let desc = (descRef as? String)?.lowercased() ?? ""

        // Gmail compose/reply windows have these patterns:
        // - New: "Compose: <subject>"
        // - Reply: "RE: <subject>" or just contains email thread
        // - Forward: "Fwd: <subject>"
        let isComposeWindow =
            title.hasPrefix("compose:") || title.contains("compose:")
            || title.hasPrefix("re:") || title.hasPrefix("fwd:")
            || desc.contains("compose") || desc.contains("reply")

        if isComposeWindow {
            NSLog("[DictationContextDetector] Found Gmail compose/reply window: \(title)")

            // Search for email addresses within this compose window
            if let emails = findEmailAddressesInDescendants(element, maxDepth: 10) {
                return emails
            }
        }

        // For inline replies, look for sender info in group titles
        // ONLY match "Name (email@domain.com)" or "Name <email@domain.com>" patterns
        // These are standard email sender formats, nothing else
        let originalTitle = (titleRef as? String) ?? ""

        // Pattern 1: "Name (email@domain.com)" - email in parentheses
        // Must have content before the opening paren, and email inside
        if let parenStart = originalTitle.firstIndex(of: "("),
            let parenEnd = originalTitle.firstIndex(of: ")"),
            parenStart < parenEnd
        {
            let beforeParen = String(originalTitle[..<parenStart]).trimmingCharacters(
                in: .whitespaces)
            let insideParen = String(
                originalTitle[originalTitle.index(after: parenStart)..<parenEnd])

            // Must have a name before the paren, and the paren must contain an email
            if !beforeParen.isEmpty && insideParen.contains("@") && insideParen.contains(".") {
                // Make sure the "name" isn't just UI junk (should be relatively short)
                if beforeParen.count < 60 && !beforeParen.lowercased().contains("unread") {
                    if let name = extractNameFromEmail(originalTitle) {
                        NSLog(
                            "[DictationContextDetector] Found sender in group title: '\(originalTitle.prefix(50))...' -> '\(name)'"
                        )
                        return name
                    }
                }
            }
        }

        // Pattern 2: "Name <email@domain.com>" - email in angle brackets
        if let angleStart = originalTitle.firstIndex(of: "<"),
            let angleEnd = originalTitle.firstIndex(of: ">"),
            angleStart < angleEnd
        {
            let beforeAngle = String(originalTitle[..<angleStart]).trimmingCharacters(
                in: .whitespaces)
            let insideAngle = String(
                originalTitle[originalTitle.index(after: angleStart)..<angleEnd])

            if !beforeAngle.isEmpty && insideAngle.contains("@") && insideAngle.contains(".") {
                if beforeAngle.count < 60 {
                    if let name = extractNameFromEmail(originalTitle) {
                        NSLog(
                            "[DictationContextDetector] Found sender in group title: '\(originalTitle.prefix(50))...' -> '\(name)'"
                        )
                        return name
                    }
                }
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

        // Check this element's value for email address (not title - that contains sender info)
        var valueRef: CFTypeRef?
        var roleRef: CFTypeRef?

        _ = AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &roleRef)
        _ = AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef)

        let role = (roleRef as? String) ?? ""
        let value = (valueRef as? String) ?? ""

        // Look for static text elements containing email addresses in their value
        if role == kAXStaticTextRole as String && value.contains("@") && value.contains(".") {
            // Skip Gmail autocomplete suggestions (they contain "Press Tab to insert" or similar)
            let lowerValue = value.lowercased()
            let isAutocompleteSuggestion =
                lowerValue.contains("press tab")
                || lowerValue.contains("to insert")
                || lowerValue.contains("tab to")

            if isAutocompleteSuggestion {
                NSLog("[DictationContextDetector] Skipping autocomplete suggestion: \(value)")
            } else if let name = extractNameFromEmail(value) {
                // This looks like a real email address - extract name from it
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

    /// Extract a name hint from an email string
    /// Handles various formats:
    /// - "Melisa from PAFORY (newsletter@pafory.com)" -> "Melisa from PAFORY"
    /// - "John Smith <john@example.com>" -> "John Smith"
    /// - "bryan.smith@gmail.com" -> "Bryan Smith"
    /// - "bryan@gmail.com" -> "Bryan"
    private func extractNameFromEmail(_ emailText: String) -> String? {
        let trimmed = emailText.trimmingCharacters(in: .whitespaces)

        // Check for "Name (email)" format - common in Gmail reply headers
        if let parenIndex = trimmed.firstIndex(of: "("),
            let closeParen = trimmed.firstIndex(of: ")"),
            parenIndex < closeParen
        {
            let namePart = String(trimmed[..<parenIndex]).trimmingCharacters(in: .whitespaces)
            if !namePart.isEmpty && namePart.count > 1 {
                return namePart
            }
        }

        // Check for "Name <email>" format
        if let angleBracket = trimmed.firstIndex(of: "<") {
            let namePart = String(trimmed[..<angleBracket]).trimmingCharacters(in: .whitespaces)
            if !namePart.isEmpty && namePart.count > 1 && !namePart.contains("@") {
                return namePart
            }
        }

        // Fall back to extracting from email username
        guard let atIndex = trimmed.firstIndex(of: "@") else { return nil }
        let username = String(trimmed[..<atIndex])
            .trimmingCharacters(in: .whitespaces)

        // Skip very short usernames or generic ones
        if username.count < 2 { return nil }
        let genericUsernames = [
            "info", "hello", "contact", "support", "admin", "noreply", "no-reply", "notifications",
            "team", "newsletter", "news", "updates", "marketing",
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
