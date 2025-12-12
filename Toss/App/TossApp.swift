import SwiftUI

@main
struct TossApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        // Only the main app window - sign-in is handled by AppDelegate
        Window("Toss", id: "main") {
            MainWindowContent()
                .environmentObject(appDelegate.meetingRepository)
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 900, height: 650)
    }
}
