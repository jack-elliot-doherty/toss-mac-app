import SwiftUI

struct PaywallView: View {
    @ObservedObject private var subscriptionManager = SubscriptionManager.shared
    @ObservedObject private var auth = AuthManager.shared

    var body: some View {
        ZStack {
            AppGlassBackground()

            VStack(spacing: 20) {
                // Ghost icon (matching Clerk's style)
                Image(systemName: "person.fill.xmark")
                    .font(.system(size: 56, weight: .thin))
                    .foregroundColor(AppTheme.secondaryText.opacity(0.5))

                // Title
                Text("Subscription Expired")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)

                // Subtitle
                Text("Your subscription has ended.\nPlease renew to continue using Toss.")
                    .font(.system(size: 15))
                    .foregroundColor(AppTheme.secondaryText)
                    .multilineTextAlignment(.center)
                    .lineSpacing(2)

                // Button row
                HStack(spacing: 12) {
                    Button {
                        subscriptionManager.openBillingPortal()
                    } label: {
                        HStack(spacing: 6) {
                            Text("Billing Portal")
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 11, weight: .semibold))
                        }
                        .foregroundColor(AppTheme.primaryText)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.white.opacity(0.12))

                    Button {
                        if let url = URL(string: "mailto:support@usetoss.com") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "questionmark.circle")
                            Text("Support")
                        }
                        .foregroundColor(AppTheme.primaryText)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(Color.white.opacity(0.12))
                }
                .padding(.top, 8)

                // Logout button
                Button {
                    auth.signOut()
                } label: {
                    Text("Logout")
                        .foregroundColor(AppTheme.primaryText)
                }
                .buttonStyle(.borderedProminent)
                .tint(Color.white.opacity(0.08))

                // Add after the Logout button in PaywallView:

                Button {
                    Task {
                        await subscriptionManager.checkSubscription()
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("I've subscribed")
                    }
                    .foregroundColor(AppTheme.secondaryText)
                }
                .buttonStyle(.plain)
                .padding(.top, 8)
            }
            .padding(40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    PaywallView()
        .frame(width: 800, height: 600)
}
