import SwiftUI

@MainActor
struct OnboardingView: View {
    @ObservedObject private var manager = OnboardingManager.shared

    var body: some View {
        ZStack {
            AppGlassBackground()

            VStack(spacing: 0) {
                // Progress bar at top
                OnboardingProgressBar(currentPhase: manager.currentPhase)

                // Main content area
                HStack(spacing: 0) {
                    // Left column - instructions
                    leftColumn
                        .frame(width: 360)
                        .frame(maxHeight: .infinity)
                        .background(Color.black.opacity(0.3))

                    // Right column - visuals/demos
                    rightColumn
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color.black.opacity(0.15))
                }
            }
        }
        .frame(minWidth: 820, minHeight: 560)
        .onAppear {
            manager.refresh()
            manager.autoAdvancePermissionsIfNeeded()
        }
    }

    // MARK: - Left Column

    @ViewBuilder
    private var leftColumn: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Back button
            if manager.canGoBack {
                Button(action: { manager.goBack() }) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 12, weight: .medium))
                        Text("Back")
                            .font(.system(size: 13, weight: .medium))
                    }
                    .foregroundColor(AppTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .padding(.top, 20)
                .padding(.leading, 24)
            } else {
                Spacer().frame(height: 44)
            }

            // Content based on current phase
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    leftColumnContent
                }
                .padding(.horizontal, 24)
                .padding(.top, 16)
                .padding(.bottom, 24)
            }

            Spacer()

            // Continue button (for phases that need it)
            if showContinueButton {
                continueButton
                    .padding(.horizontal, 24)
                    .padding(.bottom, 24)
            }
        }
    }

    @ViewBuilder
    private var leftColumnContent: some View {
        switch manager.currentPhase {
        case .permissions:
            permissionsContent
        case .setup:
            setupContent
        case .learn:
            learnContent
        case .meetings:
            meetingsContent
        }
    }

    private var showContinueButton: Bool {
        switch manager.currentPhase {
        case .permissions:
            return manager.permissionsStep == .complete
        case .setup:
            return false  // Setup uses Yes/No buttons in the right column
        case .learn:
            return true
        case .meetings:
            return true
        }
    }

    private var continueButton: some View {
        Button(action: { manager.goForward() }) {
            Text(manager.currentPhase == .meetings ? "Complete" : "Continue")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.white.opacity(0.9))
                )
        }
        .buttonStyle(.plain)
        .disabled(!canContinue)
        .opacity(canContinue ? 1 : 0.5)
    }

    private var canContinue: Bool {
        switch manager.currentPhase {
        case .permissions:
            return manager.permissionsStep == .complete
        case .setup:
            return true
        case .learn:
            return true
        case .meetings:
            return manager.screenGranted
        }
    }

    // MARK: - Right Column

    @ViewBuilder
    private var rightColumn: some View {
        VStack {
            Spacer()
            rightColumnContent
            Spacer()
        }
        .padding(40)
    }

    @ViewBuilder
    private var rightColumnContent: some View {
        switch manager.currentPhase {
        case .permissions:
            permissionsVisual
        case .setup:
            setupVisual
        case .learn:
            learnVisual
        case .meetings:
            meetingsVisual
        }
    }

    // MARK: - Permissions Phase

    @ViewBuilder
    private var permissionsContent: some View {
        switch manager.permissionsStep {
        case .accessibility:
            VStack(alignment: .leading, spacing: 16) {
                Text("Set up Toss on your computer")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(AppTheme.primaryText)

                PermissionCard(
                    title: "Allow Toss to insert spoken words",
                    description: "This lets Toss put your spoken words in the right textbox.",
                    isGranted: manager.axGranted,
                    actionTitle: "Allow",
                    onAllow: {
                        manager.requestAX()
                        manager.openAXSettings()
                    }
                )

                PermissionCard(
                    title: "Allow Toss to use your microphone",
                    description: "Toss will only access the mic when you are actively using it.",
                    isGranted: manager.micGranted,
                    actionTitle: "Allow",
                    onAllow: {}
                )
                .opacity(0.5)
            }

        case .microphone:
            VStack(alignment: .leading, spacing: 16) {
                Text("Set up Toss on your computer")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(AppTheme.primaryText)

                PermissionCard(
                    title: "Allow Toss to insert spoken words",
                    description: "This lets Toss put your spoken words in the right textbox.",
                    isGranted: manager.axGranted,
                    actionTitle: "Allow",
                    onAllow: {}
                )

                PermissionCard(
                    title: "Allow Toss to use your microphone",
                    description: "Toss will only access the mic when you are actively using it.",
                    isGranted: manager.micGranted,
                    actionTitle: "Allow",
                    onAllow: {
                        manager.requestMic()
                    }
                )
            }

        case .complete:
            VStack(alignment: .leading, spacing: 16) {
                Text("Thanks for trusting us, we value your privacy")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(AppTheme.primaryText)

                PermissionCard(
                    title: "Allow Toss to insert spoken words",
                    description: "",
                    isGranted: true,
                    actionTitle: "",
                    onAllow: {}
                )

                PermissionCard(
                    title: "Allow Toss to use your microphone",
                    description: "",
                    isGranted: true,
                    actionTitle: "",
                    onAllow: {}
                )
            }
        }
    }

    @ViewBuilder
    private var permissionsVisual: some View {
        switch manager.permissionsStep {
        case .accessibility, .microphone:
            // Show a placeholder for the system dialog visual
            VStack(spacing: 16) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 64, weight: .light))
                    .foregroundColor(AppTheme.secondaryText)

                Text("System permission dialog will appear")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.secondaryText)
            }

        case .complete:
            // Privacy/trust illustration
            VStack(spacing: 20) {
                ZStack {
                    // Folder
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.orange.opacity(0.8))
                        .frame(width: 120, height: 90)

                    // Lock badge
                    Circle()
                        .fill(AppTheme.cardBackground)
                        .frame(width: 44, height: 44)
                        .overlay(
                            Image(systemName: "lock.fill")
                                .font(.system(size: 18, weight: .medium))
                                .foregroundColor(.white)
                        )
                        .offset(x: 40, y: -35)

                    // Document
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .fill(Color.teal.opacity(0.7))
                        .frame(width: 30, height: 40)
                        .offset(x: 50, y: 15)
                }
                .frame(width: 160, height: 140)
            }
        }
    }

    // MARK: - Setup Phase

    @ViewBuilder
    private var setupContent: some View {
        switch manager.setupStep {
        case .micTest:
            VStack(alignment: .leading, spacing: 12) {
                Text("Speak to test your microphone")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(AppTheme.primaryText)

                Text("Your computer's built-in mic will ensure optimal transcription.")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.secondaryText)
            }

        case .hotkeyTest:
            VStack(alignment: .leading, spacing: 12) {
                Text("Press the keyboard shortcut to test it out")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(AppTheme.primaryText)

                HStack(spacing: 4) {
                    Text("We recommend the")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.secondaryText)

                    Text("fn")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(AppTheme.primaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.1))
                        )

                    Text("key at the bottom left of the keyboard.")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.secondaryText)
                }
            }
        }
    }

    @ViewBuilder
    private var setupVisual: some View {
        switch manager.setupStep {
        case .micTest:
            MicTestView(
                onConfirm: {
                    manager.micTestPassed = true
                    manager.goToNextSetupStep()
                },
                onChangeMic: {
                    // Open sound preferences
                    if let url = URL(string: "x-apple.systempreferences:com.apple.preference.sound")
                    {
                        NSWorkspace.shared.open(url)
                    }
                }
            )

        case .hotkeyTest:
            HotkeyTestView(
                onConfirm: {
                    manager.hotkeyTestPassed = true
                    manager.goToNextSetupStep()
                }
            )
        }
    }

    // MARK: - Learn Phase

    @ViewBuilder
    private var learnContent: some View {
        switch manager.learnStep {
        case .dictationDemo:
            VStack(alignment: .leading, spacing: 12) {
                Text("Press the keyboard shortcut to use Toss")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(AppTheme.primaryText)

                HStack(spacing: 4) {
                    Text("Hold down on the")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.secondaryText)

                    Text("fn")
                        .font(.system(size: 12, weight: .medium, design: .monospaced))
                        .foregroundColor(AppTheme.primaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .fill(Color.white.opacity(0.1))
                        )

                    Text("key, speak, and let go to insert spoken text.")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.secondaryText)
                }
            }

        case .agentIntro:
            VStack(alignment: .leading, spacing: 16) {
                Text("Meet your AI agent")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(AppTheme.primaryText)

                Text(
                    "Your agent can take actions in connected apps - send Slack messages, create Linear issues, manage your calendar, and more."
                )
                .font(.system(size: 14))
                .foregroundColor(AppTheme.secondaryText)

                VStack(alignment: .leading, spacing: 8) {
                    Text("How to use:")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)

                    HStack(spacing: 8) {
                        HStack(spacing: 4) {
                            Text("fn")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                            Text("+")
                                .font(.system(size: 12, weight: .medium))
                            Text("⌘")
                                .font(.system(size: 12, weight: .medium, design: .monospaced))
                        }
                        .foregroundColor(AppTheme.primaryText)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.1))
                        )

                        Text("Hold, speak, release")
                            .font(.system(size: 13))
                            .foregroundColor(AppTheme.secondaryText)
                    }
                }
                .padding(.top, 4)

                Text("Connect your apps in Settings after onboarding.")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.secondaryText)
                    .padding(.top, 8)
            }
        }
    }

    @ViewBuilder
    private var learnVisual: some View {
        switch manager.learnStep {
        case .dictationDemo:
            DictationDemoView()

        case .agentIntro:
            AgentDemoView()
        }
    }

    // MARK: - Meetings Phase

    @ViewBuilder
    private var meetingsContent: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Capture your meetings")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(AppTheme.primaryText)

            Text(
                "Allow screen recording so Toss can capture remote speakers for transcripts, summaries, and action items."
            )
            .font(.system(size: 14))
            .foregroundColor(AppTheme.secondaryText)

            PermissionCard(
                title: "Allow Toss to record screen audio",
                description: "Required for capturing meeting audio from Zoom, Meet, Teams, etc.",
                isGranted: manager.screenGranted,
                actionTitle: "Allow",
                onAllow: {
                    manager.requestScreenRecording()
                    manager.openScreenSettings()
                }
            )

            VStack(alignment: .leading, spacing: 12) {
                Text("What you'll get:")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)

                FeatureRow(icon: "text.quote", text: "Speaker-separated transcript")
                FeatureRow(
                    icon: "list.bullet.rectangle", text: "AI-generated summary from your notes")
                FeatureRow(icon: "checkmark.circle", text: "Action items you can delegate")
            }
            .padding(.top, 8)
        }
    }

    @ViewBuilder
    private var meetingsVisual: some View {
        VStack(spacing: 20) {
            // Meeting illustration
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(AppTheme.cardBackground)
                    .frame(width: 280, height: 180)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(AppTheme.subtleStroke, lineWidth: 1)
                    )

                VStack(spacing: 16) {
                    // Video grid placeholder
                    HStack(spacing: 8) {
                        ForEach(0..<3, id: \.self) { _ in
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .fill(Color.white.opacity(0.05))
                                .frame(width: 70, height: 50)
                                .overlay(
                                    Image(systemName: "person.fill")
                                        .font(.system(size: 20))
                                        .foregroundColor(AppTheme.secondaryText)
                                )
                        }
                    }

                    // Recording indicator
                    HStack(spacing: 6) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 8, height: 8)
                        Text("Recording meeting...")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(AppTheme.secondaryText)
                    }
                }
            }

            Text("Toss captures audio in the background")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.secondaryText)
        }
    }
}

