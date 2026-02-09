import AppKit
import SwiftUI

struct SlackConnectionStatus: Codable {
    let connected: Bool
    let teamName: String?
}

struct LinearConnectionStatus: Codable {
    let connected: Bool
    let organizationName: String?
    let requiresReauth: Bool?
    let lastErrorAt: String?
}

struct GoogleConnectionStatus: Codable {
    let connected: Bool
    let email: String?
    let requiresReauth: Bool?
    let lastErrorAt: String?
}

struct NotionConnectionStatus: Codable {
    let connected: Bool
    let workspaceName: String?
    let workspaceIcon: String?
}

struct GmailConnectionStatus: Codable {
    let connected: Bool
    let email: String?
    let requiresReauth: Bool?
    let lastErrorAt: String?
}

struct SlackBotConnectionStatus: Codable {
    let installed: Bool
    let teamName: String?
    let installedBy: String?
}

struct DiscordBotConnectionStatus: Codable {
    let installed: Bool
    let guildName: String?
    let installedBy: String?
}

@MainActor
final class IntegrationsManager: ObservableObject {
    static let shared = IntegrationsManager()

    @Published var slackStatus: SlackConnectionStatus?
    @Published var slackBotStatus: SlackBotConnectionStatus?
    @Published var discordBotStatus: DiscordBotConnectionStatus?
    @Published var linearStatus: LinearConnectionStatus?
    @Published var googleStatus: GoogleConnectionStatus?
    @Published var notionStatus: NotionConnectionStatus?
    @Published var gmailStatus: GmailConnectionStatus?

    @Published var isLoading = false
    @Published var isLoadingGoogleStatus = false
    @Published var error: String?

    /// Trigger to force view refresh after deep link (works around SwiftUI text rendering bug)
    @Published var viewRefreshTrigger = UUID()

