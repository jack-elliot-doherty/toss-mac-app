import SwiftUI

// MARK: - Common Email Domains (personal/free providers)

private let personalEmailDomains: Set<String> = [
    "gmail.com", "googlemail.com",
    "outlook.com", "hotmail.com", "live.com", "msn.com",
    "yahoo.com", "yahoo.co.uk", "ymail.com",
    "icloud.com", "me.com", "mac.com",
    "aol.com",
    "protonmail.com", "proton.me",
    "mail.com",
    "zoho.com",
    "gmx.com", "gmx.net",
    "tutanota.com", "tutamail.com",
    "fastmail.com",
    "hey.com",
    "pm.me"
]

// MARK: - Create Workspace View

enum CreateWorkspaceStep {
    case details
    case inviteMembers
}

@MainActor
struct CreateWorkspaceView: View {
    @ObservedObject private var auth = AuthManager.shared

    @State private var currentStep: CreateWorkspaceStep = .details
    @State private var workspaceName: String = ""
    @State private var allowDomainJoin: Bool = true
    @State private var isCreating: Bool = false
    @State private var createdOrgId: String?

    // Invite step state
    @State private var inviteEmails: [String] = ["", ""]
    @State private var isSendingInvites: Bool = false
    @State private var sentInviteCount: Int = 0
    @State private var copiedLink: Bool = false

