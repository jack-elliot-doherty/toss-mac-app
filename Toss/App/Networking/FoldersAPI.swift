import Foundation

enum FolderAccessType: String, Codable, CaseIterable {
    case `private`
    case team
    case subset

    var label: String {
        switch self {
        case .private: return "Private"
        case .team: return "Team"
        case .subset: return "Subset"
        }
    }
}

struct Folder: Identifiable, Codable, Equatable {
    let id: String
    let orgId: String
    let name: String
    let createdBy: String
    let accessType: FolderAccessType
    let createdAt: Date
    let updatedAt: Date
    let members: [String]
}

struct FolderSummary: Identifiable, Codable, Equatable {
    let id: String
    let name: String
    let accessType: FolderAccessType
}

struct FolderMeeting: Identifiable, Codable, Equatable {
    let id: String
    let title: String?
    let startedAt: String?
    let endedAt: String?
    let status: String?
    let userId: String?
}

final class FoldersAPI {
    static let shared = FoldersAPI()

    private let baseURL: URL

    init(baseURL: URL = Config.serverBaseURL) {
        self.baseURL = baseURL
    }

    private func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let value = try container.decode(String.self)
            if let date = formatter.date(from: value) {
                return date
            }
            if let date = ISO8601DateFormatter().date(from: value) {
                return date
            }
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid date format: \(value)"
            )
        }
        return decoder
    }

    func fetchFolders() async throws -> [Folder] {
        let url = baseURL.appendingPathComponent("/folders")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await APIClient.shared.perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(
                domain: "FoldersAPI",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch folders"]
            )
        }

        struct Response: Codable { let folders: [Folder] }
        return try makeDecoder().decode(Response.self, from: data).folders
    }

    func createFolder(
        name: String,
        accessType: FolderAccessType,
        memberUserIds: [String]
    ) async throws -> Folder {
        let url = baseURL.appendingPathComponent("/folders")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: Any] = [
            "name": name,
            "accessType": accessType.rawValue,
            "memberUserIds": memberUserIds,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await APIClient.shared.perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(
                domain: "FoldersAPI",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create folder"]
            )
        }

        struct Response: Codable { let folder: Folder }
        return try makeDecoder().decode(Response.self, from: data).folder
    }

    func updateFolder(
        folderId: String,
        name: String?,
        accessType: FolderAccessType?,
        memberUserIds: [String]?
    ) async throws -> Folder {
        let url = baseURL.appendingPathComponent("/folders/\(folderId)")
        var request = URLRequest(url: url)
        request.httpMethod = "PUT"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var body: [String: Any] = [:]
        if let name {
            body["name"] = name
        }
        if let accessType {
            body["accessType"] = accessType.rawValue
        }
        if let memberUserIds {
            body["memberUserIds"] = memberUserIds
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await APIClient.shared.perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(
                domain: "FoldersAPI",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to update folder"]
            )
        }

        struct Response: Codable { let folder: Folder }
        return try makeDecoder().decode(Response.self, from: data).folder
    }

    func deleteFolder(folderId: String) async throws {
        let url = baseURL.appendingPathComponent("/folders/\(folderId)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (_, response) = try await APIClient.shared.perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(
                domain: "FoldersAPI",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to delete folder"]
            )
        }
    }

    func fetchFolderMeetings(folderId: String) async throws -> [FolderMeeting] {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("/folders/\(folderId)/meetings"),
            resolvingAgainstBaseURL: false
        )!
        components.queryItems = [URLQueryItem(name: "includeFolder", value: "false")]
        let url = components.url!
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await APIClient.shared.perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(
                domain: "FoldersAPI",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch folder meetings"]
            )
        }

        struct Response: Codable {
            let meetings: [FolderMeeting]
        }
        return try makeDecoder().decode(Response.self, from: data).meetings
    }

    func assignMeeting(folderId: String, meetingId: String) async throws {
        let url = baseURL.appendingPathComponent("/folders/\(folderId)/meetings")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["meetingId": meetingId])

        let (data, response) = try await APIClient.shared.perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            if let body = String(data: data, encoding: .utf8) {
                NSLog("[FoldersAPI] assignMeeting error response: %@", body)
            }
            throw NSError(
                domain: "FoldersAPI",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to add meeting to folder"]
            )
        }
    }

    func removeMeeting(folderId: String, meetingId: String) async throws {
        let url = baseURL.appendingPathComponent("/folders/\(folderId)/meetings/\(meetingId)")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"

        let (data, response) = try await APIClient.shared.perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            if let body = String(data: data, encoding: .utf8) {
                NSLog("[FoldersAPI] removeMeeting error response: %@", body)
            }
            throw NSError(
                domain: "FoldersAPI",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to remove meeting from folder"]
            )
        }
    }
}