    func fetchSlackStatus() async {
        guard let url = URL(string: "\(Config.serverURL)/slack/status") else { return }

        let request = URLRequest(url: url)

        do {
            isLoading = true
            let (data, response) = try await APIClient.shared.perform(request)
            isLoading = false

            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                slackStatus = try JSONDecoder().decode(SlackConnectionStatus.self, from: data)
            }
        } catch {
            isLoading = false
            NSLog("[Integrations] Failed to fetch Slack status: %@", error.localizedDescription)
        }
    }

    func connectSlack() async {
        guard let url = URL(string: "\(Config.serverURL)/slack/connect") else { return }

        let request = URLRequest(url: url)

        do {
            let (data, response) = try await APIClient.shared.perform(request)

            if let http = response as? HTTPURLResponse, http.statusCode == 200,
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let urlString = json["url"] as? String,
                let authURL = URL(string: urlString)
            {
                NSWorkspace.shared.open(authURL)
            }
        } catch {
            self.error = "Failed to start Slack connection"
            NSLog("[Integrations] Failed to connect Slack: %@", error.localizedDescription)
        }
    }

    func disconnectSlack() async {
        guard let url = URL(string: "\(Config.serverURL)/slack/disconnect") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        do {
            let (_, response) = try await APIClient.shared.perform(request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                slackStatus = SlackConnectionStatus(connected: false, teamName: nil)
            }
        } catch {
            NSLog("[Integrations] Failed to disconnect Slack: %@", error.localizedDescription)
        }
    }

    // 3. Add Google Methods
    func fetchGoogleStatus() async {
        guard let url = URL(string: "\(Config.serverURL)/google/status") else { return }

        let request = URLRequest(url: url)

        isLoadingGoogleStatus = true
        do {
            let (data, response) = try await APIClient.shared.perform(request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                googleStatus = try JSONDecoder().decode(GoogleConnectionStatus.self, from: data)
            }
        } catch {
            NSLog("[Integrations] Failed to fetch Google status: %@", error.localizedDescription)
        }
        isLoadingGoogleStatus = false
    }

    func connectGoogle() async {
        guard let url = URL(string: "\(Config.serverURL)/google/connect") else { return }

        let request = URLRequest(url: url)

        do {
            let (data, response) = try await APIClient.shared.perform(request)

            if let http = response as? HTTPURLResponse, http.statusCode == 200,
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let urlString = json["url"] as? String,
                let authURL = URL(string: urlString)
            {
                NSWorkspace.shared.open(authURL)
            }
        } catch {
            self.error = "Failed to start Google connection"
            NSLog("[Integrations] Failed to connect Google: %@", error.localizedDescription)
        }
    }

    func disconnectGoogle() async {
        guard let url = URL(string: "\(Config.serverURL)/google/disconnect") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        do {
            let (_, response) = try await APIClient.shared.perform(request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                googleStatus = GoogleConnectionStatus(
                    connected: false, email: nil, requiresReauth: nil, lastErrorAt: nil)
            }
        } catch {
            NSLog("[Integrations] Failed to disconnect Google: %@", error.localizedDescription)
        }
    }

    // MARK: - Gmail

    func fetchGmailStatus() async {
        guard let url = URL(string: "\(Config.serverURL)/gmail/status") else { return }

        let request = URLRequest(url: url)

        do {
            let (data, response) = try await APIClient.shared.perform(request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                gmailStatus = try JSONDecoder().decode(GmailConnectionStatus.self, from: data)
            }
        } catch {
            NSLog("[Integrations] Failed to fetch Gmail status: %@", error.localizedDescription)
        }
    }

    func connectGmail() async {
        guard let url = URL(string: "\(Config.serverURL)/gmail/connect") else { return }

        let request = URLRequest(url: url)

        do {
            let (data, response) = try await APIClient.shared.perform(request)

            if let http = response as? HTTPURLResponse, http.statusCode == 200,
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let urlString = json["url"] as? String,
                let authURL = URL(string: urlString)
            {
                NSWorkspace.shared.open(authURL)
            }
        } catch {
            self.error = "Failed to start Gmail connection"
            NSLog("[Integrations] Failed to connect Gmail: %@", error.localizedDescription)
        }
    }

    func disconnectGmail() async {
        guard let url = URL(string: "\(Config.serverURL)/gmail/disconnect") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        do {
            let (_, response) = try await APIClient.shared.perform(request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                gmailStatus = GmailConnectionStatus(
                    connected: false, email: nil, requiresReauth: nil, lastErrorAt: nil)
            }
        } catch {
            NSLog("[Integrations] Failed to disconnect Gmail: %@", error.localizedDescription)
        }
    }

    func handleDeepLink(url: URL) -> Bool {
        // toss://integrations/slack?connected=1 or toss-dev://integrations/slack?connected=1
        guard url.scheme == "toss" || url.scheme == "toss-dev", url.host == "integrations" else {
            return false
        }

        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let connected = comps?.queryItems?.first(where: { $0.name == "connected" })?.value == "1"

        // Window activation is handled by AppDelegate after all URLs are processed
        // to avoid flash from multiple activation attempts

        if url.path == "/slack" {
            if connected {
                Task { await fetchSlackStatus() }
            }
            triggerViewRefresh()
            return true
        } else if url.path == "/linear" {
            if connected { Task { await fetchLinearStatus() } }
            triggerViewRefresh()
            return true
        } else if url.path == "/google" {
            if connected {
                Task {
                    await fetchGoogleStatus()
                    // Trigger calendar sync immediately after connecting
                    await MeetingsManager.shared.syncCalendar()
                }
            }
            triggerViewRefresh()
            return true
        } else if url.path == "/notion" {
            if connected {
                Task { await fetchNotionStatus() }
            }
            triggerViewRefresh()
            return true
        } else if url.path == "/slack-bot" {
            if connected {
                Task { await fetchSlackBotStatus() }
            }
            triggerViewRefresh()
            return true
        } else if url.path == "/gmail" {
            if connected {
                Task { await fetchGmailStatus() }
            }
            triggerViewRefresh()
            return true
        } else if url.path == "/discord" {
            if connected {
                Task { await fetchDiscordBotStatus() }
            }
            triggerViewRefresh()
            return true
        }
        return false
    }

    /// Force view to fully re-render (workaround for SwiftUI text rendering bug after deep link)
    private func triggerViewRefresh() {
        // Delay slightly to let the window activation settle
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.viewRefreshTrigger = UUID()
        }
    }

    func fetchLinearStatus() async {
        guard let url = URL(string: "\(Config.serverURL)/linear/status") else { return }

        let request = URLRequest(url: url)

        do {
            // Don't block UI with global loading, just fetch
            let (data, response) = try await APIClient.shared.perform(request)

            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                linearStatus = try JSONDecoder().decode(LinearConnectionStatus.self, from: data)
                NSLog(
                    "[Integrations] Linear status: connected=\(linearStatus?.connected ?? false), org=\(linearStatus?.organizationName ?? "nil")"
                )
            }
        } catch {
            NSLog("[Integrations] Failed to fetch Linear status: %@", error.localizedDescription)
        }
    }

    func connectLinear() async {
        guard let url = URL(string: "\(Config.serverURL)/linear/connect") else { return }

        let request = URLRequest(url: url)

        do {
            let (data, response) = try await APIClient.shared.perform(request)

            if let http = response as? HTTPURLResponse, http.statusCode == 200,
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let urlString = json["url"] as? String,
                let authURL = URL(string: urlString)
            {
                NSWorkspace.shared.open(authURL)
            }
        } catch {
            self.error = "Failed to start Linear connection"
            NSLog("[Integrations] Failed to connect Linear: %@", error.localizedDescription)
        }
    }

    func disconnectLinear() async {
        guard let url = URL(string: "\(Config.serverURL)/linear/disconnect") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        do {
            let (_, response) = try await APIClient.shared.perform(request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                linearStatus = LinearConnectionStatus(
                    connected: false, organizationName: nil, requiresReauth: nil, lastErrorAt: nil)
            }
        } catch {
            NSLog("[Integrations] Failed to disconnect Linear: %@", error.localizedDescription)
        }
    }

    // MARK: - Notion

    func fetchNotionStatus() async {
        guard let url = URL(string: "\(Config.serverURL)/notion/status") else { return }

        let request = URLRequest(url: url)

        do {
            let (data, response) = try await APIClient.shared.perform(request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                notionStatus = try JSONDecoder().decode(NotionConnectionStatus.self, from: data)
            }
        } catch {
            NSLog("[Integrations] Failed to fetch Notion status: %@", error.localizedDescription)
        }
    }

    func connectNotion() async {
        guard let url = URL(string: "\(Config.serverURL)/notion/connect") else { return }

        let request = URLRequest(url: url)

        do {
            let (data, response) = try await APIClient.shared.perform(request)

            if let http = response as? HTTPURLResponse, http.statusCode == 200,
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let urlString = json["url"] as? String,
                let authURL = URL(string: urlString)
            {
                NSWorkspace.shared.open(authURL)
            }
        } catch {
            self.error = "Failed to start Notion connection"
            NSLog("[Integrations] Failed to connect Notion: %@", error.localizedDescription)
        }
    }

    func disconnectNotion() async {
        guard let url = URL(string: "\(Config.serverURL)/notion/disconnect") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        do {
            let (_, response) = try await APIClient.shared.perform(request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                notionStatus = NotionConnectionStatus(
                    connected: false, workspaceName: nil, workspaceIcon: nil)
            }
        } catch {
            NSLog("[Integrations] Failed to disconnect Notion: %@", error.localizedDescription)
        }
    }

    // MARK: - Slack Bot (Toss Assistant)

    func fetchSlackBotStatus() async {
        guard let url = URL(string: "\(Config.serverURL)/slack/bot/status") else { return }

        let request = URLRequest(url: url)

        do {
            let (data, response) = try await APIClient.shared.perform(request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                slackBotStatus = try JSONDecoder().decode(SlackBotConnectionStatus.self, from: data)
            }
        } catch {
            NSLog("[Integrations] Failed to fetch Slack Bot status: %@", error.localizedDescription)
        }
    }

    func connectSlackBot() async {
        guard let url = URL(string: "\(Config.serverURL)/slack/bot/install") else {
            NSLog("[Integrations] Failed to create URL for Slack Bot install")
            return
        }

        NSLog("[Integrations] Starting Slack Bot install request to: %@", url.absoluteString)
        let request = URLRequest(url: url)

        do {
            let (data, response) = try await APIClient.shared.perform(request)

            if let http = response as? HTTPURLResponse {
                NSLog("[Integrations] Slack Bot install response status: %d", http.statusCode)

                if let responseStr = String(data: data, encoding: .utf8) {
                    NSLog("[Integrations] Slack Bot install response: %@", responseStr)
                }

                if http.statusCode == 200,
                    let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let urlString = json["url"] as? String,
                    let authURL = URL(string: urlString)
                {
                    NSLog("[Integrations] Opening Slack OAuth URL: %@", authURL.absoluteString)
                    NSWorkspace.shared.open(authURL)
                } else {
                    NSLog("[Integrations] Failed to parse Slack Bot install response")
                }
            }
        } catch {
            self.error = "Failed to start Slack Bot installation"
            NSLog("[Integrations] Failed to install Slack Bot: %@", error.localizedDescription)
        }
    }

    func disconnectSlackBot() async {
        guard let url = URL(string: "\(Config.serverURL)/slack/bot/uninstall") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        do {
            let (_, response) = try await APIClient.shared.perform(request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                slackBotStatus = SlackBotConnectionStatus(
                    installed: false, teamName: nil, installedBy: nil)
            }
        } catch {
            NSLog("[Integrations] Failed to uninstall Slack Bot: %@", error.localizedDescription)
        }
    }

    func fetchDiscordBotStatus() async {
        guard let url = URL(string: "\(Config.serverURL)/discord/bot/status") else { return }

        let request = URLRequest(url: url)

        do {
            let (data, response) = try await APIClient.shared.perform(request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                discordBotStatus = try JSONDecoder().decode(DiscordBotConnectionStatus.self, from: data)
            }
        } catch {
            NSLog("[Integrations] Failed to fetch Discord Bot status: %@", error.localizedDescription)
        }
    }

    func connectDiscordBot() async {
        guard let url = URL(string: "\(Config.serverURL)/discord/bot/install") else { return }

        let request = URLRequest(url: url)

        do {
            let (data, response) = try await APIClient.shared.perform(request)

            if let http = response as? HTTPURLResponse, http.statusCode == 200,
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let urlString = json["url"] as? String,
                let authURL = URL(string: urlString)
            {
                NSWorkspace.shared.open(authURL)
            }
        } catch {
            self.error = "Failed to start Discord Bot installation"
            NSLog("[Integrations] Failed to install Discord Bot: %@", error.localizedDescription)
        }
    }

    func disconnectDiscordBot() async {
        guard let url = URL(string: "\(Config.serverURL)/discord/bot/uninstall") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"

        do {
            let (_, response) = try await APIClient.shared.perform(request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                discordBotStatus = DiscordBotConnectionStatus(
                    installed: false, guildName: nil, installedBy: nil)
            }
        } catch {
            NSLog("[Integrations] Failed to uninstall Discord Bot: %@", error.localizedDescription)
        }
    }
}

