// import Sparkle
import SwiftUI

@main
struct TossApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Window("Toss", id: "main") {
            ContentView()
        }
        .defaultSize(width: 820, height: 520)
        // .commands {
        //     CommandGroup(after: .appInfo) {
        //         CheckForUpdatesView(updater: appDelegate.updaterController.updater)
        //     }
        // }

        Settings { EmptyView() }
    }
}

// struct CheckForUpdatesView: View {
//     var updater: SPUUpdater
//     var body: some View {
//         Button("Check for Updates") {
//             updater.checkForUpdates()
//         }.disabled(!updater.canCheckForUpdates)
//     }
// }
