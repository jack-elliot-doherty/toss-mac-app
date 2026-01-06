import Foundation
import Sparkle

@MainActor
final class UpdateManager: NSObject, ObservableObject {
    static let shared = UpdateManager()

    @Published var updateAvailable = false
    @Published var latestVersion: String?
    @Published var isCheckingForUpdates = false

    private var updaterController: SPUStandardUpdaterController?
    private var periodicTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var lastCheckTime: Date?

    override init() {
        super.init()
    }

    /// Configure with the SPUStandardUpdaterController from AppDelegate
    func configure(with controller: SPUStandardUpdaterController) {
        self.updaterController = controller

        // Enable automatic background downloads so updates are ready when user clicks "Update now"
        controller.updater.automaticallyDownloadsUpdates = true

        // Check for updates silently on launch (after a short delay to let UI settle)
        Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)  // 2 seconds
            await checkForUpdatesInBackground()
        }

        // Set up periodic background checks (every 20 minutes)
        periodicTimer = Timer.scheduledTimer(withTimeInterval: 1200, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.checkForUpdatesInBackground()
            }
        }

        // Also check when app becomes active (user switches back to app)
        // But throttle to avoid checking too frequently (minimum 5 minutes between checks)
        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                guard let self = self else { return }

                // Throttle: only check if last check was more than 5 minutes ago
                let minimumInterval: TimeInterval = 300  // 5 minutes
                if let lastCheck = self.lastCheckTime,
                   Date().timeIntervalSince(lastCheck) < minimumInterval {
                    NSLog("[UpdateManager] Skipping activation check - last check was \(Int(Date().timeIntervalSince(lastCheck)))s ago")
                    return
                }

                NSLog("[UpdateManager] App became active - checking for updates")
                await self.checkForUpdatesInBackground()
            }
        }
    }

    /// Check for updates silently in the background (no UI)
    func checkForUpdatesInBackground() async {
        #if DEBUG
            // Skip update checks in debug builds - dev builds report version "1.0"
            // which would always show as outdated compared to production releases
            NSLog("[UpdateManager] Skipping update check in DEBUG build")
            return
        #endif

        guard let updater = updaterController?.updater else {
            NSLog("[UpdateManager] No updater configured")
            return
        }

        isCheckingForUpdates = true
        NSLog("[UpdateManager] Starting background update check")

        // Use the standard update check but monitor for available updates
        // We'll use UserDefaults to check if Sparkle found an update
        do {
            // Sparkle 2 checks the appcast and caches information
            // We can check if there's a newer version by comparing versions
            guard let feedURL = updater.feedURL else {
                NSLog("[UpdateManager] Feed URL is nil")
                isCheckingForUpdates = false
                return
            }

            NSLog("[UpdateManager] Fetching appcast from: \(feedURL)")
            let currentVersion =
                Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
            NSLog("[UpdateManager] Current app version: \(currentVersion)")

            let (data, response) = try await URLSession.shared.data(from: feedURL)

            if let httpResponse = response as? HTTPURLResponse {
                NSLog("[UpdateManager] Appcast response status: \(httpResponse.statusCode)")
            }

            guard let appcastString = String(data: data, encoding: .utf8) else {
                NSLog("[UpdateManager] Failed to decode appcast data as UTF-8")
                isCheckingForUpdates = false
                return
            }

            NSLog("[UpdateManager] Appcast data length: \(appcastString.count) characters")

            // Parse the latest version from appcast XML
            // Look for sparkle:version or sparkle:shortVersionString
            guard let latestVersionFromFeed = parseLatestVersion(from: appcastString) else {
                NSLog("[UpdateManager] Failed to parse version from appcast. First 500 chars: \(String(appcastString.prefix(500)))")
                isCheckingForUpdates = false
                return
            }

            NSLog("[UpdateManager] Parsed latest version from appcast: \(latestVersionFromFeed)")

            if isNewerVersion(latestVersionFromFeed, than: currentVersion) {
                NSLog(
                    "[UpdateManager] Update available: \(latestVersionFromFeed) (current: \(currentVersion))"
                )
                self.latestVersion = latestVersionFromFeed
                self.updateAvailable = true
            } else {
                NSLog(
                    "[UpdateManager] Already on latest version: \(currentVersion) (feed has: \(latestVersionFromFeed))")
                self.updateAvailable = false
                self.latestVersion = nil
            }
        } catch {
            NSLog("[UpdateManager] Failed to check for updates: \(error.localizedDescription)")
        }

        isCheckingForUpdates = false
        lastCheckTime = Date()
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

        /// Test the actual appcast fetch and parsing (ignores version comparison)
        func debugTestAppcastFetch() async {
            guard let updater = updaterController?.updater else {
                NSLog("[UpdateManager] DEBUG: No updater configured")
                return
            }

            guard let feedURL = updater.feedURL else {
                NSLog("[UpdateManager] DEBUG: Feed URL is nil")
                return
            }

            NSLog("[UpdateManager] DEBUG: Testing appcast fetch from: \(feedURL)")

            do {
                let (data, response) = try await URLSession.shared.data(from: feedURL)

                if let httpResponse = response as? HTTPURLResponse {
                    NSLog("[UpdateManager] DEBUG: Response status: \(httpResponse.statusCode)")
                    NSLog("[UpdateManager] DEBUG: Final URL: \(httpResponse.url?.absoluteString ?? "unknown")")
                }

                guard let appcastString = String(data: data, encoding: .utf8) else {
                    NSLog("[UpdateManager] DEBUG: Failed to decode as UTF-8")
                    return
                }

                NSLog("[UpdateManager] DEBUG: Appcast length: \(appcastString.count) chars")
                NSLog("[UpdateManager] DEBUG: First 300 chars: \(String(appcastString.prefix(300)))")

                if let version = parseLatestVersion(from: appcastString) {
                    NSLog("[UpdateManager] DEBUG: Parsed version: \(version)")
                    // Force show the banner with the actual version from appcast
                    self.latestVersion = version
                    self.updateAvailable = true
                } else {
                    NSLog("[UpdateManager] DEBUG: Failed to parse version")
                }
            } catch {
                NSLog("[UpdateManager] DEBUG: Fetch failed: \(error)")
            }
        }
    #endif
}
