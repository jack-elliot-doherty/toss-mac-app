import AVFoundation
import CoreMedia
import CoreVideo
import QuartzCore
import ScreenCaptureKit

final class SystemAudioRecorder: NSObject {
    struct RecordedChunk {
        let url: URL
        let index: Int
        let startedAt: Date
    }

    private let chunkDuration: TimeInterval = 10.0
    private let streamQueue = DispatchQueue(label: "ai.toss.system-audio.stream")
    private let videoDrainQueue = DispatchQueue(label: "ai.toss.system-video.drain")
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false)!

    private var stream: SCStream?
    private var currentFile: AVAudioFile?
    private var currentURL: URL?
    private var currentStart: Date?
    private var chunkEnergy: Float = 0
    private var chunkFrames: Int = 0
    private let silenceRmsThreshold: Float = 0.03
    private var chunkIndex = 0
    private var timer: DispatchSourceTimer?
    private let debugChunkDumpEnabled: Bool = {
        #if DEBUG
            let defaultEnabled = true
        #else
            let defaultEnabled = false
        #endif
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

    // Cached converter — recreated only when input format changes
    private var cachedConverter: AVAudioConverter?
    private var cachedInputSampleRate: Float64 = 0
    private var cachedInputChannels: UInt32 = 0

    private(set) var isRunning = false
    var onChunkReady: ((URL, Int, Date) -> Void)?
    var onError: ((Error) -> Void)?
    var onRemoteLevel: ((Float) -> Void)?
    var onRemoteAudioFrame: ((AVAudioPCMBuffer) -> Void)?

    func start() async throws {
        guard !isRunning else { return }

        debugSessionDirectory = nil
        prepareDebugSessionDirectoryIfNeeded()
        NSLog("[SystemAudioRecorder] Starting system audio capture...")

        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw NSError(
                domain: "SystemAudioRecorder",
                code: -10,
                userInfo: [NSLocalizedDescriptionKey: "No displays available for capture"])
        }

        let filter = SCContentFilter(display: display, excludingWindows: [])
        let configuration = SCStreamConfiguration()
        configuration.minimumFrameInterval = CMTime(value: 1, timescale: 60)
        configuration.queueDepth = 4
        configuration.showsCursor = false
        configuration.capturesAudio = true

        let stream = SCStream(filter: filter, configuration: configuration, delegate: self)
        try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: streamQueue)
        // Register a screen output sink so SCStream does not spam "output NOT found" errors.
        try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: videoDrainQueue)

        startNewChunk()
        scheduleRotation()

        try await stream.startCapture()
        self.stream = stream
        isRunning = true
        NSLog("[SystemAudioRecorder] System audio capture started successfully")
    }

    func stop() -> RecordedChunk? {
        guard isRunning else { return nil }
        timer?.cancel()
        timer = nil
        isRunning = false

        stream?.stopCapture(completionHandler: nil)
        stream = nil

        if #available(macOS 15.0, *) {
            currentFile?.close()
        }
        // On macOS < 15, AVAudioFile closes automatically when deallocated

        guard let url = currentURL else { return nil }
        let idx = chunkIndex
        let started = currentStart ?? Date()
        dumpChunkForDebug(url: url, index: idx, startedAt: started, reason: "stop_final")

        currentFile = nil
        currentURL = nil
        currentStart = nil
        chunkIndex = 0
        debugSessionDirectory = nil

        NSLog("[SystemAudioRecorder] Stopped. Final chunk: \(url.lastPathComponent)")
        return RecordedChunk(url: url, index: idx, startedAt: started)
    }

    private func startNewChunk() {
        resetChunkStats()
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("system_chunk_\(chunkIndex)_\(UUID().uuidString).wav")
        do {
            currentFile = try AVAudioFile(forWriting: tmp, settings: targetFormat.settings)
            currentURL = tmp
            currentStart = Date()
            NSLog(
                "[SystemAudioRecorder] Started new chunk #\(chunkIndex): \(tmp.lastPathComponent)")
        } catch {
            NSLog("[SystemAudioRecorder] Error starting chunk: \(error)")
            onError?(error)
        }
    }

    private func rotateChunk() {
        guard let url = currentURL else { return }
        let silent = chunkIsSilent()
        let idx = chunkIndex
        let started = currentStart ?? Date()

        if #available(macOS 15.0, *) {
            currentFile?.close()
        }
        currentFile = nil
        currentURL = nil
        currentStart = nil

        if silent {
            dumpChunkForDebug(url: url, index: idx, startedAt: started, reason: "dropped_silent")
            try? FileManager.default.removeItem(at: url)
            NSLog("[SystemAudioRecorder] Dropping silent chunk #\(idx)")
        } else {
            dumpChunkForDebug(url: url, index: idx, startedAt: started, reason: "kept")

            DispatchQueue.main.async { [weak self] in
                self?.onChunkReady?(url, idx, started)
            }
        }

        chunkIndex += 1
        startNewChunk()
    }

    private func scheduleRotation() {
        timer?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: streamQueue)
        timer.schedule(deadline: .now() + chunkDuration, repeating: chunkDuration)
        timer.setEventHandler { [weak self] in
            self?.rotateChunk()
        }
        timer.resume()
        self.timer = timer
    }

    private func resetChunkStats() {
        chunkEnergy = 0
        chunkFrames = 0
    }

    private func recordChunkEnergy(sumSquares: Float, frames: Int) {
        chunkEnergy += sumSquares
        chunkFrames += frames
    }

    private func chunkIsSilent() -> Bool {
        guard chunkFrames > 0 else { return true }
        let avgRms = sqrt(chunkEnergy / Float(chunkFrames))
        return avgRms < silenceRmsThreshold
    }

    private func prepareDebugSessionDirectoryIfNeeded() {
        guard debugChunkDumpEnabled else { return }
        guard debugSessionDirectory == nil else { return }

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let stamp = formatter.string(from: Date())
            .replacingOccurrences(of: ":", with: "-")
        let dir = debugChunkDumpRoot
            .appendingPathComponent("system-\(stamp)-\(UUID().uuidString.prefix(8))", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            debugSessionDirectory = dir
            NSLog("[SystemAudioRecorder] Debug chunk dump enabled: %@", dir.path)
        } catch {
            NSLog("[SystemAudioRecorder] Failed to create debug chunk dump dir: %@", error.localizedDescription)
        }
    }

    private func dumpChunkForDebug(url: URL, index: Int, startedAt: Date, reason: String) {
        guard debugChunkDumpEnabled else { return }
        prepareDebugSessionDirectoryIfNeeded()
        guard let sessionDir = debugSessionDirectory else { return }

        let safeReason = reason.replacingOccurrences(of: " ", with: "_")
        let baseName = String(
            format: "remote_%04d_%@_%@",
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
            let meta = "index=\(index)\nstartedAt=\(startedAt)\nreason=\(reason)\nsource=remote\n"
            let metaURL = sessionDir.appendingPathComponent(baseName).appendingPathExtension("txt")
            try meta.write(to: metaURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("[SystemAudioRecorder] Failed to dump debug chunk #%d (%@): %@", index, reason, error.localizedDescription)
        }
    }

}

