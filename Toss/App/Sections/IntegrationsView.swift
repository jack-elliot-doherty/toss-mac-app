import SwiftUI

struct SlackConnectionStatus: Codable {
    let connected: Bool
    let teamName: String?
}

struct LinearConnectionStatus: Codable {
    let connected: Bool
    let organizationName: String?
}

struct GoogleConnectionStatus: Codable {
    let connected: Bool
    let email: String?
}

@MainActor
final class IntegrationsManager: ObservableObject {
    static let shared = IntegrationsManager()

    @Published var slackStatus: SlackConnectionStatus?
    @Published var linearStatus: LinearConnectionStatus?
    @Published var googleStatus: GoogleConnectionStatus?

    @Published var isLoading = false
    @Published var error: String?

    func fetchSlackStatus() async {
        guard let token = AuthManager.shared.accessToken else { return }
        guard let url = URL(string: "\(Config.serverURL)/slack/status") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            isLoading = true
            let (data, response) = try await URLSession.shared.data(for: request)
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
        guard let token = AuthManager.shared.accessToken else { return }
        guard let url = URL(string: "\(Config.serverURL)/slack/connect") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

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
        guard let token = AuthManager.shared.accessToken else { return }
        guard let url = URL(string: "\(Config.serverURL)/slack/disconnect") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                slackStatus = SlackConnectionStatus(connected: false, teamName: nil)
            }
        } catch {
            NSLog("[Integrations] Failed to disconnect Slack: %@", error.localizedDescription)
        }
    }

    // 3. Add Google Methods
    func fetchGoogleStatus() async {
        guard let token = AuthManager.shared.accessToken else { return }
        guard let url = URL(string: "\(Config.serverURL)/google/status") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                googleStatus = try JSONDecoder().decode(GoogleConnectionStatus.self, from: data)
            }
        } catch {
            NSLog("[Integrations] Failed to fetch Google status: %@", error.localizedDescription)
        }
    }

    func connectGoogle() async {
        guard let token = AuthManager.shared.accessToken else { return }
        guard let url = URL(string: "\(Config.serverURL)/google/connect") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

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
        guard let token = AuthManager.shared.accessToken else { return }
        guard let url = URL(string: "\(Config.serverURL)/google/disconnect") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                googleStatus = GoogleConnectionStatus(connected: false, email: nil)
            }
        } catch {
            NSLog("[Integrations] Failed to disconnect Google: %@", error.localizedDescription)
        }
    }

    func handleDeepLink(url: URL) -> Bool {
        // toss://integrations/slack?connected=1
        guard url.scheme == "toss", url.host == "integrations" else { return false }

        let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
        let connected = comps?.queryItems?.first(where: { $0.name == "connected" })?.value == "1"
        if url.path == "/slack" {
            if connected {
                Task { await fetchSlackStatus() }
            }
            return true
        } else if url.path == "/linear" {
            if connected { Task { await fetchLinearStatus() } }
            return true
        } else if url.path == "/google" {
            if connected {
                Task {
                    await fetchGoogleStatus()
                    // Trigger calendar sync immediately after connecting
                    await MeetingsManager.shared.syncCalendar()
                }
            }
            return true
        }
        return false
    }

    func fetchLinearStatus() async {
        guard let token = AuthManager.shared.accessToken else { return }
        guard let url = URL(string: "\(Config.serverURL)/linear/status") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            // Don't block UI with global loading, just fetch
            let (data, response) = try await URLSession.shared.data(for: request)

            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                linearStatus = try JSONDecoder().decode(LinearConnectionStatus.self, from: data)
            }
        } catch {
            NSLog("[Integrations] Failed to fetch Linear status: %@", error.localizedDescription)
        }
    }

    func connectLinear() async {
        guard let token = AuthManager.shared.accessToken else { return }
        guard let url = URL(string: "\(Config.serverURL)/linear/connect") else { return }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (data, response) = try await URLSession.shared.data(for: request)

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
        guard let token = AuthManager.shared.accessToken else { return }
        guard let url = URL(string: "\(Config.serverURL)/linear/disconnect") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            if let http = response as? HTTPURLResponse, http.statusCode == 200 {
                linearStatus = LinearConnectionStatus(connected: false, organizationName: nil)
            }
        } catch {
            NSLog("[Integrations] Failed to disconnect Linear: %@", error.localizedDescription)
        }
    }
}

@MainActor
struct IntegrationsView: View {
    @StateObject private var manager = IntegrationsManager.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                VStack(alignment: .leading, spacing: 12) {
                    Text("Connected Apps")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(AppTheme.secondaryText)
                        .textCase(.uppercase)

                    SlackIntegrationCard(
                        status: manager.slackStatus,
                        isLoading: manager.isLoading,
                        onConnect: { Task { await manager.connectSlack() } },
                        onDisconnect: { Task { await manager.disconnectSlack() } }
                    )
                    // 5. Add Linear Card
                    LinearIntegrationCard(
                        status: manager.linearStatus,
                        isLoading: manager.isLoading,
                        onConnect: { Task { await manager.connectLinear() } },
                        onDisconnect: { Task { await manager.disconnectLinear() } }
                    )
                    GoogleIntegrationCard(
                        status: manager.googleStatus,
                        isLoading: manager.isLoading,
                        onConnect: { Task { await manager.connectGoogle() } },
                        onDisconnect: { Task { await manager.disconnectGoogle() } }
                    )

                    // Future integrations go here
                    ComingSoonCard(
                        name: "Linear", icon: "square.stack.3d.up",
                        description: "Create and manage issues")
                    ComingSoonCard(
                        name: "Notion", icon: "doc.text", description: "Access your workspace")
                }
            }
            .padding(.horizontal, 32)
            .padding(.vertical, 32)
        }
        .onAppear {
            Task { await manager.fetchSlackStatus() }
            Task { await manager.fetchLinearStatus() }
            Task { await manager.fetchGoogleStatus() }
        }
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
            // Slack logo placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.28, green: 0.16, blue: 0.36))
                Image(systemName: "number")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
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

struct LinearIntegrationCard: View {
    let status: LinearConnectionStatus?
    let isLoading: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Linear logo placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(red: 0.36, green: 0.38, blue: 0.96))  // Linear Purple
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.white)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("Linear")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)

                if let status, status.connected, let org = status.organizationName {
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

            if let status, status.connected {
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

struct GoogleIntegrationCard: View {
    let status: GoogleConnectionStatus?
    let isLoading: Bool
    let onConnect: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 16) {
            // Google logo placeholder
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white)  // Google usually white bg
                Image(systemName: "calendar")  // Placeholder for GCal icon
                    .font(.system(size: 20, weight: .bold))
                    .foregroundColor(.blue)
            }
            .frame(width: 48, height: 48)

            VStack(alignment: .leading, spacing: 4) {
                Text("Google Calendar")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.primaryText)

                if let status, status.connected, let email = status.email {
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

            if let status, status.connected {
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
    let icon: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.gray.opacity(0.2))
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium))
                    .foregroundColor(AppTheme.secondaryText)
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
