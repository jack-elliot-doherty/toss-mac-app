import Foundation

enum Config {
    #if DEBUG
        static let serverURL = "http://127.0.0.1:8787"
    #else
        static let serverURL = "https://api.usetoss.com"
    #endif
}