extension SystemAudioRecorder: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of outputType: SCStreamOutputType
    ) {
        guard outputType == .audio,
            let file = currentFile,
            CMSampleBufferGetNumSamples(sampleBuffer) > 0,
            let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc)
        else {
            if outputType == .audio {
                NSLog("[SystemAudioRecorder] Audio sample buffer received but guard failed")
            }
            return
        }

        let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: asbd.pointee.mSampleRate,
            channels: asbd.pointee.mChannelsPerFrame,
            interleaved: false)!
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frames),
            let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frames)
        else {
            NSLog("[SystemAudioRecorder] Failed to create audio buffers")
            return
        }

        do {
            try sampleBuffer.copyPCMData(into: inputBuffer)
        } catch {
            NSLog("[SystemAudioRecorder] Failed to copy audio data: \(error)")
            return
        }

        inputBuffer.frameLength = frames

        // Calculate RMS for this buffer (existing logic, slightly adapted to feed accumulator)
        let channel = inputBuffer.floatChannelData![0]
        var sum: Float = 0
        for i in 0..<Int(frames) {
            let sample = channel[i]
            sum += sample * sample
        }
        // Feed chunk stats
        recordChunkEnergy(sumSquares: sum, frames: Int(frames))

        let remoteLevel = sqrtf(sum / max(1, Float(frames)))
        DispatchQueue.main.async { [weak self] in
            self?.onRemoteLevel?(remoteLevel)
        }
        // Reuse converter if input format hasn't changed
        let currentRate = asbd.pointee.mSampleRate
        let currentChannels = asbd.pointee.mChannelsPerFrame
        if cachedConverter == nil
            || cachedInputSampleRate != currentRate
            || cachedInputChannels != currentChannels
        {
            guard let newConverter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
                NSLog("[SystemAudioRecorder] Failed to create audio converter")
                return
            }
            cachedConverter = newConverter
            cachedInputSampleRate = currentRate
            cachedInputChannels = currentChannels
        }
        let converter = cachedConverter!

        var didProvideInput = false
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            if didProvideInput {
                outStatus.pointee = .noDataNow
                return nil
            }
            didProvideInput = true
            outStatus.pointee = .haveData
            return inputBuffer
        }

        var convertError: NSError?
        converter.convert(to: outputBuffer, error: &convertError, withInputFrom: inputBlock)

        if let convertError {
            NSLog("[SystemAudioRecorder] Conversion error: \(convertError)")
            return
        }

        // Emit 16kHz mono buffer for echo cancellation
        // Called synchronously on streamQueue to preserve frame ordering
        if let copy = outputBuffer.deepCopy() {
            self.onRemoteAudioFrame?(copy)
        }

        do {
            try file.write(from: outputBuffer)
        } catch {
            NSLog("[SystemAudioRecorder] Error writing audio: \(error)")
            onError?(error)
        }
    }
}
extension CMSampleBuffer {
    fileprivate func copyPCMData(into buffer: AVAudioPCMBuffer) throws {
        let frameCount = CMSampleBufferGetNumSamples(self)
        guard frameCount > 0 else { return }

        buffer.frameLength = AVAudioFrameCount(frameCount)

        let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
            self,
            at: 0,
            frameCount: Int32(frameCount),
            into: buffer.mutableAudioBufferList
        )

        guard status == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: nil)
        }
    }
}

extension SystemAudioRecorder: SCStreamDelegate {
    @objc func stream(_ stream: SCStream, didStopWithError error: Error) {
        NSLog("[SystemAudioRecorder] Stream stopped with error: \(error)")
        onError?(error)
    }
}

extension AVAudioPCMBuffer {
    fileprivate func rmsLevel() -> Float {
        guard let channel = floatChannelData?[0], frameLength > 0 else { return 0 }
        var sum: Float = 0
        let count = Int(frameLength)
        for i in 0..<count {
            let sample = channel[i]
            sum += sample * sample
        }
        let rms = sqrtf(sum / max(1, Float(count)))
        return min(1, rms)
    }

    func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCapacity) else {
            return nil
        }
        copy.frameLength = frameLength
        if let src = floatChannelData, let dst = copy.floatChannelData {
            for ch in 0..<Int(format.channelCount) {
                memcpy(dst[ch], src[ch], Int(frameLength) * MemoryLayout<Float>.size)
            }
        }
        return copy
    }
}
