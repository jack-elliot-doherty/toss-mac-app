import AVFoundation
import Accelerate
import Foundation

final class MeetingRecorder {

    struct RecordedChunk {
        let url: URL
        let index: Int
        let startedAt: Date
    }

    private var echoGate = EchoGate()

    private let chunkDuration: TimeInterval = 15.0

    // Audio pipeline
    private let engine = AVAudioEngine()
    private var inputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    // Ducking
    private var ducking = DuckingProcessor()
    private var remoteLevelRMS: Float = 0
    private let remoteLevelLock = NSLock()

    // Conversion & writing
    private var currentChunkFile: AVAudioFile?
    private var currentChunkURL: URL?
    private var currentChunkStartedAt: Date?
    private var chunkHasUserSpeech = false

    private var chunkTimer: Timer?
    private var chunkIndex: Int = 0
    private let ioQueue = DispatchQueue(label: "ai.toss.meeting.io")

    // Target format: 16kHz Mono Float32
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false
    )!

    var onError: ((Error) -> Void)?
    var onLevelUpdate: ((Float) -> Void)?
    var onChunkReady: ((URL, Int, Date) -> Void)?

    private(set) var isRunning = false
    private(set) var isPaused = false

    // MARK: - Public API

    func start() {
        guard !isRunning else { return }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)
        self.inputFormat = inputFormat

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            let err = NSError(
                domain: "MeetingRecorder",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Failed to create AVAudioConverter"]
            )
            onError?(err)
            return
        }
        self.converter = converter

        startNewChunk()

        // Just in case there was a previous tap
        inputNode.removeTap(onBus: 0)

        // Small-ish buffer for low latency
        let bufferSize: AVAudioFrameCount = 1024

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) {
            [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }

        do {
            try engine.start()
            isRunning = true
            NSLog("[MeetingRecorder] AVAudioEngine started")

            DispatchQueue.main.async { [weak self] in
                self?.startRotationTimer()
            }
        } catch {
            NSLog("[MeetingRecorder] Start failed: \(error)")
            onError?(error)
            teardown()
        }
    }

    func stop() -> RecordedChunk? {
        guard isRunning else { return nil }

        chunkTimer?.invalidate()
        chunkTimer = nil

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        isRunning = false
        isPaused = false

        guard let url = currentChunkURL else { return nil }
        let chunk = RecordedChunk(
            url: url,
            index: chunkIndex,
            startedAt: currentChunkStartedAt ?? Date()
        )

        currentChunkFile = nil  // closes file
        currentChunkURL = nil
        currentChunkStartedAt = nil
        chunkIndex = 0

        NSLog("[MeetingRecorder] Stopped")
        return chunk
    }

    func pause() {
        // MVP: just stop everything for now
        _ = stop()
    }

    func resume() {
        start()
    }

    // MARK: - Remote level (from SystemAudioRecorder)

    func updateRemoteLevel(_ level: Float) {
        remoteLevelLock.lock()
        remoteLevelRMS = level
        remoteLevelLock.unlock()
    }

    private func currentRemoteLevel() -> Float {
        remoteLevelLock.lock()
        let level = remoteLevelRMS
        remoteLevelLock.unlock()
        return level
    }

    // MARK: - Tap handler

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        guard let converter = self.converter else { return }

        let format = buffer.format
        guard format.commonFormat == .pcmFormatFloat32,
            let channelData = buffer.floatChannelData
        else {
            // on macOS this should be Float32.
            return
        }

        let channels = Int(format.channelCount)
        let frames = Int(buffer.frameLength)

        // Mic RMS
        var sum: Float = 0
        for ch in 0..<channels {
            let samples = channelData[ch]
            vDSP_svesq(samples, 1, &sum, vDSP_Length(frames))
        }
        let micRMS = sqrtf(sum / max(1, Float(frames * channels)))

        // UI level from mic
        let uiLevel = min(1.0, micRMS * 4.0)
        DispatchQueue.main.async { [weak self] in
            self?.onLevelUpdate?(uiLevel)
        }

        // --- Remote level & dominance ---
        let remote = currentRemoteLevel()
        let decision = echoGate.decide(remoteRMS: remote, micRMS: micRMS)

        switch decision {
        case .echoOnly:
            // Zero mic samples so ASR sees silence
            for ch in 0..<channels {
                let samples = channelData[ch]
                vDSP_vclr(samples, 1, vDSP_Length(frames))
            }

        case .userOrOverlap:
            // Mark this chunk as having user speech if mic is reasonably loud
            if micRMS > 0.02 {
                chunkHasUserSpeech = true
            }

            // Optional: keep light ducking if you like
            let gain = ducking.gain(remoteLevel: remote, micLevel: micRMS)
            if gain < 0.999 {
                var g = gain
                for ch in 0..<channels {
                    let samples = channelData[ch]
                    vDSP_vsmul(samples, 1, &g, samples, 1, vDSP_Length(frames))
                }
            }
        }

        // --- Convert to 16kHz mono and write (unchanged) ---
        guard let file = currentChunkFile else { return }

        let ratio = targetFormat.sampleRate / format.sampleRate
        let outCapacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 16)

        guard
            let outBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: outCapacity
            )
        else { return }

        var error: NSError?
        converter.convert(to: outBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            NSLog("[MeetingRecorder] Conversion error: \(error)")
            return
        }

        if outBuffer.frameLength == 0 { return }

        ioQueue.async {
            do {
                try file.write(from: outBuffer)
            } catch {
                NSLog("[MeetingRecorder] Error writing mic audio: \(error)")
            }
        }
    }

    // MARK: - Chunk lifecycle

    private func startNewChunk() {
        chunkHasUserSpeech = false

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("meeting_chunk_\(chunkIndex)_\(UUID().uuidString).wav")
        do {
            currentChunkFile = try AVAudioFile(forWriting: tmp, settings: targetFormat.settings)
            currentChunkURL = tmp
            currentChunkStartedAt = Date()
            NSLog("[MeetingRecorder] Started chunk #\(chunkIndex)")
        } catch {
            onError?(error)
        }
    }

    private func startRotationTimer() {
        chunkTimer = Timer.scheduledTimer(withTimeInterval: chunkDuration, repeats: true) {
            [weak self] _ in
            self?.rotateChunk()
        }
    }

    private func rotateChunk() {
        guard let url = currentChunkURL else { return }
        let idx = chunkIndex
        let start = currentChunkStartedAt ?? Date()

        currentChunkFile = nil  // flush file
        if chunkHasUserSpeech {

            DispatchQueue.main.async { [weak self] in
                self?.onChunkReady?(url, idx, start)
            }
        } else {
            // Remote-only or silence: delete & skip upload
            try? FileManager.default.removeItem(at: url)
            NSLog("[MeetingRecorder] Dropping mic chunk #\(idx) (no user speech detected)")
        }

        chunkIndex += 1
        startNewChunk()
    }

    private func teardown() {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }
}

