import SwiftUI

@MainActor
struct OnboardingGate: View {
    @ObservedObject private var ob = OnboardingManager.shared

    var body: some View {
        if ob.needsOnboarding {
            OnboardingView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.windowBackgroundColor))
        } else {
            HomeView()
        }
    }
}
