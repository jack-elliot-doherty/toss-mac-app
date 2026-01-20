import SwiftUI

struct CreateFolderView: View {
    let onCreate: (String, FolderAccessType, [String]) -> Void
    let onCancel: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var accessType: FolderAccessType = .private
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

            Picker("Access", selection: $accessType) {
                ForEach(FolderAccessType.allCases, id: \.self) { type in
                    Text(type.label).tag(type)
                }
            }
            .pickerStyle(.segmented)

            if accessType == .subset {
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
                    onCreate(name.trimmingCharacters(in: .whitespacesAndNewlines),
                             accessType,
                             Array(selectedMemberIds))
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canCreate)
            }
        }
        .padding(20)
        .frame(width: 360)
        .onAppear { Task { await loadMembers() } }
        .onChange(of: accessType) { _, newValue in
            if newValue == .subset {
                Task { await loadMembers() }
            } else {
                selectedMemberIds.removeAll()
            }
        }
    }

    private var canCreate: Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return false }
        if accessType == .subset {
            return !selectedMemberIds.isEmpty
        }
        return true
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

    private func loadMembers() async {
        guard accessType == .subset else { return }
        isLoadingMembers = true
        do {
            teamMembers = try await TeamAPI.shared.fetchMembers()
        } catch {
            NSLog("[CreateFolderView] Failed to load members: %@", error.localizedDescription)
        }
        isLoadingMembers = false
    }
}
