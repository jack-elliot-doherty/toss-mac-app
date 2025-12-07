import AVFoundation
import AppKit
import CoreAudio
import Foundation

final class MeetingDetector {
    private var appObserver: NSObjectProtocol?
    private var audioPropertyListener: AudioObjectPropertyListenerBlock?
    private var currentMeetingApp: String?

    private var isDictationMicActive = false
    private var isRecordingMeeting = false  // Track if we're currently recording
    private var micInactiveTimer: Timer?  // Debounce timer for end detection
    private var monitoredDeviceID: AudioDeviceID = 0  // Store device ID for continuous monitoring

    // Slack huddle monitoring
    private var slackHuddleCheckTimer: Timer?
    private var wasInSlackHuddle = false

    var onMeetingDetected: (() -> Void)?
    var onMeetingEnded: (() -> Void)?  // New callback for meeting end

    // Apps to monitor (user could configure this later)
    private var enabledMeetingApps = [
        "com.tinyspeck.slackmacgap": "Slack",
        "us.zoom.xos": "Zoom",
        "com.microsoft.teams2": "Microsoft Teams",
        "com.google.Chrome": "Chrome",
        "com.apple.Safari": "Safari",
    ]

    func start() {
        // Monitor app activation
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            else { return }
            self?.handleAppActivation(app)
        }

        // Start monitoring system audio input
        startAudioInputMonitoring()

        // observe Toss mic usage so we can ignore it when it's active
        NotificationCenter.default.addObserver(
            forName: .tossMicUsageChanged,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let active = (note.userInfo?["active"] as? Bool) ?? false
            self?.isDictationMicActive = active
        }

