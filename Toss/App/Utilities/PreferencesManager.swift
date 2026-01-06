import Foundation
import SwiftUI

final class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()

    private enum Keys {
        static let hideIdlePill = "hideIdlePill"
    }

    @Published var hideIdlePill: Bool {
        didSet {
            UserDefaults.standard.set(hideIdlePill, forKey: Keys.hideIdlePill)
            NotificationCenter.default.post(name: .hideIdlePillChanged, object: hideIdlePill)
        }
    }

    private init() {
        self.hideIdlePill = UserDefaults.standard.bool(forKey: Keys.hideIdlePill)
    }
}

extension Notification.Name {
    static let hideIdlePillChanged = Notification.Name("hideIdlePillChanged")
}
