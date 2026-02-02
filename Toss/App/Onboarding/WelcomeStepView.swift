import SwiftUI

struct WelcomeStepView: View {
    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            // Logo and app name
            VStack(spacing: 16) {
                Image("TossLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 80, height: 80)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

                Text("Toss")
                    .font(.system(size: 36, weight: .bold))
                    .foregroundColor(AppTheme.primaryText)
            }

            // Tagline - matching landing page style (same size, differentiated by color)
            (
                Text("AI that understands your work as it unfolds. ")
                    .foregroundColor(AppTheme.primaryText)
                + Text("So you don't have to explain it from scratch every time.")
                    .foregroundColor(AppTheme.secondaryText.opacity(0.6))
            )
            .font(.system(size: 20, weight: .semibold))
            .multilineTextAlignment(.center)
            .lineSpacing(4)
            .padding(.horizontal, 20)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

// MARK: - Context Filesystem Preview

struct ContextFilesystemPreview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            FileTreeRow(icon: "folder.fill", iconColor: .blue, text: "meetings/", indent: 0)
            FileTreeRow(
                icon: "doc.text.fill", iconColor: Color.white.opacity(0.4),
                text: "acme-kickoff/ → summary, action items", indent: 1)

            FileTreeRow(icon: "person.fill", iconColor: .orange, text: "people/", indent: 0)
                .padding(.top, 4)
            FileTreeRow(
                icon: "doc.text.fill", iconColor: Color.white.opacity(0.4),
                text: "Sarah Chen → context, history", indent: 1)

            FileTreeRow(icon: "brain.head.profile", iconColor: .purple, text: "memories/", indent: 0)
                .padding(.top, 4)
            FileTreeRow(
                icon: "doc.text.fill", iconColor: Color.white.opacity(0.4),
                text: "\"prefers Slack over email\"", indent: 1)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color.black.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                )
        )
    }
}

struct FileTreeRow: View {
    let icon: String
    let iconColor: Color
    let text: String
    let indent: Int

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(iconColor)
                .frame(width: 16)

            Text(text)
                .font(.system(size: 13, design: .monospaced))
                .foregroundColor(AppTheme.primaryText.opacity(indent == 0 ? 1 : 0.7))
        }
        .padding(.leading, CGFloat(indent) * 20)
    }
}

#Preview {
    ZStack {
        AppGlassBackground()
        WelcomeStepView()
            .frame(maxWidth: 520)
            .padding(40)
    }
    .frame(width: 700, height: 580)
}