        NSLog("[MeetingDetector] Started monitoring")
    }

    func stop() {
        if let observer = appObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        stopAudioInputMonitoring()
        NSLog("[MeetingDetector] Stopped")
    }

    private func handleAppActivation(_ app: NSRunningApplication) {
        guard let bundleId = app.bundleIdentifier else { return }

        if let appName = enabledMeetingApps[bundleId] {
            NSLog("[MeetingDetector] Meeting app activated: \(appName)")
            currentMeetingApp = appName
        } else {
            currentMeetingApp = nil
        }
    }

    private func startAudioInputMonitoring() {
        // Get the default input device
        var deviceID = AudioDeviceID(0)
        var propertySize = UInt32(MemoryLayout<AudioDeviceID>.size)

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultInputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &deviceID
        )

        guard status == noErr else {
            NSLog("[MeetingDetector] Failed to get input device")
            return
        }

        monitoredDeviceID = deviceID  // Store for later use

        // Monitor when the input device is being used
        propertyAddress.mSelector = kAudioDevicePropertyDeviceIsRunningSomewhere

        let listenerBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.checkIfMicIsActive(deviceID: deviceID)
        }

        AudioObjectAddPropertyListenerBlock(
            deviceID,
            &propertyAddress,
            DispatchQueue.main,
            listenerBlock
        )

        audioPropertyListener = listenerBlock

        NSLog("[MeetingDetector] Monitoring audio input device")
    }

    private func stopAudioInputMonitoring() {
        // Remove listener if needed
        audioPropertyListener = nil
    }

    private func checkIfMicIsActive(deviceID: AudioDeviceID) {

        // If its us using the mic, we should ignore it
        if isDictationMicActive {
            return
        }

        var isRunning: UInt32 = 0
        var propertySize = UInt32(MemoryLayout<UInt32>.size)

        var propertyAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let status = AudioObjectGetPropertyData(
            deviceID,
            &propertyAddress,
            0,
            nil,
            &propertySize,
            &isRunning
        )

        if status == noErr && isRunning != 0 {
            // Mic is active!
            if let appName = currentMeetingApp {
                NSLog("[MeetingDetector] Mic active in \(appName) - triggering detection!")

                // Wait 4 seconds before showing toast (let user focus on joining)
                DispatchQueue.main.asyncAfter(deadline: .now() + 4.0) { [weak self] in
                    NSLog("[MeetingDetector] Showing meeting detection prompt")
                    self?.onMeetingDetected?()
                }
                currentMeetingApp = nil  // Only trigger once per session
            }
        }
    }

    // Call this when meeting recording starts
    func setRecordingActive(_ active: Bool) {
        isRecordingMeeting = active
        if active {
            // Start monitoring for Slack huddle end
            startSlackHuddleMonitoring()
            startMeetingEndMonitoring()
        } else {
            stopSlackHuddleMonitoring()
            stopMeetingEndMonitoring()
        }
        NSLog("[MeetingDetector] Recording active: \(active)")
    }

    // MARK: - Slack Huddle Detection via Accessibility

    private func startSlackHuddleMonitoring() {
        // Check if currently in a huddle
        wasInSlackHuddle = isSlackInHuddle()
        NSLog(
            "[MeetingDetector] Starting Slack huddle monitoring. Currently in huddle: \(wasInSlackHuddle)"
        )

        // Poll every 2 seconds to check huddle state
        slackHuddleCheckTimer?.invalidate()
        slackHuddleCheckTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) {
            [weak self] _ in
            self?.checkSlackHuddleState()
        }
    }

    private func stopSlackHuddleMonitoring() {
        slackHuddleCheckTimer?.invalidate()
        slackHuddleCheckTimer = nil
        wasInSlackHuddle = false
    }

    private func checkSlackHuddleState() {
        guard isRecordingMeeting else { return }

        let currentlyInHuddle = isSlackInHuddle()

        if wasInSlackHuddle && !currentlyInHuddle {
            // Was in huddle, now not -> huddle ended!
            NSLog("[MeetingDetector] Slack huddle ended - triggering meeting end")
            onMeetingEnded?()
            stopSlackHuddleMonitoring()
        } else {
            wasInSlackHuddle = currentlyInHuddle
        }
    }

    private func isSlackInHuddle() -> Bool {
        NSLog("[MeetingDetector] === Starting Slack huddle check ===")

        // Find Slack app
        guard
            let slackApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == "com.tinyspeck.slackmacgap"
            })
        else {
            NSLog("[MeetingDetector] Slack app not found in running applications")
            return false
        }

        NSLog("[MeetingDetector] Found Slack app, PID: \(slackApp.processIdentifier)")

        let slackElement = AXUIElementCreateApplication(slackApp.processIdentifier)

        // Get all windows
        var windowsRef: CFTypeRef?
        let windowsResult = AXUIElementCopyAttributeValue(
            slackElement, kAXWindowsAttribute as CFString, &windowsRef)

        guard windowsResult == .success, let windows = windowsRef as? [AXUIElement] else {
            NSLog(
                "[MeetingDetector] Failed to get Slack windows, result: \(windowsResult.rawValue)")
            return false
        }

        NSLog("[MeetingDetector] Found \(windows.count) Slack window(s)")

        // Check each window for huddle indicators
        for (windowIndex, window) in windows.enumerated() {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
            let windowTitle = (titleRef as? String) ?? "<no title>"

            NSLog("[MeetingDetector] Window \(windowIndex): '\(windowTitle)'")

            // Check for 🎤 emoji in title - Slack adds this when in a huddle!
            if windowTitle.contains("🎤") {
                NSLog("[MeetingDetector] ✓ Found huddle indicator (🎤) in window title!")
                return true
            }

            // Also check for "Huddle" in title (for pop-out huddle window)
            if windowTitle.lowercased().contains("huddle") {
                NSLog("[MeetingDetector] ✓ Found 'huddle' in window title!")
                return true
            }
        }

        NSLog("[MeetingDetector] === No huddle indicators found ===")
        return false
    }

    // MARK: - Multi-App Detection

    private enum MeetingAppType: CustomStringConvertible {
        case slack
        case zoom
        case teams
        case chrome  // Google Meet
        case safari  // Google Meet

        var description: String {
            switch self {
            case .slack: return "Slack"
            case .zoom: return "Zoom"
            case .teams: return "Microsoft Teams"
            case .chrome: return "Chrome (Google Meet)"
            case .safari: return "Safari (Google Meet)"
            }
        }
    }

    private var detectedMeetingApp: MeetingAppType?
    private var appMonitoringTimer: Timer?

    private func detectCurrentMeetingApp() -> MeetingAppType? {
        // Check which meeting app is currently active/in foreground
        guard let frontApp = NSWorkspace.shared.frontmostApplication,
            let bundleId = frontApp.bundleIdentifier
        else {
            return nil
        }

        switch bundleId {
        case "com.tinyspeck.slackmacgap":
            return .slack
        case "us.zoom.xos":
            return .zoom
        case "com.microsoft.teams2":
            return .teams
        case "com.google.Chrome":
            // Check if it's actually a Meet tab
            if isBrowserInMeet() {
                return .chrome
            }
            return nil
        case "com.apple.Safari":
            if isBrowserInMeet() {
                return .safari
            }
            return nil
        default:
            return nil
        }
    }

    private func startMeetingEndMonitoring() {
        // Determine which app we're likely in based on what was active when recording started
        detectedMeetingApp = detectCurrentMeetingApp()

        NSLog(
            "[MeetingDetector] Monitoring for meeting end in: \(detectedMeetingApp?.description ?? "unknown")"
        )

        appMonitoringTimer?.invalidate()
        appMonitoringTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) {
            [weak self] _ in
            self?.checkMeetingEndState()
        }
    }

    private func checkMeetingEndState() {
        guard isRecordingMeeting else { return }

        switch detectedMeetingApp {
        case .slack:
            if !isSlackInHuddle() {
                triggerMeetingEnded(reason: "Slack huddle ended")
            }
        case .zoom:
            if !isZoomInMeeting() {
                triggerMeetingEnded(reason: "Zoom meeting ended")
            }
        case .teams:
            if !isTeamsInCall() {
                triggerMeetingEnded(reason: "Teams call ended")
            }
        case .chrome, .safari:
            if !isBrowserInMeet() {
                triggerMeetingEnded(reason: "Google Meet ended")
            }
        case .none:
            // Fall back to hybrid detection
            break
        }
    }

    // MARK: - Zoom Detection

    private func isZoomInMeeting() -> Bool {
        guard
            let zoomApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == "us.zoom.xos"
            })
        else {
            return false
        }

        let zoomElement = AXUIElementCreateApplication(zoomApp.processIdentifier)

        var windowsRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(zoomElement, kAXWindowsAttribute as CFString, &windowsRef)
                == .success,
            let windows = windowsRef as? [AXUIElement]
        else {
            return false
        }

        for window in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)

            if let title = titleRef as? String {
                // Zoom meeting window has "Zoom Meeting" in title, or shows meeting controls
                if title.contains("Zoom Meeting") || title.contains("Zoom Webinar") {
                    return true
                }
            }

            // Also check for the meeting toolbar (small controls window)
            var sizeRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXSizeAttribute as CFString, &sizeRef)
            if let sizeValue = sizeRef {
                var size = CGSize.zero
                if AXValueGetValue(sizeValue as! AXValue, .cgSize, &size) {
                    // Meeting toolbar is typically wide but short
                    if size.width > 400 && size.height < 100 && size.height > 30 {
                        return true
                    }
                }
            }
        }

        return false
    }

    // MARK: - Teams Detection

    private func isTeamsInCall() -> Bool {
        guard
            let teamsApp = NSWorkspace.shared.runningApplications.first(where: {
                $0.bundleIdentifier == "com.microsoft.teams2"
            })
        else {
            return false
        }

        let teamsElement = AXUIElementCreateApplication(teamsApp.processIdentifier)

        var windowsRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                teamsElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
            let windows = windowsRef as? [AXUIElement]
        else {
            return false
        }

        for window in windows {
            var titleRef: CFTypeRef?
            AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)

            if let title = titleRef as? String {
                // Teams call/meeting windows
                if title.contains("Meeting") || title.contains("Call with") {
                    return true
                }
            }
        }

        return false
    }

    // MARK: - Browser (Google Meet) Detection

    // Track if we've seen active audio/mic in current session
    private var meetHasActiveAudio = false

    private func isBrowserInMeet() -> Bool {
        NSLog("[MeetingDetector] === Starting Google Meet check ===")

        let browserBundleIds = [
            "com.google.Chrome",
            "com.apple.Safari",
            "org.mozilla.firefox",
            "com.microsoft.edgemac",
            "company.thebrowser.Browser",  // Arc browser
        ]

        for bundleId in browserBundleIds {
            guard
                let browserApp = NSWorkspace.shared.runningApplications.first(where: {
                    $0.bundleIdentifier == bundleId
                })
            else {
                continue
            }

            let browserName = browserApp.localizedName ?? bundleId
            NSLog(
                "[MeetingDetector] Checking browser: \(browserName) (PID: \(browserApp.processIdentifier))"
            )

            let browserElement = AXUIElementCreateApplication(browserApp.processIdentifier)

            var windowsRef: CFTypeRef?
            guard
                AXUIElementCopyAttributeValue(
                    browserElement, kAXWindowsAttribute as CFString, &windowsRef) == .success,
                let windows = windowsRef as? [AXUIElement]
            else {
                NSLog("[MeetingDetector] Failed to get windows for \(browserName)")
                continue
            }

            NSLog("[MeetingDetector] Found \(windows.count) window(s) for \(browserName)")

            for (windowIndex, window) in windows.enumerated() {
                var titleRef: CFTypeRef?
                AXUIElementCopyAttributeValue(window, kAXTitleAttribute as CFString, &titleRef)
                let title = (titleRef as? String) ?? "<no title>"

                NSLog("[MeetingDetector] \(browserName) Window \(windowIndex): '\(title)'")

                // Check if this is a Google Meet window
                let isMeetWindow =
                    title.hasPrefix("Meet – ") || title.hasPrefix("Meet -")
                    || title.contains("- Google Meet") || title.contains("– Google Meet")

                if !isMeetWindow {
                    continue
                }

                // Check for active audio/mic indicators (Chrome shows these when mic/speakers active)
                let hasActiveAudio =
                    title.contains("Microphone recording") || title.contains("Audio playing")
                    || title.contains("Sharing your screen")

                if hasActiveAudio {
                    // Actively in a call with mic/audio
                    meetHasActiveAudio = true
                    NSLog(
                        "[MeetingDetector] ✓ Found active Google Meet call (audio/mic active): '\(title)'"
                    )
                    return true
                } else if meetHasActiveAudio {
                    // We previously had active audio, now we don't = user left the call
                    NSLog(
                        "[MeetingDetector] ✗ Meet window exists but no audio indicators - user likely left call"
                    )
                    // Reset for next session
                    meetHasActiveAudio = false
                    return false
                } else {
                    // First time seeing Meet, hasn't had audio yet - user might be joining
                    // Give benefit of doubt for ~10 seconds initially
                    NSLog(
                        "[MeetingDetector] ⚠ Meet window exists but no audio yet (might be joining)"
                    )
                    return true  // Keep monitoring
                }
            }
        }

        // No Meet windows found at all
        meetHasActiveAudio = false
        NSLog("[MeetingDetector] === No Google Meet indicators found ===")
        return false
    }

    private func triggerMeetingEnded(reason: String) {
        NSLog("[MeetingDetector] \(reason) - triggering meeting end")
        stopMeetingEndMonitoring()
        onMeetingEnded?()
    }

    private func stopMeetingEndMonitoring() {
        appMonitoringTimer?.invalidate()
        appMonitoringTimer = nil
        detectedMeetingApp = nil
    }

    deinit {
        stop()
    }
}
