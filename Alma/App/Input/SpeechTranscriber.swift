import Foundation
import AVFoundation
import Speech

final class SpeechTranscriber {
    private let audioEngine = AVAudioEngine()
    private let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en-US"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private var audioFile: AVAudioFile?
    private var tempFileURL: URL?
    private var producedFinal = false
    private let streamingEnabled = false
    private var targetFormat: AVAudioFormat?
    private var converter: AVAudioConverter?

    var onPartial: ((String) -> Void)?
    var onFinal: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    private(set) var isRunning = false

    func start() {
        guard !isRunning else { return }

        SFSpeechRecognizer.requestAuthorization { [weak self] status in
            guard let self = self else { return }
            guard status == .authorized else {
                self.onError?(NSError(domain: "SpeechTranscriber", code: 2, userInfo: [NSLocalizedDescriptionKey: "Speech recognition not authorized"]))
                return
            }
            self.startSession()
        }
    }

    func stop() {
        guard isRunning else { return }
        recognitionRequest?.endAudio()
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
        isRunning = false

        // If we didn't get a final result, try URL-based recognition on the recorded file
        if !producedFinal, let url = tempFileURL {
            recognizeFile(url: url)
        }
    }

    private func startSession() {
        // On macOS, AVAudioSession is not required; proceed directly to engine setup

        if streamingEnabled {
            let request = SFSpeechAudioBufferRecognitionRequest()
            request.shouldReportPartialResults = true
            if #available(macOS 12.0, *) {
                request.requiresOnDeviceRecognition = false
            }
            if #available(macOS 11.0, *) {
                request.taskHint = SFSpeechRecognitionTaskHint.dictation
            }
            recognitionRequest = request
        } else {
            recognitionRequest = nil
        }

        let inputNode = audioEngine.inputNode
        let inputFormat = inputNode.inputFormat(forBus: 0)

        // Prepare a temporary WAV file to fall back on URL-based recognition if streaming fails
        do {
            let tmp = FileManager.default.temporaryDirectory.appendingPathComponent("alma_\(UUID().uuidString).wav")
            let outFormat = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: 16_000, channels: 1, interleaved: false)!
            self.targetFormat = outFormat
            self.converter = AVAudioConverter(from: inputFormat, to: outFormat)
            let file = try AVAudioFile(forWriting: tmp, settings: outFormat.settings)
            self.tempFileURL = tmp
            self.audioFile = file
        } catch {
            onError?(error)
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self = self else { return }
            if let req = self.recognitionRequest { req.append(buffer) }
            // Also write to the temp file for fallback URL recognition
            if let converter = self.converter, let outFormat = self.targetFormat, let file = self.audioFile {
                let ratio = outFormat.sampleRate / inputFormat.sampleRate
                let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio + 256)
                if let outBuffer = AVAudioPCMBuffer(pcmFormat: outFormat, frameCapacity: capacity) {
                    var convError: NSError?
                    let _ = converter.convert(to: outBuffer, error: &convError, withInputFrom: { _, outStatus in
                        outStatus.pointee = .haveData
                        return buffer
                    })
                    if convError == nil {
                        do { try file.write(from: outBuffer) } catch { /* ignore */ }
                    }
                }
            }
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            onError?(error)
            return
        }

        guard let recognizer = speechRecognizer, recognizer.isAvailable else {
            onError?(NSError(domain: "SpeechTranscriber", code: 3, userInfo: [NSLocalizedDescriptionKey: "Speech recognizer unavailable"]))
            return
        }

        if streamingEnabled, let request = recognitionRequest {
            producedFinal = false
            recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
                guard let self = self else { return }
                if let result = result {
                    let text = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.producedFinal = true
                        self.onFinal?(text)
                    } else {
                        self.onPartial?(text)
                    }
                }
                if let error = error {
                    self.onError?(error)
                }
            }
        }

        isRunning = true
    }
}

private extension SpeechTranscriber {
    func recognizeFile(url: URL) {
        guard let recognizer = speechRecognizer else { return }
        let request = SFSpeechURLRecognitionRequest(url: url)
        if #available(macOS 12.0, *) {
            request.requiresOnDeviceRecognition = false
        }
        if #available(macOS 11.0, *) {
            request.taskHint = SFSpeechRecognitionTaskHint.dictation
        }
        recognizer.recognitionTask(with: request) { [weak self] result, error in
            guard let self = self else { return }
            defer { try? FileManager.default.removeItem(at: url) }
            if let result = result {
                let text = result.bestTranscription.formattedString
                self.onFinal?(text)
                return
            }
            if let error = error {
                if CloudASRClient.shared.isConfigured {
                    CloudASRClient.shared.transcribe(fileURL: url) { res in
                        DispatchQueue.main.async {
                            switch res {
                            case .success(let text):
                                self.onFinal?(text)
                            case .failure(let err):
                                self.onError?(err)
                            }
                        }
                    }
                } else {
                    self.onError?(error)
                }
            }
        }
    }
}


