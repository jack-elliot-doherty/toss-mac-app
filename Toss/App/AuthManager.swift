import AppKit
import Foundation
import Security

// MARK: - Organization Model

struct Organization: Codable, Identifiable, Equatable {
    let id: String
    let name: String
    let imageUrl: String?
    let role: String

    var isAdmin: Bool { role == "org:admin" }
}

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var accessToken: String?
    @Published private(set) var refreshToken: String?
    @Published private(set) var userName: String?
    @Published private(set) var userEmail: String?
    @Published private(set) var userImageURL: URL?
    @Published private(set) var currentOrg: Organization?
    @Published private(set) var organizations: [Organization] = []

    // For dev builds, use a different keychain service
    #if DEBUG
        private let keychainService = "ai.toss.mac.dev"
    #else
        private let keychainService = "ai.toss.mac"
    #endif
    private let tokenAccount = "access_token"
    private let refreshAccount = "refresh_token"
    private var pendingAuthState: String?

    private var refreshTimer: Timer?
    private var consecutiveRefreshFailures = 0
    private let maxConsecutiveFailuresBeforeSignout = 3

    private init() {
        NSLog("[AuthManager] Initializing...")
        accessToken = try? readToken()
        refreshToken = try? readRefresh()
        NSLog("[AuthManager] Init complete - isAuthenticated: \(isAuthenticated)")
        Task {
            // Always refresh on launch if we have a refresh token
            if refreshToken != nil {
                NSLog("[AuthManager] Refreshing access token on launch...")
                _ = await self.refreshAccessToken()
            }
            _ = await self.refreshProfile()
            startAutoRefresh()
        }
    }

    var isAuthenticated: Bool { accessToken?.isEmpty == false }

    func startAutoRefresh() {
        // Refresh the access token every 10 minutes
        refreshTimer?.invalidate()
        consecutiveRefreshFailures = 0
        NSLog("[AuthManager] Starting auto-refresh timer (every 10 minutes)")
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10 * 60, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if self.accessToken != nil {
                    NSLog("[AuthManager] Auto-refreshing access token...")
                    let success = await self.refreshAccessToken()
                    if success {
                        self.consecutiveRefreshFailures = 0
                        NSLog("[AuthManager] Auto-refresh succeeded, reset failure counter")
                    } else {
                        self.consecutiveRefreshFailures += 1
                        NSLog("[AuthManager] Auto-refresh failed (\(self.consecutiveRefreshFailures)/\(self.maxConsecutiveFailuresBeforeSignout) consecutive failures)")

                        if self.consecutiveRefreshFailures >= self.maxConsecutiveFailuresBeforeSignout {
                            NSLog("[AuthManager] Max consecutive failures reached, signing out")
                            self.signOut(reason: "auto-refresh failed \(self.maxConsecutiveFailuresBeforeSignout) times consecutively")
                        }
                    }
                }
            }
        }
    }

    func beginBrowserLogin() {
        let redirect = "\(Config.urlScheme)://auth/callback"
        let state = generateState()
        pendingAuthState = state
        var comps = URLComponents(string: "\(Config.serverURL)/auth/start")
        comps?.queryItems = [
            URLQueryItem(name: "redirect", value: redirect),
            URLQueryItem(name: "state", value: state),
        ]
        if let url = comps?.url { NSWorkspace.shared.open(url) }
    }

    func continueWithGoogle() {
        let redirect = "\(Config.urlScheme)://auth/callback"
        let state = generateState()
        pendingAuthState = state
        var comps = URLComponents(string: "\(Config.serverURL)/auth/google/start")
        comps?.queryItems = [
            URLQueryItem(name: "redirect", value: redirect),
            URLQueryItem(name: "state", value: state),
        ]
        if let url = comps?.url { NSWorkspace.shared.open(url) }
    }

    func continueWithApple() {
        let redirect = "\(Config.urlScheme)://auth/callback"
        let state = generateState()
        pendingAuthState = state
        var comps = URLComponents(string: "\(Config.serverURL)/auth/apple/start")
        comps?.queryItems = [
            URLQueryItem(name: "redirect", value: redirect),
            URLQueryItem(name: "state", value: state),
        ]
        if let url = comps?.url { NSWorkspace.shared.open(url) }
    }

    func handleDeepLink(url: URL) -> Bool {
        // toss://auth/callback?state=... or toss-dev://auth/callback?state=...
        guard (url.scheme == "toss" || url.scheme == "toss-dev"), url.host == "auth", url.path == "/callback" else {
            return false
        }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // Back-compat: accept token params if present (older servers)
        let token = comps?.queryItems?.first(where: { $0.name == "token" })?.value
        let refresh = comps?.queryItems?.first(where: { $0.name == "refresh" })?.value
        if let token, !token.isEmpty {
            try? writeToken(token)
            // CHANGED: Set directly instead of DispatchQueue.main.async
            self.accessToken = token
            if let refresh, !refresh.isEmpty {
                try? writeRefresh(refresh)
                self.refreshToken = refresh
            }
            // Window activation is handled by AppDelegate after URL processing
            // to avoid flash from multiple activation attempts
            Task { await self.refreshProfile() }
            return true
        }

        let state = comps?.queryItems?.first(where: { $0.name == "state" })?.value
        guard let state, let pending = pendingAuthState, state == pending else { return true }
        pendingAuthState = nil
        Task { await self.exchangeState(state: state) }
        return true
    }

    /// Sign out the user and clear all auth state
    /// - Parameter reason: A description of why signOut was triggered (for debugging)
    func signOut(reason: String = "unknown") {
        NSLog("[AuthManager] signOut triggered - reason: \(reason)")

        refreshTimer?.invalidate()
        refreshTimer = nil
        try? deleteToken()
        try? deleteRefresh()
        History.shared.clear()

        accessToken = nil
        refreshToken = nil
        userName = nil
        userEmail = nil
        userImageURL = nil
        currentOrg = nil
        organizations = []

        NSLog("[AuthManager] signOut complete - user is now logged out")
    }

    @discardableResult
    func refreshProfile() async -> Bool {
        guard let token = accessToken, !token.isEmpty else { return false }
        guard let url = URL(string: "\(Config.serverURL)/me") else { return false }
        var req = URLRequest(url: url)
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            if let http = resp as? HTTPURLResponse, http.statusCode == 401 {
                if await self.refreshAccessToken() {
                    return await self.refreshProfile()
                }
                return false
            }
            if let http = resp as? HTTPURLResponse, http.statusCode != 200 { return false }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let name = json["name"] as? String
                let email = json["email"] as? String
                let image = (json["imageUrl"] as? String).flatMap { URL(string: $0) }

                // Check if this is a different user than before
                let lastEmail = UserDefaults.standard.string(forKey: "lastSignedInEmail")
                if let email = email, let lastEmail = lastEmail, email != lastEmail {
                    NSLog(
                        "[AuthManager] Different user signed in (\(email) vs \(lastEmail)), will clear local data"
                    )
                    NotificationCenter.default.post(name: .userAccountChanged, object: nil)
                }

                // Store current user email for next comparison
                if let email = email {
                    UserDefaults.standard.set(email, forKey: "lastSignedInEmail")
                }

                userName = name
                userEmail = email
                userImageURL = image

                // Parse organization data
                if let currentOrgData = json["currentOrg"] as? [String: Any] {
                    currentOrg = Organization(
                        id: currentOrgData["id"] as? String ?? "",
                        name: currentOrgData["name"] as? String ?? "",
                        imageUrl: currentOrgData["imageUrl"] as? String,
                        role: currentOrgData["role"] as? String ?? "org:member"
                    )
                }

                if let orgsData = json["organizations"] as? [[String: Any]] {
                    organizations = orgsData.compactMap { orgData -> Organization? in
                        guard let id = orgData["id"] as? String,
                              let name = orgData["name"] as? String else { return nil }
                        return Organization(
                            id: id,
                            name: name,
                            imageUrl: orgData["imageUrl"] as? String,
                            role: orgData["role"] as? String ?? "org:member"
                        )
                    }
                }

                await SubscriptionManager.shared.checkSubscription()

                return true
            }
        } catch {
            NSLog("[AuthManager] profile fetch error: %@", error.localizedDescription)
        }
        return false
    }

    // MARK: - Keychain
    private func writeToken(_ token: String) throws {
        let data = token.data(using: .utf8) ?? Data()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenAccount,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attrs[kSecAttrSynchronizable as String] = kCFBooleanFalse as Any
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            NSLog("[AuthManager] writeToken failed with status: \(status)")
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        NSLog("[AuthManager] writeToken success")
    }

    private func writeRefresh(_ token: String) throws {
        let data = token.data(using: .utf8) ?? Data()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: refreshAccount,
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        attrs[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        attrs[kSecAttrSynchronizable as String] = kCFBooleanFalse as Any
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else {
            NSLog("[AuthManager] writeRefresh failed with status: \(status)")
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
        NSLog("[AuthManager] writeRefresh success")
    }

    private func readToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenAccount,
            kSecReturnData as String: true,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound {
            NSLog("[AuthManager] readToken: no token found in keychain")
            return nil
        }
        guard status == errSecSuccess, let data = out as? Data else {
            NSLog("[AuthManager] readToken failed with status: \(status)")
            return nil
        }
        NSLog("[AuthManager] readToken: successfully read token from keychain")
        return String(data: data, encoding: .utf8)
    }

    private func readRefresh() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: refreshAccount,
            kSecReturnData as String: true,
        ]
        var out: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &out)
        if status == errSecItemNotFound {
            NSLog("[AuthManager] readRefresh: no refresh token found in keychain")
            return nil
        }
        guard status == errSecSuccess, let data = out as? Data else {
            NSLog("[AuthManager] readRefresh failed with status: \(status)")
            return nil
        }
        NSLog("[AuthManager] readRefresh: successfully read refresh token from keychain")
        return String(data: data, encoding: .utf8)
    }

    private func deleteToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenAccount,
        ]
        let status = SecItemDelete(query as CFDictionary)
        NSLog("[AuthManager] deleteToken status: \(status)")
    }

    private func deleteRefresh() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: refreshAccount,
        ]
        let status = SecItemDelete(query as CFDictionary)
        NSLog("[AuthManager] deleteRefresh status: \(status)")
    }

    // MARK: - Token Exchange & Refresh
    private func generateState() -> String {
        var bytes = [UInt8](repeating: 0, count: 16)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        if status != errSecSuccess {
            return UUID().uuidString.replacingOccurrences(of: "-", with: "")
        }
        return Data(bytes).map { String(format: "%02x", $0) }.joined()
    }

    private func exchangeState(state: String) async {
        guard let url = URL(string: "\(Config.serverURL)/auth/exchange?state=\(state)") else {
            return
        }
        var req = URLRequest(url: url)
        req.httpMethod = "GET"
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                let token = json["token"] as? String
                let refresh = json["refresh"] as? String
                if let token, !token.isEmpty { try? writeToken(token) }
                if let refresh, !refresh.isEmpty { try? writeRefresh(refresh) }

                // CHANGED: Set directly instead of DispatchQueue.main.async
                self.accessToken = token
                self.refreshToken = refresh ?? self.refreshToken

                // Activate app to bring to foreground and trigger UI update
                // Only activate if not already active to avoid window flash
                if !NSApp.isActive {
                    NSApp.activate(ignoringOtherApps: true)
                }

                await SubscriptionManager.shared.checkSubscription()
                _ = await self.refreshProfile()
            }
        } catch {
            NSLog("[AuthManager] exchange error: %@", error.localizedDescription)
        }
    }

    /// Refresh the access token with retry logic for transient failures
    /// - Parameters:
    ///   - maxRetries: Number of retry attempts (default: 3)
    ///   - retryDelay: Delay between retries in seconds (default: 1.0)
    /// - Returns: true if refresh succeeded, false otherwise
    @discardableResult
    func refreshAccessToken(maxRetries: Int = 3, retryDelay: TimeInterval = 1.0) async -> Bool {
        guard let refresh = refreshToken, !refresh.isEmpty else {
            NSLog("[AuthManager] refreshAccessToken: No refresh token available")
            return false
        }
        guard let url = URL(string: "\(Config.serverURL)/auth/refresh") else {
            NSLog("[AuthManager] refreshAccessToken: Invalid URL")
            return false
        }

        for attempt in 1...maxRetries {
            var req = URLRequest(url: url)
            req.httpMethod = "POST"
            req.setValue("Bearer \(refresh)", forHTTPHeaderField: "Authorization")

            do {
                let (data, resp) = try await URLSession.shared.data(for: req)

                if let http = resp as? HTTPURLResponse {
                    if http.statusCode == 200 {
                        if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                           let token = json["token"] as? String, !token.isEmpty {
                            try? writeToken(token)
                            // Only update the published property if the token actually changed
                            // This prevents unnecessary SwiftUI re-renders and window focus issues
                            if self.accessToken != token {
                                self.accessToken = token
                            }
                            NSLog("[AuthManager] refreshAccessToken: Success on attempt \(attempt)")
                            return true
                        }
                        NSLog("[AuthManager] refreshAccessToken: Invalid response format on attempt \(attempt)")
                    } else if http.statusCode == 401 {
                        // Refresh token is invalid/expired - no point retrying
                        NSLog("[AuthManager] refreshAccessToken: Refresh token rejected (401) - not retrying")
                        return false
                    } else {
                        NSLog("[AuthManager] refreshAccessToken: Server returned \(http.statusCode) on attempt \(attempt)")
                    }
                }
            } catch {
                NSLog("[AuthManager] refreshAccessToken: Network error on attempt \(attempt): \(error.localizedDescription)")
            }

            // Retry with delay if not the last attempt
            if attempt < maxRetries {
                NSLog("[AuthManager] refreshAccessToken: Retrying in \(retryDelay)s...")
                try? await Task.sleep(nanoseconds: UInt64(retryDelay * 1_000_000_000))
            }
        }

        NSLog("[AuthManager] refreshAccessToken: All \(maxRetries) attempts failed")
        return false
    }
}

