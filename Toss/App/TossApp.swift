import SwiftUI

@main
struct TossApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Main window - visibility controlled by AppDelegate based on auth state
        // The window content handles hiding itself when not authenticated
        Window("Toss", id: "main") {
            MainWindowContent()
                .environmentObject(appDelegate.meetingRepository)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 650)
    }
}
