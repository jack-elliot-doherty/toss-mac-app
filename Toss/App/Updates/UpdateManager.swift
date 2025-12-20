import Foundation
import Sparkle

@MainActor
final class UpdateManager: NSObject, ObservableObject {
    static let shared = UpdateManager()

    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var isCheckingForUpdates = false

    private var updaterController: SPUStandardUpdaterController?

    override init() {
        super.init()
    }

    /// Configure with the SPUStandardUpdaterController from AppDelegate
    func configure(with controller: SPUStandardUpdaterController) {
        self.updaterController = controller

        // Enable automatic background downloads so updates are ready when user clicks "Update now"
        controller.updater.automaticallyDownloadsUpdates = true

        // Check for updates silently on launch (after a delay)
        Task {
            try? await Task.sleep(nanoseconds: 3_000_000_000)  // 3 seconds
            await checkForUpdatesInBackground()
        }

        // Set up periodic background checks (every 2 hours)
        Timer.scheduledTimer(withTimeInterval: 7200, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkForUpdatesInBackground()
            }
        }
    }

    /// Check for updates silently in the background (no UI)
    func checkForUpdatesInBackground() async {
        guard let updater = updaterController?.updater else {
            NSLog("[UpdateManager] No updater configured")
            return
        }

        isCheckingForUpdates = true

        // Use the standard update check but monitor for available updates
        // We'll use UserDefaults to check if Sparkle found an update
        do {
            // Sparkle 2 checks the appcast and caches information
            // We can check if there's a newer version by comparing versions
            if let feedURL = updater.feedURL {
                let currentVersion =
                    Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

                let (data, _) = try await URLSession.shared.data(from: feedURL)
                if let appcastString = String(data: data, encoding: .utf8) {
                    // Parse the latest version from appcast XML
                    // Look for sparkle:version or sparkle:shortVersionString
                    if let latestVersionFromFeed = parseLatestVersion(from: appcastString) {
                        if isNewerVersion(latestVersionFromFeed, than: currentVersion) {
                            NSLog(
                                "[UpdateManager] Update available: \(latestVersionFromFeed) (current: \(currentVersion))"
                            )
                            self.latestVersion = latestVersionFromFeed
                            self.updateAvailable = true
                        } else {
                            NSLog(
                                "[UpdateManager] Already on latest version: \(currentVersion)")
                            self.updateAvailable = false
                            self.latestVersion = nil
                        }
                    }
                }
            }
        } catch {
            NSLog("[UpdateManager] Failed to check for updates: \(error.localizedDescription)")
        }

        isCheckingForUpdates = false
    }

    /// Show the Sparkle update UI to install the update
    func installUpdate() {
        guard let updater = updaterController?.updater else {
            NSLog("[UpdateManager] No updater configured")
            return
        }
        NSLog("[UpdateManager] Triggering update install")
        updater.checkForUpdates()
    }

    /// Parse the latest version from appcast XML
    private func parseLatestVersion(from appcast: String) -> String? {
        // The appcast uses XML element format with namespace prefix (ns0: or sparkle:)
        // e.g., <ns0:shortVersionString>1.2.54</ns0:shortVersionString>
        // or <sparkle:shortVersionString>1.2.54</sparkle:shortVersionString>

        // Try to find the first shortVersionString element with any namespace prefix
        // Pattern: <PREFIX:shortVersionString>VERSION</PREFIX:shortVersionString>
        let patterns = [
            // Element format with ns0 prefix (our current format)
            "<ns0:shortVersionString>",
            // Element format with sparkle prefix
            "<sparkle:shortVersionString>",
            // Attribute format (some appcasts use this)
            "sparkle:shortVersionString=\"",
            "ns0:shortVersionString=\"",
        ]

        for pattern in patterns {
            if let range = appcast.range(of: pattern) {
                let start = range.upperBound
                // Determine the closing delimiter based on whether it's element or attribute format
                let closingDelimiter = pattern.hasSuffix("\"") ? "\"" : "<"
                if let endRange = appcast[start...].range(of: closingDelimiter) {
                    let version = String(appcast[start..<endRange.lowerBound])
                    if !version.isEmpty {
                        return version
                    }
                }
            }
        }

        // Fall back to version element/attribute
        let versionPatterns = [
            "<ns0:version>",
            "<sparkle:version>",
            "sparkle:version=\"",
            "ns0:version=\"",
        ]

        for pattern in versionPatterns {
            if let range = appcast.range(of: pattern) {
                let start = range.upperBound
                let closingDelimiter = pattern.hasSuffix("\"") ? "\"" : "<"
                if let endRange = appcast[start...].range(of: closingDelimiter) {
                    let version = String(appcast[start..<endRange.lowerBound])
                    if !version.isEmpty {
                        return version
                    }
                }
            }
        }

        return nil
    }

    /// Compare two semantic versions
    private func isNewerVersion(_ version1: String, than version2: String) -> Bool {
        let v1Components = version1.split(separator: ".").compactMap { Int($0) }
        let v2Components = version2.split(separator: ".").compactMap { Int($0) }

        let maxLength = max(v1Components.count, v2Components.count)

        for i in 0..<maxLength {
            let v1Part = i < v1Components.count ? v1Components[i] : 0
            let v2Part = i < v2Components.count ? v2Components[i] : 0

            if v1Part > v2Part {
                return true
            } else if v1Part < v2Part {
                return false
            }
        }

        return false  // Versions are equal
    }

    /// Dismiss the update notification (user chose to skip for now)
    func dismissUpdate() {
        updateAvailable = false
    }

    #if DEBUG
        /// Force show the update banner for testing purposes
        func debugForceShowUpdate(version: String = "99.0.0") {
            NSLog("[UpdateManager] DEBUG: Forcing update banner to show")
            self.latestVersion = version
            self.updateAvailable = true
        }
    #endif
}
