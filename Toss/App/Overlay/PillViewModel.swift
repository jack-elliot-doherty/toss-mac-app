import Foundation
import SwiftUI

enum PasteResult: Equatable {
    case pasted
    case copiedNoFocus
    case error(String)
}

enum PillVisualState: Equatable {
    case idle
    case hovered
    case meetingDetected
    case listening(PillMode)
    case transcribing(PillMode)
    case upcomingMeeting(UpcomingMeeting)
    case meetingRecording(UUID, isPaused: Bool)
    case agentSessionActive  // Agent panel is minimized but session is active
}

@MainActor
final class PillViewModel: ObservableObject {
    @Published var visualState: PillVisualState = .idle
    @Published var isAlwaysOn: Bool = false
    @Published var levelRMS: Float = 0.0
    @Published var isMeetingRecordingHovered: Bool = false
    @Published var showMeetingRecordingStopButton: Bool = false  // Set AFTER window resize
    @Published var isHoverDisabled: Bool = false  // Disable hover when agent panel is open
    @Published var customPillPosition: NSPoint? = nil  // Custom position when user drags the pill

    // Callbacks the owner (AppDelegate) can observe to perform actions
    var onRequestStop: (() -> Void)?
    var onRequestCancel: (() -> Void)?
    // var onToggleAgentMode: ((Bool) -> Void)?

    var onPauseMeetingRecording: (() -> Void)?
    var onResumeMeetingRecording: (() -> Void)?

    // hover and click callbacks
    var onHoverEnter: (() -> Void)?
    var onHoverExit: (() -> Void)?
    var onPillClicked: (() -> Void)?
    var onQuickActionRecordMeeting: (() -> Void)?
    var onQuickActionDictation: (() -> Void)?
    var onQuickActionAgentChat: (() -> Void)?
    var onStopMeetingRecording: (() -> Void)?

    var onJoinAndRecordUpcoming: ((UpcomingMeeting) -> Void)?
    var onDismissUpcomingMeeting: (() -> Void)?

    // Drag callbacks for repositioning the pill
    var onDragStart: (() -> Void)?
    var onDragEnd: (() -> Void)?

    var agentModeEnabled: Bool {
        if case .listening(.command) = visualState { return true }
        return false
    }

    func listening(_ mode: PillMode) {
        visualState = .listening(mode)
    }

    func transcribing(_ mode: PillMode) {
        visualState = .transcribing(mode)
    }

    func meetingRecording(_ meetingId: UUID, isPaused: Bool) {
        visualState = .meetingRecording(meetingId, isPaused: isPaused)
    }

    func idle() {
        visualState = .idle
    }

    func meetingDetected() {
        visualState = .meetingDetected
    }

    func hovered() {
        visualState = .hovered
    }

    func upcomingMeeting(_ meeting: UpcomingMeeting) {
        visualState = .upcomingMeeting(meeting)
    }

    func agentSessionActive() {
        visualState = .agentSessionActive
    }

    func updateLevelRMS(_ value: Float) {
        // Clamp and publish; UI can animate from this
        let clamped = max(0, min(1, value))
        if abs(clamped - levelRMS) > 0.01 {
            NSLog("Updating level RMS from \(levelRMS) to \(clamped)")
        }
        levelRMS = clamped
    }
}
