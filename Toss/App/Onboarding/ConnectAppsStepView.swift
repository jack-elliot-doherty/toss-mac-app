import SwiftUI

struct ConnectAppsStepView: View {
    @StateObject private var integrations = IntegrationsManager.shared

    var body: some View {
        VStack(spacing: 28) {
            // Headline
            VStack(spacing: 8) {
                Text("Toss works where you work")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(AppTheme.primaryText)

                Text("Connect your apps so Toss can take action for you")
                    .font(.system(size: 14))
                    .foregroundColor(AppTheme.secondaryText)
            }

            // Integration rows
            VStack(spacing: 12) {
                OnboardingIntegrationRow(
                    iconName: "SlackLogo",
                    iconBackground: Color(red: 0.28, green: 0.16, blue: 0.36),
                    name: "Slack",
                    description: "@toss in any thread for help",
                    isConnected: integrations.slackBotStatus?.installed == true,
                    connectedDetail: integrations.slackBotStatus?.teamName,
                    onConnect: { Task { await integrations.connectSlackBot() } }
                )

                OnboardingIntegrationRow(
                    iconName: "GoogleCalendarLogo",
                    iconBackground: .white,
                    name: "Google Calendar",
                    description: "Schedule meetings by voice",
                    isConnected: integrations.googleStatus?.connected == true,
                    connectedDetail: integrations.googleStatus?.email,
                    onConnect: { Task { await integrations.connectGoogle() } }
                )

                OnboardingIntegrationRow(
                    iconName: "LinearLogo",
                    iconBackground: Color(red: 0.36, green: 0.38, blue: 0.96),
                    name: "Linear",
                    description: "Create issues from screenshots",
                    isConnected: integrations.linearStatus?.connected == true,
                    connectedDetail: integrations.linearStatus?.organizationName,
                    onConnect: { Task { await integrations.connectLinear() } }
                )

                OnboardingIntegrationRow(
                    iconName: "NotionLogo",
                    iconBackground: .white,
                    name: "Notion",
                    description: "Save meeting notes automatically",
                    isConnected: integrations.notionStatus?.connected == true,
                    connectedDetail: integrations.notionStatus?.workspaceName,
                    onConnect: { Task { await integrations.connectNotion() } }
                )

                OnboardingIntegrationRow(
                    iconName: "GmailLogo",
                    iconBackground: .white,
                    name: "Gmail",
                    description: "Send and search emails by voice",
                    isConnected: integrations.gmailStatus?.connected == true,
                    connectedDetail: integrations.gmailStatus?.email,
                    onConnect: { Task { await integrations.connectGmail() } }
                )
            }

            // Note
            Text("You can always connect more apps later in Settings")
                .font(.system(size: 13))
                .foregroundColor(AppTheme.secondaryText)
        }
        .onAppear {
            Task {
                await integrations.fetchSlackBotStatus()
                await integrations.fetchGoogleStatus()
                await integrations.fetchLinearStatus()
                await integrations.fetchNotionStatus()
                await integrations.fetchGmailStatus()
            }
        }
    }
}

// MARK: - Onboarding Integration Row

struct OnboardingIntegrationRow: View {
    let iconName: String
    let iconBackground: Color
    let name: String
    let description: String
    let isConnected: Bool
    let connectedDetail: String?
    let onConnect: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(iconBackground)
                if NSImage(named: iconName) != nil {
                    Image(iconName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 22, height: 22)
                } else {
                    Image(systemName: "questionmark")
                        .foregroundColor(.gray)
                }
            }
            .frame(width: 40, height: 40)

            // Text
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)

                if isConnected, let detail = connectedDetail {
                    Text(detail)
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                        .lineLimit(1)
                } else {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.secondaryText)
                }
            }

            Spacer()

            // Button
            if isConnected {
                HStack(spacing: 4) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                    Text("Connected")
                        .font(.system(size: 12, weight: .medium))
                }
                .foregroundColor(.green)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.green.opacity(0.15))
                )
            } else {
                Button(action: onConnect) {
                    Text("Connect")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.primaryText)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(AppTheme.subtleStroke, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(
                            isConnected ? Color.green.opacity(0.3) : AppTheme.subtleStroke,
                            lineWidth: 1)
                )
        )
    }
}

#Preview {
    ZStack {
        AppGlassBackground()
        ConnectAppsStepView()
            .frame(maxWidth: 520)
            .padding(40)
    }
    .frame(width: 700, height: 650)
}
