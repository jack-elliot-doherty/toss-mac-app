import Foundation
import SwiftUI

// MARK: - Shortcut Options

enum ShortcutOption: String, CaseIterable, Codable {
    case enabled = "enabled"
    case disabled = "disabled"

    var displayName: String {
        switch self {
        case .enabled: return "Hold Fn (Globe)"
        case .disabled: return "No shortcut"
        }
    }

    var agentModeDisplayName: String {
        switch self {
        case .enabled: return "Hold Fn + \u{2318}"
        case .disabled: return "No shortcut"
        }
    }

    var doubleOptionDisplayName: String {
        switch self {
        case .enabled: return "Double-tap ⌥ Option"
        case .disabled: return "No shortcut"
        }
    }
}

final class PreferencesManager: ObservableObject {
    static let shared = PreferencesManager()

    private enum Keys {
        static let hideIdlePill = "hideIdlePill"
        static let meetingReminderTime = "meetingReminderTime"
        static let autoDetectMeetings = "autoDetectMeetings"
        static let dictationShortcut = "dictationShortcut"
        static let agentModeShortcut = "agentModeShortcut"
        static let doubleOptionShortcut = "doubleOptionShortcut"
        static let hideFromScreenCapture = "hideFromScreenCapture"
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
            NotificationCenter.default.post(
                name: .meetingReminderTimeChanged, object: meetingReminderTime)
        }
    }

    @Published var autoDetectMeetings: Bool {
        didSet {
            UserDefaults.standard.set(autoDetectMeetings, forKey: Keys.autoDetectMeetings)
            NotificationCenter.default.post(
                name: .autoDetectMeetingsChanged, object: autoDetectMeetings)
        }
    }

    @Published var dictationShortcut: ShortcutOption {
        didSet {
            UserDefaults.standard.set(dictationShortcut.rawValue, forKey: Keys.dictationShortcut)
            NotificationCenter.default.post(
                name: .dictationShortcutChanged, object: dictationShortcut)
        }
    }

    @Published var agentModeShortcut: ShortcutOption {
        didSet {
            UserDefaults.standard.set(agentModeShortcut.rawValue, forKey: Keys.agentModeShortcut)
            NotificationCenter.default.post(
                name: .agentModeShortcutChanged, object: agentModeShortcut)
        }
    }

    @Published var doubleOptionShortcut: ShortcutOption {
        didSet {
            UserDefaults.standard.set(
                doubleOptionShortcut.rawValue, forKey: Keys.doubleOptionShortcut)
            NotificationCenter.default.post(
                name: .doubleOptionShortcutChanged, object: doubleOptionShortcut)
        }
    }

    @Published var hideFromScreenCapture: Bool {
        didSet {
            UserDefaults.standard.set(hideFromScreenCapture, forKey: Keys.hideFromScreenCapture)
            NotificationCenter.default.post(
                name: .hideFromScreenCaptureChanged, object: hideFromScreenCapture)
        }
    }

    private init() {
        self.hideIdlePill = UserDefaults.standard.bool(forKey: Keys.hideIdlePill)
        self.meetingReminderTime =
            UserDefaults.standard.string(forKey: Keys.meetingReminderTime) ?? "Before 1m"
        self.autoDetectMeetings =
            UserDefaults.standard.object(forKey: Keys.autoDetectMeetings) as? Bool ?? true
        self.hideFromScreenCapture = UserDefaults.standard.bool(forKey: Keys.hideFromScreenCapture)

        // Load shortcut preferences (default to enabled)
        if let dictationRaw = UserDefaults.standard.string(forKey: Keys.dictationShortcut),
            let dictation = ShortcutOption(rawValue: dictationRaw)
        {
            self.dictationShortcut = dictation
        } else {
            self.dictationShortcut = .enabled
        }

        if let agentModeRaw = UserDefaults.standard.string(forKey: Keys.agentModeShortcut),
            let agentMode = ShortcutOption(rawValue: agentModeRaw)
        {
            self.agentModeShortcut = agentMode
        } else {
            self.agentModeShortcut = .enabled
        }

        if let doubleOptionRaw = UserDefaults.standard.string(forKey: Keys.doubleOptionShortcut),
            let doubleOption = ShortcutOption(rawValue: doubleOptionRaw)
        {
            self.doubleOptionShortcut = doubleOption
        } else {
            self.doubleOptionShortcut = .enabled
        }
    }
}

extension Notification.Name {
    static let hideIdlePillChanged = Notification.Name("hideIdlePillChanged")
    static let meetingReminderTimeChanged = Notification.Name("meetingReminderTimeChanged")
    static let autoDetectMeetingsChanged = Notification.Name("autoDetectMeetingsChanged")
    static let dictationShortcutChanged = Notification.Name("dictationShortcutChanged")
    static let agentModeShortcutChanged = Notification.Name("agentModeShortcutChanged")
    static let doubleOptionShortcutChanged = Notification.Name("doubleOptionShortcutChanged")
    static let hideFromScreenCaptureChanged = Notification.Name("hideFromScreenCaptureChanged")
}
