import Foundation

// Stubbed SpeechTranscriber for the online-only architecture.
// This class remains to satisfy references but does not perform recognition.
final class SpeechTranscriber {
    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    private(set) var isRunning = false

    func start() { isRunning = true }

    func stop() { isRunning = false }
}


