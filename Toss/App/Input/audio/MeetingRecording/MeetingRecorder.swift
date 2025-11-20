import AVFoundation
import Accelerate
import AudioToolbox
import Foundation

final class MeetingRecorder {

    struct RecordedChunk {
        let url: URL
        let index: Int
        let startedAt: Date
    }

    private let chunkDuration: TimeInterval = 15.0
    private var voiceUnit: AudioUnit?
    private var graph: AUGraph?

    private var ducking = DuckingProcessor()
    private var remoteLevelRMS: Float = 0
    private let remoteLevelLock = NSLock()

    // Conversion & Writing
    private var currentChunkFile: AVAudioFile?
    private var currentChunkURL: URL?
    private var currentChunkStartedAt: Date?
    private var chunkTimer: Timer?
    private var chunkIndex: Int = 0
    private let ioQueue = DispatchQueue(label: "ai.toss.meeting.io")

    // Target format: 16kHz Mono Float32
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: 16000,
        channels: 1,
        interleaved: false
    )!

    var onError: ((Error) -> Void)?
    var onLevelUpdate: ((Float) -> Void)?
    var onChunkReady: ((URL, Int, Date) -> Void)?

    private(set) var isRunning = false
    private(set) var isPaused = false

    func start() {
        guard !isRunning else { return }

        do {
            try setupAudioGraph()
            startNewChunk()

            var status = AUGraphInitialize(graph!)
            try status.throwIfNeeded()

            status = AUGraphStart(graph!)
            try status.throwIfNeeded()

            isRunning = true
            NSLog("[MeetingRecorder] Voice Processing Graph started")

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

        if let graph = graph {
            AUGraphStop(graph)
            AUGraphUninitialize(graph)
            AUGraphClose(graph)
            DisposeAUGraph(graph)
        }
        graph = nil
        voiceUnit = nil

        isRunning = false
        isPaused = false

        guard let url = currentChunkURL else { return nil }
        let chunk = RecordedChunk(
            url: url, index: chunkIndex, startedAt: currentChunkStartedAt ?? Date())

        currentChunkFile = nil  // Closes file
        currentChunkURL = nil
        currentChunkStartedAt = nil
        chunkIndex = 0

        NSLog("[MeetingRecorder] Stopped")
        return chunk
    }

    // MARK: - Graph Setup

    private func setupAudioGraph() throws {
        var status = NewAUGraph(&graph)
        try status.throwIfNeeded()

        var cd = AudioComponentDescription(
            componentType: kAudioUnitType_Output,
            componentSubType: kAudioUnitSubType_VoiceProcessingIO,
            componentManufacturer: kAudioUnitManufacturer_Apple,
            componentFlags: 0,
            componentFlagsMask: 0
        )

        var node: AUNode = 0
        status = AUGraphAddNode(graph!, &cd, &node)
        try status.throwIfNeeded()

        status = AUGraphOpen(graph!)
        try status.throwIfNeeded()

        status = AUGraphNodeInfo(graph!, node, nil, &voiceUnit)
        try status.throwIfNeeded()

        guard let unit = voiceUnit else {
            throw NSError(domain: "MeetingRecorder", code: -1, userInfo: nil)
        }

        var enable: UInt32 = 1
        status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enable, 4)
        try status.throwIfNeeded()

        status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enable, 4)
        try status.throwIfNeeded()

        var inputCallback = AURenderCallbackStruct(
            inputProc: recordProcessedMic,
            inputProcRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1,
            &inputCallback, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        try status.throwIfNeeded()

        var asbd = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked
                | kAudioFormatFlagIsNonInterleaved,
            mBytesPerPacket: 4,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4,
            mChannelsPerFrame: 1,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        status = AudioUnitSetProperty(
            unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &asbd,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        try status.throwIfNeeded()
    }

    func updateRemoteLevel(_ level: Float) {
        remoteLevelLock.lock()
        remoteLevelRMS = level
        remoteLevelLock.unlock()
    }

    private func currentRemoteLevel() -> Float {
        remoteLevelLock.lock()
        defer { remoteLevelLock.unlock() }
        return remoteLevelRMS
    }

    private let recordProcessedMic: AURenderCallback = {
        (inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData) -> OSStatus in
        let recorder = Unmanaged<MeetingRecorder>.fromOpaque(inRefCon).takeUnretainedValue()
        return recorder.captureMicAudio(
            frameCount: inNumberFrames, timeStamp: inTimeStamp, bus: inBusNumber)
    }

    private func captureMicAudio(
        frameCount: UInt32, timeStamp: UnsafePointer<AudioTimeStamp>, bus: UInt32
    ) -> OSStatus {
        guard let unit = voiceUnit else { return noErr }

        var bufferList = AudioBufferList()
        bufferList.mNumberBuffers = 1
        bufferList.mBuffers.mNumberChannels = 1
        bufferList.mBuffers.mDataByteSize = frameCount * 4
        bufferList.mBuffers.mData = nil  // AudioUnitRender will allocate if null, or we provide scratch memory.

        // We need to allocate a buffer for AudioUnitRender to fill
        // Or simpler: Use an AVAudioPCMBuffer wrapper.

        // Let's alloc a temporary buffer
        let byteSize = Int(frameCount * 4)
        let rawPointer = UnsafeMutableRawPointer.allocate(byteCount: byteSize, alignment: 16)
        defer { rawPointer.deallocate() }

        bufferList.mBuffers.mData = rawPointer

        var flags: AudioUnitRenderActionFlags = []
        var ts = timeStamp.pointee

        let status = AudioUnitRender(unit, &flags, &ts, 1, frameCount, &bufferList)
        if status == noErr {
            // We have processed audio in rawPointer!
            // Convert to 16kHz and Write to file
            processAndWriteMicData(data: rawPointer, frames: frameCount)
        }

        return status
    }

    private func processAndWriteMicData(data: UnsafeMutableRawPointer, frames: UInt32) {
        guard
            let pcmBuffer = AVAudioPCMBuffer(
                pcmFormat: AVAudioFormat(
                    commonFormat: .pcmFormatFloat32,
                    sampleRate: 48_000,
                    channels: 1,
                    interleaved: false
                )!,
                frameCapacity: AVAudioFrameCount(frames)
            )
        else { return }

        pcmBuffer.frameLength = AVAudioFrameCount(frames)
        memcpy(pcmBuffer.floatChannelData![0], data, Int(frames * 4))

        let samples = pcmBuffer.floatChannelData![0]
        let count = Int(frames)

        var sum: Float = 0
        for i in 0..<count {
            let s = samples[i]
            sum += s * s
        }
        let micRMS = sqrtf(sum / max(1, Float(count)))

        let uiLevel = min(1.0, micRMS * 4.0)
        DispatchQueue.main.async { [weak self] in
            self?.onLevelUpdate?(uiLevel)
        }

        let remote = currentRemoteLevel()
        let gain = ducking.gain(remoteLevel: remote, micLevel: micRMS)
        if gain < 0.999 {
            var g = gain
            vDSP_vsmul(samples, 1, &g, samples, 1, vDSP_Length(count))
        }

        guard
            let converter = AVAudioConverter(from: pcmBuffer.format, to: targetFormat),
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(frames))
        else { return }

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return pcmBuffer
        }

        if let error {
            NSLog("[MeetingRecorder] Conversion error: \(error)")
            return
        }

        guard let file = currentChunkFile else { return }
        ioQueue.async {
            do {
                try file.write(from: outputBuffer)
            } catch {
                NSLog("[MeetingRecorder] Error writing mic audio: \(error)")
            }
        }
    }
    // MARK: - Lifecycle Helpers

    private func startNewChunk() {
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
            guard let self = self else { return }
            self.rotateChunk()
        }
    }

    private func rotateChunk() {
        guard let url = currentChunkURL else { return }
        let idx = chunkIndex
        let start = currentChunkStartedAt ?? Date()

        currentChunkFile = nil  // Flush file
        DispatchQueue.main.async { [weak self] in
            self?.onChunkReady?(url, idx, start)
        }

        chunkIndex += 1
        startNewChunk()
    }

    private func teardown() {
        if let graph = graph {
            AUGraphStop(graph)
            AUGraphUninitialize(graph)
            AUGraphClose(graph)
            DisposeAUGraph(graph)
        }
        graph = nil
        voiceUnit = nil
        isRunning = false
    }

    func pause() {
        // MVP: Just stop graph? Or pause writing?
        // For now, let's just stop to be safe.
        _ = stop()
    }

    func resume() {
        start()
    }
}

private struct DuckingProcessor {
    var remoteThreshold: Float = 0.08
    var micQuietThreshold: Float = 0.03
    var strongDuckGain: Float = 0.25
    var mildDuckGain: Float = 0.85
    var attack: Float = 0.05
    var release: Float = 0.2
    private(set) var currentGain: Float = 1.0

    mutating func gain(remoteLevel: Float, micLevel: Float) -> Float {
        let target: Float
        if remoteLevel > remoteThreshold {
            target = micLevel < micQuietThreshold ? strongDuckGain : mildDuckGain
        } else {
            target = 1.0
        }

        let diff = target - currentGain
        if abs(diff) < 0.001 {
            currentGain = target
            return currentGain
        }

        let step = diff > 0 ? attack : release
        currentGain += diff * step
        currentGain = max(strongDuckGain, min(currentGain, 1.0))
        return currentGain
    }
}

extension OSStatus {
    fileprivate func throwIfNeeded() throws {
        if self != noErr {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(self), userInfo: nil)
        }
    }
}
