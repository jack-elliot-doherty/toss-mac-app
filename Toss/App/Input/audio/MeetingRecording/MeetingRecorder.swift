import AVFoundation
import Accelerate
import Foundation

final class MeetingRecorder {

    struct RecordedChunk {
        let url: URL
        let index: Int
        let startedAt: Date
    }

    private let chunkDuration: TimeInterval = 10.0

    // Feature flag — set false to revert to old correlation gate
    private let useAEC3 = true
    private let defaultAecDelayMs: Int32 = {
        if
            let raw = ProcessInfo.processInfo.environment["TOSS_AEC_DELAY_MS"],
            let parsed = Int32(raw)
        {
            return max(0, parsed)
        }
        return 80
    }()

    // Audio pipeline
    private let engine = AVAudioEngine()
    private var inputFormat: AVAudioFormat?
    private var converter: AVAudioConverter?
    private var configurationObserver: NSObjectProtocol?

    private var remoteLevelRMS: Float = 0
    private let remoteLevelLock = NSLock()

    // Conversion & writing
    private var currentChunkFile: AVAudioFile?
    private var currentChunkURL: URL?
    private var currentChunkStartedAt: Date?
    private var chunkUserSpeechSamples = 0
    private var chunkRemoteActiveSamples = 0

    private var chunkTimer: Timer?
    private var chunkIndex: Int = 0
    private let ioQueue = DispatchQueue(label: "ai.toss.meeting.io")
    private let aecQueue = DispatchQueue(label: "ai.toss.meeting.aec")
    private let debugChunkDumpEnabled: Bool = {
        // Opt-in only via TOSS_DUMP_AUDIO_CHUNKS.
        let defaultEnabled = false
        guard
            let raw = ProcessInfo.processInfo.environment["TOSS_DUMP_AUDIO_CHUNKS"]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased()
        else { return defaultEnabled }
        if raw == "0" || raw == "false" || raw == "no" || raw == "off" { return false }
        return raw == "1" || raw == "true" || raw == "yes" || raw == "on"
    }()
    private let debugChunkDumpRoot: URL = {
        if let raw = ProcessInfo.processInfo.environment["TOSS_CHUNK_DUMP_DIR"],
            !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        {
            return URL(
                fileURLWithPath: raw.trimmingCharacters(in: .whitespacesAndNewlines),
                isDirectory: true
            )
        }
        return FileManager.default.temporaryDirectory
            .appendingPathComponent("toss-aec-debug", isDirectory: true)
    }()
    private var debugSessionDirectory: URL?

    // AEC3 processor (WebRTC AudioProcessing Module)
    private var aecProcessor: AECProcessor?
    private var hasLoggedAecPassthrough = false

    // [AEC] diagnostic counters
    private var aecFarCalls = 0
    private var aecNearCalls = 0
    private var aecNearDropped = 0  // 10ms-ish subframes dropped by post-AEC gating
    private var aecNearDroppedSamples = 0

    // Echo cancellation ring buffer (~2 seconds at 16kHz) — used when useAEC3 == false
    private let remoteRingSize = 16000 * 2
    private var remoteRing = [Float](repeating: 0, count: 16000 * 2)
    private var remoteRingIndex = 0
    private let remoteRingLock = NSLock()

