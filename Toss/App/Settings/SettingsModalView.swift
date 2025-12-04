import AVFoundation
import SwiftUI

@MainActor
struct SettingsModalView: View {
    enum Section: String, CaseIterable, Identifiable {
        // Account group
        case myAccount, preferences
        // Workspace group
        case general, integrations, members, billing

        var id: String { rawValue }

        var title: String {
            switch self {
            case .myAccount: return "My Account"
            case .preferences: return "Preferences"
            case .general: return "General"
            case .integrations: return "Integrations"
            case .members: return "Members"
            case .billing: return "Billing"
            }
        }

        var icon: String {
            switch self {
            case .myAccount: return "person.crop.circle"
            case .preferences: return "slider.horizontal.3"
            case .general: return "gearshape"
            case .integrations: return "puzzlepiece.extension"
            case .members: return "person.2"
            case .billing: return "creditcard"
            }
        }

        var group: SectionGroup {
            switch self {
            case .myAccount, .preferences: return .account
            case .general, .integrations, .members, .billing: return .workspace
            }
        }
    }

    enum SectionGroup: String, CaseIterable {
        case account, workspace

        var title: String {
            switch self {
            case .account: return "Account"
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
    @State private var meetingReminderTime: String = "Before 1m"
    @State private var autoDetectMeetings: Bool = true
    @State private var workspaceName: String = "My Workspace"
    @State private var companyName: String = ""
    @State private var websiteURL: String = ""
    @State private var briefDescription: String = ""
    @State private var allowedDomains: String = ""
    @State private var memberSearchText: String = ""

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
                        case .general: generalPane
                        case .integrations: integrationsPane
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
            .padding(14)
        }
        .frame(height: 560)
        .onAppear { ob.refresh() }
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
                    formFieldDropdown(label: "Role", value: "Owner")
                }
            }

            Divider()

            // Google Workspace section
            VStack(alignment: .leading, spacing: 16) {
                Text("Google Workspace")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)

                googleCalendarCard
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
        .onAppear {
            Task { await integrations.fetchGoogleStatus() }
        }
    }

    // MARK: - Google Calendar Card

    private var googleCalendarCard: some View {
        HStack(spacing: 16) {
            // Left side: Icon with Synced badge below
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(red: 0.2, green: 0.5, blue: 0.3))  // Green-ish like Google Calendar
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.white)
                }
                .frame(width: 48, height: 48)

                // Synced badge below icon (only when connected)
                if let status = integrations.googleStatus, status.connected {
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

                if let status = integrations.googleStatus, status.connected {
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

            if let status = integrations.googleStatus, status.connected {
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
                .fill(Color.black.opacity(0.03))
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
                        Button("Before 1m") { meetingReminderTime = "Before 1m" }
                        Button("Before 5m") { meetingReminderTime = "Before 5m" }
                        Button("Before 10m") { meetingReminderTime = "Before 10m" }
                        Button("Before 15m") { meetingReminderTime = "Before 15m" }
                        Divider()
                        Button("Off") { meetingReminderTime = "Off" }
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
                    isOn: $autoDetectMeetings
                )
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
                        // TODO: Leave workspace
                    }
                    .buttonStyle(.bordered)
                }

                // Delete workspace
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
                        // TODO: Delete workspace
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
                }
            }
        }
    }

    // MARK: - Integrations Pane

    private var integrationsPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Connect your workspace to external services.")
                .font(.system(size: 14))
                .foregroundColor(.secondary)

            // Google Calendar example (like Aside)
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(Color.gray.opacity(0.1))
                    .frame(width: 48, height: 48)
                    .overlay(
                        Image(systemName: "calendar")
                            .font(.system(size: 20))
                            .foregroundColor(.secondary)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("Google Calendar")
                        .font(.system(size: 14, weight: .medium))
                    Text("Sync calendar events and meeting data")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                }

                Spacer()

                Button("Connect") {
                    // TODO: Connect to Google Calendar
                }
                .buttonStyle(.bordered)
            }
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(0.03))
            )
        }
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

                // Invite button
                Button(action: {
                    // TODO: Invite members
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

            Divider()

            // Members list
            VStack(spacing: 0) {
                memberRow(
                    imageURL: auth.userImageURL,
                    name: auth.userName ?? "You",
                    email: auth.userEmail ?? "",
                    role: "Owner",
                    isCurrentUser: true
                )
            }

            Spacer()

            // Subscribe message
            HStack {
                Spacer()
                Text("Subscribe to add members to this workspace")
                    .font(.system(size: 13))
                    .foregroundColor(.secondary)
                Spacer()
            }
            .padding(.vertical, 20)
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