private struct DuckingProcessor {
    // Remote threshold: only duck when remote is clearly audible
    var remoteThreshold: Float = 0.08

    // When mic is very quiet (likely just echo), duck it hard
    var micQuietThreshold: Float = 0.03

    // Gains
    let fullGain: Float = 1.0
    let mildDuckGain: Float = 0.4  // light overlap
    let strongDuckGain: Float = 0.15  // clear remote dominance
    let muteGain: Float = 0.01  // essentially mute

    // Envelope speeds
    let duckAttack: Float = 0.85  // duck fast
    let unduckRelease: Float = 0.1  // unduck slowly

    private(set) var currentGain: Float = 1.0

    mutating func gain(remoteLevel: Float, micLevel: Float) -> Float {
        let target: Float

        if remoteLevel <= remoteThreshold {
            // No remote speech
            target = fullGain
        } else {
            // Remote is speaking
            if micLevel < micQuietThreshold {
                // Mic is very quiet → likely just echo/bleed
                target = muteGain
            } else {
                // Mic has some energy
                let safeMic = max(micLevel, 1e-4)
                let dominance = remoteLevel / safeMic

                if dominance >= 6 {
                    // Remote >> mic: strong duck
                    target = strongDuckGain
                } else if dominance >= 2.5 {
                    // Remote clearly louder: medium duck
                    target = mildDuckGain
                } else {
                    // Overlap or user louder: light duck
                    target = 0.6
                }
            }
        }

        let diff = target - currentGain
        if abs(diff) < 0.001 {
            currentGain = target
            return currentGain
        }

        let step = diff < 0 ? duckAttack : unduckRelease
        currentGain += diff * step
        currentGain = min(fullGain, max(muteGain, currentGain))

        return currentGain
    }
}

// Outside the class (file‑private helpers)
private enum MicDecision {
    case echoOnly
    case userOrOverlap
}

private struct EchoGate {
    // Tune these based on logs
    var remoteSpeechThreshold: Float = 0.04
    var micQuietThreshold: Float = 0.02
    var dominanceThreshold: Float = 5.0

    mutating func decide(remoteRMS: Float, micRMS: Float) -> MicDecision {
        let safeMic = max(micRMS, 1e-4)
        let dominance = remoteRMS / safeMic

        if remoteRMS > remoteSpeechThreshold && micRMS < micQuietThreshold
            && dominance > dominanceThreshold
        {
            return .echoOnly
        } else {
            return .userOrOverlap
        }
    }
}
