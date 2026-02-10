import Foundation

enum Config {
    #if DEBUG
        static let serverURL = "http://127.0.0.1:8787"
        static let webAppURL = "http://localhost:3000"
        static let urlScheme = "toss-dev"
        static let appDataNamespace = "ai.toss.mac.dev"
    #else
        static let serverURL = "https://api.usetoss.com"
        static let webAppURL = "https://app.usetoss.com"
        static let urlScheme = "toss"
        static let appDataNamespace = "ai.toss.mac"
    #endif

    /// Safe URL accessor that crashes with a clear message if URL is invalid
    static var serverBaseURL: URL {
        guard let url = URL(string: serverURL) else {
            fatalError("Invalid server URL configuration: \(serverURL)")
        }
        return url
    }

    /// Build-scoped app support directory to keep dev and prod local data isolated.
    static var appSupportDirectoryURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let appDir = appSupport.appendingPathComponent(appDataNamespace, isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: appDir, withIntermediateDirectories: true)
        } catch {
            NSLog(
                "[Config] Failed to create app support directory %@: %@",
                appDir.path,
                error.localizedDescription
            )
        }

        return appDir
    }

    static func appSupportFileURL(_ fileName: String) -> URL {
        appSupportDirectoryURL.appendingPathComponent(fileName)
    }

    /// Namespaces UserDefaults keys so dev and prod metadata do not collide.
    static func scopedDefaultsKey(_ key: String) -> String {
        "\(appDataNamespace).\(key)"
    }
}
