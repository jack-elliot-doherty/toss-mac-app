import SwiftUI

// MARK: - Action Item Example Types

enum ActionItemExample {
    case calendar(title: String, when: String, with: String)
    case linear(title: String, description: String, priority: String, team: String)
    case slack(to: String, message: String, attachment: String?)
}

struct ActionItemExampleData {
    let quote: String
    let timestamp: String
    let card: ActionItemExample
}

// MARK: - Action Item Preview

struct ActionItemPreview: View {
    let example: ActionItemExampleData

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Quote with accent sidebar
            HStack(alignment: .top, spacing: 12) {
                Rectangle()
                    .fill(AppTheme.accent)
                    .frame(width: 3)

                VStack(alignment: .leading, spacing: 4) {
                    Text("YOU SAID AT \(example.timestamp)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(AppTheme.secondaryText)
                        .tracking(0.5)

                    Text("\"\(example.quote)\"")
                        .font(.system(size: 14))
                        .foregroundColor(AppTheme.primaryText)
                        .italic()
                }
            }

            // Action card
            ActionItemCardView(item: example.card)
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                )
        )
    }
}

// MARK: - Action Item Card View

struct ActionItemCardView: View {
    let item: ActionItemExample

    var body: some View {
        switch item {
        case let .calendar(title, when, with):
            CalendarActionCard(title: title, when: when, with: with)
        case let .linear(title, description, priority, team):
            LinearActionCard(title: title, description: description, priority: priority, team: team)
        case let .slack(to, message, attachment):
            SlackActionCard(to: to, message: message, attachment: attachment)
        }
    }
}

// MARK: - Calendar Action Card

struct CalendarActionCard: View {
    let title: String
    let when: String
    let with: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 10) {
                    // Google Calendar logo
                    Image("GoogleCalendarLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Create Calendar Event")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.primaryText)
                        Text("Toss will create this event in your Google Calendar")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.secondaryText)
                    }
                }

                Spacer()

                OnboardingActionButton(title: "Add to Calendar")
            }

            // Details
            VStack(alignment: .leading, spacing: 8) {
                ActionDetailRow(label: "Title", value: title)
                ActionDetailRow(label: "When", value: when)
                ActionDetailRow(label: "With", value: with)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.elevatedBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                )
        )
    }
}

// MARK: - Linear Action Card

struct LinearActionCard: View {
    let title: String
    let description: String
    let priority: String
    let team: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 10) {
                    // Linear logo
                    Image("LinearLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Create Linear Issue")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.primaryText)
                        Text("Toss will create this issue in Linear")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.secondaryText)
                    }
                }

                Spacer()

                OnboardingActionButton(title: "Create Issue")
            }

            // Details
            VStack(alignment: .leading, spacing: 8) {
                ActionDetailRow(label: "Title", value: title)
                ActionDetailRow(label: "Description", value: description)
                HStack(spacing: 16) {
                    ActionDetailRow(label: "Priority", value: priority, showDot: true, dotColor: .orange)
                    ActionDetailRow(label: "Team", value: team)
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.elevatedBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                )
        )
    }
}

// MARK: - Slack Action Card

struct SlackActionCard: View {
    let to: String
    let message: String
    let attachment: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack {
                HStack(spacing: 10) {
                    // Slack logo
                    Image("SlackLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 32, height: 32)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Send to Slack")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(AppTheme.primaryText)
                        Text("Toss will send this DM to \(to)")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.secondaryText)
                    }
                }

                Spacer()

                OnboardingActionButton(title: "Send Message")
            }

            // Details
            VStack(alignment: .leading, spacing: 8) {
                ActionDetailRow(label: "To", value: to)
                ActionDetailRow(label: "Message", value: message)
                if let attachment = attachment {
                    HStack(spacing: 6) {
                        Text("Attachment")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.secondaryText)
                        Image(systemName: "paperclip")
                            .font(.system(size: 11))
                            .foregroundColor(AppTheme.secondaryText)
                        Text(attachment)
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.primaryText)
                    }
                }
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.elevatedBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                )
        )
    }
}

// MARK: - Supporting Views

struct OnboardingActionButton: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.system(size: 12, weight: .semibold))
            .foregroundColor(.white)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(AppTheme.accent)
            )
    }
}

struct ActionDetailRow: View {
    let label: String
    let value: String
    var showDot: Bool = false
    var dotColor: Color = .clear

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.secondaryText)
                .frame(width: 70, alignment: .leading)

            if showDot {
                Circle()
                    .fill(dotColor)
                    .frame(width: 8, height: 8)
            }

            Text(value)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.primaryText)
                .lineLimit(2)
        }
    }
}

#Preview {
    ZStack {
        AppGlassBackground()
        VStack(spacing: 20) {
            ActionItemPreview(
                example: ActionItemExampleData(
                    quote: "I'll schedule a follow-up for next week to go over the pricing.",
                    timestamp: "23:45",
                    card: .calendar(
                        title: "Acme Pricing Follow-up",
                        when: "Tue, Feb 4 · 2:00 PM",
                        with: "James Wilson"
                    )
                )
            )
        }
        .frame(maxWidth: 480)
        .padding(40)
    }
    .frame(width: 700, height: 600)
}
