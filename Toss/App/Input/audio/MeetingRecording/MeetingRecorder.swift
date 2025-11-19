import AVFoundation
import AudioToolbox
import Foundation

final class MeetingRecorder {

    struct RecordedChunk {
        let url: URL
        let index: Int
        let startedAt: Date
    }

    private let chunkDuration: TimeInterval = 15.0

    // Engine + voice-processing IO unit
    private let engine = AVAudioEngine()
    private let remotePlayer = AVAudioPlayerNode()
    private let remoteReferenceQueue = DispatchQueue(label: "ai.toss.meeting.remote")
    private lazy var voiceIO: AVAudioUnit = {
        let desc = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_VoiceProcessingIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        let semaphore = DispatchSemaphore(value: 0)
        var createdUnit: AVAudioUnit?
        var creationError: Error?

        AVAudioUnit.instantiate(with: desc, options: []) { unit, error in
            createdUnit = unit
            creationError = error
            semaphore.signal()
        }
        semaphore.wait()

        if let error = creationError {
            fatalError("Failed to create voice-processing unit: \(error)")
        }
        return createdUnit!
    }()
    private let mixer = AVAudioMixerNode()

    private var currentChunkFile: AVAudioFile?
    private var currentChunkURL: URL?
    private var currentChunkStartedAt: Date?
    private var chunkTimer: Timer?
    private var chunkIndex: Int = 0
    private let ioQueue = DispatchQueue(label: "ai.toss.meeting.io")

    var onError: ((Error) -> Void)?
    var onLevelUpdate: ((Float) -> Void)?
    var onChunkReady: ((URL, Int, Date) -> Void)?

    private(set) var isRunning = false
    private(set) var isPaused = false

    func start() {
        guard !isRunning else { return }

        do {
            try configureVoiceProcessingIO()
        } catch {
            onError?(error)
            return
        }

        let micFormat = voiceIO.outputFormat(forBus: 1)  // processed mic bus
        guard
            let outputFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
            )
        else {
            onError?(NSError(domain: "MeetingRecorder", code: 1, userInfo: nil))
            return
        }

        NSLog("[MeetingRecorder] Starting meeting recording at 16kHz mono")

        if remotePlayer.engine == nil { engine.attach(remotePlayer) }
        if voiceIO.engine == nil { engine.attach(voiceIO) }
        if mixer.engine == nil { engine.attach(mixer) }

        let referenceFormat = voiceIO.inputFormat(forBus: 0)

        engine.connect(remotePlayer, to: voiceIO, fromBus: 0, toBus: 0, format: referenceFormat)
        engine.connect(voiceIO, to: mixer, fromBus: 1, toBus: 0, format: micFormat)

        guard let converter = AVAudioConverter(from: micFormat, to: outputFormat) else {
            onError?(NSError(domain: "MeetingRecorder", code: 2, userInfo: nil))
            return
        }

        startNewChunk(format: outputFormat)

        mixer.installTap(onBus: 0, bufferSize: 4096, format: micFormat) { [weak self] buffer, _ in
            guard let self, let file = self.currentChunkFile else { return }

            let frameCapacity = AVAudioFrameCount(
                Double(buffer.frameLength) * outputFormat.sampleRate / micFormat.sampleRate)
            guard
                let convertedBuffer = AVAudioPCMBuffer(
                    pcmFormat: outputFormat, frameCapacity: frameCapacity)
            else { return }

            var convertError: NSError?
            let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                outStatus.pointee = .haveData
                return buffer
            }

            converter.convert(to: convertedBuffer, error: &convertError, withInputFrom: inputBlock)

            guard convertError == nil else {
                NSLog("[MeetingRecorder] Conversion error: \(convertError!)")
                return
            }

            self.ioQueue.async {
                try? file.write(from: convertedBuffer)
            }

