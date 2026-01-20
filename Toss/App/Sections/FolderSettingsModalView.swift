import SwiftUI

enum FolderSettingsTab: String, CaseIterable {
    case details = "Details"
    case sharing = "Sharing"
    case integrations = "Integrations"
}

struct FolderSettingsModalView: View {
    let folderId: String
    let initialTab: FolderSettingsTab
    let onClose: () -> Void

    @Environment(\.dismiss) private var dismiss
    @StateObject private var foldersManager = FoldersManager.shared
    @ObservedObject private var auth = AuthManager.shared
    @State private var selectedTab: FolderSettingsTab
    @State private var name: String = ""
    @State private var accessType: FolderAccessType = .private
    @State private var isTeamVisible = false
    @State private var teamMembers: [WorkspaceMember] = []
    @State private var selectedMemberIds: Set<String> = []
    @State private var isSaving = false
    @State private var isLoadingMembers = false
    @State private var showDeleteConfirm = false
    @FocusState private var isNameFocused: Bool

    init(folderId: String, initialTab: FolderSettingsTab, onClose: @escaping () -> Void) {
        self.folderId = folderId
        self.initialTab = initialTab
        self.onClose = onClose
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            tabPicker

            Divider()

            switch selectedTab {
            case .details:
                detailsTab
            case .sharing:
                sharingTab
            case .integrations:
                integrationsTab
            }

            Spacer()

            footer
        }
        .padding(20)
        .frame(width: 520, height: 420)
        .onAppear { loadFolder() }
    }

    private var header: some View {
        HStack {
            Text("Folder settings")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.primaryText)
            Spacer()
            Button {
                dismiss()
                onClose()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.secondaryText)
                    .frame(width: 24, height: 24)
            }
            .buttonStyle(.plain)
        }
    }

    private var tabPicker: some View {
        HStack(spacing: 16) {
            ForEach(FolderSettingsTab.allCases, id: \.self) { tab in
                Button {
                    selectedTab = tab
                    if tab == .details {
                        isNameFocused = true
                    }
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 13, weight: selectedTab == tab ? .semibold : .regular))
                        .foregroundColor(selectedTab == tab ? AppTheme.primaryText : AppTheme.secondaryText)
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    private var detailsTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Title")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.secondaryText)

                TextField("Folder name", text: $name)
                    .textFieldStyle(.roundedBorder)
                    .focused($isNameFocused)
            }

            Divider()

            VStack(alignment: .leading, spacing: 10) {
                Text("Delete folder")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(AppTheme.secondaryText)

                Text("Deleting this folder is permanent. Meetings inside the folder are not deleted.")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.secondaryText)

                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Text("Delete folder")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                .tint(.red)
            }
        }
        .alert("Delete folder?", isPresented: $showDeleteConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Delete folder", role: .destructive) {
                Task { await deleteFolder() }
            }
        } message: {
            Text("Deleting this folder is permanent. Meetings inside the folder are not deleted.")
        }
    }

    private var sharingTab: some View {
        VStack(alignment: .leading, spacing: 16) {
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

                Text(isTeamVisible
                     ? "Everyone in \(teamName) can access this folder."
                     : "Only people added to this folder can access it.")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.secondaryText)
            }

            if !isTeamVisible {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Members")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(AppTheme.secondaryText)

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
                        .frame(maxHeight: 180)
                    }
                }
            }
        }
    }

    private var integrationsTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Coming soon")
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(AppTheme.primaryText)
            Text("Folder-specific flows and integrations will appear here.")
                .font(.system(size: 12))
                .foregroundColor(AppTheme.secondaryText)
        }
    }

    private var footer: some View {
        HStack {
            Spacer()
            Button("Close") {
                dismiss()
                onClose()
            }
            .buttonStyle(.plain)

            Button("Save") {
                Task { await saveChanges() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    private func loadFolder() {
        if let folder = foldersManager.folders.first(where: { $0.id == folderId }) {
            name = folder.name
            accessType = folder.accessType
            selectedMemberIds = Set(folder.members)
        }
        isTeamVisible = accessType == .team
        if !isTeamVisible {
            Task { await loadMembers() }
        }
        if initialTab == .details {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                isNameFocused = true
            }
        }
    }

    private func loadMembers() async {
        isLoadingMembers = true
        do {
            teamMembers = try await TeamAPI.shared.fetchMembers()
        } catch {
            NSLog("[FolderSettingsModal] Failed to load members: %@", error.localizedDescription)
        }
        isLoadingMembers = false
    }

    private func saveChanges() async {
        isSaving = true
        do {
            let members = isTeamVisible ? [] : Array(selectedMemberIds)
            let nextAccessType: FolderAccessType = isTeamVisible
                ? .team
                : (members.isEmpty ? .private : .subset)
            _ = try await foldersManager.updateFolder(
                folderId: folderId,
                name: name,
                accessType: nextAccessType,
                memberUserIds: members
            )
        } catch {
            NSLog("[FolderSettingsModal] Failed to save: %@", error.localizedDescription)
        }
        isSaving = false
    }

    private func deleteFolder() async {
        do {
            try await foldersManager.deleteFolder(folderId: folderId)
            dismiss()
            onClose()
        } catch {
            NSLog("[FolderSettingsModal] Failed to delete: %@", error.localizedDescription)
        }
    }

    private func memberRow(_ member: WorkspaceMember) -> some View {
        Button {
            toggleMember(member.userId)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: selectedMemberIds.contains(member.userId) ? "checkmark.circle.fill" : "circle")
                    .foregroundColor(selectedMemberIds.contains(member.userId) ? .accentColor : AppTheme.secondaryText)
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

    private var teamName: String {
        auth.currentOrg?.name ?? "your team"
    }
}
