import SwiftUI

@MainActor
struct OnboardingGate: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var onboarding = OnboardingManager.shared

    var body: some View {
        if !auth.isAuthenticated {
            SignInView()
        } else if onboarding.needsOnboarding {
            OnboardingView()
        } else {
            MainAppView()
        }
    }
}