@MainActor
struct IntegrationsView: View {
    @StateObject private var manager = IntegrationsManager.shared

    private let gridColumns = [
        GridItem(.adaptive(minimum: 240, maximum: 320), spacing: 16)
    ]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 32) {
                header

                // MARK: - Personal Integrations
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AppTheme.secondaryText)
                            Text("Personal")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppTheme.secondaryText)
                                .textCase(.uppercase)
                        }
                        Text("These integrations act as you. Only you can use them.")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                    }

                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
                        IntegrationTile(
                            name: "Slack",
                            imageName: "SlackLogo",
                            backgroundColor: Color(red: 0.28, green: 0.16, blue: 0.36),
                            detail: "Toss acts as you in Slack. Send and schedule messages, read channels and DMs, and react to messages—all as yourself.",
                            isConnected: manager.slackStatus?.connected == true,
                            connectedDetail: manager.slackStatus?.teamName,
                            isLoading: manager.isLoading,
                            onConnect: { Task { await manager.connectSlack() } },
                            onDisconnect: { Task { await manager.disconnectSlack() } }
                        )
                        IntegrationTile(
                            name: "Google Calendar",
                            imageName: "GoogleCalendarLogo",
                            backgroundColor: .white,
                            detail: "Sync your calendar so Toss knows about your meetings. Auto-join calls, see upcoming events, and let Toss create calendar invites for you.",
                            isConnected: manager.googleStatus?.connected == true,
                            connectedDetail: manager.googleStatus?.email,
                            isLoading: manager.isLoading,
                            onConnect: { Task { await manager.connectGoogle() } },
                            onDisconnect: { Task { await manager.disconnectGoogle() } }
                        )
                        IntegrationTile(
                            name: "Gmail",
                            imageName: "GmailLogo",
                            backgroundColor: .white,
                            detail: "Send, search, and read emails right from Toss. Draft follow-ups after meetings, check your inbox, and reply to threads—all by voice.",
                            isConnected: manager.gmailStatus?.connected == true,
                            connectedDetail: manager.gmailStatus?.email,
                            isLoading: manager.isLoading,
                            onConnect: { Task { await manager.connectGmail() } },
                            onDisconnect: { Task { await manager.disconnectGmail() } }
                        )
                    }
                }

                // MARK: - Team Integrations
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "person.3.fill")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(AppTheme.secondaryText)
                            Text("Team")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(AppTheme.secondaryText)
                                .textCase(.uppercase)
                        }
                        Text("Shared with your team. Anyone in your org can use them.")
                            .font(.system(size: 12))
                            .foregroundColor(AppTheme.secondaryText.opacity(0.7))
                    }

                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
                        IntegrationTile(
                            name: "Toss Assistant",
                            imageName: "SlackLogo",
                            backgroundColor: Color(red: 0.28, green: 0.16, blue: 0.36),
                            detail: "A Slack bot your whole team can chat with. Ask about meetings, get action items, search contacts, and run automations—right from Slack.",
                            isConnected: manager.slackBotStatus?.installed == true,
                            connectedDetail: manager.slackBotStatus?.teamName,
                            isLoading: manager.isLoading,
                            onConnect: { Task { await manager.connectSlackBot() } },
                            onDisconnect: { Task { await manager.disconnectSlackBot() } },
                            badge: "Bot"
                        )
                        IntegrationTile(
                            name: "Discord Bot",
                            imageName: "DiscordLogo",
                            backgroundColor: Color(red: 0.35, green: 0.40, blue: 0.95),
                            detail: "Use /toss in Discord to create issues, look up meetings, and run actions—responses are private so your customers never see them.",
                            isConnected: manager.discordBotStatus?.installed == true,
                            connectedDetail: manager.discordBotStatus?.guildName,
                            isLoading: manager.isLoading,
                            onConnect: { Task { await manager.connectDiscordBot() } },
                            onDisconnect: { Task { await manager.disconnectDiscordBot() } },
                            badge: "Bot"
                        )
                        IntegrationTile(
                            name: "Linear",
                            imageName: "LinearLogo",
                            backgroundColor: Color(red: 0.36, green: 0.38, blue: 0.96),
                            detail: "Turn meeting action items into Linear issues. Toss can create issues, assign them to teammates, set priority, and link to the right project.",
                            isConnected: manager.linearStatus?.connected == true,
                            connectedDetail: manager.linearStatus?.organizationName,
                            isLoading: manager.isLoading,
                            onConnect: { Task { await manager.connectLinear() } },
                            onDisconnect: { Task { await manager.disconnectLinear() } }
                        )
                        IntegrationTile(
                            name: "Notion",
                            imageName: "NotionLogo",
                            backgroundColor: .white,
                            detail: "Save meeting notes directly to Notion. Toss can create pages, add to databases, and search your workspace to find the right place for your notes.",
                            isConnected: manager.notionStatus?.connected == true,
                            connectedDetail: manager.notionStatus?.workspaceName,
                            isLoading: manager.isLoading,
                            onConnect: { Task { await manager.connectNotion() } },
                            onDisconnect: { Task { await manager.disconnectNotion() } }
                        )
                    }
                }

                // MARK: - Other
                VStack(alignment: .leading, spacing: 16) {
                    Text("Other")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.secondaryText)
                        .textCase(.uppercase)

                    LazyVGrid(columns: gridColumns, alignment: .leading, spacing: 16) {
                        IntegrationTileStatic(
                            name: "Cursor",
                            imageName: "CursorLogo",
                            backgroundColor: .black,
                            detail: "Copy meeting context into Cursor for AI-assisted coding. Great for turning technical discussions into code or getting help with implementation details.",
                            statusText: "Always available",
                            statusColor: .green
                        )
                        IntegrationTileComingSoon(
                            name: "GitHub",
                            imageName: "GitHubLogo",
                            fallbackIcon: "chevron.left.forwardslash.chevron.right",
                            detail: "Create issues and pull requests directly from meetings. Link commits to discussions and keep your code connected to context."
                        )
                    }
                }
            }
            .padding(.horizontal, 32)
            .padding(.top, 8)
            .padding(.bottom, 32)
        }
        .onAppear {
            Task { await manager.fetchSlackStatus() }
            Task { await manager.fetchSlackBotStatus() }
            Task { await manager.fetchDiscordBotStatus() }
            Task { await manager.fetchLinearStatus() }
            Task { await manager.fetchGoogleStatus() }
            Task { await manager.fetchNotionStatus() }
            Task { await manager.fetchGmailStatus() }
        }
        // Force full view recreation when returning from OAuth deep link
        // This works around a SwiftUI text rendering bug that can cause upside-down text
        .id(manager.viewRefreshTrigger)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Integrations")
                .font(.system(size: 26, weight: .bold))
                .foregroundColor(AppTheme.primaryText)

            Text("Connect your favorite apps to supercharge Toss.")
                .font(.system(size: 14))
                .foregroundColor(AppTheme.secondaryText)
        }
    }
}

