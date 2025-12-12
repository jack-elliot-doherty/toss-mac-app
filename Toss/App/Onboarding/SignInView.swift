import AppKit
import SwiftUI

@MainActor
struct SignInView: View {
    @ObservedObject private var auth = AuthManager.shared
    @ObservedObject private var onboarding = OnboardingManager.shared

    @State private var agreedToTerms = true

    var body: some View {
        ZStack {
            // Background that fills everything including safe areas
            AppGlassBackground()
                .ignoresSafeArea()

            // Extra darkening so the top doesn't wash out
            LinearGradient(
                colors: [
                    Color.black.opacity(0.55),
                    Color.black.opacity(0.30),
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Top hero (smaller + less padding)
                VStack {
                    ZStack {
                        Image(nsImage: NSApp.applicationIconImage)
                            .resizable()
                            .interpolation(.high)
                            .aspectRatio(contentMode: .fit)
                            .padding(2)
                    }
                    .frame(width: 132, height: 132)
                    .shadow(color: Color.black.opacity(0.35), radius: 22, y: 10)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 20)
                .padding(.bottom, 18)

                // Bottom panel (touches edges, internal padding only)
                VStack(alignment: .leading, spacing: 10) {
                    // Logo in a "card"
                    HStack(spacing: 10) {
                        AppLogoMark(size: 28, cornerRadius: 12)
                            .padding(6)
                            .frame(width: 28, height: 28)

                        Text("Toss")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(.white)

                        Spacer()
                    }

                    Text("Sign in")
                        .font(.system(size: 30, weight: .bold))
                        .foregroundColor(.white)

                    Text("Sign in with Google to continue.")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Color.white.opacity(0.70))

                    Button {
                        auth.continueWithGoogle()
                    } label: {
                        HStack(spacing: 10) {
                            Image(systemName: "g.circle.fill")
                                .font(.system(size: 17, weight: .semibold))
                            Text("Sign in with Google")
                                .font(.system(size: 15, weight: .semibold))
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(WhitePillButtonStyle())
                    .disabled(!agreedToTerms)

                    Button {
                        auth.beginBrowserLogin()
                    } label: {
                        Text("More sign-in options")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color.white.opacity(0.70))
                            .underline()
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                .padding(18)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    Rectangle()
                        .fill(Color.black.opacity(0.62))
                        .background(.ultraThinMaterial)
                        .ignoresSafeArea()  // Make sure this extends to edges
                )
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background(Color.black.opacity(0.001))  // Invisible but fills space
            .ignoresSafeArea()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ignoresSafeArea()  // Ignore all safe areas
        .onAppear { onboarding.refresh() }
    }
}

// MARK: - Components

private struct AppLogoMark: View {
    let size: CGFloat
    let cornerRadius: CGFloat

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(AppTheme.accent.opacity(0.22))
                .overlay(
                    RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                        .stroke(Color.white.opacity(0.16), lineWidth: 1)
                )

            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .padding(size * 0.18)
        }
        .frame(width: size, height: size)
    }
}

private struct WhitePillButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .padding(.vertical, 12)
            .padding(.horizontal, 16)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(configuration.isPressed ? 0.88 : 0.95))
            )
            .foregroundColor(Color.black.opacity(0.92))
            .opacity(configuration.isPressed ? 0.98 : 1.0)
            .scaleEffect(configuration.isPressed ? 0.99 : 1.0)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
