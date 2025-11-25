import ServiceManagement
import SwiftUI

final class LaunchAtLogin: ObservableObject {
    static let shared = LaunchAtLogin()

    @Published var isEnabled: Bool {
        didSet {
            updateRegistration()
        }
    }

    private init() {
        self.isEnabled = SMAppService.mainApp.status == .enabled
    }

    private func updateRegistration() {
        do {
            if isEnabled {
                if SMAppService.mainApp.status == .enabled { return }
                try SMAppService.mainApp.register()
            } else {
                if SMAppService.mainApp.status == .notRegistered { return }
                try SMAppService.mainApp.unregister()
            }
        } catch {
            print("Failed to update launch at login: \(error)")
            // Revert UI on failure if needed
        }
    }
}
