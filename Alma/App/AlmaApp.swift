import SwiftUI

@main
struct AlmaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // No main window. Keep a Settings scene to satisfy SwiftUI.
        Settings { EmptyView() }
    }
}
