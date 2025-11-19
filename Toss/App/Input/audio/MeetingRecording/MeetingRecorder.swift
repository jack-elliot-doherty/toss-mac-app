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

    // Buffering for remote reference (circular buffer simplified)
    private let referenceLock = NSLock()
    private var referenceBuffer: AVAudioPCMBuffer?
    private var referenceReadOffset: Int = 0

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

        // Enable Input scope (Mic)
        var enable: UInt32 = 1
        status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Input, 1, &enable, 4)
        try status.throwIfNeeded()

        // Enable Output scope (Speaker/Reference)
        status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_EnableIO, kAudioUnitScope_Output, 0, &enable, 4)
        try status.throwIfNeeded()

        // Setup Render Callback (Where we provide remote audio for AEC)
        var renderCallback = AURenderCallbackStruct(
            inputProc: renderRemoteReference,
            inputProcRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        status = AudioUnitSetProperty(
            unit, kAudioUnitProperty_SetRenderCallback, kAudioUnitScope_Input, 0, &renderCallback,
            UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        try status.throwIfNeeded()

        // Setup Input Callback (Where we get processed mic audio)
        var inputCallback = AURenderCallbackStruct(
            inputProc: recordProcessedMic,
            inputProcRefCon: UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        )
        status = AudioUnitSetProperty(
            unit, kAudioOutputUnitProperty_SetInputCallback, kAudioUnitScope_Global, 1,
            &inputCallback, UInt32(MemoryLayout<AURenderCallbackStruct>.size))
        try status.throwIfNeeded()

        // Set Format (Standard Float32)
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 48000,
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

        // Set format on Output of Bus 1 (Mic Output from Unit)
        status = AudioUnitSetProperty(
            unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Output, 1, &asbd,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        try status.throwIfNeeded()

        // Set format on Input of Bus 0 (Reference Input to Unit)
        status = AudioUnitSetProperty(
            unit, kAudioUnitProperty_StreamFormat, kAudioUnitScope_Input, 0, &asbd,
            UInt32(MemoryLayout<AudioStreamBasicDescription>.size))
        try status.throwIfNeeded()
    }

    // MARK: - Remote Reference Ingestion

    func ingestRemoteReference(_ buffer: AVAudioPCMBuffer) {
        referenceLock.lock()
        defer { referenceLock.unlock() }

        guard buffer.format.sampleRate == 48_000 else {
            NSLog(
                "[MeetingRecorder] Reference buffer must be 48kHz; got \(buffer.format.sampleRate)")
            return
        }

        let monoCopy = AVAudioPCMBuffer(
            pcmFormat: AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 48_000,
                channels: 1,
                interleaved: false)!,
            frameCapacity: buffer.frameCapacity)!
        monoCopy.frameLength = buffer.frameLength

        let dst = monoCopy.floatChannelData![0]
        let left = buffer.floatChannelData![0]
        if buffer.format.channelCount == 2 {
            let right = buffer.floatChannelData![1]
            vDSP_vadd(left, 1, right, 1, dst, 1, vDSP_Length(buffer.frameLength))
            var scale: Float = 0.5
            vDSP_vsmul(dst, 1, &scale, dst, 1, vDSP_Length(buffer.frameLength))
        } else {
            memcpy(dst, left, Int(buffer.frameLength) * MemoryLayout<Float>.size)
        }

        referenceBuffer = monoCopy
        referenceReadOffset = 0

    }

    // MARK: - Core Audio Callbacks

    private let renderRemoteReference: AURenderCallback = {
        (inRefCon, ioActionFlags, inTimeStamp, inBusNumber, inNumberFrames, ioData) -> OSStatus in
        let recorder = Unmanaged<MeetingRecorder>.fromOpaque(inRefCon).takeUnretainedValue()
        let ioList = UnsafeMutableAudioBufferListPointer(ioData!)
        let status = recorder.provideReferenceAudio(ioData: ioList, frameCount: inNumberFrames)
        ioActionFlags.pointee.insert(.unitRenderAction_OutputIsSilence)
        for i in 0..<ioList.count {
            memset(ioList[i].mData, 0, Int(ioList[i].mDataByteSize))
        }
        return status
    }

    private func provideReferenceAudio(
        ioData: UnsafeMutableAudioBufferListPointer, frameCount: UInt32
    ) -> OSStatus {
        referenceLock.lock()
        defer { referenceLock.unlock() }

        guard let ref = referenceBuffer else {
            for i in 0..<ioData.count {
                memset(ioData[i].mData, 0, Int(ioData[i].mDataByteSize))
            }
            return noErr
        }

        let availableFrames = Int(ref.frameLength) - referenceReadOffset
        let framesToCopy = min(Int(frameCount), availableFrames)
        if framesToCopy <= 0 {
            for i in 0..<ioData.count {
                memset(ioData[i].mData, 0, Int(ioData[i].mDataByteSize))
            }
            return noErr
        }

        let bytes = framesToCopy * MemoryLayout<Float>.size
        memcpy(ioData[0].mData, ref.floatChannelData![0] + referenceReadOffset, bytes)

        if ioData.count > 1 {
            memcpy(ioData[1].mData, ref.floatChannelData![0] + referenceReadOffset, bytes)
        }

        referenceReadOffset += framesToCopy
        if referenceReadOffset >= Int(ref.frameLength) {
            referenceBuffer = nil
            referenceReadOffset = 0
        }
        return noErr
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
        // Wrap in AVAudioPCMBuffer
        guard
            let pcmBuffer = AVAudioPCMBuffer(
                pcmFormat: AVAudioFormat(
                    commonFormat: .pcmFormatFloat32, sampleRate: 48000, channels: 1,
                    interleaved: false)!, frameCapacity: AVAudioFrameCount(frames))
        else { return }

        pcmBuffer.frameLength = AVAudioFrameCount(frames)
        memcpy(pcmBuffer.floatChannelData![0], data, Int(frames * 4))

        // Convert to 16kHz
        guard let converter = AVAudioConverter(from: pcmBuffer.format, to: targetFormat),
            let outputBuffer = AVAudioPCMBuffer(
                pcmFormat: targetFormat, frameCapacity: AVAudioFrameCount(frames))
        else { return }

        var error: NSError?
        converter.convert(to: outputBuffer, error: &error) { _, outStatus in
            outStatus.pointee = .haveData
            return pcmBuffer
        }

        if let file = currentChunkFile {
            ioQueue.async {
                try? file.write(from: outputBuffer)
            }
        }

        // Level Metering
        let count = Int(frames)
        let samples = pcmBuffer.floatChannelData![0]
        var sum: Float = 0
        for i in 0..<count {
            let s = samples[i]
            sum += s * s
        }
        let rms = min(1.0, max(0.0, sqrtf(sum / max(1, Float(count))) * 4.0))
        DispatchQueue.main.async { [weak self] in self?.onLevelUpdate?(rms) }
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

extension OSStatus {
    fileprivate func throwIfNeeded() throws {
        if self != noErr {
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
        if let src = floatChannelData, let dst = copy.floatChannelData {
            for i in 0..<Int(format.channelCount) {
                memcpy(dst[i], src[i], Int(frameLength) * 4)
            }
        }
        return copy
    }
}
