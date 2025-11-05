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
    private let history: InMemoryHistoryRepository
    private let auth: AuthManager
    private let agentPanel: AgentPanelController

    init(
        audio: AudioRecorder,
        transcriber: TranscribeAPI,
        paste: PasteManager,
        pillPanel: PillPanelController,
        toast: ToastPanelController,
        viewModel: PillViewModel,
        history: InMemoryHistoryRepository,
        auth: AuthManager,
        agentPanel: AgentPanelController
    ) {
        self.audio = audio
        self.transcriber = transcriber
        self.paste = paste
        self.pillPanel = pillPanel
        self.toast = toast
        self.viewModel = viewModel
        self.history = history
        self.auth = auth
        self.agentPanel = agentPanel
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

            case .pasteText(let text):
                handlePasteOrCopy(text)

            case .copyToClipboard(let text):
                handleCopy(text)

            case .sendToAgent(let text):
                handleSendToAgent(text)

            case .setVisualStateListening:
                viewModel.listening(machine.currentMode)
                pillPanel.setState(.listening(machine.currentMode))

            case .setVisualStateTranscribing:
                viewModel.transcribing(machine.currentMode)
                pillPanel.setState(.transcribing(machine.currentMode))

            case .setVisualStateIdle:
                viewModel.idle()
                pillPanel.setState(.idle)

            case .setAlwaysOn(let on):
                viewModel.isAlwaysOn = on

            case .showToast(let message):
                toast.show(message: message, duration: 1.8)

            }
        }

    }

    // MARK: - Individual effect handlers (fill these next)

    private func handleStartAudio() {
        // Guard against re-entry
        guard !isRecording else { return }

        SoundFeedback.shared.playStart()

        // Start audio engine; provide level callback to update the waveform
        audio.start()
        audio.onLevelUpdate = { [weak self] rms in self?.viewModel.updateLevelRMS(rms) }

        isRecording = true

    }

    private var stopTime: Date?

    private func handleStopAudio() {
        guard isRecording else { return }

        SoundFeedback.shared.playStop()

        stopTime = Date()
        print("Stop time: \(stopTime!.timeIntervalSince1970)")

        // Stop audio and keep the file URL for transcription
        lastRecordingURL = audio.stop()

        isRecording = false
    }

    private func handleStartTranscription() {
        guard !isTranscribing else { return }
        guard let url = self.lastRecordingURL else {
            toast.show(message: "No recording found", duration: 1.8)
            return
        }
        isTranscribing = true

        print("⏱️ UPLOAD START: +\(Date().timeIntervalSince(stopTime!))s")

        // Get auth token (however you manage it)
        let token = auth.accessToken

        // Call your Hono/Wispr API and map completion back into the machine
        transcriber.transcribe(fileURL: url, token: token) { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }

                self.isTranscribing = false

                switch result {
                case .success(let text):
                    self.send(.transcriptionSucceeded(text: text))

                case .failure(let error):
                    let nsError = error as NSError
                    var displayMessage = error.localizedDescription

                    // Handle specific error cases
                    if nsError.code == 401 {
                        // Unauthorized - show sign in prompt
                        displayMessage = "Please sign in to use transcription"
                        self.toast.show(message: displayMessage, duration: 3.0)

                        // Optionally: Open app to sign in screen
                        // NotificationCenter.default.post(name: .showSignInRequired, object: nil)
                    } else {
                        // Other errors
                        self.toast.show(
                            message: "Transcription failed: \(displayMessage)", duration: 3.0)
                    }

                    self.send(.transcriptionFailed(text: displayMessage))
                }
            }
        }
    }

    private func handlePasteOrCopy(_ text: String) {

        // Decide based on AX focus and trust; then use your PasteManager

        let hasFocus = AXFocusHelper.hasFocusedTextInput()
        let axTrusted = AccessibilityAuth.ensureAccess(prompt: true)
        paste.pasteOrCopy(text: text, hasFocus: hasFocus, axTrusted: axTrusted, delay: 0.1) {
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
            // Cache to local history regardless
            self.cacheTranscript(text)
        }
    }

    private func handleCopy(_ text: String) {
        //        paste.copy(text); toast.show("Copied", …); cacheTranscript(text)
    }

    private func handleSendToAgent(_ text: String) {
        log("Sending to agent: \(text)")
        // TODO: Cache the transcript locally
        agentPanel.show(with: text)
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
