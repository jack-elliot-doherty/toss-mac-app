import SwiftUI

/// Overlay that displays flow toast notifications in-app
struct FlowToastOverlay: View {
    @ObservedObject var notificationManager = FlowNotificationManager.shared

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            ForEach(notificationManager.activeToasts) { toast in
                FlowToastView(toast: toast) {
                    withAnimation(.easeOut(duration: 0.2)) {
                        notificationManager.dismissToast(toast)
                    }
                }
                .transition(
                    .asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .trailing).combined(with: .opacity)
                    ))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
        .allowsHitTesting(!notificationManager.activeToasts.isEmpty)
        .animation(
            .spring(response: 0.4, dampingFraction: 0.75), value: notificationManager.activeToasts)
    }
}

/// Individual toast notification view
struct FlowToastView: View {
    let toast: FlowToast
    let onDismiss: () -> Void

    @State private var isHovered = false
    @State private var showCheckmark = false

    private var isRunning: Bool {
        toast.id.contains("-running")
    }

    var body: some View {
        HStack(spacing: 14) {
            // App icons flow: Toss → destination
            iconFlowView
                .frame(width: 56)

            // Content
            VStack(alignment: .leading, spacing: 3) {
                Text(toast.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text(toast.message)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(2)
            }

            Spacer(minLength: 8)

            // Status indicator
            statusIndicator
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .frame(width: 340)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(white: 0.15),
                            Color(white: 0.1),
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .shadow(color: .black.opacity(0.3), radius: 20, y: 8)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.1), lineWidth: 1)
        )
        .onAppear {
            if !isRunning {
                // Animate checkmark appearing
                withAnimation(.spring(response: 0.4, dampingFraction: 0.7).delay(0.1)) {
                    showCheckmark = true
                }
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovered = hovering
            }
        }
    }

    @ViewBuilder
    private var statusIndicator: some View {
        if isHovered && !isRunning {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
            .transition(.opacity)
        } else if isRunning {
            // Spinner for running state
            ProgressView()
                .progressViewStyle(CircularProgressViewStyle(tint: .white.opacity(0.8)))
                .scaleEffect(0.8)
        } else {
            // Checkmark or X for completed state
            Image(systemName: toast.isError ? "xmark.circle.fill" : "checkmark.circle.fill")
                .font(.system(size: 18))
                .foregroundColor(toast.isError ? .red : .green)
                .scaleEffect(showCheckmark ? 1.0 : 0.5)
                .opacity(showCheckmark ? 1.0 : 0.0)
        }
    }

    /// Shows Toss icon → arrow → destination app icon(s)
    @ViewBuilder
    private var iconFlowView: some View {
        let icons = inferIcons()

        HStack(spacing: 4) {
            // Toss app icon
            Image("TossLogo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 24, height: 24)
                .clipShape(RoundedRectangle(cornerRadius: 6))

            // Arrow
            Image(systemName: "arrow.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.5))

            // Destination app icon(s)
            if icons.count == 1 {
                singleAppIcon(icons[0])
                    .frame(width: 24, height: 24)
            } else if icons.count > 1 {
                // Stack multiple icons
                ZStack {
                    ForEach(Array(icons.prefix(2).enumerated()), id: \.offset) { index, iconName in
                        singleAppIcon(iconName)
                            .frame(width: 20, height: 20)
                            .offset(x: CGFloat(index) * 8)
                    }
                }
                .frame(width: 28)
            } else {
                // Generic icon when no specific app detected
                Image(systemName: "arrow.right.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
    }

    /// Infer icons from the icon field, falling back to title/message if needed
    private func inferIcons() -> [String] {
        // First try the icon field
        if let iconString = toast.icon,
            !iconString.isEmpty,
            iconString != "generic"
        {
            let icons = iconString.split(separator: ",").map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
            if !icons.isEmpty {
                return icons
            }
        }

        // Fallback: infer from title and message
        let searchText = (toast.title + " " + toast.message).lowercased()
        var inferred: [String] = []

        if searchText.contains("slack") { inferred.append("slack") }
        if searchText.contains("notion") { inferred.append("notion") }
        if searchText.contains("linear") { inferred.append("linear") }
        if searchText.contains("calendar") || searchText.contains("gcal") {
            inferred.append("calendar")
        }

        return inferred
    }

    @ViewBuilder
    private func singleAppIcon(_ iconName: String) -> some View {
        let assetName = iconAssetName(for: iconName)
        if let assetName = assetName {
            Image(assetName)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        } else {
            Image(systemName: "app.fill")
                .font(.system(size: 18))
                .foregroundColor(.white.opacity(0.6))
        }
    }

    private func iconAssetName(for iconName: String) -> String? {
        switch iconName.lowercased() {
        case "slack":
            return "SlackLogo"
        case "notion":
            return "NotionLogo"
        case "linear":
            return "LinearLogo"
        case "calendar":
            return "GoogleCalendarLogo"
        default:
            return nil
        }
    }
}

#Preview {
    ZStack {
        Color.black.opacity(0.8)

        FlowToastOverlay()
    }
    .frame(width: 500, height: 400)
    .onAppear {
        FlowNotificationManager.shared.activeToasts = [
            FlowToast(
                id: "1-running",
                title: "Syncing to Notion",
                message: "Running automation...",
                icon: "notion",
                isError: false,
                timestamp: Date()
            ),
            FlowToast(
                id: "2-completed",
                title: "Posted to Slack",
                message: "Successfully sent meeting summary to #team-updates",
                icon: "slack",
                isError: false,
                timestamp: Date()
            ),
        ]
    }
}