    // Echo detection thresholds — used when useAEC3 == false
    private let echoCorrelationThreshold: Float = 0.55
    private let echoRemoteLevelThreshold: Float = 0.008
    private let echoMaxDelaySamples = max(
        800,
        MeetingRecorder.envInt("TOSS_ECHO_MAX_DELAY_SAMPLES", defaultValue: 3200)
    )  // default ~200ms at 16kHz
    private let echoDelayStep = max(
        80,
        MeetingRecorder.envInt("TOSS_ECHO_DELAY_STEP_SAMPLES", defaultValue: 160)
    )
    private let postAecFrameSamples = 160  // 10ms at 16kHz
    private let postAecFrameGateEnabled = MeetingRecorder.envBool(
        "TOSS_AEC_ENABLE_POST_FRAME_GATE", defaultValue: true)
    private let postAecNearToRemoteRatioThreshold = MeetingRecorder.envFloat(
        "TOSS_AEC_RESIDUAL_NEAR_REMOTE_RATIO", defaultValue: 0.75)
    private let postAecResidualCorrelationThreshold = MeetingRecorder.envFloat(
        "TOSS_AEC_RESIDUAL_CORR_THRESHOLD", defaultValue: 0.60)
    private let postAecDropRemoteRatio = MeetingRecorder.envFloat(
        "TOSS_AEC_DROP_REMOTE_RATIO", defaultValue: 0.55)
    private let postAecSpeechFloorRms = MeetingRecorder.envFloat(
        "TOSS_AEC_SPEECH_FLOOR_RMS", defaultValue: 0.005)
    private let postAecSpeechRemoteRatio = MeetingRecorder.envFloat(
        "TOSS_AEC_SPEECH_REMOTE_RATIO", defaultValue: 0.20)
    private let postAecSpeechRejectNearRemoteRatio = MeetingRecorder.envFloat(
        "TOSS_AEC_SPEECH_REJECT_NEAR_REMOTE_RATIO", defaultValue: 1.40)
    private let postAecSpeechRejectCorrThreshold = MeetingRecorder.envFloat(
        "TOSS_AEC_SPEECH_REJECT_CORR_THRESHOLD", defaultValue: 0.45)
    private let minUserSpeechMsPerChunk = MeetingRecorder.envInt(
        "TOSS_AEC_MIN_USER_SPEECH_MS", defaultValue: 450)
    private let minUserSpeechMsPerChunkWhenRemote = MeetingRecorder.envInt(
        "TOSS_AEC_MIN_USER_SPEECH_MS_WHEN_REMOTE", defaultValue: 1100)
    private let remoteActiveMsThresholdForStrictSpeech = MeetingRecorder.envInt(
        "TOSS_AEC_REMOTE_ACTIVE_MS_THRESHOLD", defaultValue: 3000)
    private var minUserSpeechSamplesPerChunk: Int {
        max(0, Int((Double(minUserSpeechMsPerChunk) * targetFormat.sampleRate) / 1000.0))
    }
    private var minUserSpeechSamplesPerChunkWhenRemote: Int {
        max(
            minUserSpeechSamplesPerChunk,
            Int((Double(minUserSpeechMsPerChunkWhenRemote) * targetFormat.sampleRate) / 1000.0)
        )
    }
    private var remoteActiveSamplesThresholdForStrictSpeech: Int {
        max(
            0,
            Int((Double(remoteActiveMsThresholdForStrictSpeech) * targetFormat.sampleRate) / 1000.0)
        )
    }

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

        debugSessionDirectory = nil
        prepareDebugSessionDirectoryIfNeeded()
        setupAudioEngine()
        startNewChunk()

        // Listen for audio device changes (e.g., switching to AirPods)
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            self?.handleConfigurationChange()
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

    private func setupAudioEngine() {
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

        // Just in case there was a previous tap
        inputNode.removeTap(onBus: 0)

        // Small-ish buffer for low latency
        let bufferSize: AVAudioFrameCount = 1024

        inputNode.installTap(onBus: 0, bufferSize: bufferSize, format: inputFormat) {
            [weak self] buffer, _ in
            self?.handleInputBuffer(buffer)
        }
    }

    private func handleConfigurationChange() {
        NSLog("[MeetingRecorder] Audio configuration changed (device switch detected)")

        // Reset AEC state for new device
        aecQueue.sync {
            if let aec = aecProcessor {
                aec.reset()
                aec.setBufferDelayMs(defaultAecDelayMs)
            }
        }

        // Stop the engine and remove the old tap
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        // Re-setup with new device configuration
        setupAudioEngine()

        do {
            try engine.start()
            NSLog("[MeetingRecorder] AVAudioEngine restarted after device change")
        } catch {
            NSLog("[MeetingRecorder] Failed to restart after device change: \(error)")
            onError?(error)
        }
    }