struct SlackIntegrationCard: View {
    let status: SlackConnectionStatus?
    let isLoading: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Slack logo
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.28, green: 0.16, blue: 0.36))
                Image("SlackLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("Slack")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)

                if let status, status.connected, let team = status.teamName {
                    Text("Connected to \(team)")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                } else {
                    Text("Send and read messages from Slack")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.secondaryText)
                }
            }

            Spacer()

            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            } else if let status, status.connected {
                Button("Disconnect") {
                    onDisconnect()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Connect") {
                    onConnect()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.elevatedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.subtleStroke, lineWidth: 1)
        )
    }
}

struct SlackBotIntegrationCard: View {
    let status: SlackBotConnectionStatus?
    let isLoading: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Toss Assistant logo (Slack with bot indicator)
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.28, green: 0.16, blue: 0.36))
                Image("SlackLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
                // Small bot badge
                Circle()
                    .fill(Color.blue)
                    .frame(width: 14, height: 14)
                    .overlay(
                        Image(systemName: "sparkles")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundColor(.white)
                    )
                    .offset(x: 14, y: 14)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text("Toss Assistant")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)
                    Text("Team")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.blue.opacity(0.15)))
                }

                if let status, status.installed, let team = status.teamName {
                    Text("Installed in \(team)")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                } else {
                    Text("AI assistant your team can chat with in Slack")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.secondaryText)
                }
            }

            Spacer()

            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            } else if let status, status.installed {
                Button("Remove") {
                    onDisconnect()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Install") {
                    onConnect()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.elevatedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.subtleStroke, lineWidth: 1)
        )
    }
}

