import AVFoundation
import Combine
import SwiftUI

// MARK: - Onboarding Step

enum OnboardingStep: Int, CaseIterable {
    case welcome          // Value prop + context preview
    case permissions      // All permissions consolidated
    case setupTest        // Mic test + Hotkey test combined
    case meetings         // Action items preview + screen recording
    case dictation        // Practice dictation
    case agent            // Meet the agent
    case connectApps      // Optional integrations
}

// MARK: - Onboarding Manager

@MainActor
final class OnboardingManager: ObservableObject {
    static let shared = OnboardingManager()

    static let onboardingVersion = 1
    private let onboardingVersionKey = "onboardingCompletedVersion"

    // Permission states
    @Published var axGranted: Bool = AccessibilityAuth.isTrusted()
    @Published var micStatus: AVAuthorizationStatus = AVCaptureDevice.authorizationStatus(
        for: .audio)
    @Published var screenGranted: Bool = ScreenRecordingAuth.status()

    // Auth state
    @Published var isSignedIn: Bool = false
    @Published var completedVersion: Int = 0

    // Step navigation
    @Published var currentStep: OnboardingStep = .welcome

    // Setup confirmations
    @Published var micTestPassed: Bool = false
    @Published var hotkeyTestPassed: Bool = false
    @Published var dictationTested: Bool = false

    private var cancellables = Set<AnyCancellable>()

    var micGranted: Bool { micStatus == .authorized }
    var isOnboardingComplete: Bool { completedVersion >= Self.onboardingVersion }

    var needsOnboarding: Bool {
        // Only check if onboarding was completed, not individual permissions
        // Users can revoke permissions later and we shouldn't force them back through onboarding
        return !isSignedIn || !isOnboardingComplete
    }

    /// Whether the user can proceed from the current step
    var canProceedFromCurrentStep: Bool {
        switch currentStep {
        case .welcome:
            return true
        case .permissions:
            return axGranted && micGranted  // Screen recording is optional
        case .setupTest:
            return micTestPassed && hotkeyTestPassed
        case .meetings:
            return true  // Just informational, screen recording already requested in permissions
        case .dictation:
            return true  // Optional to actually dictate
        case .agent:
            return true  // Just informational
        case .connectApps:
            return true  // All integrations optional
        }
    }

    /// Whether the user can go back from the current step
    var canGoBack: Bool {
        return currentStep != .welcome
    }

    private init() {
        isSignedIn = AuthManager.shared.isAuthenticated
        completedVersion = UserDefaults.standard.integer(forKey: onboardingVersionKey)

        // Observe AuthManager changes
        AuthManager.shared.$accessToken
            .map { $0?.isEmpty == false }
            .assign(to: &$isSignedIn)

        // Listen for app activation to check permissions
        NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)
            .sink { [weak self] _ in
                self?.refresh()
            }
            .store(in: &cancellables)
    }

    func refresh() {
        // Only update @Published properties if values actually changed
        // to prevent unnecessary SwiftUI re-renders and potential window focus issues
        let newAxGranted = AccessibilityAuth.isTrusted()
        let newMicStatus = AVCaptureDevice.authorizationStatus(for: .audio)
        let newIsSignedIn = AuthManager.shared.isAuthenticated
        let newScreenGranted = ScreenRecordingAuth.status()
        let newCompletedVersion = UserDefaults.standard.integer(forKey: onboardingVersionKey)

        if axGranted != newAxGranted { axGranted = newAxGranted }
        if micStatus != newMicStatus { micStatus = newMicStatus }
        if isSignedIn != newIsSignedIn { isSignedIn = newIsSignedIn }
        if screenGranted != newScreenGranted { screenGranted = newScreenGranted }
        if completedVersion != newCompletedVersion { completedVersion = newCompletedVersion }
    }

    // MARK: - Permission Requests

    func requestAX() {
        _ = AccessibilityAuth.ensureAccess(prompt: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.refresh() }
    }

    func requestMic() {
        let status = AVCaptureDevice.authorizationStatus(for: .audio)

        switch status {
        case .notDetermined:
            // First time - show system prompt
            AVCaptureDevice.requestAccess(for: .audio) { _ in
                DispatchQueue.main.async { self.refresh() }
            }
        case .denied, .restricted:
            // Already denied - open System Preferences
            openMicSettings()
        case .authorized:
            // Already granted
            refresh()
        @unknown default:
            openMicSettings()
        }
    }

    func requestScreenRecording() {
        ScreenRecordingAuth.requestAccess { granted in
            self.screenGranted = granted
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

    func openScreenSettings() {
        ScreenRecordingAuth.openSettings()
    }

    // MARK: - Navigation

    func goForward() {
        guard let nextStep = OnboardingStep(rawValue: currentStep.rawValue + 1) else {
            // We're at the last step - complete onboarding
            markOnboardingComplete()
            return
        }
        currentStep = nextStep
    }

    func goBack() {
        guard let previousStep = OnboardingStep(rawValue: currentStep.rawValue - 1) else {
            return  // Can't go back from first step
        }
        currentStep = previousStep
    }

    func markOnboardingComplete() {
        UserDefaults.standard.set(Self.onboardingVersion, forKey: onboardingVersionKey)
        refresh()
    }

    /// Reset onboarding for testing
    func resetOnboarding() {
        UserDefaults.standard.removeObject(forKey: onboardingVersionKey)
        currentStep = .welcome
        micTestPassed = false
        hotkeyTestPassed = false
        dictationTested = false
        refresh()
    }
}
