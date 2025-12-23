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
    private var detectedDictationMode: DictationMode = .plain

    private var activeMeetingId: UUID?
    private var meetingRecorder: MeetingRecorder?  // create this on demand as we dont need it until we start a meeting
    private var systemAudioMeetingRecorder: SystemAudioRecorder?

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
    private let meetingRepository: PersistentMeetingRepository
    private let meetingDetector: MeetingDetector

    init(
        audio: AudioRecorder,
        transcriber: TranscribeAPI,
        paste: PasteManager,
        pillPanel: PillPanelController,
        toast: ToastPanelController,
        viewModel: PillViewModel,
        history: PersistentHistoryRepository,
        auth: AuthManager,
        agentPanel: AgentPanelController,
        meetingRepository: PersistentMeetingRepository,
        meetingDetector: MeetingDetector
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
        self.meetingRepository = meetingRepository
        self.meetingDetector = meetingDetector
    }

    private func log(_ s: String) { print("[PillController] \(s)") }

    // Call this once from AppDelegate to wire keyboard  + buttons
    func start() {
        // TODO hook up hotkey callbacks and pill buttons to send()

    }

    /// Public ingress: feed events into the machine, then perform returned effects.
    func send(_ event: PillEvent) {
        log("EVENT: \(event)")

        // Intercept events that require auth before state machine processes them
        switch event {
        case .fnDown(_), .doubleTapFn, .quickActionDictation, .quickActionRecordMeeting,
            .startMeetingRecording:
            guard auth.isAuthenticated else {
                toast.show(
                    icon: Image(systemName: "person.crop.circle.badge.exclamationmark"),
                    title: "Please sign in",
                    subtitle: "Sign in to use dictation",
                    duration: 3.0
                )
                // Reset visual state in case we're in a weird state
                pillPanel.setState(.idle)
                return
            }
        default:
            break
        }

        let effects = machine.handle(event)
        log("STATE: \(machineStateDebug()) EFFECTS: \(effects)")
        perform(effects)
    }

    // Effect executor
    private func perform(_ effects: [PillEffect]) {

        for effect in effects {
            switch effect {
            case .setVisualStateHovered:
                pillPanel.setState(.hovered)

            case .setVisualStateMeetingDetected:
                pillPanel.setState(.meetingDetected)

            case .openMeetingView(let meetingId):
                handleOpenMeetingView(meetingId)

            case .startAudioCapture:
                handleStartAudio()

            case .stopAudioCapture:
                handleStopAudio()

            case .startTranscription:
                handleStartTranscription()

            case .pasteText(let text, let rawText):
                handlePasteOrCopy(text, rawText: rawText)

            case .copyToClipboard(let text):
                handleCopy(text)

            case .sendToAgent(let text):
                handleSendToAgent(text)

            case .setVisualStateListening:
                pillPanel.setState(.listening(machine.currentMode))

            case .setVisualStateTranscribing:
                pillPanel.setState(.transcribing(machine.currentMode))

            case .setVisualStateIdle:
                pillPanel.setState(.idle)

            case .setVisualStateAgentSessionActive:
                pillPanel.setState(.agentSessionActive)

            case .restoreAgentPanel:
                agentPanel.restore()

            case .showAgentPanel:
                handleShowAgentPanel()

            case .setAlwaysOn(let on):
                viewModel.isAlwaysOn = on

            case .startMeetingRecording(let meetingId, let startedFromDetection):
                handleStartMeetingRecording(meetingId, startedFromDetection: startedFromDetection)

            case .stopMeetingRecording:
                handleStopMeetingRecording()

            case .uploadMeetingChunk(let meetingId, let speaker, let url, let index, let startedAt):
                handleUploadMeetingChunk(
                    meetingId: meetingId, speaker: speaker, url: url, index: index,
                    startedAt: startedAt)

            case .setVisualStateMeetingRecording(let meetingId, let isPaused):
                viewModel.meetingRecording(meetingId, isPaused: isPaused)
                pillPanel.setState(.meetingRecording(meetingId, isPaused: isPaused))

            case .setVisualStateUpcomingMeeting(let meeting):
                viewModel.upcomingMeeting(meeting)
                pillPanel.setState(.upcomingMeeting(meeting))

            case .scheduleUpcomingMeetingTimeout(let timeout):
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
                    self.send(.meetingDetectionExpired)
                }

            case .openURL(let url):
                NSWorkspace.shared.open(url)

            case .pauseMeetingRecording:
                handlePauseMeetingRecording()

            case .resumeMeetingRecording:
                handleResumeMeetingRecording()

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

        // Detect context BEFORE starting recording (while user's cursor is in the target field)
        detectedDictationMode = DictationContextDetector.shared.detectContext()
        NSLog("[PillController] Detected dictation mode: \(detectedDictationMode.rawValue)")

        // Start audio engine; provide level callback to update the waveform
        audio.start()
        audio.onLevelUpdate = { [weak self] rms in self?.viewModel.updateLevelRMS(rms) }

        audio.onError = { error in
            // On audio errors show a toast and set the pill back to idle
            self.toast.show(title: "Audio error: \(error)", duration: 3.0)
            self.pillPanel.setState(.idle)
        }

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
        guard let wavURL = self.lastRecordingURL else {
            toast.show(title: "No recording found", duration: 1.8)
            return
        }
        isTranscribing = true

        print("⏱️ UPLOAD START: +\(Date().timeIntervalSince(stopTime!))s")

        Task.detached {
            do {
                let compressedURL = try await AudioCompressor.compressToM4A(sourceURL: wavURL)
                await self.startUpload(with: compressedURL)
            } catch {
                NSLog("[PillController] Compression failed: \(error)")
                await self.startUpload(with: wavURL)  // fallback to WAV
            }
        }

    }

    @MainActor
    private func startUpload(with url: URL) {
        let mode = self.detectedDictationMode
        transcriber.transcribe(fileURL: url, mode: mode) { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }

                self.isTranscribing = false

                switch result {
                case .success(let response):
                    self.send(
                        .transcriptionSucceeded(text: response.text, rawText: response.rawText))

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

    private func handlePasteOrCopy(_ text: String, rawText: String? = nil) {

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
            self.cacheTranscript(text, rawText: rawText)
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

    private func handleShowAgentPanel() {
        log("Showing empty agent panel for text chat")
        agentPanel.showEmpty()
    }

    private func cacheTranscript(_ text: String, rawText: String? = nil) {
        let thread = History.shared.upsertThread(title: "Quick Dictations")
        _ = History.shared.appendMessage(
            threadId: thread.id,
            role: .user,
            content: text,
            rawTranscript: rawText,
            status: .final
        )
    }

    // MARK: - Meeting recording handlers

    private func handleStartMeetingRecording(_ meetingId: UUID, startedFromDetection: Bool = false)
    {

        guard ScreenRecordingAuth.status() else {
            toast.show(
                icon: Image(systemName: "speaker.slash"),
                title: "Enable Screen Recording",
                subtitle: "Allow in System Settings to capture remote audio.",
                duration: 4
            )
            return
        }

        guard meetingRecorder == nil else { return }

        activeMeetingId = meetingId

        _ = meetingRepository.createMeeting(
            id: meetingId,
            title: "Untitled Meeting",
            // TODO: this could be calendar if the user is joining a meeting from the calendar or the pill state
            source: .adhoc
        )

        // create the meeting recorder on demand
        let recorder = MeetingRecorder()
        recorder.onLevelUpdate = { [weak self] rms in self?.viewModel.updateLevelRMS(rms) }
        recorder.onChunkReady = { [weak self] url, index, startedAt in
            guard let self, self.activeMeetingId != nil else { return }
            self.send(.meetingChunkReady(.user, url, index, startedAt))
        }
        recorder.onError = { error in
            NSLog("[PillController] Meeting recorder error: \(error)")
        }

        recorder.start()
        meetingRecorder = recorder

        let systemRecorder = SystemAudioRecorder()
        systemRecorder.onRemoteLevel = { [weak recorder] level in
            recorder?.updateRemoteLevel(level)
        }

        systemRecorder.onRemoteAudioFrame = { [weak meetingRecorder] buffer in
            meetingRecorder?.ingestRemoteBuffer(buffer)
        }

        systemRecorder.onChunkReady = { [weak self] url, index, startedAt in
            guard let self, self.activeMeetingId != nil else { return }
            self.send(.meetingChunkReady(.remote, url, index, startedAt))
        }
        Task { [weak self] in
            guard let self else { return }
            do {
                try await systemRecorder.start()
                await MainActor.run {
                    self.systemAudioMeetingRecorder = systemRecorder
                }
            } catch {
                NSLog("[PillController] System audio recorder error: \(error)")
                await MainActor.run {
                    self.toast.show(
                        icon: Image(systemName: "speaker.slash"),
                        title: "System audio unavailable",
                        subtitle: error.localizedDescription,
                        duration: 4
                    )
                }
            }
        }

        SoundFeedback.shared.playStart()
        meetingDetector.setRecordingActive(true, startedFromDetection: startedFromDetection)
        NSLog(
            "[PillController] Meeting recording started for meeting (startedFromDetection: \(startedFromDetection))"
        )

        // Bring app to foreground and position for note-taking
        positionWindowForMeeting()
    }

    private func handleStopMeetingRecording() {
        guard let meetingId = activeMeetingId else { return }

        if let chunk = meetingRecorder?.stop() {
            handleUploadMeetingChunk(
                meetingId: meetingId,
                speaker: .user,
                url: chunk.url,
                index: chunk.index,
                startedAt: chunk.startedAt
            )
        }
        if let chunk = systemAudioMeetingRecorder?.stop() {
            handleUploadMeetingChunk(
                meetingId: meetingId,
                speaker: .remote,
                url: chunk.url,
                index: chunk.index,
                startedAt: chunk.startedAt
            )
        }

        meetingRecorder = nil  // reset the recorder
        systemAudioMeetingRecorder = nil  // reset the system audio recorder
        meetingRepository.endMeeting(id: meetingId)

        let fullTranscript = meetingRepository.getFullTranscript(meetingId: meetingId)

        // Auto‑title
        MeetingsApi.shared.generateTitle(
            for: meetingId,
            transcript: fullTranscript
        ) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let title):
                    self?.meetingRepository.updateMeetingTitle(meetingId: meetingId, title: title)
                case .failure(let error):
                    NSLog("[PillController] Auto-title failed: \(error)")
                }
            }
        }

        // Auto-summary
        MeetingsApi.shared.generateOverview(
            for: meetingId,
            transcript: fullTranscript
        ) { [weak self] result in
            Task { @MainActor in
                switch result {
                case .success(let summary):
                    self?.meetingRepository.updateMeetingNotes(meetingId: meetingId, notes: summary)
                case .failure(let error):
                    NSLog("[PillController] Auto-summary failed: \(error)")
                }

                // Sync meeting to server after summary is saved (or failed)
                await MeetingSyncManager.shared.syncMeeting(meetingId)
            }
        }

        activeMeetingId = nil
        SoundFeedback.shared.playStop()
        NSLog("[PillController] Meeting recording stopped for meeting \(meetingId)")
        meetingDetector.setRecordingActive(false)
    }

    private func handleUploadMeetingChunk(
        meetingId: UUID,
        speaker: MeetingSpeaker,
        url: URL,
        index: Int,
        startedAt: Date
    ) {
        // // Upload the meeting chunk to the server
        NSLog("[PillController] Uploading chunk #\(index)...")

        transcriber.transcribeMeetingChunk(
            meetingId: meetingId,
            chunkIndex: index,
            speaker: speaker,
            fileURL: url
        ) { [weak self] result in
            Task { @MainActor in
                guard let self = self else { return }

                switch result {
                case .success(let transcriptionResponse):
                    // Save chunk transcript to repository
                    let savedChunk = self.meetingRepository.appendChunk(
                        meetingId: meetingId,
                        index: index,
                        transcript: transcriptionResponse.text,
                        startedAt: startedAt,
                        speaker: speaker
                    )

                    if savedChunk != nil {
                        // chunk was kept
                        NSLog(
                            "[PillController] Chunk #\(index) kept: \(transcriptionResponse.text.prefix(40))..."
                        )
                    } else {
                        // chunk was dropped as duplicate
                        NSLog(
                            "[PillController] Chunk #\(index) dropped as duplicate: \(transcriptionResponse.text.prefix(40))..."
                        )
                    }

                case .failure(let error):
                    NSLog("[PillController] Chunk upload error: \(error)")
                }

                // Clean up temp file
                try? FileManager.default.removeItem(at: url)
            }
        }

    }

    private func handlePauseMeetingRecording() {
        meetingRecorder?.pause()
    }

    private func handleResumeMeetingRecording() {
        meetingRecorder?.resume()
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

    // Add this public method
    func endActiveRecordingIfNeeded() {
        if let meetingId = activeMeetingId {
            NSLog("[PillController] Force-ending active meeting on app termination: \(meetingId)")
            handleStopMeetingRecording()
        }
    }

    private func positionWindowForMeeting() {
        // Activate the app
        NSApp.activate(ignoringOtherApps: true)

        // Find the main Toss window
        guard
            let window = NSApp.windows.first(where: {
                $0.title == "Toss" || $0.identifier?.rawValue == "main"
            })
        else {
            // If no window exists, just activate - SwiftUI will create one
            return
        }

        // Get the screen
        guard let screen = window.screen ?? NSScreen.main else { return }
        let visibleFrame = screen.visibleFrame

        // Position: right side of screen, 500px wide, full height
        let width: CGFloat = 500
        let height = visibleFrame.height
        let x = visibleFrame.maxX - width
        let y = visibleFrame.minY

        let newFrame = NSRect(x: x, y: y, width: width, height: height)

        // Animate the window to new position
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.3
            ctx.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            window.animator().setFrame(newFrame, display: true)
        }

        window.makeKeyAndOrderFront(nil)

        // Navigate to the meeting view
        NotificationCenter.default.post(
            name: NSNotification.Name("OpenMeetingView"),
            object: nil,
            userInfo: ["meetingId": activeMeetingId as Any]
        )

        NSLog("[PillController] Positioned window for meeting note-taking")
    }

    private func machineStateDebug() -> String {
        // Helpful when reading logs
        return "\(machine)"
    }
}