struct LinearIntegrationCard: View {
    let status: LinearConnectionStatus?
    let isLoading: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    private var requiresReauth: Bool {
        status?.requiresReauth == true
    }

    var body: some View {
        HStack(spacing: 16) {
            // Linear logo
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(
                        requiresReauth
                            ? Color.orange.opacity(0.15) : Color(red: 0.36, green: 0.38, blue: 0.96)
                    )
                if requiresReauth {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.orange)
                } else {
                    Image("LinearLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                }
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("Linear")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)

                if requiresReauth, let org = status?.organizationName {
                    Text("Reconnect required for \(org)")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                } else if let status, status.connected, let org = status.organizationName {
                    Text("Connected to \(org)")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                } else {
                    Text("Create and manage issues")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.secondaryText)
                }
            }

            Spacer()

            if requiresReauth {
                Button("Reconnect") {
                    onConnect()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
            } else if let status, status.connected {
                Button("Disconnect") {
                    onDisconnect()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Connect") {
                    onConnect()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.elevatedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    requiresReauth ? Color.orange.opacity(0.5) : AppTheme.subtleStroke,
                    lineWidth: requiresReauth ? 2 : 1)
        )
    }
}

struct GoogleIntegrationCard: View {
    let status: GoogleConnectionStatus?
    let isLoading: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    private var requiresReauth: Bool {
        status?.requiresReauth == true
    }