    func stop() -> RecordedChunk? {
        guard isRunning else { return nil }

        chunkTimer?.invalidate()
        chunkTimer = nil

        if let observer = configurationObserver {
            NotificationCenter.default.removeObserver(observer)
            configurationObserver = nil
        }

        engine.inputNode.removeTap(onBus: 0)
        engine.stop()

        isRunning = false
        isPaused = false

        // Drain queued writes before any stop-time flush write.
        ioQueue.sync {}

        // Flush any buffered AEC tail and serialize writes on ioQueue.
        if let aec = aecProcessor, let file = currentChunkFile {
            let capacity = 160
            var flushBuffer = [Float](repeating: 0, count: capacity)

            while true {
                let flushed = aecQueue.sync { () -> Int32 in
                    flushBuffer.withUnsafeMutableBufferPointer { ptr -> Int32 in
                        aec.flushNearEnd(ptr.baseAddress!, capacity: Int32(capacity))
                    }
                }
                if flushed <= 0 { break }

                guard
                    let outBuffer = AVAudioPCMBuffer(
                        pcmFormat: targetFormat,
                        frameCapacity: AVAudioFrameCount(flushed)
                    )
                else { break }

                outBuffer.frameLength = AVAudioFrameCount(flushed)
                if let dst = outBuffer.floatChannelData?[0] {
                    _ = flushBuffer.withUnsafeBufferPointer { src in
                        memcpy(dst, src.baseAddress!, Int(flushed) * MemoryLayout<Float>.size)
                    }
                }

                ioQueue.sync {
                    do {
                        try file.write(from: outBuffer)
                    } catch {
                        NSLog("[MeetingRecorder] Error writing flushed AEC audio: \(error)")
                    }
                }
            }

            aecQueue.sync {
                aec.reset()
                aec.setBufferDelayMs(defaultAecDelayMs)
            }
        }

        guard let url = currentChunkURL else { return nil }
        let chunk = RecordedChunk(
            url: url,
            index: chunkIndex,
            startedAt: currentChunkStartedAt ?? Date()
        )
        dumpChunkForDebug(
            url: url,
            index: chunk.index,
            startedAt: chunk.startedAt,
            reason: "stop_final"
        )

        currentChunkFile = nil  // closes file
        currentChunkURL = nil
        currentChunkStartedAt = nil
        chunkIndex = 0
        debugSessionDirectory = nil

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

    // MARK: - AEC3

    func enableAEC() {
        guard useAEC3 else { return }
        let processor = AECProcessor(sampleRate: 16000, channelCount: 1)
        if processor.isValid {
            processor.setBufferDelayMs(defaultAecDelayMs)
            aecProcessor = processor
            hasLoggedAecPassthrough = false
            NSLog("[MeetingRecorder] AEC3 enabled (delay=%dms)", defaultAecDelayMs)
        } else {
            aecProcessor = nil
            NSLog("[MeetingRecorder] AEC3 init failed — running without echo cancellation")
        }
    }

    func disableAEC() {
        aecQueue.sync {
            aecProcessor?.reset()
        }
        aecProcessor = nil
        NSLog("[MeetingRecorder] AEC3 disabled")
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

    func ingestRemoteBuffer(_ buffer: AVAudioPCMBuffer) {
        guard let channel = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        if frames == 0 { return }

        // Keep far-end history for post-AEC residual correlation checks.
        remoteRingLock.lock()
        for i in 0..<frames {
            remoteRing[remoteRingIndex] = channel[i]
            remoteRingIndex = (remoteRingIndex + 1) % remoteRingSize
        }
        remoteRingLock.unlock()

        if useAEC3 {
            // AEC3: feed far-end audio to ProcessReverseStream
            aecQueue.sync {
                aecProcessor?.feedFarEnd(channel, count: Int32(frames))
            }
            aecFarCalls += 1
            if aecFarCalls % 100 == 1 {
                NSLog("[AEC] ingestRemoteBuffer: call #%d, frames=%d, aecProcessor=%@",
                      aecFarCalls, frames, aecProcessor != nil ? "alive" : "nil")
            }
        }
    }

    private func echoCorrelation(for micBuffer: AVAudioPCMBuffer) -> Float {
        guard let mic = micBuffer.floatChannelData?[0] else { return 0 }
        return echoCorrelation(forMicSamples: mic, count: Int(micBuffer.frameLength))
    }

    private func echoCorrelation(forMicSamples mic: UnsafePointer<Float>, count n: Int) -> Float {
        if n == 0 || n > remoteRingSize { return 0 }

        let configuredDelaySamples = Int((Double(defaultAecDelayMs) * targetFormat.sampleRate) / 1000.0)
        let searchDelaySamples = max(
            echoMaxDelaySamples,
            configuredDelaySamples + (postAecFrameSamples * 4)
        )
        let boundedDelay = min(searchDelaySamples, max(0, remoteRingSize - n))
        let segmentSize = n + boundedDelay

        remoteRingLock.lock()
        var remoteSegment = [Float](repeating: 0, count: segmentSize)
        var idx = (remoteRingIndex - segmentSize + remoteRingSize) % remoteRingSize
        for i in 0..<segmentSize {
            remoteSegment[i] = remoteRing[idx]
            idx = (idx + 1) % remoteRingSize
        }
        remoteRingLock.unlock()

        var maxCorr: Float = 0

        for offset in stride(from: 0, through: boundedDelay, by: echoDelayStep) {
            if offset + n > segmentSize { break }

            var dot: Float = 0
            var micEnergy: Float = 0
            var remoteEnergy: Float = 0

            remoteSegment.withUnsafeBufferPointer { ptr in
                vDSP_dotpr(mic, 1, ptr.baseAddress! + offset, 1, &dot, vDSP_Length(n))
                vDSP_svesq(mic, 1, &micEnergy, vDSP_Length(n))
                vDSP_svesq(ptr.baseAddress! + offset, 1, &remoteEnergy, vDSP_Length(n))
            }

            let denom = sqrt(micEnergy * remoteEnergy) + 1e-6
            let corr = dot / denom
            maxCorr = max(maxCorr, abs(corr))
        }

        return maxCorr
    }

    // MARK: - Tap handler

    private func handleInputBuffer(_ buffer: AVAudioPCMBuffer) {
        guard buffer.frameLength > 0 else { return }
        guard let converter = self.converter else { return }

        let format = buffer.format
        guard format.commonFormat == .pcmFormatFloat32,
            let channelData = buffer.floatChannelData
        else {
            return
        }

        let channels = Int(format.channelCount)
        let frames = Int(buffer.frameLength)

        // Mic RMS on original buffer
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

        // Convert to 16k mono
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
        var didProvideInput = false
        converter.convert(to: outBuffer, error: &error) { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return buffer
        }

        if let error {
            NSLog("[MeetingRecorder] Conversion error: \(error)")
            return
        }

        if outBuffer.frameLength == 0 { return }

        if useAEC3 {
            // AEC3: remove echo in-place
            let preAecFrames = outBuffer.frameLength
            let preAecRMS = computeRMS(outBuffer)
            if let aec = aecProcessor, let samples = outBuffer.floatChannelData?[0] {
                let processed = aecQueue.sync {
                    aec.processNearEnd(samples, count: Int32(outBuffer.frameLength))
                }
                outBuffer.frameLength = AVAudioFrameCount(processed)
                aecNearCalls += 1
            } else if !hasLoggedAecPassthrough {
                hasLoggedAecPassthrough = true
                NSLog("[AEC] WARN: processor unavailable, writing raw mic audio")
            }

            // Speech gating: use POST-AEC energy
            if outBuffer.frameLength > 0 {
                let remoteLevel = currentRemoteLevel()
                if remoteLevel > echoRemoteLevelThreshold {
                    chunkRemoteActiveSamples += Int(outBuffer.frameLength)
                }
                let gateStats = applyPostAecFrameGate(outBuffer, remoteLevel: remoteLevel)
                chunkUserSpeechSamples += gateStats.speechSamples
                aecNearDropped += gateStats.droppedFrames
                aecNearDroppedSamples += gateStats.droppedSamples

                if outBuffer.frameLength == 0 {
                    if aecNearDropped % 50 == 1 {
                        NSLog(
                            "[AEC] dropped remote-dominant mic frame batch (totalDroppedFrames=%d totalDroppedSamples=%d)",
                            aecNearDropped,
                            aecNearDroppedSamples
                        )
                    }
                    return
                }

                let postAecRMS = computeRMS(outBuffer)

                // Periodic diagnostic
                if aecNearCalls % 100 == 1 {
                    let speechMs = Int((Double(chunkUserSpeechSamples) * 1000.0) / targetFormat.sampleRate)
                    NSLog("[AEC] handleInput: call #%d, preFrames=%d postFrames=%d, preRMS=%.4f postRMS=%.4f, remoteRMS=%.4f, speechMs=%d, droppedFrames=%d, droppedSamples=%d, farCalls=%d",
                          aecNearCalls, preAecFrames, outBuffer.frameLength,
                          preAecRMS, postAecRMS, remoteLevel,
                          speechMs, aecNearDropped, aecNearDroppedSamples, aecFarCalls)
                }
            }
        } else {
            // Old correlation gate
            let remoteLevel = currentRemoteLevel()

            if remoteLevel > echoRemoteLevelThreshold {
                let corr = echoCorrelation(for: outBuffer)

                let isEcho =
                    micRMS < remoteLevel * 2.0
                    && corr > echoCorrelationThreshold

                if isEcho {
                    NSLog("[MeetingRecorder] Echo detected - skipping frame")
                    return
                }
            }

            if micRMS > 0.005 {
                chunkUserSpeechSamples += Int(outBuffer.frameLength)
            }
        }

        // Write to file
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
        chunkUserSpeechSamples = 0
        chunkRemoteActiveSamples = 0

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
        let speechMs = Int((Double(chunkUserSpeechSamples) * 1000.0) / targetFormat.sampleRate)
        let remoteActiveMs = Int(
            (Double(chunkRemoteActiveSamples) * 1000.0) / targetFormat.sampleRate
        )
        let remoteHeavyChunk =
            chunkRemoteActiveSamples >= remoteActiveSamplesThresholdForStrictSpeech
        let requiredSpeechSamples =
            remoteHeavyChunk
            ? minUserSpeechSamplesPerChunkWhenRemote
            : minUserSpeechSamplesPerChunk
        let requiredSpeechMs = Int((Double(requiredSpeechSamples) * 1000.0) / targetFormat.sampleRate)
        let hasUserSpeech = chunkUserSpeechSamples >= requiredSpeechSamples

        currentChunkFile = nil  // flush file
        if hasUserSpeech {
            dumpChunkForDebug(url: url, index: idx, startedAt: start, reason: "kept")

            DispatchQueue.main.async { [weak self] in
                self?.onChunkReady?(url, idx, start)
            }
        } else {
            dumpChunkForDebug(url: url, index: idx, startedAt: start, reason: "dropped_no_speech")
            // Remote-only or silence: delete & skip upload
            try? FileManager.default.removeItem(at: url)
            NSLog(
                "[MeetingRecorder] Dropping mic chunk #\(idx) (speechMs=\(speechMs), required=\(requiredSpeechMs)ms, remoteActiveMs=\(remoteActiveMs), remoteHeavy=\(remoteHeavyChunk))"
            )
        }

        chunkIndex += 1
        startNewChunk()
    }

    private struct PostAecGateStats {
        let speechSamples: Int
        let droppedFrames: Int
        let droppedSamples: Int
    }

    private func applyPostAecFrameGate(_ buffer: AVAudioPCMBuffer, remoteLevel: Float) -> PostAecGateStats {
        let totalSamples = Int(buffer.frameLength)
        guard totalSamples > 0, let samples = buffer.floatChannelData?[0] else {
            return PostAecGateStats(speechSamples: 0, droppedFrames: 0, droppedSamples: 0)
        }

        let speechThreshold = max(postAecSpeechFloorRms, remoteLevel * postAecSpeechRemoteRatio)
        let dropThreshold = max(postAecSpeechFloorRms, remoteLevel * postAecDropRemoteRatio)
        guard postAecFrameGateEnabled else {
            let rms = computeRMS(buffer)
            let speechSamples = rms > speechThreshold ? totalSamples : 0
            return PostAecGateStats(speechSamples: speechSamples, droppedFrames: 0, droppedSamples: 0)
        }

        var speechSamples = 0
        var droppedFrames = 0
        var droppedSamples = 0
        var writeIndex = 0
        var offset = 0

        while offset < totalSamples {
            let frameCount = min(postAecFrameSamples, totalSamples - offset)
            let framePtr = samples + offset

            var sumSquares: Float = 0
            vDSP_svesq(framePtr, 1, &sumSquares, vDSP_Length(frameCount))
            let frameRms = sqrtf(sumSquares / Float(max(1, frameCount)))
            let nearToRemoteRatio = frameRms / max(remoteLevel, 1e-6)
            let remoteActive = remoteLevel > echoRemoteLevelThreshold

            var dropFrame = false
            var residualCorr: Float?

            if remoteActive && frameRms < dropThreshold {
                if nearToRemoteRatio < postAecNearToRemoteRatioThreshold {
                    let corr = echoCorrelation(forMicSamples: framePtr, count: frameCount)
                    residualCorr = corr
                    if corr > postAecResidualCorrelationThreshold {
                        dropFrame = true
                    }
                }
            }

            if dropFrame {
                droppedFrames += 1
                droppedSamples += frameCount
            } else {
                if writeIndex != offset {
                    memmove(samples + writeIndex, framePtr, frameCount * MemoryLayout<Float>.size)
                }
                writeIndex += frameCount

                var countsAsSpeech = frameRms > speechThreshold
                if countsAsSpeech && remoteActive
                    && nearToRemoteRatio < postAecSpeechRejectNearRemoteRatio
                {
                    let corr = residualCorr ?? echoCorrelation(forMicSamples: framePtr, count: frameCount)
                    if corr > postAecSpeechRejectCorrThreshold {
                        countsAsSpeech = false
                    }
                }

                if countsAsSpeech {
                    speechSamples += frameCount
                }
            }

            offset += frameCount
        }

        buffer.frameLength = AVAudioFrameCount(writeIndex)
        return PostAecGateStats(
            speechSamples: speechSamples,
            droppedFrames: droppedFrames,
            droppedSamples: droppedSamples
        )
    }

    private func computeRMS(_ buffer: AVAudioPCMBuffer) -> Float {
        guard let channel = buffer.floatChannelData?[0] else { return 0 }
        let frames = Int(buffer.frameLength)
        guard frames > 0 else { return 0 }
        var sumSquares: Float = 0
        vDSP_svesq(channel, 1, &sumSquares, vDSP_Length(frames))
        return sqrtf(sumSquares / Float(frames))
    }

    private func prepareDebugSessionDirectoryIfNeeded() {
        guard debugChunkDumpEnabled else { return }
        guard debugSessionDirectory == nil else { return }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let dir = debugChunkDumpRoot
            .appendingPathComponent("meeting-\(stamp)-\(UUID().uuidString.prefix(8))", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            debugSessionDirectory = dir
            NSLog("[MeetingRecorder] Debug chunk dump enabled: %@", dir.path)
        } catch {
            NSLog("[MeetingRecorder] Failed to create debug chunk dump dir: %@", error.localizedDescription)
        }
    }

    private func dumpChunkForDebug(url: URL, index: Int, startedAt: Date, reason: String) {
        guard debugChunkDumpEnabled else { return }
        prepareDebugSessionDirectoryIfNeeded()
        guard let sessionDir = debugSessionDirectory else { return }

        let safeReason = reason.replacingOccurrences(of: " ", with: "_")
        let baseName = String(
            format: "mic_%04d_%@_%@",
            index,
            safeReason,
            UUID().uuidString
        )
        let outURL = sessionDir.appendingPathComponent(baseName).appendingPathExtension("wav")
        do {
            if FileManager.default.fileExists(atPath: outURL.path) {
                try FileManager.default.removeItem(at: outURL)
            }
            try FileManager.default.copyItem(at: url, to: outURL)
            let meta = "index=\(index)\nstartedAt=\(startedAt)\nreason=\(reason)\nsource=mic\n"
            let metaURL = sessionDir.appendingPathComponent(baseName).appendingPathExtension("txt")
            try meta.write(to: metaURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("[MeetingRecorder] Failed to dump debug chunk #%d (%@): %@", index, reason, error.localizedDescription)
        }
    }

    private static func envBool(_ key: String, defaultValue: Bool) -> Bool {
        guard
            let raw = ProcessInfo.processInfo.environment[key]?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased(),
            !raw.isEmpty
        else { return defaultValue }

        if ["1", "true", "yes", "on"].contains(raw) { return true }
        if ["0", "false", "no", "off"].contains(raw) { return false }
        return defaultValue
    }

    private static func envFloat(_ key: String, defaultValue: Float) -> Float {
        guard
            let raw = ProcessInfo.processInfo.environment[key]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            let parsed = Float(raw),
            parsed.isFinite
        else { return defaultValue }
        return parsed
    }

    private static func envInt(_ key: String, defaultValue: Int) -> Int {
        guard
            let raw = ProcessInfo.processInfo.environment[key]?
                .trimmingCharacters(in: .whitespacesAndNewlines),
            let parsed = Int(raw)
        else { return defaultValue }
        return parsed
    }

    private func teardown() {
        if let observer = configurationObserver {
            NotificationCenter.default.removeObserver(observer)
            configurationObserver = nil
        }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        isRunning = false
    }
}
