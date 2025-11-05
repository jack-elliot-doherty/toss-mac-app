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

    private let keychainService = "ai.alma.mac"
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
        let redirect = "alma://auth/callback"
        let state = generateState()
        pendingAuthState = state
        var comps = URLComponents(string: "http://127.0.0.1:8787/auth/start")
        comps?.queryItems = [
            URLQueryItem(name: "redirect", value: redirect),
            URLQueryItem(name: "state", value: state),
        ]
        if let url = comps?.url { NSWorkspace.shared.open(url) }
    }

    func continueWithGoogle() {
        let redirect = "alma://auth/callback"
        let state = generateState()
        pendingAuthState = state
        var comps = URLComponents(string: "http://127.0.0.1:8787/auth/google/start")
        comps?.queryItems = [
            URLQueryItem(name: "redirect", value: redirect),
            URLQueryItem(name: "state", value: state),
        ]
        if let url = comps?.url { NSWorkspace.shared.open(url) }
    }

    func continueWithApple() {
        let redirect = "alma://auth/callback"
        let state = generateState()
        pendingAuthState = state
        var comps = URLComponents(string: "http://127.0.0.1:8787/auth/apple/start")
        comps?.queryItems = [
            URLQueryItem(name: "redirect", value: redirect),
            URLQueryItem(name: "state", value: state),
        ]
        if let url = comps?.url { NSWorkspace.shared.open(url) }
    }

    func handleDeepLink(url: URL) -> Bool {
        // alma://auth/callback?state=...
        guard url.scheme == "alma", url.host == "auth", url.path == "/callback" else {
            return false
        }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        // Back-compat: accept token params if present (older servers)
        let token = comps?.queryItems?.first(where: { $0.name == "token" })?.value
        let refresh = comps?.queryItems?.first(where: { $0.name == "refresh" })?.value
        if let token, !token.isEmpty {
            try? writeToken(token)
            DispatchQueue.main.async { [weak self] in self?.accessToken = token }
            if let refresh, !refresh.isEmpty {
                try? writeRefresh(refresh)
                DispatchQueue.main.async { [weak self] in self?.refreshToken = refresh }
            }
            Task { await self.refreshProfile() }
            return true
        }

        let state = comps?.queryItems?.first(where: { $0.name == "state" })?.value
        guard let state, let pending = pendingAuthState, state == pending else { return true }
        pendingAuthState = nil
        Task { await self.exchangeState(state: state) }
        return true
    }

    func signInDevToken() {
        let alert = NSAlert()
        alert.messageText = "Enter developer token"
        alert.informativeText =
            "Paste a temporary API token from the server to authenticate this device."
        alert.addButton(withTitle: "Save")
        alert.addButton(withTitle: "Cancel")

        let input = NSTextField(frame: NSRect(x: 0, y: 0, width: 320, height: 24))
        alert.accessoryView = input
        let response = alert.runModal()
        guard response == .alertFirstButtonReturn else { return }
        let token = input.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return }
        try? writeToken(token)
        DispatchQueue.main.async { [weak self] in self?.accessToken = token }
    }

    func signOut() {

        refreshTimer?.invalidate()
        refreshTimer = nil
        try? deleteToken()
        try? deleteRefresh()
        History.shared.clear()
        DispatchQueue.main.async { [weak self] in
            self?.accessToken = nil
            self?.refreshToken = nil
            self?.userName = nil
            self?.userEmail = nil
            self?.userImageURL = nil
        }
    }

    @discardableResult
    func refreshProfile() async -> Bool {
        guard let token = accessToken, !token.isEmpty else { return false }
        guard let url = URL(string: "http://127.0.0.1:8787/me") else { return false }
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
                DispatchQueue.main.async { [weak self] in
                    self?.userName = name
                    self?.userEmail = email
                    self?.userImageURL = image
                }
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
        guard let url = URL(string: "http://127.0.0.1:8787/auth/exchange?state=\(state)") else {
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
                DispatchQueue.main.async { [weak self] in
                    self?.accessToken = token
                    self?.refreshToken = (json["refresh"] as? String) ?? self?.refreshToken
                }
                _ = await self.refreshProfile()
            }
        } catch {
            NSLog("[AuthManager] exchange error: %@", error.localizedDescription)
        }
    }

    @discardableResult
    private func refreshAccessToken() async -> Bool {
        guard let refresh = refreshToken, !refresh.isEmpty else { return false }
        guard let url = URL(string: "http://127.0.0.1:8787/auth/refresh") else { return false }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("Bearer \(refresh)", forHTTPHeaderField: "Authorization")
        do {
            let (data, resp) = try await URLSession.shared.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return false }
            if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let token = json["token"] as? String, !token.isEmpty {
                    try? writeToken(token)
                    DispatchQueue.main.async { [weak self] in self?.accessToken = token }
                    return true
                }
            }
        } catch {
            NSLog("[AuthManager] refresh token error: %@", error.localizedDescription)
        }
        return false
    }
}
