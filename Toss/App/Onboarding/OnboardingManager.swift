import AVFoundation
import Combine
import SwiftUI

// MARK: - Onboarding Phase

enum OnboardingPhase: Int, CaseIterable {
    case permissions
    case setup
    case learn
    case meetings

    var title: String {
        switch self {
        case .permissions: return "PERMISSIONS"
        case .setup: return "SET UP"
        case .learn: return "LEARN"
        case .meetings: return "MEETINGS"
        }
    }
}

// MARK: - Sub-steps within each phase

enum PermissionsStep: Int, CaseIterable {
    case accessibility
    case microphone
    case complete
}

enum SetupStep: Int, CaseIterable {
    case micTest
    case hotkeyTest
}

enum LearnStep: Int, CaseIterable {
    case dictationDemo
    case agentIntro
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

    // Phase navigation
    @Published var currentPhase: OnboardingPhase = .permissions
    @Published var permissionsStep: PermissionsStep = .accessibility
    @Published var setupStep: SetupStep = .micTest
    @Published var learnStep: LearnStep = .dictationDemo

    // Setup confirmations
    @Published var micTestPassed: Bool = false
    @Published var hotkeyTestPassed: Bool = false

    private var cancellables = Set<AnyCancellable>()

    var micGranted: Bool { micStatus == .authorized }
    var isOnboardingComplete: Bool { completedVersion >= Self.onboardingVersion }

    var needsOnboarding: Bool {
        // Only check if onboarding was completed, not individual permissions
        // Users can revoke permissions later and we shouldn't force them back through onboarding
        return !isSignedIn || !isOnboardingComplete
    }

    /// Whether the user can proceed from the current permissions step
    var canProceedFromPermissions: Bool {
        switch permissionsStep {
        case .accessibility:
            return axGranted
        case .microphone:
            return micGranted
        case .complete:
            return true
        }
    }

    /// Whether all required permissions for the PERMISSIONS phase are granted
    var allPermissionsGranted: Bool {
        axGranted && micGranted
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
                self?.autoAdvancePermissionsIfNeeded()
            }
            .store(in: &cancellables)

        // Auto-advance when permissions change
        $axGranted
            .dropFirst()
            .sink { [weak self] granted in
                if granted {
                    self?.autoAdvancePermissionsIfNeeded()
                }
            }
            .store(in: &cancellables)

        $micStatus
            .dropFirst()
            .sink { [weak self] status in
                if status == .authorized {
                    self?.autoAdvancePermissionsIfNeeded()
                }
            }
            .store(in: &cancellables)
    }

    func autoAdvancePermissionsIfNeeded() {
        guard currentPhase == .permissions else { return }

        // Loop to advance through all already-granted permissions
        while true {
            switch permissionsStep {
            case .accessibility:
                if axGranted {
                    permissionsStep = .microphone
                } else {
                    return
                }
            case .microphone:
                if micGranted {
                    permissionsStep = .complete
                }
                return
            case .complete:
                return
            }
        }
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

    func goToNextPermissionsStep() {
        switch permissionsStep {
        case .accessibility:
            permissionsStep = .microphone
        case .microphone:
            permissionsStep = .complete
        case .complete:
            currentPhase = .setup
        }
    }

    func goToPreviousPermissionsStep() {
        switch permissionsStep {
        case .accessibility:
            break  // Can't go back
        case .microphone:
            permissionsStep = .accessibility
        case .complete:
            permissionsStep = .microphone
        }
    }

    func goToNextSetupStep() {
        switch setupStep {
        case .micTest:
            setupStep = .hotkeyTest
        case .hotkeyTest:
            currentPhase = .learn
        }
    }

    func goToPreviousSetupStep() {
        switch setupStep {
        case .micTest:
            currentPhase = .permissions
            permissionsStep = .complete
        case .hotkeyTest:
            setupStep = .micTest
        }
    }

    func goToNextLearnStep() {
        switch learnStep {
        case .dictationDemo:
            learnStep = .agentIntro
        case .agentIntro:
            currentPhase = .meetings
        }
    }

    func goToPreviousLearnStep() {
        switch learnStep {
        case .dictationDemo:
            currentPhase = .setup
            setupStep = .hotkeyTest
        case .agentIntro:
            learnStep = .dictationDemo
        }
    }

    func goBack() {
        switch currentPhase {
        case .permissions:
            goToPreviousPermissionsStep()
        case .setup:
            goToPreviousSetupStep()
        case .learn:
            goToPreviousLearnStep()
        case .meetings:
            currentPhase = .learn
            learnStep = .agentIntro
        }
    }

    func goForward() {
        switch currentPhase {
        case .permissions:
            goToNextPermissionsStep()
        case .setup:
            goToNextSetupStep()
        case .learn:
            goToNextLearnStep()
        case .meetings:
            markOnboardingComplete()
        }
    }

    var canGoBack: Bool {
        switch currentPhase {
        case .permissions:
            return permissionsStep != .accessibility
        case .setup, .learn, .meetings:
            return true
        }
    }

    func markOnboardingComplete() {
        UserDefaults.standard.set(Self.onboardingVersion, forKey: onboardingVersionKey)
        refresh()
    }

    /// Reset onboarding for testing
    func resetOnboarding() {
        UserDefaults.standard.removeObject(forKey: onboardingVersionKey)
        currentPhase = .permissions
        permissionsStep = .accessibility
        setupStep = .micTest
        learnStep = .dictationDemo
        micTestPassed = false
        hotkeyTestPassed = false
        refresh()
    }
}
