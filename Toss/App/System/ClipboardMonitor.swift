import Cocoa
import UniformTypeIdentifiers

/// Monitors the system clipboard for changes and tracks when content was copied.
/// Used to provide clipboard context to the agent when the user recently copied something.
final class ClipboardMonitor {
    static let shared = ClipboardMonitor()

    enum ClipboardContent {
        case text(String)
        case image(data: Data, contentType: String)
    }

    struct FreshClipboard {
        let content: ClipboardContent
        let ageSeconds: Int
    }

    private var lastChangeCount: Int = 0
    private var lastChangeTime: Date?
    private var lastContent: ClipboardContent?
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
            lastContent = readClipboardContent()
        }
    }

    private func readClipboardContent() -> ClipboardContent? {
        let pasteboard = NSPasteboard.general

        // Prefer text when available.
        if let text = pasteboard.string(forType: .string), !text.isEmpty {
            return .text(text)
        }

        // Most screenshot/image clipboard entries on macOS are PNG or TIFF.
        if let pngData = pasteboard.data(forType: .png), !pngData.isEmpty {
            return .image(data: pngData, contentType: "image/png")
        }

        if let tiffData = pasteboard.data(forType: .tiff), !tiffData.isEmpty {
            if let image = NSImage(data: tiffData), let pngData = image.pngData() {
                return .image(data: pngData, contentType: "image/png")
            }
        }

        // Some apps place image file URLs on the pasteboard.
        if
            let urls = pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [URL]
        {
            for url in urls {
                guard
                    let uti = try? url.resourceValues(forKeys: [.typeIdentifierKey]).typeIdentifier,
                    let utType = UTType(uti),
                    utType.conforms(to: .image)
                else {
                    continue
                }

                if let image = NSImage(contentsOf: url), let pngData = image.pngData() {
                    return .image(data: pngData, contentType: "image/png")
                }
            }
        }

        return nil
    }

    /// Returns clipboard content if copied within maxAge seconds.
    /// Text is truncated to 8K chars.
    /// - Parameter maxAge: Maximum age in seconds for clipboard to be considered "fresh" (default 90)
    /// - Returns: Clipboard payload with age if clipboard is fresh, nil otherwise.
    func getFreshClipboard(maxAge: TimeInterval = 90) -> FreshClipboard? {
        guard let content = lastContent,
              let time = lastChangeTime else { return nil }

        let age = Date().timeIntervalSince(time)
        guard age <= maxAge else { return nil }

        switch content {
        case .text(let text):
            // Truncate to 8K chars if larger
            let truncated = text.count > 8000 ? String(text.prefix(8000)) : text
            return FreshClipboard(content: .text(truncated), ageSeconds: Int(age))
        case .image(let data, let contentType):
            return FreshClipboard(
                content: .image(data: data, contentType: contentType),
                ageSeconds: Int(age)
            )
        }
    }

    /// Mark the current clipboard content as "consumed" so it won't be sent again.
    /// If the user copies something new, it will be detected and available again.
    func markClipboardConsumed() {
        lastChangeTime = nil
    }
}

private extension NSImage {
    func pngData() -> Data? {
        guard
            let tiff = tiffRepresentation,
            let bitmap = NSBitmapImageRep(data: tiff)
        else {
            return nil
        }
        return bitmap.representation(using: .png, properties: [:])
    }
}
