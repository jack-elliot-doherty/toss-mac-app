import AVFoundation
import PostHog
import SwiftUI

// MARK: - Team Models

struct TeamMember: Identifiable, Codable {
    let id: String
    let userId: String
    let name: String
    let email: String
    let imageUrl: String?
    let role: String
    let joinedAt: Int

    var isAdmin: Bool { role == "org:admin" }

    var joinedAtDate: Date {
        Date(timeIntervalSince1970: TimeInterval(joinedAt) / 1000)
    }
}

struct TeamInvitation: Identifiable, Codable {
    let id: String
    let emailAddress: String
    let role: String
    let status: String
    let createdAt: Int

    var createdAtDate: Date {
        Date(timeIntervalSince1970: TimeInterval(createdAt) / 1000)
    }
}

struct TeamMembersResponse: Codable {
    let ok: Bool
    let members: [TeamMember]?
}

struct TeamInvitationsResponse: Codable {
    let ok: Bool
    let invitations: [TeamInvitation]?
}

// MARK: - Memory Model

struct AgentMemory: Codable, Identifiable, Equatable {
    let id: String
    var content: String
    let createdAt: String

    var createdAtDate: Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: createdAt)
    }
}

struct MemoriesResponse: Codable {
    let memories: [AgentMemory]
}

// MARK: - Memories API

final class MemoriesAPI {
    static let shared = MemoriesAPI()
    private let baseURL: URL

    init(baseURL: URL = Config.serverBaseURL) {
        self.baseURL = baseURL
    }

