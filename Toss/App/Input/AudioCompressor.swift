import AVFoundation

enum AudioCompressorError: Error {
    case readerInitFailed
    case writerInitFailed
    case exportFailed(String)
}

struct AudioCompressor {
    /// Compresses a 16 kHz mono WAV to AAC (.m4a) at ≈32 kbps.
    static func compressToM4A(sourceURL: URL) async throws -> URL {
        let asset = AVURLAsset(url: sourceURL)
        guard let reader = try? AVAssetReader(asset: asset) else {
            throw AudioCompressorError.readerInitFailed
        }

        guard let track = asset.tracks(withMediaType: .audio).first else {
            throw AudioCompressorError.exportFailed("No audio track")
        }

        let outputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
        ]
        let readerOutput = AVAssetReaderTrackOutput(track: track, outputSettings: outputSettings)
        reader.add(readerOutput)

        let tmpM4A = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("m4a")

        guard let writer = try? AVAssetWriter(outputURL: tmpM4A, fileType: .m4a) else {
            throw AudioCompressorError.writerInitFailed
        }

        let inputSettings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: 16_000,
            AVNumberOfChannelsKey: 1,
            AVEncoderBitRateKey: 32_000,
        ]
        let writerInput = AVAssetWriterInput(mediaType: .audio, outputSettings: inputSettings)
        writerInput.expectsMediaDataInRealTime = false
        writer.add(writerInput)

        reader.startReading()
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)

        let queue = DispatchQueue(label: "ai.toss.audio.compressor")
        try await withCheckedThrowingContinuation { continuation in
            writerInput.requestMediaDataWhenReady(on: queue) {
                while writerInput.isReadyForMoreMediaData {
                    if let buffer = readerOutput.copyNextSampleBuffer() {
                        writerInput.append(buffer)
                    } else {
                        writerInput.markAsFinished()
                        writer.finishWriting {
                            if reader.status == .completed && writer.status == .completed {
                                continuation.resume(returning: tmpM4A)
                            } else {
                                continuation.resume(
                                    throwing: AudioCompressorError.exportFailed(
                                        writer.error?.localizedDescription ?? reader.error?
                                            .localizedDescription ?? "Unknown error"
                                    )
                                )
                            }
                        }
                        return
                    }
                }
            }
        }

        return tmpM4A
    }
}
