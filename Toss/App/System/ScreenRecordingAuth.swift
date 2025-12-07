import AppKit
import CoreGraphics
import ScreenCaptureKit

enum ScreenRecordingAuth {
    static func status() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestAccess(completion: @escaping (Bool) -> Void) {
        // Attempt a real capture to force macOS to add us to the Screen Recording list
        // This is required on macOS 14+ for the app to appear in System Settings
        Task {
            do {
                // This triggers the permission prompt AND adds the app to the list
                _ = try await SCShareableContent.excludingDesktopWindows(
                    false, onScreenWindowsOnly: true)
                let granted = CGPreflightScreenCaptureAccess()
                await MainActor.run { completion(granted) }
            } catch {
                // Even if it fails (permission denied), the app will now be in the list
                let granted = CGPreflightScreenCaptureAccess()
                await MainActor.run { completion(granted) }
            }
        }
    }

    static func openSettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        ) {
            NSWorkspace.shared.open(url)
        }
    }
}