// MARK: - Organization Management

extension AuthManager {
    /// Switch to a different organization
    /// - Parameter orgId: The organization ID to switch to
    /// - Throws: Error if switch fails
    func switchOrganization(to orgId: String) async throws {
        NSLog("[AuthManager] Switching to organization: \(orgId)")

        guard let refresh = refreshToken, !refresh.isEmpty else {
            throw AuthError.noRefreshToken
        }

        guard let url = URL(string: "\(Config.serverURL)/auth/switch-org") else {
            throw AuthError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(refresh)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["orgId": orgId])

        let (data, resp) = try await URLSession.shared.data(for: req)

        guard let http = resp as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if http.statusCode == 403 {
            throw AuthError.notAMember
        }

        guard http.statusCode == 200 else {
            throw AuthError.switchFailed(statusCode: http.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let token = json["token"] as? String,
              let newRefresh = json["refresh"] as? String else {
            throw AuthError.invalidResponse
        }

        // Store new tokens
        try? writeToken(token)
        try? writeRefresh(newRefresh)
        accessToken = token
        refreshToken = newRefresh

        // Refresh profile to get updated org info
        _ = await refreshProfile()

        // Post notification for org change
        NotificationCenter.default.post(name: .organizationChanged, object: nil)

        NSLog("[AuthManager] Successfully switched to organization: \(orgId)")
    }

    /// Create a new organization
    /// - Parameter name: The name for the new organization
    /// - Throws: Error if creation fails
    func createOrganization(name: String) async throws {
        NSLog("[AuthManager] Creating organization: \(name)")

        guard let token = accessToken, !token.isEmpty else {
            throw AuthError.noAccessToken
        }

        guard let url = URL(string: "\(Config.serverURL)/team") else {
            throw AuthError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONEncoder().encode(["name": name])

        let (data, resp) = try await URLSession.shared.data(for: req)

        guard let http = resp as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        guard http.statusCode == 201 else {
            throw AuthError.createFailed(statusCode: http.statusCode)
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let newToken = json["token"] as? String,
              let newRefresh = json["refresh"] as? String else {
            throw AuthError.invalidResponse
        }

        // Store new tokens for the new org
        try? writeToken(newToken)
        try? writeRefresh(newRefresh)
        accessToken = newToken
        refreshToken = newRefresh

        // Refresh profile to get updated org info
        _ = await refreshProfile()

        // Post notification for org change
        NotificationCenter.default.post(name: .organizationChanged, object: nil)

        NSLog("[AuthManager] Successfully created organization: \(name)")
    }

    /// Leave the current organization
    /// - Throws: Error if leaving fails
    func leaveOrganization() async throws {
        NSLog("[AuthManager] Leaving current organization")

        guard let token = accessToken, !token.isEmpty else {
            throw AuthError.noAccessToken
        }

        guard let url = URL(string: "\(Config.serverURL)/team/leave") else {
            throw AuthError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, resp) = try await URLSession.shared.data(for: req)

        guard let http = resp as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if http.statusCode == 400 {
            // Check for specific error
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String,
               error == "cannot_leave_as_only_admin" {
                throw AuthError.cannotLeaveAsOnlyAdmin
            }
        }

        guard http.statusCode == 204 else {
            throw AuthError.leaveFailed(statusCode: http.statusCode)
        }

        // Switch to another org if available, otherwise we need to handle no-org state
        if let nextOrg = organizations.first(where: { $0.id != currentOrg?.id }) {
            try await switchOrganization(to: nextOrg.id)
        } else {
            // No other orgs - user needs to create one
            currentOrg = nil
            organizations = []
            NotificationCenter.default.post(name: .organizationChanged, object: nil)
        }

        NSLog("[AuthManager] Successfully left organization")
    }

    /// Delete the current organization (admin only)
    /// - Throws: Error if deletion fails
    func deleteOrganization() async throws {
        NSLog("[AuthManager] Deleting current organization")

        guard let token = accessToken, !token.isEmpty else {
            throw AuthError.noAccessToken
        }

        guard let url = URL(string: "\(Config.serverURL)/team") else {
            throw AuthError.invalidURL
        }

        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (_, resp) = try await URLSession.shared.data(for: req)

        guard let http = resp as? HTTPURLResponse else {
            throw AuthError.invalidResponse
        }

        if http.statusCode == 403 {
            throw AuthError.adminRequired
        }

        guard http.statusCode == 204 else {
            throw AuthError.deleteFailed(statusCode: http.statusCode)
        }

        // Switch to another org if available
        if let nextOrg = organizations.first(where: { $0.id != currentOrg?.id }) {
            try await switchOrganization(to: nextOrg.id)
        } else {
            // No other orgs - user needs to create one
            currentOrg = nil
            organizations = []
            NotificationCenter.default.post(name: .organizationChanged, object: nil)
        }

        NSLog("[AuthManager] Successfully deleted organization")
    }
}

// MARK: - Auth Errors

enum AuthError: LocalizedError {
    case noRefreshToken
    case noAccessToken
    case invalidURL
    case invalidResponse
    case notAMember
    case cannotLeaveAsOnlyAdmin
    case adminRequired
    case switchFailed(statusCode: Int)
    case createFailed(statusCode: Int)
    case leaveFailed(statusCode: Int)
    case deleteFailed(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .noRefreshToken:
            return "No refresh token available"
        case .noAccessToken:
            return "No access token available"
        case .invalidURL:
            return "Invalid URL"
        case .invalidResponse:
            return "Invalid server response"
        case .notAMember:
            return "You are not a member of this organization"
        case .cannotLeaveAsOnlyAdmin:
            return "You cannot leave as the only admin. Transfer ownership or delete the workspace."
        case .adminRequired:
            return "Admin privileges required"
        case .switchFailed(let code):
            return "Failed to switch organization (status: \(code))"
        case .createFailed(let code):
            return "Failed to create organization (status: \(code))"
        case .leaveFailed(let code):
            return "Failed to leave organization (status: \(code))"
        case .deleteFailed(let code):
            return "Failed to delete organization (status: \(code))"
        }
    }
}

extension Notification.Name {
    static let userAccountChanged = Notification.Name("userAccountChanged")
    static let organizationChanged = Notification.Name("organizationChanged")
}