    var body: some View {
        HStack(spacing: 16) {
            // Google Calendar logo
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(requiresReauth ? Color.orange.opacity(0.15) : Color.white)
                if requiresReauth {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 20, weight: .bold))
                        .foregroundColor(.orange)
                } else {
                    Image("GoogleCalendarLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                }
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("Google Calendar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)

                if requiresReauth, let email = status?.email {
                    Text("Reconnect required for \(email)")
                        .font(.system(size: 12))
                        .foregroundColor(.orange)
                } else if let status, status.connected, let email = status.email {
                    Text("Connected as \(email)")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                } else {
                    Text("Sync meetings and auto-join calls")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.secondaryText)
                }
            }

            Spacer()

            if requiresReauth {
                Button("Reconnect") {
                    onConnect()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .controlSize(.small)
            } else if let status, status.connected {
                Button("Disconnect") {
                    onDisconnect()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Connect") {
                    onConnect()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.elevatedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(
                    requiresReauth ? Color.orange.opacity(0.5) : AppTheme.subtleStroke,
                    lineWidth: requiresReauth ? 2 : 1)
        )
    }
}

struct CursorIntegrationCard: View {
    var body: some View {
        HStack(spacing: 16) {
            // Cursor logo
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.black)
                Image("CursorLogo")
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 28, height: 28)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("Cursor")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)

                Text("Turn call context into Cursor prompts automatically")
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.secondaryText)
            }

            Spacer()

            Text("Always available")
                .font(.system(size: 12))
                .foregroundColor(.green)
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.elevatedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.subtleStroke, lineWidth: 1)
        )
    }
}

