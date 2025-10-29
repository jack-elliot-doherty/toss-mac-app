import Foundation
import SwiftUI

enum PasteResult: Equatable {
    case pasted
    case copiedNoFocus
    case error(String)
}

enum PillState: Equatable {
    case idle
    case listening
    case transcribing
    case done(PasteResult)
    case cancelled
}

@MainActor
final class PillViewModel: ObservableObject {
    @Published var state: PillState = .idle
    @Published var isAlwaysOn: Bool = false
    @Published var levelRMS: Float = 0.0
    @Published var agentModeEnabled: Bool = false

    // Callbacks the owner (AppDelegate) can observe to perform actions
    var onRequestStop: (() -> Void)?
    var onRequestCancel: (() -> Void)?
    var onToggleAgentMode: ((Bool) -> Void)?

    func beginListening() {
        state = .listening
    }

    func endListening() {
        // Owner should start transcription
        state = .transcribing
        onRequestStop?()
    }

    func cancel() {
        state = .cancelled
        onRequestCancel?()
    }

    func toggleAlwaysOn() {
        isAlwaysOn.toggle()
    }

    func setState(_ newState: PillState) {
        state = newState
    }

    func onTranscriptionResult(_ text: String) {
        // Owner will handle paste/copy/toast; here we simply mark done
        state = .done(.pasted) // placeholder; owner should set precise PasteResult via setState
    }

    func updateLevelRMS(_ value: Float) {
        // Clamp and publish; UI can animate from this
        let clamped = max(0, min(1, value))
        levelRMS = clamped
    }

    func toggleAgentMode() {
        agentModeEnabled.toggle()
        onToggleAgentMode?(agentModeEnabled)
    }
}


