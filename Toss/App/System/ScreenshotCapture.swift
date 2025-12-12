import AppKit
import ScreenCaptureKit

/// Handles screenshot capture for the Toss agent using ScreenCaptureKit
enum ScreenshotCapture {

    enum CaptureTarget {
        case fullscreen
        case activeWindow
    }

    struct CaptureResult {
        let success: Bool
        let imageData: String?  // Base64 PNG data
        let error: String?
        let windowTitle: String?
        let appName: String?
    }

    /// Capture a screenshot of the screen or active window
    /// - Parameter target: What to capture (fullscreen or active window)
    /// - Returns: CaptureResult with base64 image data or error
    static func capture(target: CaptureTarget) async -> CaptureResult {
        // Check screen recording permission first
        guard ScreenRecordingAuth.status() else {
            return CaptureResult(
                success: false,
                imageData: nil,
                error:
                    "Screen recording permission not granted. Please enable it in System Settings > Privacy & Security > Screen Recording.",
                windowTitle: nil,
                appName: nil
            )
        }

        switch target {
        case .fullscreen:
            return await captureFullscreen()
        case .activeWindow:
            return await captureActiveWindow()
        }
    }

    // MARK: - Private Implementation

    private static func captureFullscreen() async -> CaptureResult {
        do {
            // Get available content
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)

            guard let display = content.displays.first else {
                return CaptureResult(
                    success: false,
                    imageData: nil,
                    error: "No display found",
                    windowTitle: nil,
                    appName: nil
                )
            }

            // Create a filter for the entire display
            let filter = SCContentFilter(display: display, excludingWindows: [])

            // Configure capture settings
            let config = SCStreamConfiguration()
            config.width = display.width
            config.height = display.height
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = true

            // Capture the screenshot
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )

            guard let base64 = cgImageToBase64(image) else {
                return CaptureResult(
                    success: false,
                    imageData: nil,
                    error: "Failed to encode image",
                    windowTitle: nil,
                    appName: nil
                )
            }

            return CaptureResult(
                success: true,
                imageData: base64,
                error: nil,
                windowTitle: nil,
                appName: nil
            )

        } catch {
            return CaptureResult(
                success: false,
                imageData: nil,
                error: "Failed to capture screen: \(error.localizedDescription)",
                windowTitle: nil,
                appName: nil
            )
        }
    }

    private static func captureActiveWindow() async -> CaptureResult {
        do {
            // Get the frontmost application
            guard let frontApp = NSWorkspace.shared.frontmostApplication else {
                return CaptureResult(
                    success: false,
                    imageData: nil,
                    error: "No active application found",
                    windowTitle: nil,
                    appName: nil
                )
            }

            let appName = frontApp.localizedName ?? "Unknown"
            let pid = frontApp.processIdentifier

            // Get available content
            let content = try await SCShareableContent.excludingDesktopWindows(
                false, onScreenWindowsOnly: true)

            // Find windows belonging to the frontmost app
            let appWindows = content.windows.filter { window in
                window.owningApplication?.processID == pid
            }

            // Get the first (frontmost) window, or fall back to any window from the app
            guard let targetWindow = appWindows.first else {
                return CaptureResult(
                    success: false,
                    imageData: nil,
                    error: "No window found for \(appName)",
                    windowTitle: nil,
                    appName: appName
                )
            }

            let windowTitle = targetWindow.title

            // We need a display for the content filter
            guard let display = content.displays.first else {
                return CaptureResult(
                    success: false,
                    imageData: nil,
                    error: "No display found",
                    windowTitle: windowTitle,
                    appName: appName
                )
            }

            // Create a filter for just this window
            let filter = SCContentFilter(display: display, including: [targetWindow])

            // Configure capture settings
            let config = SCStreamConfiguration()
            config.width = Int(targetWindow.frame.width) * 2  // Retina
            config.height = Int(targetWindow.frame.height) * 2  // Retina
            config.pixelFormat = kCVPixelFormatType_32BGRA
            config.showsCursor = false
            config.captureResolution = .best

            // Capture the screenshot
            let image = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: config
            )

            guard let base64 = cgImageToBase64(image) else {
                return CaptureResult(
                    success: false,
                    imageData: nil,
                    error: "Failed to encode image",
                    windowTitle: windowTitle,
                    appName: appName
                )
            }

            return CaptureResult(
                success: true,
                imageData: base64,
                error: nil,
                windowTitle: windowTitle,
                appName: appName
            )

        } catch {
            return CaptureResult(
                success: false,
                imageData: nil,
                error: "Failed to capture window: \(error.localizedDescription)",
                windowTitle: nil,
                appName: nil
            )
        }
    }

    private static func cgImageToBase64(_ cgImage: CGImage) -> String? {
        let bitmapRep = NSBitmapImageRep(cgImage: cgImage)
        guard let pngData = bitmapRep.representation(using: .png, properties: [:]) else {
            return nil
        }
        return pngData.base64EncodedString()
    }
}
