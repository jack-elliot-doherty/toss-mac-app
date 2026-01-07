import Foundation

/// Centralized API client that handles auth token injection and automatic refresh on 401
final class APIClient {
    static let shared = APIClient()

    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    /// Perform an authenticated request with automatic token refresh on 401
    /// Note: This method does NOT sign out on refresh failure - the auto-refresh timer
    /// handles sign-out after multiple consecutive failures to avoid aggressive logout
    /// during transient issues like app updates or network hiccups.
    func perform(_ request: URLRequest) async throws -> (Data, URLResponse) {
        // Configure with current token (access MainActor property)
        let token = await MainActor.run { AuthManager.shared.accessToken }
        let configuredRequest = request.configured(token: token)

        let (data, response) = try await session.data(for: configuredRequest)

        // Check for 401 - try refresh and retry once
        if let http = response as? HTTPURLResponse, http.statusCode == 401 {
            NSLog("[APIClient] Got 401, attempting token refresh...")

            let refreshed = await AuthManager.shared.refreshAccessToken()
            if refreshed {
                NSLog("[APIClient] Token refreshed successfully, retrying request...")
                let newToken = await MainActor.run { AuthManager.shared.accessToken }
                let retryRequest = request.configured(token: newToken)
                return try await session.data(for: retryRequest)
            } else {
                // Don't sign out here - let the auto-refresh timer handle sign-out
                // after multiple consecutive failures. This prevents aggressive logout
                // during transient issues like app updates, network hiccups, or
                // temporary server issues.
                NSLog("[APIClient] Token refresh failed - returning 401 to caller (auto-refresh timer will handle sign-out if needed)")
            }
        }

        return (data, response)
    }

    /// Callback-based version for existing code
    func perform(
        _ request: URLRequest,
        completion: @escaping (Result<(Data, URLResponse), Error>) -> Void
    ) {
        Task {
            do {
                let result = try await perform(request)
                completion(.success(result))
            } catch {
                completion(.failure(error))
            }
        }
    }
}

extension APIClient {
    /// Drop-in replacement for URLSession.dataTask with automatic token refresh
    func dataTask(
        with request: URLRequest,
        completionHandler: @escaping (Data?, URLResponse?, Error?) -> Void
    ) {
        perform(request) { result in
            switch result {
            case .success(let (data, response)):
                completionHandler(data, response, nil)
            case .failure(let error):
                completionHandler(nil, nil, error)
            }
        }
    }
}
