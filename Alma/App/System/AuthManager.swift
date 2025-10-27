import Foundation
import Security
import AppKit

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

    private init() {
        accessToken = try? readToken()
        Task { await self.refreshProfile() }
    }

    var isAuthenticated: Bool { accessToken?.isEmpty == false }

    func beginBrowserLogin() {
        let redirect = "alma://auth/callback"
        guard let url = URL(string: "http://127.0.0.1:8787/auth/start?redirect=" + (redirect.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) else { return }
        NSWorkspace.shared.open(url)
    }

    func continueWithGoogle() {
        let redirect = "alma://auth/callback"
        guard let url = URL(string: "http://127.0.0.1:8787/auth/google/start?redirect=" + (redirect.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) else { return }
        NSWorkspace.shared.open(url)
    }

    func continueWithApple() {
        let redirect = "alma://auth/callback"
        guard let url = URL(string: "http://127.0.0.1:8787/auth/apple/start?redirect=" + (redirect.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")) else { return }
        NSWorkspace.shared.open(url)
    }

    func handleDeepLink(url: URL) -> Bool {
        // alma://auth/callback?token=...&refresh=...
        guard url.scheme == "alma", url.host == "auth", url.path == "/callback" else { return false }
        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let token = comps?.queryItems?.first(where: { $0.name == "token" })?.value
        let refresh = comps?.queryItems?.first(where: { $0.name == "refresh" })?.value
        if let token, !token.isEmpty {
            try? writeToken(token)
            DispatchQueue.main.async { [weak self] in self?.accessToken = token }
            Task { await self.refreshProfile() }
        }
        if let refresh, !refresh.isEmpty {
            try? writeRefresh(refresh)
            DispatchQueue.main.async { [weak self] in self?.refreshToken = refresh }
        }
        return true
    }

    func signInDevToken() {
        let alert = NSAlert()
        alert.messageText = "Enter developer token"
        alert.informativeText = "Paste a temporary API token from the server to authenticate this device."
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
        try? deleteToken()
        try? deleteRefresh()
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
            kSecAttrAccount as String: tokenAccount
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    private func writeRefresh(_ token: String) throws {
        let data = token.data(using: .utf8) ?? Data()
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: refreshAccount
        ]
        SecItemDelete(query as CFDictionary)
        var attrs = query
        attrs[kSecValueData as String] = data
        let status = SecItemAdd(attrs as CFDictionary, nil)
        guard status == errSecSuccess else { throw NSError(domain: NSOSStatusErrorDomain, code: Int(status)) }
    }

    private func readToken() throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenAccount,
            kSecReturnData as String: true
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
            kSecAttrAccount as String: tokenAccount
        ]
        SecItemDelete(query as CFDictionary)
    }

    private func deleteRefresh() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: refreshAccount
        ]
        SecItemDelete(query as CFDictionary)
    }
}
