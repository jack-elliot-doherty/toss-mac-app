import SwiftUI

struct CreateFolderView: View {
    let onCreate: (String, FolderAccessType, [String]) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var auth = AuthManager.shared
    @State private var name = ""
    @State private var isTeamVisible = false
    @State private var teamMembers: [WorkspaceMember] = []
    @State private var selectedMemberIds: Set<String> = []
    @State private var isLoadingMembers = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Create folder")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.primaryText)

            TextField("Folder name", text: $name)
                .textFieldStyle(.roundedBorder)

            VStack(alignment: .leading, spacing: 8) {
                Text("Folder visibility")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.secondaryText)

                Menu {
                    Button {
                        isTeamVisible = false
                        Task { await loadMembers() }
                    } label: {
                        if !isTeamVisible {
                            Label("Members only", systemImage: "checkmark")
                        } else {
                            Text("Members only")
                        }
                    }

                    Button {
                        isTeamVisible = true
                    } label: {
                        if isTeamVisible {
                            Label("Everyone at \(teamName)", systemImage: "checkmark")
                        } else {
                            Text("Everyone at \(teamName)")
                        }
                    }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: isTeamVisible ? "person.2" : "lock")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(AppTheme.secondaryText)
                        Text(isTeamVisible ? "Everyone at \(teamName)" : "Members only")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(AppTheme.primaryText)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(AppTheme.secondaryText)
                    }
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color.white.opacity(0.06))
                    )
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
            }

            if !isTeamVisible {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Invite members")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)

                    if isLoadingMembers {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        ScrollView {
                            VStack(spacing: 6) {
                                ForEach(teamMembers) { member in
                                    memberRow(member)
                                }
                            }
                        }
                        .frame(maxHeight: 200)
                    }
                }
            }

            HStack {
                Button("Cancel") {
                    onCancel()
                    dismiss()
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Create") {
                    let accessType: FolderAccessType = isTeamVisible ? .team : .subset
                    onCreate(
                        name.trimmingCharacters(in: .whitespacesAndNewlines),
                        accessType,
                        Array(selectedMemberIds)
                    )
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear {
            if !isTeamVisible {
                Task { await loadMembers() }
            }
        }
    }

    private var canCreate: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if !isTeamVisible {
            return true
        }
        return true
    }

    private func memberRow(_ member: WorkspaceMember) -> some View {
        Button {
            toggleMember(member.userId)
        } label: {
            HStack(spacing: 10) {
                Image(
                    systemName: selectedMemberIds.contains(member.userId)
                        ? "checkmark.circle.fill" : "circle"
                )
                .foregroundColor(
                    selectedMemberIds.contains(member.userId)
                        ? .accentColor : AppTheme.secondaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(member.name)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(AppTheme.primaryText)
                    Text(member.email)
                        .font(.system(size: 11))
                        .foregroundColor(AppTheme.secondaryText)
                }
                Spacer()
            }
            .padding(.vertical, 6)
            .padding(.horizontal, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func toggleMember(_ userId: String) {
        if selectedMemberIds.contains(userId) {
            selectedMemberIds.remove(userId)
        } else {
            selectedMemberIds.insert(userId)
        }
    }

    private func loadMembers() async {
        isLoadingMembers = true
        do {
            teamMembers = try await TeamAPI.shared.fetchMembers()
        } catch {
            NSLog("[CreateFolderView] Failed to load members: %@", error.localizedDescription)
        }
        isLoadingMembers = false
    }

    private var teamName: String {
        auth.currentOrg?.name ?? "your team"
    }
}