            if let ch0 = buffer.floatChannelData?[0] {
                let count = Int(buffer.frameLength)
                var sum: Float = 0
                for i in 0..<count {
                    let s = ch0[i]
                    sum += s * s
                }
                let rms = min(1.0, max(0.0, sqrtf(sum / max(1, Float(count))) * 4.0))
                DispatchQueue.main.async { [weak self] in self?.onLevelUpdate?(rms) }
            }
        }

        engine.prepare()

        do {
            try engine.start()
            remotePlayer.play()
            isRunning = true
            chunkTimer = Timer.scheduledTimer(withTimeInterval: chunkDuration, repeats: true) {
                [weak self] _ in
                guard let self, let format = self.currentChunkFile?.processingFormat else { return }
                self.rotateChunk(format: format)
            }
            NSLog("[MeetingRecorder] Engine started, chunk rotation scheduled")
        } catch {
            onError?(error)
        }
    }

    private func configureVoiceProcessingIO() throws {
        if voiceIO.engine == nil {
            engine.attach(voiceIO)
        }

        try voiceIO.setIO(enabled: true, scope: kAudioUnitScope_Input, bus: 1)  // enable mic
        try voiceIO.setIO(enabled: false, scope: kAudioUnitScope_Output, bus: 0)  // disable speaker out
        try voiceIO.setVoiceProcessing(bypassed: false)
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

        currentChunkFile = nil
        DispatchQueue.main.async { [weak self] in
            self?.onChunkReady?(url, index, startedAt)
        }

        chunkIndex += 1
        startNewChunk(format: format)
    }

    func stop() -> RecordedChunk? {
        guard isRunning else { return nil }
        chunkTimer?.invalidate()
        chunkTimer = nil
        mixer.removeTap(onBus: 0)
        engine.stop()
        remotePlayer.stop()

        do {
            try voiceIO.setVoiceProcessing(bypassed: true)
        } catch {
            NSLog("[MeetingRecorder] Failed to disable voice processing: \(error)")
        }

        isRunning = false
        isPaused = false

        guard let url = currentChunkURL else { return nil }
        let chunk = RecordedChunk(
            url: url, index: chunkIndex, startedAt: currentChunkStartedAt ?? Date())

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
                [weak self] _ in self?.rotateChunk(format: format)
            }
            RunLoop.main.add(chunkTimer!, forMode: .common)
        } catch {
            onError?(error)
        }
    }

    func ingestRemoteReference(_ buffer: AVAudioPCMBuffer) {
        remoteReferenceQueue.async { [weak self] in
            guard let self, self.isRunning, let prepared = self.prepareReferenceBuffer(buffer)
            else { return }
            self.remotePlayer.scheduleBuffer(prepared, completionHandler: nil)
        }
    }

    private func prepareReferenceBuffer(_ buffer: AVAudioPCMBuffer) -> AVAudioPCMBuffer? {
        let targetFormat = voiceIO.inputFormat(forBus: 0)

        if buffer.matches(format: targetFormat) {
            return buffer.deepCopy()
        }

        guard
            let converter = AVAudioConverter(from: buffer.format, to: targetFormat),
            let converted = AVAudioPCMBuffer(
                pcmFormat: targetFormat,
                frameCapacity: AVAudioFrameCount(
                    Double(buffer.frameLength) * targetFormat.sampleRate / buffer.format.sampleRate)
            )
        else { return nil }

        var error: NSError?
        let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
            outStatus.pointee = .haveData
            return buffer
        }
        converter.convert(to: converted, error: &error, withInputFrom: inputBlock)
        return error == nil ? converted : nil
    }

}
// MARK: - AudioUnit helpers

extension AVAudioUnit {
    fileprivate func setIO(enabled: Bool, scope: AudioUnitScope, bus: AudioUnitElement) throws {
        var value: UInt32 = enabled ? 1 : 0
        let status = AudioUnitSetProperty(
            audioUnit,
            kAudioOutputUnitProperty_EnableIO,
            scope,
            bus,
            &value,
            UInt32(MemoryLayout.size(ofValue: value))
        )
        try status.throwIfNeeded()
    }

    fileprivate func setVoiceProcessing(bypassed: Bool) throws {
        var flag: UInt32 = bypassed ? 1 : 0
        let status = AudioUnitSetProperty(
            audioUnit,
            kAUVoiceIOProperty_BypassVoiceProcessing,
            kAudioUnitScope_Global,
            0,
            &flag,
            UInt32(MemoryLayout.size(ofValue: flag))
        )
        try status.throwIfNeeded()
    }
}

extension OSStatus {
    fileprivate func throwIfNeeded() throws {
        guard self == noErr else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(self), userInfo: nil)
        }
    }
}

extension AVAudioPCMBuffer {
    fileprivate func deepCopy() -> AVAudioPCMBuffer? {
        guard let copy = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameLength) else {
            return nil
        }
        copy.frameLength = frameLength
        let channels = Int(format.channelCount)
        let bytes = Int(frameLength) * MemoryLayout<Float>.size
        for ch in 0..<channels {
            memcpy(copy.floatChannelData![ch], floatChannelData![ch], bytes)
        }
        return copy
    }

    fileprivate func matches(format other: AVAudioFormat) -> Bool {
        format.commonFormat == other.commonFormat && format.sampleRate == other.sampleRate
            && format.channelCount == other.channelCount && !format.isInterleaved
            && !other.isInterleaved
    }
}
