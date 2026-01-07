import AppKit
import Foundation
import Security

@MainActor
final class AuthManager: ObservableObject {
    static let shared = AuthManager()

    @Published private(set) var accessToken: String?
    @Published private(set) var refreshToken: String?
    @Published private(set) var userName: String?
    @Published private(set) var userEmail: String?
    @Published private(set) var userImageURL: URL?

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

    private init() {
        accessToken = try? readToken()
        refreshToken = try? readRefresh()
        Task {
            // Always refresh on launch if we have a refresh token
            if refreshToken != nil {
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
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10 * 60, repeats: true) {
            [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }
                if self.accessToken != nil {
                    NSLog("[AuthManager] Auto-refreshing access token")
                    let success = await self.refreshAccessToken()
                    if !success {
                        NSLog("[AuthManager] Auto-refresh failed, signing out")
                        self.signOut()
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

    func signOut() {

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
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
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
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
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
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { return nil }
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
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func deleteToken() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func deleteRefresh() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: refreshAccount,
        ]
        SecItemDelete(query as CFDictionary)
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

    @discardableResult
    func refreshAccessToken() async -> Bool {
        guard let refresh = refreshToken, !refresh.isEmpty else { return false }
        guard let url = URL(string: "\(Config.serverURL)/auth/refresh") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(refresh)", forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return false }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let token = json["token"] as? String, !token.isEmpty {
                    try? writeToken(token)
                    // Only update the published property if the token actually changed
                    // This prevents unnecessary SwiftUI re-renders and window focus issues
                    if self.accessToken != token {
                        self.accessToken = token
                    }
                    return true
                }
            }
        } catch {
            NSLog("[AuthManager] refresh token error: %@", error.localizedDescription)
        }
        return false
    }
}

extension Notification.Name {
    static let userAccountChanged = Notification.Name("userAccountChanged")
}
