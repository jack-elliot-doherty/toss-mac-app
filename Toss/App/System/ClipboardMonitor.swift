import Cocoa

/// Monitors the system clipboard for changes and tracks when content was copied.
/// Used to provide clipboard context to the agent when the user recently copied something.
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    private var lastChangeCount: Int = 0
    private var lastChangeTime: Date?
    private var lastContent: String?
    private var timer: Timer?

    private init() {
        lastChangeCount = NSPasteboard.general.changeCount
    }

    /// Start polling the clipboard for changes (call on app launch)
    func startMonitoring() {
        // Capture current state immediately
        checkForChanges()

        // Poll every 0.5 seconds - this is cheap since we only read an int most of the time
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.checkForChanges()
        }
    }

    /// Stop monitoring (call on app termination if needed)
    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
    }

    private func checkForChanges() {
        let currentCount = NSPasteboard.general.changeCount
        if currentCount != lastChangeCount {
            lastChangeCount = currentCount
            lastChangeTime = Date()
            lastContent = NSPasteboard.general.string(forType: .string)
        }
    }

    /// Returns clipboard content if copied within maxAge seconds, truncated to 8K chars
    /// - Parameter maxAge: Maximum age in seconds for clipboard to be considered "fresh" (default 90)
    /// - Returns: Tuple of (content, ageInSeconds) if clipboard is fresh, nil otherwise
    func getFreshClipboard(maxAge: TimeInterval = 90) -> (content: String, ageSeconds: Int)? {
        guard let content = lastContent,
              let time = lastChangeTime else { return nil }

        let age = Date().timeIntervalSince(time)
        guard age <= maxAge else { return nil }

        // Truncate to 8K chars if larger
        let truncated = content.count > 8000 ? String(content.prefix(8000)) : content
        return (truncated, Int(age))
    }

    /// Mark the current clipboard content as "consumed" so it won't be sent again.
    /// If the user copies something new, it will be detected and available again.
    func markClipboardConsumed() {
        lastChangeTime = nil
    }
}