    let onComplete: () -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack {
            // Background
            Color(NSColor.windowBackgroundColor)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Header with cancel
                HStack {
                    Button(action: onCancel) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundColor(.secondary)
                            .frame(width: 32, height: 32)
                            .background(Circle().fill(Color.black.opacity(0.05)))
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    // Step indicator
                    HStack(spacing: 8) {
                        stepDot(isActive: currentStep == .details, isComplete: currentStep == .inviteMembers)
                        Rectangle()
                            .fill(currentStep == .inviteMembers ? Color.accentColor : Color.gray.opacity(0.3))
                            .frame(width: 24, height: 2)
                        stepDot(isActive: currentStep == .inviteMembers, isComplete: false)
                    }

                    Spacer()

                    // Placeholder for symmetry
                    Color.clear
                        .frame(width: 32, height: 32)
                }
                .padding(.horizontal, 24)
                .padding(.top, 20)

                Spacer()

                // Content
                switch currentStep {
                case .details:
                    detailsStep
                case .inviteMembers:
                    inviteMembersStep
                }

                Spacer()
            }
        }
        .frame(minWidth: 500, minHeight: 500)
        .onAppear {
            // Default workspace name to user's name
            workspaceName = auth.userName ?? ""
        }
    }

    private func stepDot(isActive: Bool, isComplete: Bool) -> some View {
        ZStack {
            Circle()
                .fill(isActive || isComplete ? Color.accentColor : Color.gray.opacity(0.3))
                .frame(width: 10, height: 10)

            if isComplete {
                Image(systemName: "checkmark")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundColor(.white)
            }
        }
    }

    // MARK: - Step 1: Details

    private var detailsStep: some View {
        VStack(spacing: 32) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "building.2")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
            }

            VStack(spacing: 8) {
                Text("Create a workspace")
                    .font(.system(size: 24, weight: .semibold))

                Text("Workspaces let you collaborate with your team")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 20) {
                // Workspace name field
                VStack(alignment: .leading, spacing: 8) {
                    Text("Workspace name")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.secondary)

                    TextField("My Company", text: $workspaceName)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 16))
                }

                // Domain auto-join toggle (only for work emails)
                if let domain = userEmailDomain, !isPersonalEmail {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(isOn: $allowDomainJoin) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Allow anyone with @\(domain) to join")
                                    .font(.system(size: 14, weight: .medium))
                                Text("People with this email domain can automatically join your workspace")
                                    .font(.system(size: 12))
                                    .foregroundColor(.secondary)
                            }
                        }
                        .toggleStyle(.switch)
                    }
                    .padding(14)
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(Color.blue.opacity(0.05))
                    )
                }
            }
            .frame(maxWidth: 360)

            // Continue button
            Button(action: createWorkspace) {
                HStack(spacing: 8) {
                    if isCreating {
                        ProgressView()
                            .scaleEffect(0.8)
                            .frame(width: 16, height: 16)
                    }
                    Text("Continue")
                        .font(.system(size: 15, weight: .medium))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(Color.accentColor)
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(workspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
            .frame(maxWidth: 360)
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Step 2: Invite Members

    private var inviteMembersStep: some View {
        VStack(spacing: 32) {
            // Icon
            ZStack {
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.accentColor.opacity(0.1))
                    .frame(width: 80, height: 80)
                Image(systemName: "person.badge.plus")
                    .font(.system(size: 32))
                    .foregroundColor(.accentColor)
            }

            VStack(spacing: 8) {
                Text("Invite your team")
                    .font(.system(size: 24, weight: .semibold))

                Text("Add teammates to \(workspaceName)")
                    .font(.system(size: 14))
                    .foregroundColor(.secondary)
            }

            VStack(alignment: .leading, spacing: 16) {
                Text("Invite by email")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.secondary)

                VStack(spacing: 10) {
                    ForEach(inviteEmails.indices, id: \.self) { index in
                        TextField("name@company.com", text: Binding(
                            get: { inviteEmails.indices.contains(index) ? inviteEmails[index] : "" },
                            set: { newValue in
                                guard inviteEmails.indices.contains(index) else { return }
                                inviteEmails[index] = newValue
                                // Auto-add new field when typing in the last field
                                if index == inviteEmails.count - 1 && !newValue.isEmpty {
                                    inviteEmails.append("")
                                }
                            }
                        ))
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 15))
                    }
                }

                // Copy invite link button
                Button(action: copyInviteLink) {
                    HStack(spacing: 8) {
                        Image(systemName: copiedLink ? "checkmark" : "link")
                            .font(.system(size: 13, weight: .medium))
                        Text(copiedLink ? "Copied!" : "Copy invite link")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.gray.opacity(0.1))
                    .foregroundColor(copiedLink ? .green : .primary)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .frame(maxWidth: 360)

            HStack(spacing: 16) {
                // Skip button
                Button(action: {
                    completeWizard()
                }) {
                    Text("Skip")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .disabled(isSendingInvites)

                // Send invites button
                Button(action: sendInvites) {
                    HStack(spacing: 8) {
                        if isSendingInvites {
                            ProgressView()
                                .scaleEffect(0.8)
                                .frame(width: 16, height: 16)
                        }
                        Text(validEmailCount > 0 ? "Send invites" : "Send invites")
                            .font(.system(size: 15, weight: .medium))
                    }
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(validEmailCount > 0 ? Color.primary : Color.gray.opacity(0.3))
                    .foregroundColor(validEmailCount > 0 ? Color(NSColor.windowBackgroundColor) : .white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .disabled(validEmailCount == 0 || isSendingInvites)
            }

            // Success message if invites sent
            if sentInviteCount > 0 {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text("\(sentInviteCount) invite\(sentInviteCount == 1 ? "" : "s") sent!")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.green)
                }
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.green.opacity(0.1))
                )
            }
        }
        .padding(.horizontal, 40)
    }

    // MARK: - Helpers

    private var userEmailDomain: String? {
        guard let email = auth.userEmail,
              let atIndex = email.lastIndex(of: "@") else { return nil }
        return String(email[email.index(after: atIndex)...]).lowercased()
    }

    private var isPersonalEmail: Bool {
        guard let domain = userEmailDomain else { return true }
        return personalEmailDomains.contains(domain)
    }

    private func isValidEmail(_ email: String) -> Bool {
        let trimmed = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let emailRegex = "[A-Z0-9a-z._%+-]+@[A-Za-z0-9.-]+\\.[A-Za-z]{2,64}"
        let emailPredicate = NSPredicate(format: "SELF MATCHES %@", emailRegex)
        return emailPredicate.evaluate(with: trimmed)
    }

    private var validEmailCount: Int {
        inviteEmails.filter { isValidEmail($0) }.count
    }

    // MARK: - Actions

    private func createWorkspace() {
        guard !workspaceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }

        isCreating = true
        Task {
            do {
                try await auth.createOrganization(name: workspaceName)
                createdOrgId = auth.currentOrg?.id

                // TODO: If allowDomainJoin is enabled, we'd need a server endpoint to configure this
                // For now, just proceed to invite step

                withAnimation {
                    currentStep = .inviteMembers
                }
            } catch {
                NSLog("[CreateWorkspaceView] Failed to create workspace: \(error)")
            }
            isCreating = false
        }
    }

    private func copyInviteLink() {
        // For now, construct a basic invite URL
        // TODO: Generate actual invite link from server
        if let orgId = auth.currentOrg?.id {
            let inviteUrl = "\(Config.serverURL)/join/\(orgId)"
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(inviteUrl, forType: .string)

            copiedLink = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                copiedLink = false
            }
        }
    }

    private func sendInvites() {
        let validEmails = inviteEmails
            .filter { isValidEmail($0) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

        guard !validEmails.isEmpty else { return }

        isSendingInvites = true
        sentInviteCount = 0

        Task {
            guard let token = auth.accessToken else {
                isSendingInvites = false
                return
            }

            var successCount = 0
            for email in validEmails {
                if let url = URL(string: "\(Config.serverURL)/team/invite") {
                    var request = URLRequest(url: url)
                    request.httpMethod = "POST"
                    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    request.httpBody = try? JSONEncoder().encode(["email": email, "role": "org:member"])

                    do {
                        let (_, response) = try await URLSession.shared.data(for: request)
                        if let http = response as? HTTPURLResponse, http.statusCode == 201 {
                            successCount += 1
                        }
                    } catch {
                        NSLog("[CreateWorkspaceView] Failed to invite \(email): \(error)")
                    }
                }
            }

            sentInviteCount = successCount
            isSendingInvites = false

            // Auto-complete after a short delay to show success
            if successCount > 0 {
                try? await Task.sleep(nanoseconds: 1_500_000_000)
                completeWizard()
            }
        }
    }

    private func completeWizard() {
        onComplete()
    }
}
