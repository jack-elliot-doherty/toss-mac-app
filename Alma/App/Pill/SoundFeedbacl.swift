import AppKit

final class SoundFeedback {
    static let shared = SoundFeedback()

    func playStart() {
        NSSound(named: "Pop")?.play()  // High ping
    }

    func playStop() {
        NSSound(named: "Frog")?.play()
    }
}
