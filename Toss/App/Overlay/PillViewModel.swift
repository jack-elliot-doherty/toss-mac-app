import Foundation
import SwiftUI

enum PasteResult: Equatable {
    case pasted
    case copiedNoFocus
    case error(String)
}

enum PillVisualState: Equatable {
    case idle
    case listening(PillMode)
    case transcribing(PillMode)
    case meetingRecording(UUID)
}

@MainActor
final class PillViewModel: ObservableObject {
    @Published var visualState: PillVisualState = .idle
    @Published var isAlwaysOn: Bool = false
    @Published var levelRMS: Float = 0.0

    // Callbacks the owner (AppDelegate) can observe to perform actions
    var onRequestStop: (() -> Void)?
    var onRequestCancel: (() -> Void)?
    var onToggleAgentMode: ((Bool) -> Void)?

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
    
    func meetingRecording(_ meetingId: UUID) {
        visualState = .meetingRecording(meetingId)
    }

    func idle() {
        visualState = .idle
    }

    func updateLevelRMS(_ value: Float) {
        // Clamp and publish; UI can animate from this
        let clamped = max(0, min(1, value))
        levelRMS = clamped
    }
}
