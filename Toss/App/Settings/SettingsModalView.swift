import AVFoundation
import SwiftUI

@MainActor
struct SettingsModalView: View {
    enum Section: String, CaseIterable, Identifiable {
        case general, system, account, plans, privacy
        var id: String { rawValue }
        var title: String {
            switch self {
            case .general: return "General"
            case .system: return "System"
            case .account: return "Account"
            case .plans: return "Plans and Billing"
            case .privacy: return "Data and Privacy"
            }
        }
        var icon: String {
            switch self {
            case .general: return "slider.horizontal.3"
            case .system: return "desktopcomputer"
            case .account: return "person.crop.circle"
            case .plans: return "creditcard"
            case .privacy: return "lock.shield"
            }
        }
    }

    @ObservedObject private var ob = OnboardingManager.shared
    @ObservedObject private var auth = AuthManager.shared
    @State private var selection: Section = .general

    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.22), radius: 28, x: 0, y: 18)

            HStack(spacing: 0) {
                // Sidebar
                List(Section.allCases, selection: $selection) { s in
                    Label(s.title, systemImage: s.icon)
                }
                .listStyle(.sidebar)
                .frame(width: 220)

                Divider()

                // Content
                VStack(alignment: .leading, spacing: 20) {
                    Text(selection.title).font(.system(size: 20, weight: .semibold))

                    switch selection {
                    case .general: generalPane
                    case .system: systemPane
                    case .account: accountPane
                    case .plans: plansPane
                    case .privacy: privacyPane
                    }
                    Spacer(minLength: 0)
                }
                .padding(22)
                .frame(minWidth: 480, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Circle().fill(Color.black.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .padding(10)
        }
        .frame(height: 520)
        .onAppear { ob.refresh() }
    }

    private var generalPane: some View {
        VStack(spacing: 12) {
            settingsRow(title: "Keyboard shortcuts", subtitle: "Hold ⌘ and speak. Learn more →") {
                // TODO: shortcut editor
            }
            settingsRow(
                title: "Microphone",
                subtitle: ob.micGranted ? "Allowed" : "Built‑in mic (recommended)",
                action: {
                    if ob.micGranted { ob.openMicSettings() } else { ob.requestMic() }
                }, actionTitle: (ob.micGranted ? "Change" : "Allow"))
            settingsRow(title: "Languages", subtitle: "English") {}
        }
    }

    private var systemPane: some View {
        VStack(spacing: 12) {
            settingsRow(
                title: "Accessibility", subtitle: ob.axGranted ? "Allowed" : "Required for pasting",
                action: {
                    if ob.axGranted {
                        ob.openAXSettings()
                    } else {
                        ob.requestAX()
                        ob.openAXSettings()
                    }
                }, actionTitle: (ob.axGranted ? "Open" : "Allow…"))
        }
    }

    private var accountPane: some View {
        VStack(spacing: 12) {
            if auth.isAuthenticated {
                settingsRow(
                    title: "Signed in", subtitle: auth.userEmail ?? auth.userName ?? "",
                    action: {
                        auth.signOut()
                        ob.refresh()
                    }, actionTitle: "Sign out")
            } else {
                settingsRow(
                    title: "Not signed in", subtitle: "Click to sign in",
                    action: {
                        auth.beginBrowserLogin()
                    }, actionTitle: "Sign in")
            }
        }
    }

    private var plansPane: some View {
        Text("Plans and Billing coming soon").foregroundColor(.secondary)
    }

    private var privacyPane: some View {
        Text("Data and Privacy controls coming soon").foregroundColor(.secondary)
    }

    private func settingsRow(
        title: String,
        subtitle: String,
        action: @escaping () -> Void,
        actionTitle: String = "Change"
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .semibold))
                Text(subtitle).font(.system(size: 12)).foregroundColor(.secondary)
            }
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 12).fill(Color.black.opacity(0.05))
        )
    }
}
