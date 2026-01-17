import Foundation
import SwiftUI

final class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()

    private enum Keys {
        static let hideIdlePill = "hideIdlePill"
        static let meetingReminderTime = "meetingReminderTime"
        static let autoDetectMeetings = "autoDetectMeetings"
    }

    @Published var hideIdlePill: Bool {
        didSet {
            UserDefaults.standard.set(hideIdlePill, forKey: Keys.hideIdlePill)
            NotificationCenter.default.post(name: .hideIdlePillChanged, object: hideIdlePill)
        }
    }

    @Published var meetingReminderTime: String {
        didSet {
            UserDefaults.standard.set(meetingReminderTime, forKey: Keys.meetingReminderTime)
            NotificationCenter.default.post(name: .meetingReminderTimeChanged, object: meetingReminderTime)
        }
    }

    @Published var autoDetectMeetings: Bool {
        didSet {
            UserDefaults.standard.set(autoDetectMeetings, forKey: Keys.autoDetectMeetings)
            NotificationCenter.default.post(name: .autoDetectMeetingsChanged, object: autoDetectMeetings)
        }
    }

    private init() {
        self.hideIdlePill = UserDefaults.standard.bool(forKey: Keys.hideIdlePill)
        self.meetingReminderTime = UserDefaults.standard.string(forKey: Keys.meetingReminderTime) ?? "Before 1m"
        self.autoDetectMeetings = UserDefaults.standard.object(forKey: Keys.autoDetectMeetings) as? Bool ?? true
    }
}

extension Notification.Name {
    static let hideIdlePillChanged = Notification.Name("hideIdlePillChanged")
    static let meetingReminderTimeChanged = Notification.Name("meetingReminderTimeChanged")
    static let autoDetectMeetingsChanged = Notification.Name("autoDetectMeetingsChanged")
}
