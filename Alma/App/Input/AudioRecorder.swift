import Foundation
import AVFoundation

final class AudioRecorder {
    private let engine = AVAudioEngine()
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?

    var onError: ((Error) -> Void)?

    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        NSLog("[AudioRecorder] start — input format: sr=%.0f ch=%d interleaved=%@",
              inputFormat.sampleRate,
              inputFormat.channelCount,
              inputFormat.isInterleaved ? "true" : "false")

        do {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("alma_\(UUID().uuidString).wav")
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
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self, let file = self.audioFile else { return }
            do { try file.write(from: buffer) } catch { /* ignore */ }
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
        if let url = tempFileURL {
            if let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
               let size = attrs[.size] as? NSNumber {
                NSLog("[AudioRecorder] stopped — file %@ (%.0f bytes)", url.lastPathComponent, size.doubleValue)
            } else {
                NSLog("[AudioRecorder] stopped — file %@", url.lastPathComponent)
            }
        }
        return tempFileURL
    }
}


