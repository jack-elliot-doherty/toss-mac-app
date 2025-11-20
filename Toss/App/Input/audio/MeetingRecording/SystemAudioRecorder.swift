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

    private let chunkDuration: TimeInterval = 15
    private let streamQueue = DispatchQueue(label: "ai.toss.system-audio.stream")
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false)!

    private var stream: SCStream?
    private var currentFile: AVAudioFile?
    private var currentURL: URL?
    private var currentStart: Date?
    private var chunkIndex = 0
    private var timer: DispatchSourceTimer?

    private(set) var isRunning = false
    var onChunkReady: ((URL, Int, Date) -> Void)?
    var onError: ((Error) -> Void)?
    var onRemoteLevel: ((Float) -> Void)?

    func start() async throws {
        guard !isRunning else { return }

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

        if let file = currentFile {
            file.close()
        }

        guard let url = currentURL else { return nil }
        let idx = chunkIndex
        let started = currentStart ?? Date()

        currentFile = nil
        currentURL = nil
        currentStart = nil
        chunkIndex = 0

        NSLog("[SystemAudioRecorder] Stopped. Final chunk: \(url.lastPathComponent)")
        return RecordedChunk(url: url, index: idx, startedAt: started)
    }

    private func startNewChunk() {
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
        let idx = chunkIndex
        let started = currentStart ?? Date()

        DispatchQueue.main.async { [weak self] in
            self?.onChunkReady?(url, idx, started)
        }

        currentFile = nil
        currentURL = nil
        currentStart = nil

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

        NSLog(
            "[SystemAudioRecorder] Received audio: \(frames) frames, \(asbd.pointee.mSampleRate) Hz, \(asbd.pointee.mChannelsPerFrame) channels"
        )

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

        let remoteLevel = inputBuffer.rmsLevel()
        DispatchQueue.main.async { [weak self] in
            self?.onRemoteLevel?(remoteLevel)
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            NSLog("[SystemAudioRecorder] Failed to create audio converter")
            return
        }

        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return inputBuffer
        }

        var convertError: NSError?
        converter.convert(to: outputBuffer, error: &convertError, withInputFrom: inputBlock)

        if let convertError {
            NSLog("[SystemAudioRecorder] Conversion error: \(convertError)")
            return
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
}
