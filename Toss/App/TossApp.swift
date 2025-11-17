import SwiftUI

@main
struct TossApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Toss", id: "main") {
            ContentView().environmentObject(appDelegate.meetingRepository)
        }
        .defaultSize(width: 820, height: 520)
    }
}