    func listMemories() async throws -> [AgentMemory] {
        let url = baseURL.appendingPathComponent("memories")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, _) = try await APIClient.shared.perform(request)
        let response = try JSONDecoder().decode(MemoriesResponse.self, from: data)
        return response.memories
    }

    func updateMemory(id: String, content: String) async throws {
        let url = baseURL.appendingPathComponent("memories/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(["content": content])

        let (_, response) = try await APIClient.shared.perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }

    func deleteMemory(id: String) async throws {
        let url = baseURL.appendingPathComponent("memories/\(id)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await APIClient.shared.perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }
    }
}

// MARK: - Settings Modal View

@MainActor
struct SettingsModalView: View {
    enum Section: String, CaseIterable, Identifiable {
        // Account group
        case myAccount, preferences
        // Agent group
        case dictationHistory, agentMemories
        // Workspace group
        case general, members, billing

        var id: String { rawValue }

        var title: String {
            switch self {
            case .myAccount: return "My Account"
            case .preferences: return "Preferences"
            case .dictationHistory: return "Dictation History"
            case .agentMemories: return "Memories"
            case .general: return "General"
            case .members: return "Members"
            case .billing: return "Billing"
            }
        }

        var icon: String {
            switch self {
            case .myAccount: return "person.crop.circle"
            case .preferences: return "slider.horizontal.3"
            case .dictationHistory: return "text.bubble"
            case .agentMemories: return "brain.head.profile"
            case .general: return "gearshape"
            case .members: return "person.2"
            case .billing: return "creditcard"
            }
        }

        var group: SectionGroup {
            switch self {
            case .myAccount, .preferences: return .account
            case .dictationHistory, .agentMemories: return .agent
            case .general, .members, .billing: return .workspace
            }
        }
    }

    enum SectionGroup: String, CaseIterable {
        case account, agent, workspace

        var title: String {
            switch self {
            case .account: return "Account"
            case .agent: return "Agent"
            case .workspace: return "Workspace"
            }
        }

        var sections: [Section] {
            Section.allCases.filter { $0.group == self }
        }
    }

    @ObservedObject private var ob = OnboardingManager.shared
    @ObservedObject private var auth = AuthManager.shared
    @State private var selection: Section = .myAccount
    @StateObject private var integrations = IntegrationsManager.shared
    @StateObject private var launchAtLogin = LaunchAtLogin.shared
    @StateObject private var preferences = PreferencesManager.shared
    @State private var meetingReminderTime: String = "Before 1m"
    @State private var autoDetectMeetings: Bool = true
    @State private var workspaceName: String = ""
    @State private var companyName: String = ""
    @State private var websiteURL: String = ""
    @State private var briefDescription: String = ""
    @State private var allowedDomains: String = ""
    @State private var memberSearchText: String = ""
    @State private var hasLoadedWorkspaceData = false

    // Team members state
    @State private var teamMembers: [TeamMember] = []
    @State private var teamInvitations: [TeamInvitation] = []
    @State private var isLoadingMembers = false
    @State private var showInviteSheet = false
    @State private var inviteEmail = ""
    @State private var inviteRole = "org:member"
    @State private var isInviting = false
    @State private var memberToRemove: TeamMember?
    @State private var showRemoveConfirmation = false
    @State private var invitationToRevoke: TeamInvitation?
    @State private var showRevokeConfirmation = false

    // Danger zone state
    @State private var showLeaveConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var deleteConfirmationText = ""
    @State private var isLeavingOrg = false
    @State private var isDeletingOrg = false
    
    // Error state for user feedback
    @State private var operationError: String?
    @State private var showOperationError = false

    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(NSColor.windowBackgroundColor))
                .shadow(color: .black.opacity(0.22), radius: 28, x: 0, y: 18)

            HStack(spacing: 0) {
                // Sidebar with grouped sections
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        ForEach(SectionGroup.allCases, id: \.self) { group in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(group.title)
                                    .font(.system(size: 11, weight: .semibold))
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                    .kerning(0.5)
                                    .padding(.horizontal, 12)

                                VStack(spacing: 2) {
                                    ForEach(group.sections) { section in
                                        sidebarButton(for: section)
                                    }
                                }
                            }
                        }
                    }
                    .padding(.vertical, 20)
                    .padding(.horizontal, 8)
                }
                .frame(width: 180)
                .background(Color.black.opacity(0.02))

                Divider()

                // Content
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        // Content based on selection (no title - it's clear from sidebar)
                        switch selection {
                        case .myAccount: myAccountPane
                        case .preferences: preferencesPane
                        case .dictationHistory: dictationHistoryPane
                        case .agentMemories: agentMemoriesPane
                        case .general: generalPane
                        case .members: membersPane
                        case .billing: billingPane
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(28)
                }
                .frame(minWidth: 500, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity)
            }

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(8)
                    .background(Circle().fill(Color.black.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Close settings")
            .padding(14)
        }
        .frame(height: 560)
        .onAppear {
            ob.refresh()
            loadWorkspaceData()
            meetingReminderTime = preferences.meetingReminderTime
            autoDetectMeetings = preferences.autoDetectMeetings
        }
    }

    private func loadWorkspaceData() {
        guard !hasLoadedWorkspaceData else { return }
        hasLoadedWorkspaceData = true
        workspaceName = auth.currentOrg?.name ?? ""
    }

    private func setMeetingReminderTime(_ time: String) {
        meetingReminderTime = time
        preferences.meetingReminderTime = time
    }

    // MARK: - Sidebar Button

    private func sidebarButton(for section: Section) -> some View {
        Button(action: { selection = section }) {
            HStack(spacing: 10) {
                Image(systemName: section.icon)
                    .font(.system(size: 14))
                    .foregroundColor(selection == section ? .primary : .secondary)
                    .frame(width: 20)

                Text(section.title)
                    .font(.system(size: 13, weight: selection == section ? .medium : .regular))
                    .foregroundColor(selection == section ? .primary : .primary.opacity(0.85))

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(selection == section ? Color.primary.opacity(0.1) : Color.clear)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - My Account Pane

    private var myAccountPane: some View {
        VStack(alignment: .leading, spacing: 28) {
            // Profile header with avatar and name/role fields
            HStack(alignment: .top, spacing: 20) {
                if let url = auth.userImageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: Color.gray.opacity(0.2)
                        }
                    }
                    .frame(width: 80, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 80, height: 100)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary)
                        )
                }

                VStack(alignment: .leading, spacing: 16) {
                    formField(label: "Full name", value: auth.userName ?? "—")
                    formField(label: "Role", value: userRoleDisplayName)
                }
            }

            Divider()

            // Danger zone
            VStack(alignment: .leading, spacing: 16) {
                Text("Danger zone")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Delete account")
                            .font(.system(size: 14, weight: .medium))
                        Text(
                            "Delete your account and detach from all workspaces. This action cannot be undone."
                        )
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(action: {
                        // TODO: Implement account deletion
                    }) {
                        Text("Delete my account")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.red.opacity(0.5), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var userRoleDisplayName: String {
        guard let role = auth.currentOrg?.role else { return "Member" }
        switch role {
        case "org:admin": return "Admin"
        case "org:member": return "Member"
        default: return role.replacingOccurrences(of: "org:", with: "").capitalized
        }
    }

    // MARK: - Google Calendar Card

    private var googleRequiresReauth: Bool {
        integrations.googleStatus?.requiresReauth == true
    }

    private var googleCalendarCard: some View {
        HStack(spacing: 16) {
            // Left side: Icon with status badge below
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(
                            googleRequiresReauth
                                ? Color.orange.opacity(0.15)
                                : Color(red: 0.2, green: 0.5, blue: 0.3))
                    Image(
                        systemName: googleRequiresReauth
                            ? "exclamationmark.triangle.fill" : "calendar.badge.clock"
                    )
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(googleRequiresReauth ? .orange : .white)
                }
                .frame(width: 48, height: 48)

                // Status badge below icon
                if googleRequiresReauth {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 9, weight: .bold))
                        Text("Reauth needed")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.orange.opacity(0.15))
                    )
                } else if let status = integrations.googleStatus, status.connected {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark")
                            .font(.system(size: 9, weight: .bold))
                        Text("Synced")
                            .font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule()
                            .fill(Color.green.opacity(0.15))
                    )
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Google Calendar")
                    .font(.system(size: 14, weight: .semibold))

                if googleRequiresReauth {
                    Text("Connection expired — tap Reconnect")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                } else if let status = integrations.googleStatus, status.connected {
                    Text("Calendar events sync and meeting data")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                } else {
                    Text("Connect to sync calendar events")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if googleRequiresReauth {
                Button("Reconnect") {
                    Task { await integrations.connectGoogle() }
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
            } else if let status = integrations.googleStatus, status.connected {
                Button("Disconnect") {
                    Task { await integrations.disconnectGoogle() }
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Connect") {
                    Task { await integrations.connectGoogle() }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(googleRequiresReauth ? Color.orange.opacity(0.05) : Color.black.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(
                    googleRequiresReauth ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Preferences Pane

    private var preferencesPane: some View {
        VStack(alignment: .leading, spacing: 28) {
            // Launch at startup
            toggleRow(
                title: "Launch when system starts",
                subtitle: "This will launch Toss automatically when your system starts.",
                isOn: $launchAtLogin.isEnabled
            )

            // Hide idle pill
            toggleRow(
                title: "Hide pill when idle",
                subtitle: "Hide the floating pill when not recording or transcribing. It will appear when active.",
                isOn: $preferences.hideIdlePill
            )

            Divider()

            // Recording section
            VStack(alignment: .leading, spacing: 20) {
                Text("Recording")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                // Remind before meetings
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Remind me before meetings")
                            .font(.system(size: 14, weight: .medium))
                        Text("Show notifications before the start of meetings on your calendar")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Menu {
                        Button("Before 1m") { setMeetingReminderTime("Before 1m") }
                        Button("Before 5m") { setMeetingReminderTime("Before 5m") }
                        Button("Before 10m") { setMeetingReminderTime("Before 10m") }
                        Button("Before 15m") { setMeetingReminderTime("Before 15m") }
                        Divider()
                        Button("Off") { setMeetingReminderTime("Off") }
                    } label: {
                        HStack(spacing: 6) {
                            Text(meetingReminderTime)
                                .font(.system(size: 13))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.05))
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                // Auto-detect meetings
                toggleRow(
                    title: "Auto-detect meetings",
                    subtitle:
                        "Show notifications when a call is detected (Determined by microphone usage).",
                    isOn: Binding(
                        get: { autoDetectMeetings },
                        set: { newValue in
                            autoDetectMeetings = newValue
                            preferences.autoDetectMeetings = newValue
                        }
                    )
                )
            }

            Divider()

            // Keyboard Shortcuts section
            VStack(alignment: .leading, spacing: 20) {
                Text("Keyboard Shortcuts")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                // Dictation shortcut
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dictation")
                            .font(.system(size: 14, weight: .medium))
                        Text("Start dictation from anywhere on your desktop")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Menu {
                        Button("Hold Fn (Globe)") {
                            preferences.dictationShortcut = .enabled
                        }
                        Divider()
                        Button("No shortcut") {
                            preferences.dictationShortcut = .disabled
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(preferences.dictationShortcut.displayName)
                                .font(.system(size: 13))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.05))
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }

                // Agent mode shortcut
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Agent mode")
                            .font(.system(size: 14, weight: .medium))
                        Text("Talk to Toss agent from anywhere on your desktop")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Menu {
                        Button("Hold Fn + \u{2318}") {
                            preferences.agentModeShortcut = .enabled
                        }
                        Divider()
                        Button("No shortcut") {
                            preferences.agentModeShortcut = .disabled
                        }
                    } label: {
                        HStack(spacing: 6) {
                            Text(preferences.agentModeShortcut.agentModeDisplayName)
                                .font(.system(size: 13))
                            Image(systemName: "chevron.down")
                                .font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.05))
                        )
                    }
                    .menuStyle(.borderlessButton)
                    .fixedSize()
                }
            }

            Divider()

            // Permissions section
            VStack(alignment: .leading, spacing: 20) {
                Text("Permissions")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                formFieldWithAction(
                    title: "Microphone",
                    subtitle: ob.micGranted ? "Allowed" : "Required for dictation",
                    actionTitle: ob.micGranted ? "Change" : "Allow"
                ) {
                    if ob.micGranted { ob.openMicSettings() } else { ob.requestMic() }
                }

                formFieldWithAction(
                    title: "Accessibility",
                    subtitle: ob.axGranted ? "Allowed" : "Required for pasting",
                    actionTitle: ob.axGranted ? "Open Settings" : "Allow…"
                ) {
                    if ob.axGranted {
                        ob.openAXSettings()
                    } else {
                        ob.requestAX()
                        ob.openAXSettings()
                    }
                }
            }
        }
    }

    // MARK: - General Pane (Workspace Settings)

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 28) {
            // Workspace name with avatar
            HStack(alignment: .top, spacing: 20) {
                // Workspace avatar placeholder
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 80, height: 100)
                    .overlay(
                        Text("T")
                            .font(.system(size: 32, weight: .bold))
                            .foregroundColor(.accentColor)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text("Name")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField("Workspace name", text: $workspaceName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.05))
                        )
                }
            }

            Divider()

            // Company section
            VStack(alignment: .leading, spacing: 20) {
                Text("Company")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                // Company name
                VStack(alignment: .leading, spacing: 6) {
                    Text("Company name")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField("Enter company name", text: $companyName)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.05))
                        )
                }

                // Website URL
                VStack(alignment: .leading, spacing: 6) {
                    Text("Website URL")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    TextField("https://", text: $websiteURL)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.05))
                        )
                }

                // Brief description
                VStack(alignment: .leading, spacing: 6) {
                    Text("Brief description")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)
                    TextEditor(text: $briefDescription)
                        .font(.system(size: 14))
                        .scrollContentBackground(.hidden)
                        .padding(12)
                        .frame(height: 100)
                        .background(
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.black.opacity(0.05))
                        )
                }
            }

            Divider()

            // Allowed email domains
            VStack(alignment: .leading, spacing: 6) {
                Text("Allowed email domains")
                    .font(.system(size: 14, weight: .medium))
                Text(
                    "Anyone with email addresses at these domains can automatically join your workspace. Comma-separated."
                )
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

                TextField("acme.com, company.io", text: $allowedDomains)
                    .textFieldStyle(.plain)
                    .font(.system(size: 14))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.05))
                    )
            }

            Divider()

            // Danger zone
            VStack(alignment: .leading, spacing: 20) {
                Text("Danger zone")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                // Leave workspace
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Leave workspace")
                            .font(.system(size: 14, weight: .medium))
                        Text(
                            "Remove yourself from this workspace. You will lose access to all workspace data."
                        )
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button("Leave workspace") {
                        showLeaveConfirmation = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLeavingOrg)
                }

                // Delete workspace (admin only)
                if auth.currentOrg?.isAdmin == true {
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Delete entire workspace")
                                .font(.system(size: 14, weight: .medium))
                            Text(
                                "Delete this workspace and remove all users. This action cannot be undone."
                            )
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer()
                        Button(action: {
                            deleteConfirmationText = ""
                            showDeleteConfirmation = true
                        }) {
                            Text("Delete workspace")
                                .font(.system(size: 13, weight: .medium))
                                .foregroundColor(.red)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 8)
                                .background(
                                    RoundedRectangle(cornerRadius: 8)
                                        .stroke(Color.red.opacity(0.5), lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(isDeletingOrg)
                    }
                }
            }
            .confirmationDialog(
                "Leave \(auth.currentOrg?.name ?? "workspace")?",
                isPresented: $showLeaveConfirmation,
                titleVisibility: .visible
            ) {
                Button("Leave", role: .destructive) {
                    Task { await leaveWorkspace() }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("You'll lose access to all shared meetings and data in this workspace.")
            }
            .alert("Delete \(auth.currentOrg?.name ?? "workspace")?", isPresented: $showDeleteConfirmation) {
                TextField("Type 'delete' to confirm", text: $deleteConfirmationText)
                Button("Delete", role: .destructive) {
                    Task { await deleteWorkspace() }
                }
                .disabled(deleteConfirmationText.lowercased() != "delete")
                Button("Cancel", role: .cancel) {
                    deleteConfirmationText = ""
                }
            } message: {
                Text("This will permanently delete all data in this workspace. This action cannot be undone.")
            }

            #if DEBUG
                Divider()

                // Debug section
                VStack(alignment: .leading, spacing: 20) {
                    Text("Debug")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.secondary)

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Test Update Check")
                                .font(.system(size: 14, weight: .medium))
                            Text("Fetch appcast and show banner (ignores version comparison)")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Test Appcast") {
                            Task {
                                await UpdateManager.shared.debugTestAppcastFetch()
                            }
                        }
                        .buttonStyle(.bordered)
                    }

                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Force Show Update Banner")
                                .font(.system(size: 14, weight: .medium))
                            Text("Show the update banner without checking appcast")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        Button("Show Banner") {
                            UpdateManager.shared.debugForceShowUpdate()
                        }
                        .buttonStyle(.bordered)
                    }
                }
            #endif
        }
    }

    // MARK: - Integrations Pane

    private var integrationsPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Connect your workspace to external services.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            // Google Calendar
            integrationCard(
                icon: "calendar",
                iconColor: Color(red: 0.2, green: 0.5, blue: 0.3),
                name: "Google Calendar",
                description: integrations.googleStatus?.connected == true
                    ? (integrations.googleStatus?.email ?? "Connected")
                    : "Sync calendar events and meeting data",
                isConnected: integrations.googleStatus?.connected == true,
                requiresReauth: integrations.googleStatus?.requiresReauth == true,
                onConnect: { Task { await integrations.connectGoogle() } },
                onDisconnect: { Task { await integrations.disconnectGoogle() } }
            )

            // Slack
            integrationCard(
                icon: "number",
                iconColor: Color(red: 0.91, green: 0.26, blue: 0.42),
                name: "Slack",
                description: integrations.slackStatus?.connected == true
                    ? (integrations.slackStatus?.teamName ?? "Connected")
                    : "Send messages and receive notifications",
                isConnected: integrations.slackStatus?.connected == true,
                requiresReauth: false,
                onConnect: { Task { await integrations.connectSlack() } },
                onDisconnect: { Task { await integrations.disconnectSlack() } }
            )

            // Linear
            integrationCard(
                icon: "square.stack.3d.up",
                iconColor: Color(red: 0.38, green: 0.38, blue: 0.95),
                name: "Linear",
                description: integrations.linearStatus?.connected == true
                    ? (integrations.linearStatus?.organizationName ?? "Connected")
                    : "Create and manage issues",
                isConnected: integrations.linearStatus?.connected == true,
                requiresReauth: integrations.linearStatus?.requiresReauth == true,
                onConnect: { Task { await integrations.connectLinear() } },
                onDisconnect: { Task { await integrations.disconnectLinear() } }
            )

            // Notion
            integrationCard(
                icon: "doc.text",
                iconColor: .primary,
                name: "Notion",
                description: integrations.notionStatus?.connected == true
                    ? (integrations.notionStatus?.workspaceName ?? "Connected")
                    : "Access and search your Notion workspace",
                isConnected: integrations.notionStatus?.connected == true,
                requiresReauth: false,
                onConnect: { Task { await integrations.connectNotion() } },
                onDisconnect: { Task { await integrations.disconnectNotion() } }
            )
        }
        .onAppear {
            Task {
                await integrations.fetchGoogleStatus()
                await integrations.fetchSlackStatus()
                await integrations.fetchLinearStatus()
                await integrations.fetchNotionStatus()
            }
        }
    }

    private func integrationCard(
        icon: String,
        iconColor: Color,
        name: String,
        description: String,
        isConnected: Bool,
        requiresReauth: Bool,
        onConnect: @escaping () -> Void,
        onDisconnect: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(requiresReauth ? Color.orange.opacity(0.15) : (isConnected ? iconColor.opacity(0.15) : Color.gray.opacity(0.1)))
                Image(systemName: requiresReauth ? "exclamationmark.triangle.fill" : icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(requiresReauth ? .orange : (isConnected ? iconColor : .secondary))
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(name).font(.system(size: 14, weight: .medium))
                    if isConnected && !requiresReauth {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                            Text("Connected").font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.15)))
                    } else if requiresReauth {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 9, weight: .bold))
                            Text("Reauth").font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                    }
                }
                Text(description).font(.system(size: 12)).foregroundColor(.secondary)
            }

            Spacer()

            if requiresReauth {
                Button("Reconnect", action: onConnect)
                    .buttonStyle(.borderedProminent).tint(.orange).controlSize(.small)
            } else if isConnected {
                Button("Disconnect", action: onDisconnect)
                    .buttonStyle(.bordered).controlSize(.small)
            } else {
                Button("Connect", action: onConnect)
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(requiresReauth ? Color.orange.opacity(0.05) : Color.black.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(requiresReauth ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Members Pane

    private var membersPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with search and invite
            HStack(spacing: 12) {
                // Search field
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    TextField("Search", text: $memberSearchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 14))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.05))
                )

                Spacer()

                // Invite button (only for admins)
                if auth.currentOrg?.isAdmin == true {
                    Button(action: {
                        inviteEmail = ""
                        inviteRole = "org:member"
                        showInviteSheet = true
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Invite")
                                .font(.system(size: 13, weight: .medium))
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
                }
            }

            Divider()

            if isLoadingMembers {
                HStack {
                    Spacer()
                    ProgressView()
                        .scaleEffect(0.8)
                    Spacer()
                }
                .padding(.vertical, 40)
            } else {
                // Members list
                VStack(alignment: .leading, spacing: 16) {
                    Text("Members (\(filteredMembers.count))")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.secondary)

                    VStack(spacing: 0) {
                        ForEach(filteredMembers) { member in
                            teamMemberRow(member: member)
                            if member.id != filteredMembers.last?.id {
                                Divider()
                                    .padding(.leading, 52)
                            }
                        }
                    }
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.black.opacity(0.02))
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Pending Invitations (admin only)
                if auth.currentOrg?.isAdmin == true && !teamInvitations.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Pending Invitations (\(teamInvitations.count))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)

                        VStack(spacing: 0) {
                            ForEach(teamInvitations) { invitation in
                                invitationRow(invitation: invitation)
                                if invitation.id != teamInvitations.last?.id {
                                    Divider()
                                        .padding(.leading, 52)
                                }
                            }
                        }
                        .background(
                            RoundedRectangle(cornerRadius: 10)
                                .fill(Color.black.opacity(0.02))
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }

            Spacer()

            // Danger Zone
            dangerZoneSection
        }
        .onAppear {
            Task { await loadTeamData() }
        }
        .sheet(isPresented: $showInviteSheet) {
            inviteSheet
        }
        .confirmationDialog(
            "Remove \(memberToRemove?.name ?? "member")?",
            isPresented: $showRemoveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let member = memberToRemove {
                    Task { await removeMember(member) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("They will lose access to this workspace and all shared data.")
        }
        .confirmationDialog(
            "Revoke invitation?",
            isPresented: $showRevokeConfirmation,
            titleVisibility: .visible
        ) {
            Button("Revoke", role: .destructive) {
                if let invitation = invitationToRevoke {
                    Task { await revokeInvitation(invitation) }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The invitation to \(invitationToRevoke?.emailAddress ?? "") will be cancelled.")
        }
        .confirmationDialog(
            "Leave \(auth.currentOrg?.name ?? "workspace")?",
            isPresented: $showLeaveConfirmation,
            titleVisibility: .visible
        ) {
            Button("Leave", role: .destructive) {
                Task { await leaveWorkspace() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("You'll lose access to all shared meetings and data in this workspace.")
        }
        .alert("Delete \(auth.currentOrg?.name ?? "workspace")?", isPresented: $showDeleteConfirmation) {
            TextField("Type 'delete' to confirm", text: $deleteConfirmationText)
            Button("Delete", role: .destructive) {
                Task { await deleteWorkspace() }
            }
            .disabled(deleteConfirmationText.lowercased() != "delete")
            Button("Cancel", role: .cancel) {
                deleteConfirmationText = ""
            }
        } message: {
            Text("This will permanently delete all data in this workspace. This action cannot be undone.")
        }
        .alert("Error", isPresented: $showOperationError) {
            Button("OK", role: .cancel) {
                operationError = nil
            }
        } message: {
            Text(operationError ?? "An error occurred")
        }
    }

    private var filteredMembers: [TeamMember] {
        if memberSearchText.isEmpty {
            return teamMembers
        }
        return teamMembers.filter { member in
            member.name.localizedCaseInsensitiveContains(memberSearchText) ||
            member.email.localizedCaseInsensitiveContains(memberSearchText)
        }
    }

    private func teamMemberRow(member: TeamMember) -> some View {
        HStack(spacing: 12) {
            // Avatar
            if let imageUrl = member.imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: memberAvatarPlaceholder(name: member.name)
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            } else {
                memberAvatarPlaceholder(name: member.name)
            }

            // Name and email
            VStack(alignment: .leading, spacing: 2) {
                Text(member.name)
                    .font(.system(size: 14, weight: .medium))
                Text(member.email)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Role badge
            Text(member.isAdmin ? "Admin" : "Member")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(member.isAdmin ? .orange : .secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(member.isAdmin ? Color.orange.opacity(0.15) : Color.gray.opacity(0.1))
                )

            // Actions menu (admin only, can't remove self)
            if auth.currentOrg?.isAdmin == true {
                Menu {
                    // Compare member email to current user email (not org ID)
                    if member.email != auth.userEmail {
                        Button(role: .destructive) {
                            memberToRemove = member
                            showRemoveConfirmation = true
                        } label: {
                            Label("Remove from workspace", systemImage: "person.badge.minus")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton)
                .frame(width: 28)
            }
        }
        .padding(12)
    }

    private func memberAvatarPlaceholder(name: String) -> some View {
        let initial = name.prefix(1).uppercased()
        return ZStack {
            Circle()
                .fill(Color.accentColor.opacity(0.2))
            Text(initial)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.accentColor)
        }
        .frame(width: 36, height: 36)
    }

    private func invitationRow(invitation: TeamInvitation) -> some View {
        HStack(spacing: 12) {
            // Email icon
            ZStack {
                Circle()
                    .fill(Color.blue.opacity(0.1))
                Image(systemName: "envelope")
                    .font(.system(size: 14))
                    .foregroundColor(.blue)
            }
            .frame(width: 36, height: 36)

            // Email and status
            VStack(alignment: .leading, spacing: 2) {
                Text(invitation.emailAddress)
                    .font(.system(size: 14, weight: .medium))
                Text("Invited \(timeAgo(from: invitation.createdAtDate))")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Role badge
            Text(invitation.role == "org:admin" ? "Admin" : "Member")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.gray.opacity(0.1))
                )

            // Revoke button
            Button(action: {
                invitationToRevoke = invitation
                showRevokeConfirmation = true
            }) {
                Text("Revoke")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.red)
            }
            .buttonStyle(.plain)
        }
        .padding(12)
    }

    private var inviteSheet: some View {
        VStack(spacing: 20) {
            Text("Invite to \(auth.currentOrg?.name ?? "Workspace")")
                .font(.system(size: 18, weight: .semibold))

            VStack(alignment: .leading, spacing: 8) {
                Text("Email address")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)

                TextField("teammate@example.com", text: $inviteEmail)
                    .textFieldStyle(.plain)
                    .font(.system(size: 15))
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.black.opacity(0.05))
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Role")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)

                Picker("Role", selection: $inviteRole) {
                    Text("Member").tag("org:member")
                    Text("Admin").tag("org:admin")
                }
                .pickerStyle(.segmented)
            }

            Text("They'll receive an email with a link to join your workspace.")
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Cancel") {
                    showInviteSheet = false
                }
                .buttonStyle(.bordered)

                Button(action: {
                    Task { await sendInvite() }
                }) {
                    HStack {
                        if isInviting {
                            ProgressView()
                                .scaleEffect(0.7)
                                .frame(width: 14, height: 14)
                        }
                        Text("Send Invite")
                    }
                }
                .buttonStyle(.borderedProminent)
                .disabled(inviteEmail.isEmpty || !inviteEmail.contains("@") || isInviting)
            }
        }
        .padding(24)
        .frame(width: 360)
    }

    private var dangerZoneSection: some View {
        VStack(alignment: .leading, spacing: 16) {
            Divider()

            Text("Danger Zone")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(.red)

            VStack(alignment: .leading, spacing: 12) {
                // Leave workspace
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Leave workspace")
                            .font(.system(size: 14, weight: .medium))
                        Text("Remove yourself from this workspace. You'll lose access to all shared meetings and data.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button(action: {
                        showLeaveConfirmation = true
                    }) {
                        if isLeavingOrg {
                            ProgressView()
                                .scaleEffect(0.7)
                        } else {
                            Text("Leave")
                        }
                    }
                    .buttonStyle(.bordered)
                    .disabled(isLeavingOrg)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.red.opacity(0.03))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.red.opacity(0.2), lineWidth: 1)
                        )
                )

                // Delete workspace (admin only)
                if auth.currentOrg?.isAdmin == true {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Delete workspace")
                                .font(.system(size: 14, weight: .medium))
                            Text("Permanently delete this workspace and all its data. This action cannot be undone.")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        Spacer()

                        Button(action: {
                            deleteConfirmationText = ""
                            showDeleteConfirmation = true
                        }) {
                            if isDeletingOrg {
                                ProgressView()
                                    .scaleEffect(0.7)
                            } else {
                                Text("Delete")
                            }
                        }
                        .buttonStyle(.bordered)
                        .tint(.red)
                        .disabled(isDeletingOrg)
                    }
                    .padding(12)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.red.opacity(0.03))
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.red.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
            }
        }
    }

    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Team API Methods

    private func loadTeamData() async {
        isLoadingMembers = true
        defer { isLoadingMembers = false }

        guard let token = AuthManager.shared.accessToken else { return }

        // Load members
        if let membersUrl = URL(string: "\(Config.serverURL)/team/members") {
            var request = URLRequest(url: membersUrl)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let membersData = json["members"] as? [[String: Any]] {
                        teamMembers = membersData.compactMap { memberData -> TeamMember? in
                            guard let id = memberData["id"] as? String,
                                  let userId = memberData["userId"] as? String,
                                  let email = memberData["email"] as? String else { return nil }
                            return TeamMember(
                                id: id,
                                userId: userId,
                                name: memberData["name"] as? String ?? email,
                                email: email,
                                imageUrl: memberData["imageUrl"] as? String,
                                role: memberData["role"] as? String ?? "org:member",
                                joinedAt: memberData["joinedAt"] as? Int ?? 0
                            )
                        }
                    }
                }
            } catch {
                NSLog("[SettingsModalView] Failed to load members: \(error)")
            }
        }

        // Load invitations (admin only)
        if auth.currentOrg?.isAdmin == true {
            if let invitationsUrl = URL(string: "\(Config.serverURL)/team/invitations") {
                var request = URLRequest(url: invitationsUrl)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let invitationsData = json["invitations"] as? [[String: Any]] {
                            teamInvitations = invitationsData.compactMap { invData -> TeamInvitation? in
                                guard let id = invData["id"] as? String,
                                      let email = invData["emailAddress"] as? String else { return nil }
                                return TeamInvitation(
                                    id: id,
                                    emailAddress: email,
                                    role: invData["role"] as? String ?? "org:member",
                                    status: invData["status"] as? String ?? "pending",
                                    createdAt: invData["createdAt"] as? Int ?? 0
                                )
                            }
                        }
                    }
                } catch {
                    NSLog("[SettingsModalView] Failed to load invitations: \(error)")
                }
            }
        }
    }

    private func sendInvite() async {
        isInviting = true
        defer { isInviting = false }

        guard let token = AuthManager.shared.accessToken,
              let url = URL(string: "\(Config.serverURL)/team/invite") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(["email": inviteEmail, "role": inviteRole])

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 201 {
                    showInviteSheet = false
                    inviteEmail = ""
                    await loadTeamData()
                } else if http.statusCode == 409 {
                    operationError = "This email has already been invited."
                    showOperationError = true
                } else if http.statusCode == 403 {
                    operationError = "You don't have permission to invite members."
                    showOperationError = true
                } else {
                    operationError = "Failed to send invitation. Please try again."
                    showOperationError = true
                }
            }
        } catch {
            NSLog("[SettingsModalView] Failed to send invite: \(error)")
            operationError = "Failed to send invitation: \(error.localizedDescription)"
            showOperationError = true
        }
    }

    private func removeMember(_ member: TeamMember) async {
        guard let token = AuthManager.shared.accessToken,
              let url = URL(string: "\(Config.serverURL)/team/members/\(member.userId)") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 204 {
                    await loadTeamData()
                } else if http.statusCode == 403 {
                    operationError = "You don't have permission to remove this member."
                    showOperationError = true
                } else {
                    operationError = "Failed to remove member. Please try again."
                    showOperationError = true
                }
            }
        } catch {
            NSLog("[SettingsModalView] Failed to remove member: \(error)")
            operationError = "Failed to remove member: \(error.localizedDescription)"
            showOperationError = true
        }
    }

    private func revokeInvitation(_ invitation: TeamInvitation) async {
        guard let token = AuthManager.shared.accessToken,
              let url = URL(string: "\(Config.serverURL)/team/invitations/\(invitation.id)/revoke") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse {
                if http.statusCode == 204 {
                    await loadTeamData()
                } else if http.statusCode == 403 {
                    operationError = "You don't have permission to revoke this invitation."
                    showOperationError = true
                } else {
                    operationError = "Failed to revoke invitation. Please try again."
                    showOperationError = true
                }
            }
        } catch {
            NSLog("[SettingsModalView] Failed to revoke invitation: \(error)")
            operationError = "Failed to revoke invitation: \(error.localizedDescription)"
            showOperationError = true
        }
    }

    private func leaveWorkspace() async {
        isLeavingOrg = true
        defer { isLeavingOrg = false }

        do {
            try await AuthManager.shared.leaveOrganization()
            onClose()
        } catch {
            NSLog("[SettingsModalView] Failed to leave workspace: \(error)")
            operationError = "Failed to leave workspace: \(error.localizedDescription)"
            showOperationError = true
        }
    }

    private func deleteWorkspace() async {
        isDeletingOrg = true
        defer { isDeletingOrg = false }

        do {
            try await AuthManager.shared.deleteOrganization()
            onClose()
        } catch {
            NSLog("[SettingsModalView] Failed to delete workspace: \(error)")
            operationError = "Failed to delete workspace: \(error.localizedDescription)"
            showOperationError = true
        }
    }

    // MARK: - Billing Pane

    private var billingPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            // Header with manage button
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Billing")
                        .font(.system(size: 20, weight: .semibold))

                    Text("View and manage your subscription, payment methods, and billing history.")
                        .font(.system(size: 14))
                        .foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button(action: {
                    // Open Stripe billing portal or your billing URL
                    if let url = URL(string: "\(Config.serverURL)/billing/portal") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 6) {
                        Text("Manage")
                            .font(.system(size: 13, weight: .medium))
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.regular)
            }

            Spacer()
        }
    }

    // MARK: - Dictation History Pane

    @State private var dictations: [MessageModel] = []
    @State private var copiedDictationId: UUID?
    @State private var hoveredDictationId: UUID?
    @State private var showingRawId: UUID?
    @State private var feedbackMessage: MessageModel?
    @State private var feedbackText: String = ""

    private struct DictationSection: Identifiable {
        var id: String { title }
        let title: String
        let messages: [MessageModel]
    }

    private var dictationSections: [DictationSection] {
        let grouped = Dictionary(grouping: dictations) { sectionTitle(for: $0.createdAt) }
        let sections = grouped.map { key, messages -> DictationSection in
            DictationSection(
                title: key,
                messages: messages.sorted { $0.createdAt > $1.createdAt }
            )
        }
        return sections.sorted { lhs, rhs in
            guard let lhsDate = lhs.messages.first?.createdAt,
                let rhsDate = rhs.messages.first?.createdAt
            else { return false }
            return lhsDate > rhsDate
        }
    }

    private func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            return "Today"
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }

    private var dictationHistoryPane: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Your recent voice dictations. Click any item to copy it.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                if dictations.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "text.bubble")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary.opacity(0.5))

                        Text("No dictations yet")
                            .font(.system(size: 14, weight: .medium))

                        Text("Hold Fn to start dictating")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    LazyVStack(alignment: .leading, spacing: 16) {
                        ForEach(dictationSections) { section in
                            VStack(alignment: .leading, spacing: 6) {
                                Text(section.title)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundColor(.secondary)

                                VStack(spacing: 2) {
                                    ForEach(section.messages) { message in
                                        dictationRow(message)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .onAppear {
                loadDictationHistory()
            }

            // Feedback modal overlay
            if feedbackMessage != nil {
                dictationFeedbackModal
            }
        }
    }

    private func dictationRow(_ message: MessageModel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            // Timestamp
            Text(dictationTime(message.createdAt))
                .font(.system(size: 12))
                .foregroundColor(.secondary)
                .frame(width: 55, alignment: .leading)

            // Content
            VStack(alignment: .leading, spacing: 4) {
                if showingRawId == message.id, let raw = message.rawTranscript {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Raw transcript")
                            .font(.system(size: 9, weight: .medium))
                            .foregroundColor(.orange)
                            .textCase(.uppercase)
                        Text(raw)
                            .font(.system(size: 13))
                            .foregroundColor(.primary.opacity(0.8))
                    }
                } else {
                    Text(message.content)
                        .font(.system(size: 13))
                        .foregroundColor(.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Action buttons
            HStack(spacing: 6) {
                // Copy button
                Button {
                    copyDictation(message, copyRaw: showingRawId == message.id)
                } label: {
                    Group {
                        if copiedDictationId == message.id {
                            Image(systemName: "checkmark")
                                .foregroundColor(.green)
                        } else {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(hoveredDictationId == message.id ? .primary : .secondary.opacity(0.5))
                        }
                    }
                    .font(.system(size: 11))
                    .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help("Copy to clipboard")

                // Raw transcript toggle
                if message.rawTranscript != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showingRawId = showingRawId == message.id ? nil : message.id
                        }
                    } label: {
                        Image(systemName: showingRawId == message.id ? "text.badge.checkmark" : "text.badge.minus")
                            .font(.system(size: 11))
                            .foregroundColor(showingRawId == message.id ? .orange : (hoveredDictationId == message.id ? .primary : .secondary.opacity(0.5)))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain)
                    .help(showingRawId == message.id ? "Show AI formatted" : "View raw transcript")
                }

                // Flag button
                Button {
                    feedbackText = ""
                    feedbackMessage = message
                } label: {
                    Image(systemName: message.flaggedAt != nil ? "flag.fill" : "flag")
                        .font(.system(size: 11))
                        .foregroundColor(message.flaggedAt != nil ? .orange : (hoveredDictationId == message.id ? .primary : .secondary.opacity(0.5)))
                        .frame(width: 20, height: 20)
                }
                .buttonStyle(.plain)
                .help(message.flaggedAt != nil ? "Already flagged" : "Report formatting issue")
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hoveredDictationId == message.id ? Color.black.opacity(0.05) : Color.clear)
        )
        .onHover { hovering in
            hoveredDictationId = hovering ? message.id : nil
        }
    }

    private var dictationFeedbackModal: some View {
        ZStack {
            Color.black.opacity(0.4)
                .onTapGesture { feedbackMessage = nil }

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Report Formatting Issue")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Button { feedbackMessage = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                if let message = feedbackMessage {
                    if let raw = message.rawTranscript, raw != message.content {
                        VStack(alignment: .leading, spacing: 10) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("Raw transcript")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                Text(raw)
                                    .font(.system(size: 12))
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.08)))
                            }

                            VStack(alignment: .leading, spacing: 3) {
                                Text("AI formatted")
                                    .font(.system(size: 10, weight: .medium))
                                    .foregroundColor(.secondary)
                                    .textCase(.uppercase)
                                Text(message.content)
                                    .font(.system(size: 12))
                                    .padding(8)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(RoundedRectangle(cornerRadius: 6).fill(Color.blue.opacity(0.08)))
                            }
                        }
                    } else {
                        Text(message.content)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(3)
                    }
                }

                Text("What should it have been?")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)

                TextEditor(text: $feedbackText)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(height: 80)
                    .background(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3), lineWidth: 1))

                HStack {
                    Spacer()
                    Button {
                        sendDictationFeedback()
                    } label: {
                        Text("Send Feedback")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.accentColor))
                    }
                    .buttonStyle(.plain)
                    .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                    Spacer()
                }
            }
            .padding(20)
            .frame(width: 420)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.windowBackgroundColor)))
            .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
        }
    }

    private func copyDictation(_ message: MessageModel, copyRaw: Bool = false) {
        let textToCopy = copyRaw ? (message.rawTranscript ?? message.content) : message.content
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(textToCopy, forType: .string)
        withAnimation { copiedDictationId = message.id }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            withAnimation {
                if copiedDictationId == message.id { copiedDictationId = nil }
            }
        }
    }

    private func sendDictationFeedback() {
        guard let message = feedbackMessage else { return }
        History.shared.toggleMessageFlag(messageId: message.id)
        PostHogSDK.shared.capture(
            "dictation_feedback_submitted",
            properties: [
                "message_id": message.id.uuidString,
                "raw_transcript": message.rawTranscript ?? "",
                "formatted_text": message.content,
                "user_feedback": feedbackText,
                "created_at": ISO8601DateFormatter().string(from: message.createdAt),
            ])
        feedbackMessage = nil
        feedbackText = ""
        loadDictationHistory()
    }

    private func loadDictationHistory() {
        let thread = History.shared.upsertThread(title: "Quick Dictations")
        dictations = History.shared.listMessages(threadId: thread.id).reversed()
    }

    private func dictationTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    // MARK: - Agent Memories Pane

    @State private var memories: [AgentMemory] = []
    @State private var isLoadingMemories = false
    @State private var memoriesError: String?
    @State private var editingMemory: AgentMemory?
    @State private var editMemoryText: String = ""
    @State private var hoveredMemoryId: String?
    @State private var deletingMemoryId: String?

    private var agentMemoriesPane: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 20) {
                Text("Facts the agent has learned about you and your contacts.")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)

                if isLoadingMemories && memories.isEmpty {
                    VStack(spacing: 12) {
                        ProgressView()
                            .scaleEffect(0.8)
                        Text("Loading memories...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else if let error = memoriesError {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 28))
                            .foregroundColor(.orange)

                        Text("Failed to load memories")
                            .font(.system(size: 14, weight: .medium))

                        Text(error)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)

                        Button("Try Again") {
                            loadAgentMemories()
                        }
                        .buttonStyle(.bordered)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else if memories.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "brain.head.profile")
                            .font(.system(size: 28))
                            .foregroundColor(.secondary.opacity(0.5))

                        Text("No memories yet")
                            .font(.system(size: 14, weight: .medium))

                        Text("The agent will remember facts as you interact with it")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
                } else {
                    VStack(spacing: 2) {
                        ForEach(memories) { memory in
                            memoryRow(memory)
                        }
                    }
                }
            }
            .onAppear {
                loadAgentMemories()
            }

            // Edit modal overlay
            if editingMemory != nil {
                memoryEditModal
            }
        }
    }

    private var memoryEditModal: some View {
        ZStack {
            Color.black.opacity(0.4)
                .onTapGesture { editingMemory = nil }

            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Text("Edit Memory")
                        .font(.system(size: 16, weight: .semibold))
                    Spacer()
                    Button { editingMemory = nil } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }

                TextEditor(text: $editMemoryText)
                    .font(.system(size: 13))
                    .scrollContentBackground(.hidden)
                    .padding(10)
                    .frame(height: 80)
                    .background(RoundedRectangle(cornerRadius: 8).stroke(Color.secondary.opacity(0.3), lineWidth: 1))

                HStack {
                    Button("Cancel") { editingMemory = nil }
                        .buttonStyle(.plain)
                        .foregroundColor(.secondary)

                    Spacer()

                    Button {
                        saveMemoryEdit()
                    } label: {
                        Text("Save")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.white)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Capsule().fill(Color.accentColor))
                    }
                    .buttonStyle(.plain)
                    .disabled(editMemoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .opacity(editMemoryText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
                }
            }
            .padding(20)
            .frame(width: 380)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(NSColor.windowBackgroundColor)))
            .shadow(color: .black.opacity(0.25), radius: 16, y: 8)
        }
    }

    private func memoryRow(_ memory: AgentMemory) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "lightbulb.fill")
                .font(.system(size: 12))
                .foregroundColor(.yellow.opacity(0.8))
                .frame(width: 20)

            Text(memory.content)
                .font(.system(size: 13))
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)

            if let date = memory.createdAtDate {
                Text(memoryDate(date))
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            HStack(spacing: 6) {
                Button {
                    editMemoryText = memory.content
                    editingMemory = memory
                } label: {
                    Image(systemName: "pencil")
                        .font(.system(size: 11))
                        .foregroundColor(hoveredMemoryId == memory.id ? .primary : .secondary.opacity(0.5))
                }
                .buttonStyle(.plain)

                Button {
                    deleteAgentMemory(memory)
                } label: {
                    if deletingMemoryId == memory.id {
                        ProgressView()
                            .scaleEffect(0.4)
                            .frame(width: 16, height: 16)
                    } else {
                        Image(systemName: "trash")
                            .font(.system(size: 11))
                            .foregroundColor(hoveredMemoryId == memory.id ? .red.opacity(0.8) : .secondary.opacity(0.5))
                    }
                }
                .buttonStyle(.plain)
                .disabled(deletingMemoryId == memory.id)
            }
            .frame(width: 50)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(hoveredMemoryId == memory.id ? Color.black.opacity(0.05) : Color.clear)
        )
        .onHover { hovering in
            hoveredMemoryId = hovering ? memory.id : nil
        }
    }

    private func loadAgentMemories() {
        isLoadingMemories = true
        memoriesError = nil

        Task {
            do {
                memories = try await MemoriesAPI.shared.listMemories()
                isLoadingMemories = false
            } catch {
                memoriesError = error.localizedDescription
                isLoadingMemories = false
            }
        }
    }

    private func deleteAgentMemory(_ memory: AgentMemory) {
        deletingMemoryId = memory.id

        Task {
            do {
                try await MemoriesAPI.shared.deleteMemory(id: memory.id)
                withAnimation {
                    memories.removeAll { $0.id == memory.id }
                }
            } catch {
                NSLog("[Settings] Failed to delete memory: \(error)")
            }
            deletingMemoryId = nil
        }
    }

    private func saveMemoryEdit() {
        guard let memory = editingMemory else { return }
        let newContent = editMemoryText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !newContent.isEmpty else { return }

        Task {
            do {
                try await MemoriesAPI.shared.updateMemory(id: memory.id, content: newContent)
                if let index = memories.firstIndex(where: { $0.id == memory.id }) {
                    memories[index].content = newContent
                }
                editingMemory = nil
            } catch {
                NSLog("[Settings] Failed to update memory: \(error)")
            }
        }
    }

    private func memoryDate(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) {
            let formatter = DateFormatter()
            formatter.dateFormat = "h:mm a"
            return formatter.string(from: date)
        } else if calendar.isDateInYesterday(date) {
            return "Yesterday"
        } else {
            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d"
            return formatter.string(from: date)
        }
    }

    // MARK: - Form Components

    private func formField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            Text(value)
                .font(.system(size: 14))
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.black.opacity(0.05))
                )
        }
    }

    private func formFieldWithAction(
        title: String,
        subtitle: String,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
        }
    }

    private func formFieldDropdown(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            HStack {
                Text(value)
                    .font(.system(size: 14))
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.black.opacity(0.05))
            )
        }
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Toggle("", isOn: isOn)
                .toggleStyle(.switch)
                .labelsHidden()
        }
    }

    private func memberRow(
        imageURL: URL?,
        name: String,
        email: String,
        role: String,
        isCurrentUser: Bool
    ) -> some View {
        HStack(spacing: 12) {
            // Avatar
            if let url = imageURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: Color.gray.opacity(0.2)
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.gray.opacity(0.15))
                    .frame(width: 36, height: 36)
                    .overlay(
                        Text(String(name.prefix(1)).uppercased())
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.secondary)
                    )
            }

            // Name and email
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 14, weight: .medium))
                Text(email)
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)
            }

            Spacer()

            // Role dropdown
            Menu {
                Button("Owner") {}
                Button("Admin") {}
                Button("Member") {}
                Divider()
                Button("Remove from workspace", role: .destructive) {}
            } label: {
                HStack(spacing: 6) {
                    Text(role)
                        .font(.system(size: 13))
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .medium))
                }
                .foregroundColor(.primary)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Color.black.opacity(0.05))
                )
            }
            .menuStyle(.borderlessButton)
            .fixedSize()

            // More options
            Menu {
                Button("View profile") {}
                Button("Send message") {}
                Divider()
                Button("Remove from workspace", role: .destructive) {}
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
                    .frame(width: 28, height: 28)
            }
            .menuStyle(.borderlessButton)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 4)
    }
}

