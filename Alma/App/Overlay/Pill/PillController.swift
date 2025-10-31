import Foundation

// ORchestrates inputs, feed them to state machine and carries out side effects

@MainActor
final class PillController {
    private var machine = PillStateMachine()

    // orchestration flags
    private var isRecording = false
    private var isTranscribing = false
    private var lastRecordingURL: URL?

    // dependencies injected from AppDelegate
    private let audio: AudioRecorder
    private let transcriber: TranscribeAPI
    private let paste: PasteManager
    private let pillPanel: PillPanelController
    private let toast: ToastPanelController
    private let viewModel: PillViewModel
    private let history: HistoryRepo
    private let auth: AuthManager

    init(
        audio: AudioRecorder,
        transcriber: TranscribeAPI,
        paste: PasteManager,
        pillPanel: PillPanelController,
        toast: ToastPanelController,
        viewModel: PillViewModel,
        history: HistoryRepository,
        auth: AuthManager
    ) {
        self.audio = audio
        self.transcriber = transcriber
        self.paste = paste
        self.pillPanel = pillPanel
        self.toast = toast
        self.viewModel = viewModel
        self.history = history
        self.auth = auth
    }

    private func log(_ s: String) { print("[PillController] \(s)") }

    // Call this once from AppDelegate to wire keyboard  + buttons
    func start() {
        // TODO hook up hotkey callbacks and pill buttons to send()

    }

    /// Public ingress: feed events into the machine, then perform returned effects.
    func send(_ event: PillEvent) {
        log("EVENT: \(event)")
        let effects = machine.handle(event)
        log("STATE: \(machineStateDebug()) EFFECTS: \(effects)")
        perform(effects)
    }

    // Effect executor
    private func perform(_ effects: [PillEffect]) {

        for effect in effects {
            switch effect {
            case .startAudioCapture:
                handleStartAudio()

            case .stopAudioCapture:
                handleStopAudio()

            case .startTranscription:
                handleStartTranscription()

            case .pasteText(let Text):
                handlePasteOrCopyText(Text)

            case .copyToClipboard(let Text):
                handleCopy(text)

            case .sendToAgent(let text):
                handleSendToAgent(text)

            case .setVisualStateListening:
                viewModel.setListeningUI()
                pillPanel.setState(.listening)

            case .setVisualStateTranscribing:
                viewModel.setTranscribingUI()
                pillPanel.setState(.transcribing)

            case .setVisualStateIdle:
                viewModel.setIdleUI()
                pillPanel.setState(.idle)

            case .showToast(let message):
                toast.show(message: message, duration: 1.8)

            }
        }

    }

    // MARK: - Individual effect handlers (fill these next)

    private func handleStartAudio() {
        // Guard against re-entry
        guard !isRecording else { return }
        isRecording = true

        // Start audio engine; provide level callback to update the waveform
        // TODO: audio.start()
        // TODO: audio.onLevelUpdate = { [weak self] rms in self?.viewModel.updateLevelRMS(rms) }
    }

    private func handleStopAudio() {
        guard isRecording else { return }
        isRecording = false

        // Stop audio and keep the file URL for transcription
        // TODO: lastRecordingURL = audio.stop()
    }

    private func handleStartTranscription() {
        guard !isTranscribing else { return }
        guard let url = self.lastRecordingURL else {
            toast.show(message: "No recording found", duration: 1.8)
            return
        }
        isTranscribing = true

        // Get auth token (however you manage it)
        // TODO: let token = auth.accessToken

        // Call your Hono/Wispr API and map completion back into the machine
        // TODO: transcriber.transcribe(fileURL: url, token: token) { [weak self] result in
        //   Task { @MainActor in
        //     self?.isTranscribing = false
        //     switch result {
        //       case .success(let text): self?.send(.transcriptionSucceeded(text: text))
        //       case .failure(let err):  self?.send(.transcriptionFailed(error: err.localizedDescription))
        //     }
        //   }
        // }
    }

    private func handlePasteOrCopy(_ text: String) {

        let hasFocus = AXFocusHelper.hasFocusedTextInput()
        let axTrusted = AccessibilityAuth.isTrusted()
        paste.pasteOrCopy(text: text, hasFocus: hasFocus, axTrusted: axTrusted, delay: 0.08) {
            result in
            switch result {
            case .pasted:
                self.toast.show(
                    message: "Pasted • Undo", duration: 2.0, onTap: { self.paste.sendCmdZ() })
            case .copiedNoFocus:
                self.toast.show(
                    message: "No input detected — text copied to clipboard", duration: 2.0)
            case .error(let e):
                self.toast.show(message: "Paste error: \(e)", duration: 2.0)
            }
            self.cacheTranscript(text)
        }
    }

    private func handleCopy(_ text: String) {
        // TODO: paste.copy(text); toast.show("Copied", …); cacheTranscript(text)
    }

    private func handleSendToAgent(_ text: String) {
        // Cache locally, then open/expand agent panel and kick off agent request (later)
        // TODO:
        // let thread = history.upsertThread(title: "Quick Dictations")
        // history.appendMessage(threadId: thread.id, role: .user, content: text, status: .final)
        // agentPanel.show(for: thread)   // if you inject it; or send a notification the agent listens to
    }

    private func cacheTranscript(_ text: String) {
        // TODO: let thread = history.upsertThread(title: "Quick Dictations")
        //       history.appendMessage(threadId: thread.id, role: .user, content: text, status: .final)
    }

    // MARK: - Logging helpers

    private func machineStateDebug() -> String {
        // Helpful when reading logs
        return "\(machine)"
    }

}