struct NotionIntegrationCard: View {
    let status: NotionConnectionStatus?
    let isLoading: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Notion logo
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)
                if NSImage(named: "NotionLogo") != nil {
                    Image("NotionLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                } else {
                    Image(systemName: "doc.text")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundColor(.black)
                }
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("Notion")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)

                if let status, status.connected, let workspace = status.workspaceName {
                    Text("Connected to \(workspace)")
                        .font(.system(size: 12))
                        .foregroundColor(.green)
                } else {
                    Text("Save meeting notes and search your workspace")
                        .font(.system(size: 12))
                        .foregroundColor(AppTheme.secondaryText)
                }
            }

            Spacer()

            if isLoading {
                ProgressView()
                    .scaleEffect(0.7)
            } else if let status, status.connected {
                Button("Disconnect") {
                    onDisconnect()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
            } else {
                Button("Connect") {
                    onConnect()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.elevatedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.subtleStroke, lineWidth: 1)
        )
    }
}

struct ComingSoonCard: View {
    let name: String
    let imageName: String?
    let fallbackIcon: String
    let description: String

    init(name: String, imageName: String? = nil, fallbackIcon: String, description: String) {
        self.name = name
        self.imageName = imageName
        self.fallbackIcon = fallbackIcon
        self.description = description
    }

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.gray.opacity(0.2))
                if let imageName, NSImage(named: imageName) != nil {
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 28, height: 28)
                        .opacity(0.6)
                } else {
                    Image(systemName: fallbackIcon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)
                }
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text(name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)

                    Text("Coming Soon")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundColor(AppTheme.secondaryText)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.gray.opacity(0.2)))
                }

                Text(description)
                    .font(.system(size: 12))
                    .foregroundColor(AppTheme.secondaryText)
            }

            Spacer()
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.elevatedBackground.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.subtleStroke.opacity(0.5), lineWidth: 1)
        )
        .opacity(0.6)
    }
}