// MARK: - Standalone Settings Content View

/// A standalone view for rendering settings content without the modal wrapper.
/// Used when settings is displayed in the main app layout instead of a modal.
@MainActor
struct SettingsContentView: View {
    @Binding var section: SettingsModalView.Section

    @ObservedObject private var ob = OnboardingManager.shared
    @ObservedObject private var auth = AuthManager.shared
    @StateObject private var integrations = IntegrationsManager.shared
    @StateObject private var launchAtLogin = LaunchAtLogin.shared
    @StateObject private var preferences = PreferencesManager.shared

    // Form state - these are initialized in onAppear from their respective sources
    @State private var meetingReminderTime: String = "Before 1m"
    @State private var autoDetectMeetings: Bool = true
    @State private var workspaceName: String = ""
    @State private var companyName: String = ""
    @State private var websiteURL: String = ""
    @State private var briefDescription: String = ""
    @State private var allowedDomains: String = ""
    @State private var memberSearchText: String = ""
    @State private var hasLoadedWorkspaceData = false
    @State private var isSavingWorkspace = false
    @State private var workspaceSaveError: String?

    // Team members state
    @State private var teamMembers: [TeamMember] = []
    @State private var teamInvitations: [TeamInvitation] = []
    @State private var isLoadingMembers = false
    @State private var showInviteSheet = false
    @State private var inviteEmail = ""
    @State private var inviteRole = "org:member"
    @State private var isInviting = false
    @State private var memberToRemove: TeamMember?
    @State private var showRemoveConfirmation = false
    @State private var invitationToRevoke: TeamInvitation?
    @State private var showRevokeConfirmation = false

