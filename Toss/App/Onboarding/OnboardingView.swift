import AVFoundation
import SwiftUI

@MainActor
struct OnboardingView: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var ob = OnboardingManager.shared

    var body: some View {
        VStack(spacing: 24) {
            Text(ob.needsOnboarding ? "Let’s set up Toss" : "All set")
                .font(.system(size: 26, weight: .semibold))
                .foregroundColor(AppTheme.primaryText)

            VStack(spacing: 14) {
                stepCard(
                    title: "Sign in",
                    subtitle: "Use your account to sync and personalize.",
                    status: ob.isSignedIn ? .done : .action("Sign in"),
                    action: { auth.beginBrowserLogin() }
                )

                stepCard(
                    title: "Allow Accessibility",
                    subtitle: "Lets Toss paste your dictated text anywhere.",
                    status: ob.axGranted ? .done : .action("Open Settings"),
                    action: {
                        ob.requestAX()
                        ob.openAXSettings()
                    }
                )

                stepCard(
                    title: "Allow Microphone",
                    subtitle: "Toss listens while you hold the hotkey.",
                    status: ob.micGranted ? .done : .action("Allow"),
                    action: { ob.requestMic() }
                )

                stepCard(
                    title: "Allow Screen Recording",
                    subtitle: "Needed to capture remote speakers during meetings.",
                    status: ob.screenGranted ? .done : .action("Allow"),
                    action: {
                        ob.requestScreenRecording()
                        ob.openScreenSettings()
                    }
                )
            }

            Button {
                ob.refresh()
            } label: {
                Text(ob.needsOnboarding ? "Refresh checks" : "Continue")
                    .frame(maxWidth: .infinity)
                    .foregroundColor(AppTheme.primaryText)
            }
            .buttonStyle(.borderedProminent)
            .tint(Color.white.opacity(0.12))
            .disabled(ob.needsOnboarding)
            .keyboardShortcut(.defaultAction)
        }
        .padding(32)
        .frame(maxWidth: 640)
        .background(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 24, style: .continuous)
                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                )
        )
        .onAppear { ob.refresh() }
    }

    private enum StepStatus {
        case done
        case action(String)
    }

    private func stepCard(
        title: String, subtitle: String, status: StepStatus, action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 14) {
            Image(systemName: icon(for: status))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(color(for: status))
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)
                Text(subtitle)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.secondaryText)
            }
            Spacer()
            switch status {
            case .done:
                Text("Done")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.accent)
            case .action(let label):
                Button(label, action: action)
                    .buttonStyle(.borderedProminent)
                    .tint(Color.white.opacity(0.12))
                    .foregroundColor(AppTheme.primaryText)
            }
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                )
        )
    }

    private func icon(for s: StepStatus) -> String {
        if case .done = s {
            return "checkmark.circle.fill"
        } else {
            return "exclamationmark.circle"
        }
    }
    private func color(for s: StepStatus) -> Color {
        if case .done = s { return AppTheme.accent } else { return .orange }
    }
}
