import SwiftUI

struct PermissionsStepView: View {
    @ObservedObject private var manager = OnboardingManager.shared

    var body: some View {
        VStack(spacing: 32) {
            // Headline
            VStack(spacing: 8) {
                Text("Toss needs a few permissions")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(AppTheme.primaryText)

                Text("These let Toss help you get things done")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.secondaryText)
            }

            // Permission cards stacked
            VStack(spacing: 12) {
                PermissionCard(
                    title: "Type where you're typing",
                    description: "So you can dictate into any text field",
                    isGranted: manager.axGranted,
                    actionTitle: "Allow",
                    onAllow: {
                        manager.requestAX()
                        manager.openAXSettings()
                    }
                )

                PermissionCard(
                    title: "Use your microphone",
                    description: "To hear you when you speak to Toss",
                    isGranted: manager.micGranted,
                    actionTitle: "Allow",
                    onAllow: { manager.requestMic() }
                )

                PermissionCard(
                    title: "Capture meeting audio",
                    description: "To transcribe calls from Zoom, Meet, Teams",
                    isGranted: manager.screenGranted,
                    actionTitle: "Allow",
                    onAllow: {
                        manager.requestScreenRecording()
                        manager.openScreenSettings()
                    },
                    isOptional: true
                )
            }

            // Status message
            if manager.axGranted && manager.micGranted {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("Required permissions granted")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.secondaryText)
                }
            }
        }
    }
}

#Preview {
    ZStack {
        AppGlassBackground()
        PermissionsStepView()
            .frame(maxWidth: 520)
            .padding(40)
    }
    .frame(width: 700, height: 580)
}
