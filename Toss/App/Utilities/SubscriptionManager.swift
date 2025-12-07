import AppKit
import Foundation

struct SubscriptionStatus: Codable {
    let hasActiveSubscription: Bool
    let plan: String?
    let status: String?
    let trialEndsAt: String?
    let error: String?

    var isTrialing: Bool {
        status == "trialing"
    }

    var trialEndDate: Date? {
        guard let trialEndsAt else { return nil }
        let formatter = ISO8601DateFormatter()
        return formatter.date(from: trialEndsAt)
    }

    var daysLeftInTrial: Int? {
        guard let endDate = trialEndDate else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Date(), to: endDate).day
        return max(0, days ?? 0)
    }
}

@MainActor
final class SubscriptionManager: ObservableObject {
    static let shared = SubscriptionManager()

    @Published private(set) var status: SubscriptionStatus?
    @Published private(set) var isLoading = false
    @Published private(set) var lastChecked: Date?

    var hasAccess: Bool {
        status?.hasActiveSubscription ?? false
    }

    var needsSubscription: Bool {
        guard let status else { return true }
        return !status.hasActiveSubscription
    }

    private init() {}

    func checkSubscription() async {
        guard AuthManager.shared.isAuthenticated else {
            status = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        guard let url = URL(string: "\(Config.serverURL)/subscription/status") else {
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        do {
            let (data, response) = try await APIClient.shared.perform(request)

            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                NSLog("[SubscriptionManager] Failed to check subscription: bad status")
                return
            }

            let decoded = try JSONDecoder().decode(SubscriptionStatus.self, from: data)
            self.status = decoded
            self.lastChecked = Date()

            NSLog(
                "[SubscriptionManager] Subscription status: hasAccess=\(decoded.hasActiveSubscription), plan=\(decoded.plan ?? "none")"
            )
        } catch {
            NSLog("[SubscriptionManager] Error checking subscription: \(error)")
        }
    }

    func openBillingPortal() {
        guard let url = URL(string: "\(Config.serverURL)/subscription/portal") else { return }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"

        Task {
            do {
                let (data, _) = try await APIClient.shared.perform(request)
                if let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                    let urlString = json["url"] as? String,
                    let portalURL = URL(string: urlString)
                {
                    await MainActor.run {
                        NSWorkspace.shared.open(portalURL)
                    }
                }
            } catch {
                NSLog("[SubscriptionManager] Error getting portal URL: \(error)")
            }
        }
    }
}
