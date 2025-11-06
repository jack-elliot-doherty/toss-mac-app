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
            }

            Button {
                ob.refresh()
            } label: {
                Text(ob.needsOnboarding ? "Refresh checks" : "Continue")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(ob.needsOnboarding)
            .keyboardShortcut(.defaultAction)
        }
        .padding(24)
        .frame(maxWidth: 640)
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
                Text(title).font(.system(size: 16, weight: .semibold))
                Text(subtitle).font(.system(size: 13)).foregroundColor(.secondary)
            }
            Spacer()
            switch status {
            case .done:
                Text("Done")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.green)
            case .action(let label):
                Button(label, action: action).buttonStyle(.bordered)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black.opacity(0.06))
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
        if case .done = s { return .green } else { return .orange }
    }
}
