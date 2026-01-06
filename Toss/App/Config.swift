import Foundation

enum Config {
    #if DEBUG
        static let serverURL = "http://127.0.0.1:8787"
        static let urlScheme = "toss-dev"
    #else
        static let serverURL = "https://api.usetoss.com"
        static let urlScheme = "toss"
    #endif
}
