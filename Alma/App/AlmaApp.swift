import SwiftUI

@main
struct AlmaApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Alma", id: "main") {
            ContentView()
        }
        .defaultSize(width: 820, height: 520)

        Settings { EmptyView() }
    }
}
