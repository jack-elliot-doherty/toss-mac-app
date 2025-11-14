import AVFoundation
import Foundation

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private let ioQueue = DispatchQueue(label: "ai.toss.audio.io")

    var onError: ((Error) -> Void)?
    var onLevelUpdate: ((Float) -> Void)?  // 0…1 linear RMS

    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        // Optimal format for Whisper transcription
        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            )
        else {
            onError?(
                NSError(
                    domain: "AudioRecorder", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create output format"]))
            return
        }

        NSLog("[AudioRecorder] recording at 16kHz mono (engine-native conversion)")

        // Attach mixer if not already attached
        if mixer.engine == nil {
            engine.attach(mixer)
        }

        // Connect: input -> mixer (at input format)
        engine.connect(inputNode, to: mixer, format: inputFormat)

        NSLog(
            "[AudioRecorder] Input: %.0fHz %dch -> Output: %.0fHz %dch",
            inputFormat.sampleRate, inputFormat.channelCount,
            outputFormat.sampleRate, outputFormat.channelCount)

        // Create file for 16kHz Float32
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("toss_\(UUID().uuidString).wav")

        do {
            // Write mic input format directly; WAV supports linear PCM (incl. float)
            let file = try AVAudioFile(forWriting: tmp, settings: outputFormat.settings)
            tempFileURL = tmp
            audioFile = file
        } catch {
            onError?(error)
            return
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            onError?(
                NSError(
                    domain: "AudioRecorder", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to create converter"]))
            return
        }

        mixer.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
            [weak self] buffer, _ in
            guard let self = self, self.audioFile != nil else { return }

            // Convert manually using the converter
            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * outputFormat.sampleRate / inputFormat.sampleRate)
            guard
                let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat, frameCapacity: frameCapacity)
            else {
                return
            }

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

            if error == nil {

                self.ioQueue.async {
                    try? self.audioFile?.write(from: convertedBuffer)
                }
                // Compute RMS level for UI waveform (mono aggregation)
                if let ch0 = buffer.floatChannelData?[0] {
                    let frameCount = Int(buffer.frameLength)
                    var sum: Float = 0
                    var i = 0
                    while i < frameCount {
                        let s = ch0[i]
                        sum += s * s
                        i += 1
                    }
                    let mean = sum / max(1, Float(frameCount))
                    var rms = sqrtf(mean)

                    // Boost perceived loudness: gamma curve + higher gain
                    rms = powf(rms, 0.6) * 6.0
                    rms = min(1.0, max(0.0, rms))

                    DispatchQueue.main.async { [weak self] in self?.onLevelUpdate?(rms) }
                }
            }
        }

        engine.prepare()
        do {
            try engine.start()
            NSLog("[AudioRecorder] engine started")
        } catch {
            onError?(error)
            return
        }
        isRunning = true
    }

    func stop() -> URL? {
        guard isRunning else { return nil }

        mixer.removeTap(onBus: 0)
        engine.stop()
        isRunning = false

        audioFile = nil

        // Get URL before clearing
        guard let url = tempFileURL else { return nil }

        if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
            let size = attrs[.size] as? NSNumber
        {
            NSLog("[AudioRecorder] stopped — %.1f MB", size.doubleValue / 1_000_000)
        }

        // Clear for next recording
        tempFileURL = nil

        return url
    }
}
