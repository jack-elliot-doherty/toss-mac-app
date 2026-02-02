import SwiftUI

struct MeetingsStepView: View {
    @State private var currentExample = 0
    @State private var timer: Timer?

    private let examples: [ActionItemExampleData] = [
        ActionItemExampleData(
            quote: "I'll schedule a follow-up for next week to go over the pricing.",
            timestamp: "23:45",
            card: .calendar(
                title: "Acme Pricing Follow-up",
                when: "Tue, Feb 4 · 2:00 PM",
                with: "James Wilson"
            )
        ),
        ActionItemExampleData(
            quote: "We should fix that dashboard bug before the next demo.",
            timestamp: "31:12",
            card: .linear(
                title: "Dashboard loading bug reported by Acme",
                description: "Dashboard takes 5+ seconds to load",
                priority: "Medium",
                team: "Engineering"
            )
        ),
        ActionItemExampleData(
            quote: "Can you send them the pricing PDF we talked about?",
            timestamp: "42:08",
            card: .slack(
                to: "James Wilson",
                message: "Hey James! Here's the pricing PDF we discussed.",
                attachment: "enterprise-pricing-2025.pdf"
            )
        ),
    ]

    var body: some View {
        VStack(spacing: 28) {
            // Headline
            VStack(spacing: 8) {
                Text("Turn meeting talk into done tasks")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundColor(AppTheme.primaryText)

                Text(
                    "When you say \"I'll send that over\" or \"I'll create a ticket,\" Toss catches it. One click and it's done."
                )
                .font(.system(size: 14))
                .foregroundColor(AppTheme.secondaryText)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }

            // Animated action item example
            ActionItemPreview(example: examples[currentExample])
                .id(currentExample)  // Force view recreation for animation
                .transition(.opacity.combined(with: .scale(scale: 0.98)))

            // Dot indicators for examples
            HStack(spacing: 8) {
                ForEach(0..<examples.count, id: \.self) { i in
                    Circle()
                        .fill(i == currentExample ? AppTheme.accent : Color.white.opacity(0.3))
                        .frame(width: 6, height: 6)
                        .animation(.easeInOut(duration: 0.2), value: currentExample)
                }
            }

            // Privacy note
            HStack(spacing: 8) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.secondaryText)
                Text("Recorded locally on your Mac — no bots join your calls")
                    .font(.system(size: 13))
                    .foregroundColor(AppTheme.secondaryText)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(Color.white.opacity(0.05))
            )
        }
        .onAppear {
            startTimer()
        }
        .onDisappear {
            stopTimer()
        }
    }

    private func startTimer() {
        timer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { _ in
            withAnimation(.easeInOut(duration: 0.4)) {
                currentExample = (currentExample + 1) % examples.count
            }
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }
}

#Preview {
    ZStack {
        AppGlassBackground()
        MeetingsStepView()
            .frame(maxWidth: 520)
            .padding(40)
    }
    .frame(width: 700, height: 700)
}