    // Danger zone state
    @State private var showLeaveConfirmation = false
    @State private var showDeleteConfirmation = false
    @State private var deleteConfirmationText = ""
    @State private var isLeavingOrg = false
    @State private var isDeletingOrg = false

    // Dictation history state
    @State private var dictations: [MessageModel] = []
    @State private var copiedDictationId: UUID?
    @State private var hoveredDictationId: UUID?
    @State private var showingRawId: UUID?
    @State private var feedbackMessage: MessageModel?
    @State private var feedbackText: String = ""

    // Agent memories state
    @State private var memories: [AgentMemory] = []
    @State private var isLoadingMemories = false
    @State private var memoriesError: String?
    @State private var editingMemory: AgentMemory?
    @State private var editMemoryText: String = ""
    @State private var hoveredMemoryId: String?
    @State private var deletingMemoryId: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                switch section {
                case .myAccount: myAccountPane
                case .preferences: preferencesPane
                case .dictationHistory: dictationHistoryPane
                case .agentMemories: agentMemoriesPane
                case .general: generalPane
                case .members: membersPane
                case .billing: billingPane
                }
                Spacer(minLength: 0)
            }
            .padding(28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            ob.refresh()
            loadWorkspaceData()
            // Load preferences from PreferencesManager
            meetingReminderTime = preferences.meetingReminderTime
            autoDetectMeetings = preferences.autoDetectMeetings
        }
    }

    private func loadWorkspaceData() {
        guard !hasLoadedWorkspaceData else { return }
        hasLoadedWorkspaceData = true

        // Load from auth manager
        workspaceName = auth.currentOrg?.name ?? ""

        // TODO: Load company details from server when API is available
        // For now, these remain empty until we have an endpoint
    }

    private func setMeetingReminderTime(_ time: String) {
        meetingReminderTime = time
        preferences.meetingReminderTime = time
    }

    private var userRoleDisplayName: String {
        guard let role = auth.currentOrg?.role else { return "Member" }
        switch role {
        case "org:admin": return "Admin"
        case "org:member": return "Member"
        default: return role.replacingOccurrences(of: "org:", with: "").capitalized
        }
    }

    // MARK: - My Account Pane

    private var googleRequiresReauth: Bool {
        integrations.googleStatus?.requiresReauth == true
    }

    private var myAccountPane: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top, spacing: 20) {
                if let url = auth.userImageURL {
                    AsyncImage(url: url) { phase in
                        switch phase {
                        case .success(let image): image.resizable().scaledToFill()
                        default: Color.gray.opacity(0.2)
                        }
                    }
                    .frame(width: 80, height: 100)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    RoundedRectangle(cornerRadius: 12)
                        .fill(Color.gray.opacity(0.15))
                        .frame(width: 80, height: 100)
                        .overlay(
                            Image(systemName: "person.fill")
                                .font(.system(size: 28))
                                .foregroundColor(.secondary)
                        )
                }

                VStack(alignment: .leading, spacing: 16) {
                    formField(label: "Full name", value: auth.userName ?? "—")
                    formField(label: "Role", value: userRoleDisplayName)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 16) {
                Text("Danger zone")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Delete account")
                            .font(.system(size: 14, weight: .medium))
                        Text("Delete your account and detach from all workspaces. This action cannot be undone.")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(action: {}) {
                        Text("Delete my account")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(.red)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.red.opacity(0.5), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private var googleCalendarCard: some View {
        HStack(spacing: 16) {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(googleRequiresReauth ? Color.orange.opacity(0.15) : Color(red: 0.2, green: 0.5, blue: 0.3))
                    Image(systemName: googleRequiresReauth ? "exclamationmark.triangle.fill" : "calendar.badge.clock")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(googleRequiresReauth ? .orange : .white)
                }
                .frame(width: 48, height: 48)

                if googleRequiresReauth {
                    HStack(spacing: 4) {
                        Image(systemName: "exclamationmark.circle.fill").font(.system(size: 9, weight: .bold))
                        Text("Reauth needed").font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.orange)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.orange.opacity(0.15)))
                } else if let status = integrations.googleStatus, status.connected {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                        Text("Synced").font(.system(size: 10, weight: .medium))
                    }
                    .foregroundColor(.green)
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(Capsule().fill(Color.green.opacity(0.15)))
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Google Calendar").font(.system(size: 14, weight: .semibold))
                if googleRequiresReauth {
                    Text("Connection expired — tap Reconnect").font(.system(size: 12)).foregroundColor(.orange)
                } else if let status = integrations.googleStatus, status.connected {
                    Text("Calendar events sync and meeting data").font(.system(size: 12)).foregroundColor(.secondary)
                } else {
                    Text("Connect to sync calendar events").font(.system(size: 12)).foregroundColor(.secondary)
                }
            }

            Spacer()

            if googleRequiresReauth {
                Button("Reconnect") { Task { await integrations.connectGoogle() } }
                    .buttonStyle(.borderedProminent).tint(.orange).controlSize(.small)
            } else if let status = integrations.googleStatus, status.connected {
                Button("Disconnect") { Task { await integrations.disconnectGoogle() } }
                    .buttonStyle(.bordered).controlSize(.small)
            } else {
                Button("Connect") { Task { await integrations.connectGoogle() } }
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(googleRequiresReauth ? Color.orange.opacity(0.05) : Color.black.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(googleRequiresReauth ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Preferences Pane

    private var preferencesPane: some View {
        VStack(alignment: .leading, spacing: 28) {
            toggleRow(title: "Launch when system starts",
                      subtitle: "This will launch Toss automatically when your system starts.",
                      isOn: $launchAtLogin.isEnabled)

            toggleRow(title: "Hide pill when idle",
                      subtitle: "Hide the floating pill when not recording or transcribing.",
                      isOn: $preferences.hideIdlePill)

            Divider()

            VStack(alignment: .leading, spacing: 20) {
                Text("Recording").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Remind me before meetings").font(.system(size: 14, weight: .medium))
                        Text("Show notifications before the start of meetings on your calendar")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Menu {
                        Button("Before 1m") { setMeetingReminderTime("Before 1m") }
                        Button("Before 5m") { setMeetingReminderTime("Before 5m") }
                        Button("Before 10m") { setMeetingReminderTime("Before 10m") }
                        Button("Before 15m") { setMeetingReminderTime("Before 15m") }
                        Divider()
                        Button("Off") { setMeetingReminderTime("Off") }
                    } label: {
                        HStack(spacing: 6) {
                            Text(meetingReminderTime).font(.system(size: 13))
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.05)))
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }

                toggleRow(title: "Auto-detect meetings",
                          subtitle: "Show notifications when a call is detected (Determined by microphone usage).",
                          isOn: Binding(
                              get: { autoDetectMeetings },
                              set: { newValue in
                                  autoDetectMeetings = newValue
                                  preferences.autoDetectMeetings = newValue
                              }
                          ))
            }

            Divider()

            // Keyboard Shortcuts section
            VStack(alignment: .leading, spacing: 20) {
                Text("Keyboard Shortcuts").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)

                // Dictation shortcut
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Dictation").font(.system(size: 14, weight: .medium))
                        Text("Start dictation from anywhere on your desktop")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Menu {
                        Button("Hold Fn (Globe)") { preferences.dictationShortcut = .enabled }
                        Divider()
                        Button("No shortcut") { preferences.dictationShortcut = .disabled }
                    } label: {
                        HStack(spacing: 6) {
                            Text(preferences.dictationShortcut.displayName).font(.system(size: 13))
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.05)))
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }

                // Agent mode shortcut
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Agent mode").font(.system(size: 14, weight: .medium))
                        Text("Talk to Toss agent from anywhere on your desktop")
                            .font(.system(size: 12)).foregroundColor(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Menu {
                        Button("Hold Fn + \u{2318}") { preferences.agentModeShortcut = .enabled }
                        Divider()
                        Button("No shortcut") { preferences.agentModeShortcut = .disabled }
                    } label: {
                        HStack(spacing: 6) {
                            Text(preferences.agentModeShortcut.agentModeDisplayName).font(.system(size: 13))
                            Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.primary)
                        .padding(.horizontal, 12).padding(.vertical, 8)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.05)))
                    }
                    .menuStyle(.borderlessButton).fixedSize()
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 20) {
                Text("Permissions").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)

                formFieldWithAction(title: "Microphone",
                                    subtitle: ob.micGranted ? "Allowed" : "Required for dictation",
                                    actionTitle: ob.micGranted ? "Change" : "Allow") {
                    if ob.micGranted { ob.openMicSettings() } else { ob.requestMic() }
                }

                formFieldWithAction(title: "Accessibility",
                                    subtitle: ob.axGranted ? "Allowed" : "Required for pasting",
                                    actionTitle: ob.axGranted ? "Open Settings" : "Allow…") {
                    if ob.axGranted { ob.openAXSettings() } else { ob.requestAX(); ob.openAXSettings() }
                }
            }
        }
    }

    // MARK: - Dictation History Pane

    // MARK: - Dictation Section

    private struct DictationSection: Identifiable {
        var id: String { title }
        let title: String
        let messages: [MessageModel]
    }

    private var dictationSections: [DictationSection] {
        let grouped = Dictionary(grouping: dictations) { sectionTitle(for: $0.createdAt) }
        let sections = grouped.map { key, messages -> DictationSection in
            DictationSection(title: key, messages: messages.sorted { $0.createdAt > $1.createdAt })
        }
        return sections.sorted { lhs, rhs in
            guard let lhsDate = lhs.messages.first?.createdAt,
                  let rhsDate = rhs.messages.first?.createdAt
            else { return false }
            return lhsDate > rhsDate
        }
    }

    private func sectionTitle(for date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        else if calendar.isDateInYesterday(date) { return "Yesterday" }
        else {
            let formatter = DateFormatter()
            formatter.dateFormat = "EEEE, MMM d"
            return formatter.string(from: date)
        }
    }

    private var dictationHistoryPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Your recent voice dictations. Click any item to copy it.")
                .font(.system(size: 14)).foregroundColor(.secondary)

            if dictations.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "text.bubble").font(.system(size: 28)).foregroundColor(.secondary.opacity(0.5))
                    Text("No dictations yet").font(.system(size: 14, weight: .medium))
                    Text("Hold Fn to start dictating").font(.system(size: 12)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(dictationSections) { section in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(section.title)
                                .font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)

                            VStack(spacing: 2) {
                                ForEach(section.messages) { message in
                                    dictationRow(message)
                                }
                            }
                        }
                    }
                }
            }
        }
        .onAppear { loadDictationHistory() }
    }

    private func dictationRow(_ message: MessageModel) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text(dictationTime(message.createdAt))
                .font(.system(size: 12)).foregroundColor(.secondary)
                .frame(width: 55, alignment: .leading)

            VStack(alignment: .leading, spacing: 4) {
                if showingRawId == message.id, let raw = message.rawTranscript {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Raw transcript").font(.system(size: 9, weight: .medium)).foregroundColor(.orange).textCase(.uppercase)
                        Text(raw).font(.system(size: 13)).foregroundColor(.primary.opacity(0.8))
                    }
                } else {
                    Text(message.content).font(.system(size: 13)).foregroundColor(.primary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                Button {
                    copyDictation(message, copyRaw: showingRawId == message.id)
                } label: {
                    Group {
                        if copiedDictationId == message.id {
                            Image(systemName: "checkmark").foregroundColor(.green)
                        } else {
                            Image(systemName: "doc.on.doc")
                                .foregroundColor(hoveredDictationId == message.id ? .primary : .secondary.opacity(0.5))
                        }
                    }
                    .font(.system(size: 11)).frame(width: 20, height: 20)
                }
                .buttonStyle(.plain).help("Copy to clipboard")

                if message.rawTranscript != nil {
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            showingRawId = showingRawId == message.id ? nil : message.id
                        }
                    } label: {
                        Image(systemName: showingRawId == message.id ? "text.quote" : "arrow.uturn.left")
                            .font(.system(size: 11))
                            .foregroundColor(showingRawId == message.id ? .orange : .secondary.opacity(0.5))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain).help(showingRawId == message.id ? "Show corrected" : "Show raw")
                }
            }
            .opacity(hoveredDictationId == message.id || copiedDictationId == message.id || showingRawId == message.id ? 1 : 0)
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 8).fill(hoveredDictationId == message.id ? Color.black.opacity(0.04) : Color.clear))
        .onHover { hovering in hoveredDictationId = hovering ? message.id : nil }
    }

    private func copyDictation(_ message: MessageModel, copyRaw: Bool = false) {
        let text = copyRaw ? (message.rawTranscript ?? message.content) : message.content
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
        copiedDictationId = message.id
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
            if copiedDictationId == message.id { copiedDictationId = nil }
        }
    }

    private func dictationTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "h:mm a"
        return formatter.string(from: date)
    }

    private func loadDictationHistory() {
        let thread = History.shared.upsertThread(title: "Quick Dictations")
        dictations = History.shared.listMessages(threadId: thread.id).reversed()
    }

    // MARK: - Agent Memories Pane

    private var agentMemoriesPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Facts the agent has learned about you and your contacts.")
                .font(.system(size: 14)).foregroundColor(.secondary)

            if isLoadingMemories && memories.isEmpty {
                VStack(spacing: 12) {
                    ProgressView().scaleEffect(0.8)
                    Text("Loading memories...").font(.system(size: 12)).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else if let error = memoriesError {
                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.triangle").font(.system(size: 28)).foregroundColor(.orange)
                    Text("Failed to load memories").font(.system(size: 14, weight: .medium))
                    Text(error).font(.system(size: 12)).foregroundColor(.secondary)
                    Button("Retry") { loadAgentMemories() }.buttonStyle(.bordered)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else if memories.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "brain.head.profile").font(.system(size: 28)).foregroundColor(.secondary.opacity(0.5))
                    Text("No memories yet").font(.system(size: 14, weight: .medium))
                    Text("The agent will remember facts as you interact with it")
                        .font(.system(size: 12)).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                LazyVStack(alignment: .leading, spacing: 8) {
                    ForEach(memories) { memory in
                        memoryRow(memory)
                    }
                }
            }
        }
        .onAppear { loadAgentMemories() }
    }

    private func memoryRow(_ memory: AgentMemory) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "brain").font(.system(size: 12)).foregroundColor(.secondary).padding(.top, 2)

            if editingMemory?.id == memory.id {
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Memory", text: $editMemoryText, axis: .vertical)
                        .textFieldStyle(.plain).font(.system(size: 13))
                        .padding(8).background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.05)))

                    HStack(spacing: 8) {
                        Button("Cancel") {
                            editingMemory = nil
                            editMemoryText = ""
                        }
                        .buttonStyle(.bordered).controlSize(.small)

                        Button("Save") {
                            Task {
                                try? await MemoriesAPI.shared.updateMemory(id: memory.id, content: editMemoryText)
                                if let idx = memories.firstIndex(where: { $0.id == memory.id }) {
                                    memories[idx].content = editMemoryText
                                }
                                editingMemory = nil
                                editMemoryText = ""
                            }
                        }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text(memory.content).font(.system(size: 13)).foregroundColor(.primary)
                    if let date = memory.createdAtDate {
                        Text(date, style: .relative).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 6) {
                    Button {
                        editingMemory = memory
                        editMemoryText = memory.content
                    } label: {
                        Image(systemName: "pencil").font(.system(size: 11))
                            .foregroundColor(hoveredMemoryId == memory.id ? .primary : .secondary.opacity(0.5))
                            .frame(width: 20, height: 20)
                    }
                    .buttonStyle(.plain).help("Edit memory")

                    Button {
                        deletingMemoryId = memory.id
                        Task {
                            try? await MemoriesAPI.shared.deleteMemory(id: memory.id)
                            memories.removeAll { $0.id == memory.id }
                            deletingMemoryId = nil
                        }
                    } label: {
                        if deletingMemoryId == memory.id {
                            ProgressView().scaleEffect(0.5).frame(width: 20, height: 20)
                        } else {
                            Image(systemName: "trash").font(.system(size: 11))
                                .foregroundColor(hoveredMemoryId == memory.id ? .red : .secondary.opacity(0.5))
                                .frame(width: 20, height: 20)
                        }
                    }
                    .buttonStyle(.plain).help("Delete memory")
                }
                .opacity(hoveredMemoryId == memory.id || deletingMemoryId == memory.id ? 1 : 0)
            }
        }
        .padding(.vertical, 8).padding(.horizontal, 12)
        .background(RoundedRectangle(cornerRadius: 8).fill(hoveredMemoryId == memory.id ? Color.black.opacity(0.04) : Color.clear))
        .onHover { hovering in if editingMemory == nil { hoveredMemoryId = hovering ? memory.id : nil } }
    }

    private func loadAgentMemories() {
        isLoadingMemories = true
        memoriesError = nil
        Task {
            do {
                memories = try await MemoriesAPI.shared.listMemories()
            } catch {
                memoriesError = error.localizedDescription
            }
            isLoadingMemories = false
        }
    }

    // MARK: - General Pane (Workspace Settings)

    private var generalPane: some View {
        VStack(alignment: .leading, spacing: 28) {
            HStack(alignment: .top, spacing: 20) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.accentColor.opacity(0.2))
                    .frame(width: 80, height: 100)
                    .overlay(Text("T").font(.system(size: 32, weight: .bold)).foregroundColor(.accentColor))

                VStack(alignment: .leading, spacing: 6) {
                    Text("Name").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                    TextField("Workspace name", text: $workspaceName)
                        .textFieldStyle(.plain).font(.system(size: 14))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.05)))
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 20) {
                Text("Company").font(.system(size: 13, weight: .semibold)).foregroundColor(.secondary)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Company name").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                    TextField("Enter company name", text: $companyName)
                        .textFieldStyle(.plain).font(.system(size: 14))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.05)))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Website URL").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                    TextField("https://", text: $websiteURL)
                        .textFieldStyle(.plain).font(.system(size: 14))
                        .padding(.horizontal, 14).padding(.vertical, 10)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.05)))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text("Brief description").font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
                    TextEditor(text: $briefDescription)
                        .font(.system(size: 14)).scrollContentBackground(.hidden)
                        .padding(12).frame(height: 100)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.05)))
                }
            }
        }
    }

    // MARK: - Integrations Pane

    private var integrationsPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Connect your workspace to external services.")
                .font(.system(size: 14)).foregroundColor(.secondary)

            // Google Calendar
            integrationCard(
                icon: "calendar",
                iconColor: Color(red: 0.2, green: 0.5, blue: 0.3),
                name: "Google Calendar",
                description: integrations.googleStatus?.connected == true
                    ? (integrations.googleStatus?.email ?? "Connected")
                    : "Sync calendar events and meeting data",
                isConnected: integrations.googleStatus?.connected == true,
                requiresReauth: integrations.googleStatus?.requiresReauth == true,
                onConnect: { Task { await integrations.connectGoogle() } },
                onDisconnect: { Task { await integrations.disconnectGoogle() } }
            )

            // Slack
            integrationCard(
                icon: "number",
                iconColor: Color(red: 0.91, green: 0.26, blue: 0.42),
                name: "Slack",
                description: integrations.slackStatus?.connected == true
                    ? (integrations.slackStatus?.teamName ?? "Connected")
                    : "Send messages and receive notifications",
                isConnected: integrations.slackStatus?.connected == true,
                requiresReauth: false,
                onConnect: { Task { await integrations.connectSlack() } },
                onDisconnect: { Task { await integrations.disconnectSlack() } }
            )

            // Linear
            integrationCard(
                icon: "square.stack.3d.up",
                iconColor: Color(red: 0.38, green: 0.38, blue: 0.95),
                name: "Linear",
                description: integrations.linearStatus?.connected == true
                    ? (integrations.linearStatus?.organizationName ?? "Connected")
                    : "Create and manage issues",
                isConnected: integrations.linearStatus?.connected == true,
                requiresReauth: integrations.linearStatus?.requiresReauth == true,
                onConnect: { Task { await integrations.connectLinear() } },
                onDisconnect: { Task { await integrations.disconnectLinear() } }
            )

            // Notion
            integrationCard(
                icon: "doc.text",
                iconColor: .primary,
                name: "Notion",
                description: integrations.notionStatus?.connected == true
                    ? (integrations.notionStatus?.workspaceName ?? "Connected")
                    : "Access and search your Notion workspace",
                isConnected: integrations.notionStatus?.connected == true,
                requiresReauth: false,
                onConnect: { Task { await integrations.connectNotion() } },
                onDisconnect: { Task { await integrations.disconnectNotion() } }
            )
        }
        .onAppear {
            Task {
                await integrations.fetchGoogleStatus()
                await integrations.fetchSlackStatus()
                await integrations.fetchLinearStatus()
                await integrations.fetchNotionStatus()
            }
        }
    }

    private func integrationCard(
        icon: String,
        iconColor: Color,
        name: String,
        description: String,
        isConnected: Bool,
        requiresReauth: Bool,
        onConnect: @escaping () -> Void,
        onDisconnect: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(requiresReauth ? Color.orange.opacity(0.15) : (isConnected ? iconColor.opacity(0.15) : Color.gray.opacity(0.1)))
                Image(systemName: requiresReauth ? "exclamationmark.triangle.fill" : icon)
                    .font(.system(size: 20, weight: .medium))
                    .foregroundColor(requiresReauth ? .orange : (isConnected ? iconColor : .secondary))
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(name).font(.system(size: 14, weight: .medium))
                    if isConnected && !requiresReauth {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                            Text("Connected").font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.green)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.green.opacity(0.15)))
                    } else if requiresReauth {
                        HStack(spacing: 4) {
                            Image(systemName: "exclamationmark.circle.fill").font(.system(size: 9, weight: .bold))
                            Text("Reauth").font(.system(size: 10, weight: .medium))
                        }
                        .foregroundColor(.orange)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(Capsule().fill(Color.orange.opacity(0.15)))
                    }
                }
                Text(description).font(.system(size: 12)).foregroundColor(.secondary)
            }

            Spacer()

            if requiresReauth {
                Button("Reconnect", action: onConnect)
                    .buttonStyle(.borderedProminent).tint(.orange).controlSize(.small)
            } else if isConnected {
                Button("Disconnect", action: onDisconnect)
                    .buttonStyle(.bordered).controlSize(.small)
            } else {
                Button("Connect", action: onConnect)
                    .buttonStyle(.borderedProminent).controlSize(.small)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(requiresReauth ? Color.orange.opacity(0.05) : Color.black.opacity(0.03))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(requiresReauth ? Color.orange.opacity(0.3) : Color.clear, lineWidth: 1)
        )
    }

    // MARK: - Members Pane

    private var filteredMembers: [TeamMember] {
        if memberSearchText.isEmpty {
            return teamMembers
        }
        return teamMembers.filter { member in
            member.name.localizedCaseInsensitiveContains(memberSearchText) ||
            member.email.localizedCaseInsensitiveContains(memberSearchText)
        }
    }

    private var membersPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").font(.system(size: 13)).foregroundColor(.secondary)
                    TextField("Search", text: $memberSearchText).textFieldStyle(.plain).font(.system(size: 14))
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.05)))

                Spacer()

                if auth.currentOrg?.isAdmin == true {
                    Button(action: { showInviteSheet = true }) {
                        HStack(spacing: 6) {
                            Image(systemName: "plus").font(.system(size: 12, weight: .semibold))
                            Text("Invite").font(.system(size: 13, weight: .medium))
                        }
                    }
                    .buttonStyle(.borderedProminent).controlSize(.regular)
                }
            }

            Divider()

            if isLoadingMembers {
                HStack { Spacer(); ProgressView().scaleEffect(0.8); Spacer() }.padding(.vertical, 40)
            } else if filteredMembers.isEmpty {
                VStack(spacing: 12) {
                    Image(systemName: "person.3").font(.system(size: 28)).foregroundColor(.secondary.opacity(0.5))
                    Text("No members found").font(.system(size: 14, weight: .medium))
                    if !memberSearchText.isEmpty {
                        Text("Try a different search term").font(.system(size: 12)).foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 40)
            } else {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Members (\(filteredMembers.count))")
                        .font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)

                    VStack(spacing: 0) {
                        ForEach(filteredMembers) { member in
                            teamMemberRow(member: member)
                            if member.id != filteredMembers.last?.id {
                                Divider().padding(.leading, 52)
                            }
                        }
                    }
                    .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.02)))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }

                // Pending invitations (admin only)
                if auth.currentOrg?.isAdmin == true && !teamInvitations.isEmpty {
                    VStack(alignment: .leading, spacing: 16) {
                        Text("Pending Invitations (\(teamInvitations.count))")
                            .font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)

                        VStack(spacing: 0) {
                            ForEach(teamInvitations) { invitation in
                                invitationRow(invitation: invitation)
                                if invitation.id != teamInvitations.last?.id {
                                    Divider().padding(.leading, 52)
                                }
                            }
                        }
                        .background(RoundedRectangle(cornerRadius: 10).fill(Color.black.opacity(0.02)))
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
            }
        }
        .onAppear { Task { await loadTeamData() } }
    }

    private func teamMemberRow(member: TeamMember) -> some View {
        HStack(spacing: 12) {
            if let imageUrl = member.imageUrl, let url = URL(string: imageUrl) {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image): image.resizable().scaledToFill()
                    default: memberAvatarPlaceholder(name: member.name)
                    }
                }
                .frame(width: 36, height: 36)
                .clipShape(Circle())
            } else {
                memberAvatarPlaceholder(name: member.name)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(member.name).font(.system(size: 14, weight: .medium))
                Text(member.email).font(.system(size: 12)).foregroundColor(.secondary)
            }

            Spacer()

            Text(member.isAdmin ? "Admin" : "Member")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(member.isAdmin ? .orange : .secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(member.isAdmin ? Color.orange.opacity(0.15) : Color.gray.opacity(0.1)))

            if auth.currentOrg?.isAdmin == true {
                Menu {
                    if member.userId != auth.currentOrg?.id {
                        Button(role: .destructive) {
                            memberToRemove = member
                            showRemoveConfirmation = true
                        } label: {
                            Label("Remove from workspace", systemImage: "person.badge.minus")
                        }
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 14)).foregroundColor(.secondary)
                        .frame(width: 28, height: 28).contentShape(Rectangle())
                }
                .menuStyle(.borderlessButton).frame(width: 28)
            }
        }
        .padding(12)
    }

    private func memberAvatarPlaceholder(name: String) -> some View {
        let initial = name.prefix(1).uppercased()
        return ZStack {
            Circle().fill(Color.accentColor.opacity(0.2))
            Text(initial).font(.system(size: 14, weight: .semibold)).foregroundColor(.accentColor)
        }
        .frame(width: 36, height: 36)
    }

    private func invitationRow(invitation: TeamInvitation) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(Color.blue.opacity(0.1))
                Image(systemName: "envelope").font(.system(size: 14)).foregroundColor(.blue)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text(invitation.emailAddress).font(.system(size: 14, weight: .medium))
                Text("Invited \(timeAgo(from: invitation.createdAtDate))")
                    .font(.system(size: 12)).foregroundColor(.secondary)
            }

            Spacer()

            Text(invitation.role == "org:admin" ? "Admin" : "Member")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.secondary)
                .padding(.horizontal, 8).padding(.vertical, 4)
                .background(RoundedRectangle(cornerRadius: 4).fill(Color.gray.opacity(0.1)))

            Button(role: .destructive) {
                invitationToRevoke = invitation
                showRevokeConfirmation = true
            } label: {
                Image(systemName: "xmark").font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.borderless)
        }
        .padding(12)
    }

    private func loadTeamData() async {
        isLoadingMembers = true
        defer { isLoadingMembers = false }

        guard let token = AuthManager.shared.accessToken else { return }

        // Load members
        if let membersUrl = URL(string: "\(Config.serverURL)/team/members") {
            var request = URLRequest(url: membersUrl)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            do {
                let (data, response) = try await URLSession.shared.data(for: request)
                if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                    if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                       let membersData = json["members"] as? [[String: Any]] {
                        teamMembers = membersData.compactMap { memberData -> TeamMember? in
                            guard let id = memberData["id"] as? String,
                                  let userId = memberData["userId"] as? String,
                                  let email = memberData["email"] as? String else { return nil }
                            return TeamMember(
                                id: id,
                                userId: userId,
                                name: memberData["name"] as? String ?? email,
                                email: email,
                                imageUrl: memberData["imageUrl"] as? String,
                                role: memberData["role"] as? String ?? "org:member",
                                joinedAt: memberData["joinedAt"] as? Int ?? 0
                            )
                        }
                    }
                }
            } catch {
                NSLog("[SettingsContentView] Failed to load members: \(error)")
            }
        }

        // Load invitations (admin only)
        if auth.currentOrg?.isAdmin == true {
            if let invitationsUrl = URL(string: "\(Config.serverURL)/team/invitations") {
                var request = URLRequest(url: invitationsUrl)
                request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

                do {
                    let (data, response) = try await URLSession.shared.data(for: request)
                    if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let invitationsData = json["invitations"] as? [[String: Any]] {
                            teamInvitations = invitationsData.compactMap { invData -> TeamInvitation? in
                                guard let id = invData["id"] as? String,
                                      let email = invData["emailAddress"] as? String else { return nil }
                                return TeamInvitation(
                                    id: id,
                                    emailAddress: email,
                                    role: invData["role"] as? String ?? "org:member",
                                    status: invData["status"] as? String ?? "pending",
                                    createdAt: invData["createdAt"] as? Int ?? 0
                                )
                            }
                        }
                    }
                } catch {
                    NSLog("[SettingsContentView] Failed to load invitations: \(error)")
                }
            }
        }
    }

    private func timeAgo(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    // MARK: - Billing Pane

    private var billingPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Billing").font(.system(size: 20, weight: .semibold))
                    Text("View and manage your subscription, payment methods, and billing history.")
                        .font(.system(size: 14)).foregroundColor(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer()
                Button(action: {
                    if let url = URL(string: "\(Config.serverURL)/billing/portal") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    HStack(spacing: 6) {
                        Text("Manage").font(.system(size: 13, weight: .medium))
                        Image(systemName: "arrow.up.right").font(.system(size: 11, weight: .semibold))
                    }
                }
                .buttonStyle(.borderedProminent).controlSize(.regular)
            }
            Spacer()
        }
    }

    // MARK: - Form Components

    private func formField(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
            Text(value).font(.system(size: 14))
                .padding(.horizontal, 14).padding(.vertical, 10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.05)))
        }
    }

    private func formFieldDropdown(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundColor(.secondary)
            HStack {
                Text(value).font(.system(size: 14))
                Spacer()
                Image(systemName: "chevron.down").font(.system(size: 10, weight: .medium)).foregroundColor(.secondary)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .background(RoundedRectangle(cornerRadius: 8).fill(Color.black.opacity(0.05)))
        }
    }

    private func formFieldWithAction(title: String, subtitle: String, actionTitle: String, action: @escaping () -> Void) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(subtitle).font(.system(size: 12)).foregroundColor(.secondary)
            }
            Spacer()
            Button(actionTitle, action: action).buttonStyle(.bordered)
        }
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title).font(.system(size: 14, weight: .medium))
                Text(subtitle).font(.system(size: 12)).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer()
            Toggle("", isOn: isOn).toggleStyle(.switch).labelsHidden()
        }
    }
}
