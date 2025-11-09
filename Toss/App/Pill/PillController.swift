import Foundation
import SwiftUI

// ORchestrates inputs, feed them to state machine and carries out side effects

@MainActor
final class PillController {
    private var machine = PillStateMachine()

    // orchestration flags
    private var isRecording = false
    private var isTranscribing = false
    private var lastRecordingURL: URL?

    private var activeMeetingId: UUID?
    private var meetingRecorder: MeetingRecorder?  // create this on demand as we dont need it until we start a meeting
    private let meetingRepo = PersistentMeetingRepository()

    // dependencies injected from AppDelegate
    private let audio: AudioRecorder
    private let transcriber: TranscribeAPI
    private let paste: PasteManager
    private let pillPanel: PillPanelController
    private let toast: ToastPanelController
    private let viewModel: PillViewModel
    private let history: PersistentHistoryRepository
    private let auth: AuthManager
    private let agentPanel: AgentPanelController

    init(
        audio: AudioRecorder,
        transcriber: TranscribeAPI,
        paste: PasteManager,
        pillPanel: PillPanelController,
        toast: ToastPanelController,
        viewModel: PillViewModel,
        history: PersistentHistoryRepository,
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
            case .setVisualStateHovered:
                viewModel.hovered()
                pillPanel.setState(.hovered)

            case .openMeetingView(let meetingId):
                handleOpenMeetingView(meetingId)

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

            case .startMeetingRecording(let meetingId):
                handleStartMeetingRecording(meetingId)

            case .stopMeetingRecording:
                handleStopMeetingRecording()

            case .uploadMeetingChunk(let meetingId, let url, let index):
                handleUploadMeetingChunk(meetingId: meetingId, url: url, index: index)

            case .setVisualStateMeetingRecording(let meetingId):
                viewModel.meetingRecording(meetingId)
                pillPanel.setState(.meetingRecording(meetingId))

            case .scheduleMeetingDetectionTimeout(let timeout):
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    self.send(.meetingDetectionExpired)
                }
            case .showToast(
                let icon, let title, let subtitle, let primary, let secondary, let duration,
                let offsetAboveAnchor):

                let iconImage = icon != nil ? Image(systemName: icon!) : nil

                let primaryAction =
                    primary != nil
                    ? ToastAction(
                        title: primary!.title, eventToSend: primary!.eventToSend,
                        variant: primary!.variant) : nil
                let secondaryAction =
                    secondary != nil
                    ? ToastAction(
                        title: secondary!.title, eventToSend: secondary!.eventToSend,
                        variant: secondary!.variant) : nil

                toast.show(
                    icon: iconImage,
                    title: title,
                    subtitle: subtitle,
                    primary: primaryAction,
                    secondary: secondaryAction,
                    duration: duration ?? 3.0,
                    offsetAboveAnchor: offsetAboveAnchor ?? 30
                )

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
            toast.show(title: "No recording found", duration: 1.8)
            return
        }
        isTranscribing = true

        print("⏱️ UPLOAD START: +\(Date().timeIntervalSince(stopTime!))s")

        let token = auth.accessToken
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
                        self.toast.show(title: displayMessage, duration: 3.0)

                        // Optionally: Open app to sign in screen
                        // NotificationCenter.default.post(name: .showSignInRequired, object: nil)
                    } else {
                        // Other errors
                        self.toast.show(
                            title: "Transcription failed: \(displayMessage)", duration: 3.0)
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
                // Do nothing, we might want to if they are a new user show something here but leave it for now
                NSLog("[PillController] Pasted text: \(text)")
            case .copiedNoFocus:
                self.toast.show(
                    icon: Image(systemName: "doc.on.clipboard"),
                    title: "No input detected",
                    subtitle: "Text copied to clipboard. Open Toss to view your dictation history.",
                    duration: 3.5
                )
            case .error(let e):
                self.toast.show(title: "Paste error: \(e)", duration: 2.0)
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
        let thread = History.shared.upsertThread(title: "Quick Dictations")
        _ = History.shared.appendMessage(
            threadId: thread.id, role: .user, content: text, status: .final)
    }

    // MARK: - Meeting recording handlers

    private func handleStartMeetingRecording(_ meetingId: UUID) {
        guard meetingRecorder == nil else { return }

        activeMeetingId = meetingId

        let meeting = meetingRepo.createMeeting(
            id: meetingId,
            title: "Meeting \(Date().formatted(date: .abbreviated, time: .shortened))"
        )

        // create the meeting recorder on demand
        let recorder = MeetingRecorder()
        recorder.onLevelUpdate = { [weak self] rms in self?.viewModel.updateLevelRMS(rms) }

        recorder.onChunkReady = { [weak self] url, index in
            guard let self = self, self.activeMeetingId != nil else { return }
            // Now we know which meeting this chunk belongs to!
            self.send(.meetingChunkReady(url, index))
        }
        recorder.onError = { error in
            NSLog("[PillController] Meeting recorder error: \(error)")
        }

        recorder.start()
        meetingRecorder = recorder

        SoundFeedback.shared.playStart()
        NSLog("[PillController] Meeting recording started for meeting \(meeting.id)")
    }

    private func handleStopMeetingRecording() {
        guard let meetingRecorder = meetingRecorder, let meetingId = activeMeetingId else { return }

        let finalChunkIndex = meetingRecorder.chunkIndex

        // Stop recorder and upload the final chunk
        if let finalChunkURL = meetingRecorder.stop() {
            handleUploadMeetingChunk(
                meetingId: meetingId, url: finalChunkURL, index: finalChunkIndex)
        }

        self.meetingRecorder = nil  // reset the recorder

        meetingRepo.endMeeting(id: meetingId)

        activeMeetingId = nil

        SoundFeedback.shared.playStop()
        NSLog("[PillController] Meeting recording stopped for meeting \(meetingId)")
    }

    private func handleUploadMeetingChunk(meetingId: UUID, url: URL, index: Int) {
        // // Upload the meeting chunk to the server
        guard let token = auth.accessToken else {
            NSLog("[PillController] No auth token for chunk upload")
            return
        }

        NSLog("[PillController] Uploading chunk #\(index)...")

        transcriber.transcribeMeetingChunk(
            meetingId: meetingId,
            chunkIndex: index,
            fileURL: url,
            token: token
        ) { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }

                switch result {
                case .success(let text):
                    // Save chunk transcript to repository
                    _ = self.meetingRepo.appendChunk(
                        meetingId: meetingId,
                        index: index,
                        transcript: text
                    )
                    NSLog("[PillController] Chunk #\(index) transcribed: \(text.prefix(40))...")

                case .failure(let error):
                    NSLog("[PillController] Chunk upload error: \(error)")
                }

                // Clean up temp file
                try? FileManager.default.removeItem(at: url)
            }
        }

    }

    private func handleMeetingChunkReady(meetingId: UUID, url: URL, index: Int) {
        // // Handle the meeting chunk ready event
        // send(.meetingChunkReady(meetingId, url, index))
    }

    private func handleOpenMeetingView(_ meetingId: UUID) {
        NSLog("[PillController] Opening meeting view for \(meetingId)")

        // Activate the app
        NSApp.activate(ignoringOtherApps: true)

        // Post notification to navigate to meeting
        NotificationCenter.default.post(
            name: NSNotification.Name("OpenMeetingView"),
            object: nil,
            userInfo: ["meetingId": meetingId]
        )
    }

    // MARK: - Logging helpers

    private func machineStateDebug() -> String {
        // Helpful when reading logs
        return "\(machine)"
    }

}
