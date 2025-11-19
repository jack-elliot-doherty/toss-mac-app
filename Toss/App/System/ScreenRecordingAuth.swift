import AppKit
import CoreGraphics

enum ScreenRecordingAuth {
    static func status() -> Bool {
        CGPreflightScreenCaptureAccess()
    }

    static func requestAccess(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async {
            let granted = CGRequestScreenCaptureAccess()
            DispatchQueue.main.async { completion(granted) }
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
