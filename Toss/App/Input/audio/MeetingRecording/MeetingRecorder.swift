import AVFoundation
import Foundation

final class MeetingRecorder {

    struct RecordedChunk {
        let url: URL
        let index: Int
        let startedAt: Date
    }

    private let chunkDuration: TimeInterval = 15.0
    private let engine = AVAudioEngine()
    private let mixer = AVAudioMixerNode()
    private var currentChunkFile: AVAudioFile?
    private var currentChunkURL: URL?
    private var currentChunkStartedAt: Date?
    private var chunkTimer: Timer?
    private var chunkIndex: Int = 0
    private let ioQueue = DispatchQueue(label: "ai.toss.meeting.io")

    var onError: ((Error) -> Void)?
    var onLevelUpdate: ((Float) -> Void)?
    var onChunkReady: ((URL, Int, Date) -> Void)?  // Called every 30s with audio file + index

    private(set) var isRunning = false
    private(set) var isPaused = false

    func start() {
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16000,
                channels: 1,
                interleaved: false
            )
        else {
            onError?(NSError(domain: "MeetingRecorder", code: 1, userInfo: nil))
            return
        }

        NSLog("[MeetingRecorder] Starting meeting recording at 16kHz mono")

        if mixer.engine == nil {
            engine.attach(mixer)
        }

        engine.connect(inputNode, to: mixer, format: inputFormat)

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            onError?(NSError(domain: "MeetingRecorder", code: 2, userInfo: nil))
            return
        }

        // Start first chunk
        startNewChunk(format: outputFormat)

        mixer.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
            [weak self] buffer, _ in
            guard let self = self, self.currentChunkFile != nil else { return }

            // Convert to 16kHz mono
            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * outputFormat.sampleRate / inputFormat.sampleRate)
            guard
                let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat, frameCapacity: frameCapacity)
            else { return }

            var error: NSError?
            let inputBlock: AVAudioConverterInputBlock = { inNumPackets, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

            if error == nil {
                self.ioQueue.async {
                    try? self.currentChunkFile?.write(from: convertedBuffer)
                }

                // Update RMS for UI
                if let ch0 = buffer.floatChannelData?[0] {
                    let frameCount = Int(buffer.frameLength)
                    var sum: Float = 0
                    for i in 0..<frameCount {
                        let s = ch0[i]
                        sum += s * s
                    }
                    let rms = min(1.0, max(0.0, sqrtf(sum / max(1, Float(frameCount))) * 4.0))
                    DispatchQueue.main.async { [weak self] in self?.onLevelUpdate?(rms) }
                }
            }
        }

        engine.prepare()
        do {
            try engine.start()
            isRunning = true

            // Schedule chunk rotation every 30 seconds
            chunkTimer = Timer.scheduledTimer(withTimeInterval: chunkDuration, repeats: true) {
                [weak self] _ in
                self?.rotateChunk(format: outputFormat)
            }

            NSLog("[MeetingRecorder] Engine started, chunk rotation scheduled")
        } catch {
            onError?(error)
        }
    }

    private func startNewChunk(format: AVAudioFormat) {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting_chunk_\(chunkIndex)_\(UUID().uuidString).wav")

        do {
            let file = try AVAudioFile(forWriting: tmp, settings: format.settings)
            currentChunkURL = tmp
            currentChunkFile = file
            currentChunkStartedAt = Date()
            NSLog("[MeetingRecorder] Started chunk #\(chunkIndex)")
        } catch {
            onError?(error)
        }
    }

    private func rotateChunk(format: AVAudioFormat) {
        guard let url = currentChunkURL else { return }
        let index = chunkIndex
        let startedAt = currentChunkStartedAt ?? Date()

        // Close current chunk
        currentChunkFile = nil
        DispatchQueue.main.async { [weak self] in
            self?.onChunkReady?(url, index, startedAt)
        }

        // Start next chunk
        chunkIndex += 1
        startNewChunk(format: format)
    }

    func stop() -> RecordedChunk? {
        guard isRunning else { return nil }
        chunkTimer?.invalidate()
        chunkTimer = nil
        mixer.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
        isPaused = false

        guard let url = currentChunkURL else { return nil }
        let chunk = RecordedChunk(
            url: url, index: chunkIndex, startedAt: currentChunkStartedAt ?? Date())

        // Close and return final chunk
        currentChunkFile = nil
        currentChunkURL = nil
        currentChunkStartedAt = nil
        chunkIndex = 0
        NSLog("[MeetingRecorder] Stopped")
        return chunk
    }

    func pause() {
        guard isRunning, !isPaused else { return }
        chunkTimer?.invalidate()
        chunkTimer = nil
        if let format = currentChunkFile?.processingFormat {
            rotateChunk(format: format)
        }
        engine.pause()
        isPaused = true
    }

    func resume() {
        guard isRunning, isPaused, let format = currentChunkFile?.processingFormat else { return }
        engine.prepare()
        do {
            try engine.start()
            isPaused = false
            chunkTimer = Timer.scheduledTimer(withTimeInterval: chunkDuration, repeats: true) {
                [weak self] _ in
                self?.rotateChunk(format: format)
            }
            RunLoop.main.add(chunkTimer!, forMode: .common)
        } catch {
            onError?(error)
        }
    }
}
