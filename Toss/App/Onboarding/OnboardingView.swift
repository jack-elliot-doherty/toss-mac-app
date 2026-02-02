import SwiftUI

@MainActor
struct OnboardingView: View {
    @ObservedObject private var manager = OnboardingManager.shared

    var body: some View {
        ZStack {
            AppGlassBackground()

            VStack(spacing: 0) {
                // Progress dots at top
                OnboardingProgressBar(currentStep: manager.currentStep)

                // Main content area - centered, max width
                ScrollView {
                    stepContent
                        .frame(maxWidth: 520)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 40)
                        .padding(.vertical, 32)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // Bottom navigation bar
                navigationBar
                    .padding(.horizontal, 32)
                    .padding(.bottom, 28)
            }
        }
        .frame(minWidth: 700, minHeight: 580)
        .ignoresSafeArea()  // Fill entire window including titlebar area
        .preferredColorScheme(.dark)
        .onAppear {
            manager.refresh()
        }
    }

    // MARK: - Step Content

    @ViewBuilder
    private var stepContent: some View {
        switch manager.currentStep {
        case .welcome:
            WelcomeStepView()
        case .permissions:
            PermissionsStepView()
        case .setupTest:
            SetupTestStepView()
        case .meetings:
            MeetingsStepView()
        case .dictation:
            DictationStepView()
        case .agent:
            AgentStepView()
        case .connectApps:
            ConnectAppsStepView()
        }
    }

    // MARK: - Navigation Bar

    private var navigationBar: some View {
        HStack {
            // Back button (left, secondary)
            if manager.canGoBack {
                Button(action: { manager.goBack() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                        Text("Back")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundColor(AppTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }

            Spacer()

            // Continue button (right, primary)
            Button(action: { manager.goForward() }) {
                Text(continueButtonTitle)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.black)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(manager.canProceedFromCurrentStep ? 0.95 : 0.4))
                    )
            }
            .buttonStyle(.plain)
            .disabled(!manager.canProceedFromCurrentStep)
        }
    }

    private var continueButtonTitle: String {
        switch manager.currentStep {
        case .welcome:
            return "Get Started"
        case .connectApps:
            return "Finish Setup"
        default:
            return "Continue"
        }
    }
}

// MARK: - Shared Components

struct KeyboardKey: View {
    let key: String

    init(_ key: String) {
        self.key = key
    }

    var body: some View {
        Text(key)
            .font(.system(size: 12, weight: .medium, design: .monospaced))
            .foregroundColor(AppTheme.primaryText)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(Color.white.opacity(0.1))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(AppTheme.subtleStroke, lineWidth: 1)
                    )
            )
    }
}

#Preview {
    OnboardingView()
        .frame(width: 800, height: 650)
}
