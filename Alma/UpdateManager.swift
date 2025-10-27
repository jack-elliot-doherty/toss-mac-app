import Foundation

final class UpdateManager {
    static let shared = UpdateManager()

    // Change this to your hosted appcast.xml URL (HTTPS)
    // Example: https://your.cdn.com/alma/appcast.xml
    var appcastURLString: String? = nil

    func checkForUpdates() {
        #if canImport(Sparkle)
        if let urlString = appcastURLString, let url = URL(string: urlString) {
            let updater = Sparkle.SUUpdater()
            updater.feedURL = url
            updater.automaticallyChecksForUpdates = false
            updater.checkForUpdates(nil)
            return
        }
        // Fall back to default Sparkle configuration (Info.plist SUPublicEDKey + SUFeedURL)
        let updater = Sparkle.SUUpdater()
        updater.automaticallyChecksForUpdates = false
        updater.checkForUpdates(nil)
        #else
        NSLog("[UpdateManager] Sparkle is not linked; skipping update check")
        #endif
    }
}


