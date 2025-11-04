import AVFoundation
import Foundation

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?

    var onError: ((Error) -> Void)?
    var onLevelUpdate: ((Float) -> Void)?  // 0…1 linear RMS

    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        NSLog(
            "[AudioRecorder] start — input format: sr=%.0f ch=%d interleaved=%@",
            inputFormat.sampleRate,
            inputFormat.channelCount,
            inputFormat.isInterleaved ? "true" : "false")

        do {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent(
                "alma_\(UUID().uuidString).wav")
            // Write mic input format directly; WAV supports linear PCM (incl. float)
            let file = try AVAudioFile(forWriting: tmp, settings: inputFormat.settings)
            tempFileURL = tmp
            audioFile = file
            NSLog("[AudioRecorder] writing to %@", tmp.path)
        } catch {
            onError?(error)
            return
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) {
            [weak self] buffer, _ in
            guard let self = self, let file = self.audioFile else { return }
            do { try file.write(from: buffer) } catch { /* ignore */  }
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
                // Simple normalization for visual use
                rms = min(1.0, max(0.0, rms * 4.0))
                DispatchQueue.main.async { [weak self] in self?.onLevelUpdate?(rms) }
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
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false

        guard let wavUrl = tempFileURL else { return nil }

        // compress the wav file to lower sample rate
        if let compressdUrl = compressAudio(wavUrl) {
            NSLog("[AudioRecorder] compressed wav file to %@", compressdUrl.lastPathComponent)
            return compressdUrl
        }

        return wavUrl
    }

    private func compressAudio(_ inputURL: URL) -> URL? {
        guard let inputFile = try? AVAudioFile(forReading: inputURL) else {
            return nil
        }

        // Output at 16kHz mono (sufficient for speech, much smaller)
        let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatInt16,
            sampleRate: 16000,
            channels: 1,
            interleaved: true
        )!

        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("alma_compressed_\(UUID().uuidString).wav")

        guard
            let outputFile = try? AVAudioFile(
                forWriting: outputURL,
                settings: outputFormat.settings
            )
        else {
            return nil
        }

        guard
            let converter = AVAudioConverter(
                from: inputFile.processingFormat,
                to: outputFormat
            )
        else {
            return nil
        }

        let inputBuffer = AVAudioPCMBuffer(
            pcmFormat: inputFile.processingFormat,
            frameCapacity: AVAudioFrameCount(inputFile.length)
        )!

        try? inputFile.read(into: inputBuffer)

        let outputBuffer = AVAudioPCMBuffer(
            pcmFormat: outputFormat,
            frameCapacity: AVAudioFrameCount(
                Double(inputBuffer.frameLength) * outputFormat.sampleRate
                    / inputFile.processingFormat.sampleRate
            )
        )!

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }

        if error == nil {
            try? outputFile.write(from: outputBuffer)
            return outputURL
        }

        return nil
    }

}
