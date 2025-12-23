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
}
