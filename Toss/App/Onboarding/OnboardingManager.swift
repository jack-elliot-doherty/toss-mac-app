import AVFoundation
import Combine
import SwiftUI

@MainActor
final class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()

    @Published var axGranted: Bool = AccessibilityAuth.isTrusted()
    @Published var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(
        for: .audio)
    @Published var isSignedIn: Bool = false

    private var cancellables = Set<AnyCancellable>()

    var micGranted: Bool { micStatus == .authorized }
    var needsOnboarding: Bool { !isSignedIn || !axGranted || !micGranted }

    private init() {  // Initial state
        isSignedIn = AuthManager.shared.isAuthenticated

        // Observe AuthManager changes
        AuthManager.shared.$accessToken
            .map { $0?.isEmpty == false }
            .assign(to: &$isSignedIn)

        // Listen for app activation to check AX permission
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.checkAXPermission()
            }
            .store(in: &cancellables)
    }

    private func checkAXPermission() {
        let newAx = AccessibilityAuth.isTrusted()
        if newAx != axGranted {
            axGranted = newAx
        }
    }

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
