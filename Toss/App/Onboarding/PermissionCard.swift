import SwiftUI

struct PermissionCard: View {
    let title: String
    let description: String
    let isGranted: Bool
    let actionTitle: String
    let onAllow: () -> Void

    private let grantedColor = Color(red: 0.3, green: 0.8, blue: 0.5)

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    if isGranted {
                        Image(systemName: "checkmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(grantedColor)
                    }

                    Text(isGranted ? grantedTitle : title)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(isGranted ? grantedColor : AppTheme.primaryText)
                }

                if !isGranted {
                    Text(description)
                        .font(.system(size: 13))
                        .foregroundColor(AppTheme.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer()

            if !isGranted {
                Button(action: onAllow) {
                    Text(actionTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(AppTheme.primaryText)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(AppTheme.subtleStroke, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppTheme.cardBackground)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(AppTheme.subtleStroke, lineWidth: 1)
                )
        )
    }

    private var grantedTitle: String {
        // Convert "Allow Toss to..." to "Toss can now..."
        if title.hasPrefix("Allow Toss to ") {
            let action = title.replacingOccurrences(of: "Allow Toss to ", with: "")
            return "Toss can now \(action)"
        }
        return title
    }
}

#Preview {
    VStack(spacing: 16) {
        PermissionCard(
            title: "Allow Toss to insert spoken words",
            description: "This lets Toss put your spoken words in the right textbox.",
            isGranted: false,
            actionTitle: "Allow",
            onAllow: {}
        )

        PermissionCard(
            title: "Allow Toss to insert spoken words",
            description: "This lets Toss put your spoken words in the right textbox.",
            isGranted: true,
            actionTitle: "Allow",
            onAllow: {}
        )

        PermissionCard(
            title: "Allow Toss to use your microphone",
            description: "Toss will only access the mic when you are actively using it.",
            isGranted: false,
            actionTitle: "Allow",
            onAllow: {}
        )
    }
    .padding()
    .background(Color.black)
}
