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
    case meetingRecording(UUID, isPaused: Bool)
}

@MainActor
final class PillViewModel: ObservableObject {
    @Published var visualState: PillVisualState = .idle
    @Published var isAlwaysOn: Bool = false
    @Published var levelRMS: Float = 0.0

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
    var onStopMeetingRecording: (() -> Void)?

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

    func updateLevelRMS(_ value: Float) {
        // Clamp and publish; UI can animate from this
        let clamped = max(0, min(1, value))
        if abs(clamped - levelRMS) > 0.01 {
            NSLog("Updating level RMS from \(levelRMS) to \(clamped)")
        }
        levelRMS = clamped
    }
}