// MARK: - New Tile Components

struct IntegrationTile: View {
    let name: String
    let imageName: String
    let backgroundColor: Color
    let detail: String
    let isConnected: Bool
    let connectedDetail: String?
    let isLoading: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void
    var badge: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(backgroundColor)
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                }
                .frame(width: 40, height: 40)

                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText)
                    if let badge {
                        Text(badge)
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.blue))
                    }
                }
            }

            // Description
            Text(detail)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.secondaryText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            // Status & Action
            HStack {
                if isConnected, let connectedDetail {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 6, height: 6)
                        Text(connectedDetail)
                            .font(.system(size: 10))
                            .foregroundColor(.green)
                            .lineLimit(1)
                    }
                }
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                } else if isConnected {
                    Button("Disconnect") { onDisconnect() }
                        .buttonStyle(.bordered)
                        .controlSize(.mini)
                } else {
                    Button("Connect") { onConnect() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.mini)
                }
            }
        }
        .padding(16)
        .frame(minWidth: 240, maxWidth: 320, minHeight: 160)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.elevatedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(isConnected ? Color.green.opacity(0.3) : AppTheme.subtleStroke, lineWidth: 1)
        )
    }
}

struct IntegrationTileStatic: View {
    let name: String
    let imageName: String
    let backgroundColor: Color
    let detail: String
    let statusText: String
    let statusColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(backgroundColor)
                    Image(imageName)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 24, height: 24)
                }
                .frame(width: 40, height: 40)

                Text(name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)
            }

            // Description
            Text(detail)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.secondaryText)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            // Status
            HStack {
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusText)
                        .font(.system(size: 10))
                        .foregroundColor(statusColor)
                }
                Spacer()
            }
        }
        .padding(16)
        .frame(minWidth: 240, maxWidth: 320, minHeight: 160)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.elevatedBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.subtleStroke, lineWidth: 1)
        )
    }
}

struct IntegrationTileComingSoon: View {
    let name: String
    let imageName: String?
    let fallbackIcon: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color.gray.opacity(0.2))
                    if let imageName, NSImage(named: imageName) != nil {
                        Image(imageName)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 24, height: 24)
                            .opacity(0.5)
                    } else {
                        Image(systemName: fallbackIcon)
                            .font(.system(size: 16, weight: .medium))
                            .foregroundColor(AppTheme.secondaryText.opacity(0.5))
                    }
                }
                .frame(width: 40, height: 40)

                HStack(spacing: 6) {
                    Text(name)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(AppTheme.primaryText.opacity(0.5))
                    Text("Soon")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(AppTheme.secondaryText)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.gray.opacity(0.2)))
                }
            }

            // Description
            Text(detail)
                .font(.system(size: 12))
                .foregroundColor(AppTheme.secondaryText.opacity(0.5))
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)
        }
        .padding(16)
        .frame(minWidth: 240, maxWidth: 320, minHeight: 160)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(AppTheme.elevatedBackground.opacity(0.5))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(AppTheme.subtleStroke.opacity(0.5), lineWidth: 1)
        )
    }
}
