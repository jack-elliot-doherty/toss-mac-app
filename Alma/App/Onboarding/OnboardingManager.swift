import AVFoundation
import SwiftUI

@MainActor
final class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()

    @Published var axGranted: Bool = AccessibilityAuth.isTrusted()
    @Published var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(
        for: .audio)
    @Published var isSignedIn: Bool = AuthManager.shared.isAuthenticated

    var micGranted: Bool { micStatus == .authorized }
    var needsOnboarding: Bool { !isSignedIn || !axGranted || !micGranted }

    func refresh() {
        axGranted = AccessibilityAuth.isTrusted()
        micStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        isSignedIn = AuthManager.shared.isAuthenticated
    }

    func requestAX() {
        _ = AccessibilityAuth.ensureAccess(prompt: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refresh() }
    }

    func requestMic() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in
            DispatchQueue.main.async { self.refresh() }
        }
    }

    func openAXSettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        {
            NSWorkspace.shared.open(url)
        }
    }

    func openMicSettings() {
        if let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        {
            NSWorkspace.shared.open(url)
        }
    }
}
