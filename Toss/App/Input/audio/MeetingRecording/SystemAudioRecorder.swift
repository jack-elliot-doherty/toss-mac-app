import AVFoundation
import CoreMedia
import CoreVideo
import QuartzCore

final class SystemAudioRecorder: NSObject {
    struct RecordedChunk {
        let url: URL
        let index: Int
        let startedAt: Date
    }

    private let chunkDuration: TimeInterval = 15
    private let session = AVCaptureSession()
    private let audioOutput = AVCaptureAudioDataOutput()
    private let processingQueue = DispatchQueue(label: "ai.toss.system-audio.capture")
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16_000,
        channels: 1,
        interleaved: false)!

    private var currentFile: AVAudioFile?
    private var currentURL: URL?
    private var currentStart: Date?
    private var chunkIndex = 0
    private var timer: Timer?

    private(set) var isRunning = false
    var onChunkReady: ((URL, Int, Date) -> Void)?
    var onError: ((Error) -> Void)?

    func start() throws {
        guard !isRunning else { return }

        guard let screenInput = AVCaptureScreenInput(displayID: CGMainDisplayID()) else {
            throw NSError(
                domain: "SystemAudioRecorder",
                code: -1,
                userInfo: [NSLocalizedDescriptionKey: "Unable to access display"])
        }
        screenInput.capturesCursor = false
        screenInput.capturesMouseClicks = false

        session.beginConfiguration()
        session.sessionPreset = .high

        if session.canAddInput(screenInput) {
            session.addInput(screenInput)
        } else {
            session.commitConfiguration()
            throw NSError(
                domain: "SystemAudioRecorder",
                code: -2,
                userInfo: [NSLocalizedDescriptionKey: "Cannot add screen input"])
        }

        if session.canAddOutput(audioOutput) {
            session.addOutput(audioOutput)
        } else {
            session.commitConfiguration()
            throw NSError(
                domain: "SystemAudioRecorder",
                code: -3,
                userInfo: [NSLocalizedDescriptionKey: "Cannot add audio output"])
        }

        session.commitConfiguration()

        audioOutput.setSampleBufferDelegate(self, queue: processingQueue)

        startNewChunk()
        scheduleRotation()

        session.startRunning()
        isRunning = true
    }

    func stop() -> RecordedChunk? {
        guard isRunning else { return nil }

        timer?.invalidate()
        timer = nil
        session.stopRunning()
        isRunning = false

        guard let url = currentURL else { return nil }
        let chunk = RecordedChunk(
            url: url,
            index: chunkIndex,
            startedAt: currentStart ?? Date()
        )

        currentFile = nil
        currentURL = nil
        currentStart = nil
        chunkIndex = 0
        return chunk
    }

    private func startNewChunk() {
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("system_chunk_\(chunkIndex)_\(UUID().uuidString).wav")
        do {
            currentFile = try AVAudioFile(forWriting: tmp, settings: targetFormat.settings)
            currentURL = tmp
            currentStart = Date()
        } catch {
            onError?(error)
        }
    }

    private func rotateChunk() {
        guard let url = currentURL else { return }
        let idx = chunkIndex
        let started = currentStart ?? Date()
        currentFile = nil

        DispatchQueue.main.async { [weak self] in
            self?.onChunkReady?(url, idx, started)
        }

        chunkIndex += 1
        startNewChunk()
    }

    private func scheduleRotation() {
        timer = Timer.scheduledTimer(withTimeInterval: chunkDuration, repeats: true) {
            [weak self] _ in
            self?.rotateChunk()
        }
        if let timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }
}

extension SystemAudioRecorder: AVCaptureAudioDataOutputSampleBufferDelegate {
    func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let file = currentFile,
            let formatDesc = CMSampleBufferGetFormatDescription(sampleBuffer),
            let asbd = CMAudioFormatDescriptionGetStreamBasicDescription(formatDesc),
            let block = CMSampleBufferGetDataBuffer(sampleBuffer)
        else { return }

        let inputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: asbd.pointee.mSampleRate,
            channels: asbd.pointee.mChannelsPerFrame,
            interleaved: false)!
        let frames = AVAudioFrameCount(CMSampleBufferGetNumSamples(sampleBuffer))

        guard let inputBuffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: frames),
            let outputBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: frames)
        else { return }

        inputBuffer.frameLength = frames
        block.copyAudioBufferContents(to: inputBuffer)

        guard let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else { return }
        converter.convert(to: outputBuffer, error: nil) { _, _ in inputBuffer }

        do {
            try file.write(from: outputBuffer)
        } catch {
            onError?(error)
        }
    }
}

extension CMBlockBuffer {
    fileprivate func copyAudioBufferContents(to buffer: AVAudioPCMBuffer) {
        let length = Int(buffer.frameLength) * Int(buffer.stride)
        var data = Data(count: length)
        data.withUnsafeMutableBytes { dest in
            _ = CMBlockBufferCopyDataBytes(
                self,
                atOffset: 0,
                dataLength: length,
                destination: dest.baseAddress!)
        }
        memcpy(buffer.floatChannelData![0], data.withUnsafeBytes { $0.baseAddress! }, length)
    }
}
