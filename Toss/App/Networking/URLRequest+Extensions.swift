import Foundation

extension URLRequest {
    /// Returns a copy of the request with standard headers applied:
    /// - x-app-version: The current app version
    /// - Authorization: Bearer token

    func configured(token: String? = nil) -> URLRequest {
        var request = self

        // Add App Version
        if let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String {
            request.setValue(version, forHTTPHeaderField: "x-app-version")
        }

        // Add Auth Token
        if let token = token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        return request
    }

    /// Execute this request with automatic auth handling
    func execute() async throws -> (Data, URLResponse) {
        try await APIClient.shared.perform(self)
    }
}
