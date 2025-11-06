import Foundation
import AVFoundation
import Accelerate

final class AudioEngine {
    private let engine = AVAudioEngine()
    private let sessionQueue = DispatchQueue(label: "ai.toss.audio.session")

    var onRMSUpdate: ((Float) -> Void)?
    var onError: ((Error) -> Void)?

    private(set) var isRunning: Bool = false

    func start() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.requestMicrophoneAccess { granted in
                guard granted else {
                    self.onError?(NSError(domain: "AudioEngine", code: 1, userInfo: [NSLocalizedDescriptionKey: "Microphone access denied"]))
                    return
                }
                do {
                    try self.configureAndStartEngine()
                } catch {
                    self.onError?(error)
                }
            }
        }
    }

    func stop() {
        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            self.engine.inputNode.removeTap(onBus: 0)
            self.engine.stop()
            self.isRunning = false
        }
    }

    private func configureAndStartEngine() throws {
        let input = engine.inputNode
        let format = input.inputFormat(forBus: 0)

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] (buffer, _) in
            guard let self = self else { return }
            self.reportRMS(buffer: buffer)
        }

        engine.prepare()
        try engine.start()
        isRunning = true
    }

    private func reportRMS(buffer: AVAudioPCMBuffer) {
        guard let channelData = buffer.floatChannelData?[0] else { return }
        let frameLength = Int(buffer.frameLength)
        if frameLength == 0 { return }
        var meanSquare: Float = 0
        vDSP_measqv(channelData, 1, &meanSquare, vDSP_Length(frameLength))
        let rms = sqrtf(meanSquare)
        onRMSUpdate?(rms)
    }

    private func requestMicrophoneAccess(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .denied, .restricted:
            completion(false)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio) { granted in
                completion(granted)
            }
        @unknown default:
            completion(false)
        }
    }
}


