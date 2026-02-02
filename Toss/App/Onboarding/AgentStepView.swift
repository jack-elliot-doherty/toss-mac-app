import SwiftUI

struct AgentStepView: View {
    var body: some View {
        VStack(spacing: 32) {
            // Headline
            VStack(spacing: 8) {
                Text("Talk to Toss about your work")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(AppTheme.primaryText)

                Text(
                    "Toss knows your meetings, contacts, and context. Just tell it what you need — no explaining."
                )
                .font(.system(size: 14))
                .foregroundColor(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            // Hotkey visualization
            VStack(spacing: 20) {
                HStack(spacing: 6) {
                    Text("Hold")
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.secondaryText)
                    KeyboardKey("fn")
                    Text("+")
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.secondaryText)
                    KeyboardKey("⌘")
                    Text("and speak")
                        .font(.system(size: 15))
                        .foregroundColor(AppTheme.secondaryText)
                }

                // Try prompt
                Text("Try: \"What can you do?\"")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundColor(AppTheme.primaryText)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.05))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(AppTheme.subtleStroke, lineWidth: 1)
                            )
                    )
            }

            // Example commands
            VStack(alignment: .leading, spacing: 12) {
                Text("Examples of what you can say:")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(AppTheme.secondaryText)

                VStack(alignment: .leading, spacing: 8) {
                    ExampleCommand(text: "Send Dave the pricing we discussed")
                    ExampleCommand(text: "Create an issue for this bug")
                    ExampleCommand(text: "Schedule a follow-up with Acme")
                    ExampleCommand(text: "What did we decide about the timeline?")
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
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
}

// MARK: - Example Command Row

struct ExampleCommand: View {
    let text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "quote.opening")
                .font(.system(size: 10))
                .foregroundColor(AppTheme.accent)

            Text(text)
                .font(.system(size: 13))
                .foregroundColor(AppTheme.primaryText)
        }
    }
}

#Preview {
    ZStack {
        AppGlassBackground()
        AgentStepView()
            .frame(maxWidth: 520)
            .padding(40)
    }
    .frame(width: 700, height: 580)
}
