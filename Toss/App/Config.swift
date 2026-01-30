import Foundation

enum Config {
    #if DEBUG
        static let serverURL = "http://127.0.0.1:8787"
        static let webAppURL = "http://localhost:3000"
        static let urlScheme = "toss-dev"
    #else
        static let serverURL = "https://api.usetoss.com"
        static let webAppURL = "https://app.usetoss.com"
        static let urlScheme = "toss"
    #endif

    /// Safe URL accessor that crashes with a clear message if URL is invalid
    static var serverBaseURL: URL {
        guard let url = URL(string: serverURL) else {
            fatalError("Invalid server URL configuration: \(serverURL)")
        }
        return url
    }
}
