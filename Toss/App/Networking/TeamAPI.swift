import Foundation

struct WorkspaceMember: Identifiable, Codable, Equatable {
    let id: String
    let userId: String
    let role: String
    let email: String
    let name: String
    let imageUrl: String?
    let joinedAt: String?
}

final class TeamAPI {
    static let shared = TeamAPI()

    private let baseURL: URL

    init(baseURL: URL = Config.serverBaseURL) {
        self.baseURL = baseURL
    }

	func fetchMembers() async throws -> [WorkspaceMember] {
        let url = baseURL.appendingPathComponent("/team/members")
        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        let (data, response) = try await APIClient.shared.perform(request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(
                domain: "TeamAPI",
                code: (response as? HTTPURLResponse)?.statusCode ?? 0,
                userInfo: [NSLocalizedDescriptionKey: "Failed to fetch team members"]
            )
        }

		struct Response: Codable { let members: [WorkspaceMember] }
        return try JSONDecoder().decode(Response.self, from: data).members
    }
}
