import SwiftUI

struct OnboardingProgressBar: View {
    let currentPhase: OnboardingPhase

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(OnboardingPhase.allCases.enumerated()), id: \.element) { index, phase in
                if index > 0 {
                    // Chevron separator
                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color.white.opacity(0.3))
                        .padding(.horizontal, 16)
                }

                Button {
                    // Only allow clicking on completed phases
                } label: {
                    Text(phase.title)
                        .font(.system(size: 12, weight: .semibold))
                        .tracking(0.5)
                        .foregroundColor(textColor(for: phase))
                }
                .buttonStyle(.plain)
                .disabled(true)  // Navigation handled by back/continue buttons
            }
        }
        .padding(.vertical, 16)
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.2))
    }

    private func textColor(for phase: OnboardingPhase) -> Color {
        if phase == currentPhase {
            return .white
        } else if phase.rawValue < currentPhase.rawValue {
            return Color.white.opacity(0.6)
        } else {
            return Color.white.opacity(0.35)
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        OnboardingProgressBar(currentPhase: .permissions)
        OnboardingProgressBar(currentPhase: .setup)
        OnboardingProgressBar(currentPhase: .learn)
        OnboardingProgressBar(currentPhase: .meetings)
    }
    .background(Color.black)
}