// MARK: - Supporting Views

private struct FeatureRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.secondaryText)
                .frame(width: 20)

            Text(text)
                .font(.system(size: 14))
                .foregroundColor(AppTheme.primaryText)
        }
    }
}

private struct DictationDemoView: View {
    @State private var messageText: String = ""
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Slack header
            HStack(spacing: 8) {
                Image(systemName: "number")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.secondaryText)
                Text("general")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)
            }

            // Message from teammate
            HStack(alignment: .top, spacing: 10) {
                Circle()
                    .fill(Color.orange.opacity(0.3))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text("T")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.orange)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Text("Tobias")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.primaryText)
                        Text("2:34 PM")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.secondaryText)
                    }
                    Text("Hey! Is Toss working for you? Try replying with your voice 👇")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.primaryText)
                }
            }

            // Reply input field - real text field that can receive dictation
            HStack(spacing: 8) {
                TextField("Hold fn and speak to reply...", text: $messageText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.primaryText)
                    .focused($isTextFieldFocused)

                if !messageText.isEmpty {
                    Button {
                        // Could simulate sending
                        messageText = ""
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundColor(AppTheme.accent)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .stroke(
                                isTextFieldFocused ? AppTheme.accent : AppTheme.subtleStroke,
                                lineWidth: 1)
                    )
            )

            Text("Hold fn, speak your reply, then release to insert text")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.secondaryText)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                )
        )
        .frame(maxWidth: 380)
        .onAppear {
            // Auto-focus the text field so user can immediately dictate
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                isTextFieldFocused = true
            }
        }
    }
}

private struct AgentDemoView: View {
    var body: some View {
        VStack(spacing: 24) {
            // Icon
            ZStack {
                Circle()
                    .fill(AppTheme.accent.opacity(0.15))
                    .frame(width: 64, height: 64)

                Image(systemName: "sparkles")
                    .font(.system(size: 28, weight: .medium))
                    .foregroundColor(AppTheme.accent)
            }

            // Try it prompt
            VStack(spacing: 12) {
                Text("Try asking:")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(AppTheme.secondaryText)

                Text("\"What can you do?\"")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(AppTheme.subtleStroke, lineWidth: 1)
                            )
                    )
            }

            // Instructions
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Text("Hold")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.secondaryText)

                    HStack(spacing: 3) {
                        Text("fn + ⌘")
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                    }
                    .foregroundColor(AppTheme.primaryText)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .fill(Color.white.opacity(0.1))
                    )

                    Text("and speak")
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.secondaryText)
                }

                Text("The agent panel will appear")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.secondaryText.opacity(0.7))
            }
        }
        .padding(28)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                )
        )
        .frame(maxWidth: 340)
    }
}

#Preview {
    OnboardingView()
        .frame(width: 900, height: 650)
}
