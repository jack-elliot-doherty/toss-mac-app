import AVFoundation
import AppKit
import CoreAudio
import Foundation

final class MeetingDetector {
    private var appObserver: NSObjectProtocol?
    private var audioPropertyListener: AudioObjectPropertyListenerBlock?
    private var currentMeetingApp: String?

    var onMeetingDetected: (() -> Void)?

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

    deinit {
        stop()
    }
}
