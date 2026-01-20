import Foundation

@MainActor
final class FoldersManager: ObservableObject {
    static let shared = FoldersManager()

    @Published private(set) var folders: [Folder] = []
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?

    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleOrgChange),
            name: .organizationChanged,
            object: nil
        )
    }

    @objc private func handleOrgChange() {
        Task { await refresh() }
    }

    func refresh() async {
        isLoading = true
        do {
            folders = try await FoldersAPI.shared.fetchFolders()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
            NSLog("[FoldersManager] Failed to fetch folders: %@", error.localizedDescription)
        }
        isLoading = false
    }

    func createFolder(
        name: String,
        accessType: FolderAccessType,
        memberUserIds: [String]
    ) async throws -> Folder {
        let folder = try await FoldersAPI.shared.createFolder(
            name: name,
            accessType: accessType,
            memberUserIds: memberUserIds
        )
        folders.insert(folder, at: 0)
        return folder
    }

    func updateFolder(
        folderId: String,
        name: String?,
        accessType: FolderAccessType?,
        memberUserIds: [String]?
    ) async throws -> Folder {
        let updated = try await FoldersAPI.shared.updateFolder(
            folderId: folderId,
            name: name,
            accessType: accessType,
            memberUserIds: memberUserIds
        )
        if let index = folders.firstIndex(where: { $0.id == folderId }) {
            folders[index] = updated
        }
        return updated
    }

    func deleteFolder(folderId: String) async throws {
        try await FoldersAPI.shared.deleteFolder(folderId: folderId)
        folders.removeAll { $0.id == folderId }
    }
}
