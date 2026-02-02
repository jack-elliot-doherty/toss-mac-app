import SwiftUI

struct OnboardingProgressBar: View {
    let currentStep: OnboardingStep
    private let totalSteps = OnboardingStep.allCases.count

    var body: some View {
        HStack(spacing: 8) {
            ForEach(0..<totalSteps, id: \.self) { index in
                Circle()
                    .fill(dotColor(for: index))
                    .frame(width: 8, height: 8)
                    .animation(.easeInOut(duration: 0.2), value: currentStep)
            }
        }
        .padding(.vertical, 20)
    }

    private func dotColor(for index: Int) -> Color {
        if index < currentStep.rawValue {
            return Color.white.opacity(0.5)  // Completed
        } else if index == currentStep.rawValue {
            return Color.white  // Current
        } else {
            return Color.white.opacity(0.2)  // Future
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        OnboardingProgressBar(currentStep: .welcome)
        OnboardingProgressBar(currentStep: .permissions)
        OnboardingProgressBar(currentStep: .setupTest)
        OnboardingProgressBar(currentStep: .meetings)
        OnboardingProgressBar(currentStep: .dictation)
        OnboardingProgressBar(currentStep: .agent)
        OnboardingProgressBar(currentStep: .connectApps)
    }
    .padding(40)
    .background(Color.black)
}
