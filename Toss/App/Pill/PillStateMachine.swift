import Foundation
import SwiftUI

// Were going to use this to manage the state that the pill should be in based on the users actions and the shortcuts they are holding

// the user will be able to hold fn in order to start the listening mode, and release to stop capturing audio and start transcribing that audio that was captured
// Additionally they will be able to double click the fn key in order to toggle on the always on mode which is has the same functionality as the hold to talk mode
// but it will not stop capturing audio until the clicks clicks the fn key or hits one of 2 buttons on the pill that are shown in this mode

// finally if the user holds command + fn then they will enter command mode, initially this looks the same as the hold to talk mode, but instead of pasting the text
// into the focused text field, it will start a chat with the agent and paste their spoken text as the first message instructing the agent

// the purpose of the current audio capture
enum PillMode: Equatable {
    case dictation  // paste to focused text field flow
    case command  // start a chat with the agent in order to instruct it to perform an action
    case meeting  // recording a longer meeting with 2 streams of audio, one for the user and one for the system audio
}

enum PillState: Equatable {
    case idle
    case hovered
    case meetingDetected  // Were now going to have the pill transform rather than show a toast
    case listening(PillMode)  // audio capture running, waveform shown
    case transcribing(PillMode)  // audio capture stopped, uploading/awaiting text transcription
    case meetingRecording(UUID, isPaused: Bool)
}

enum PillEvent: Equatable {
    // key and UI inputs
    case fnDown
    case fnUp
    case cmdDown
    case cmdUp
    case doubleTapFn
    case stopButton
    case cancelButton
    case escapePressed

    // meetings
    case startMeetingRecording
    case stopMeetingRecording
    case pauseMeetingRecording
    case resumeMeetingRecording
    case meetingChunkReady(MeetingSpeaker, URL, Int, Date)  // audio chunk ready for transcription

    // meeting detection events
    case meetingDetected
    case meetingDetectionExpired  // auto dismiss meeting detected
    case dismissMeetingDetection

    // hover events
    case pillHoverEnter
    case pillHoverExit
    case quickActionRecordMeeting  // clicking a button shown in the hover state to start a meeting recording
    case quickActionDictation  // clicking a button shown in the hover state to start a dictation
    // TODO we might need a button to start a command mode session but we havent added command mode yet so leave it for now
    case pillClicked  // clicking during meeting state will open app

    // async results
    case transcriptionSucceeded(text: String)
    case transcriptionFailed(text: String)
}

// Things the machine asks the outside world to do
enum PillEffect: Equatable {
    // audio lifecycle
    case startAudioCapture
    case stopAudioCapture

    // networking
    case startTranscription  // using the last recorded audio buffer

    // routing/side effects on success
    case pasteText(String)
    case copyToClipboard(String)
    case sendToAgent(String)

    // UI
    case showToast(
        _: String?,
        _: String,
        _: String?,
        _: ToastAction?,
        _: ToastAction?,
        _: TimeInterval?,
        _: CGFloat?
    )
    case setVisualStateListening
    case setVisualStateTranscribing
    case setVisualStateIdle
    case setVisualStateHovered
    case setVisualStateMeetingDetected
    case setVisualStateMeetingRecording(UUID, isPaused: Bool)
    case setAlwaysOn(Bool)

    // meetings
    case scheduleMeetingDetectionTimeout(TimeInterval)
    case startMeetingRecording(UUID)
    case stopMeetingRecording
    case pauseMeetingRecording
    case resumeMeetingRecording
    case uploadMeetingChunk(UUID, MeetingSpeaker, URL, Int, Date)
    case openMeetingView(UUID)  // when the pill body is clicked during meeting state will open the meeting view for that meeting

}

extension PillEffect {
    static func showToast(
        icon: String? = nil,
        title: String,
        subtitle: String? = nil,
        primary: ToastAction? = nil,
        secondary: ToastAction? = nil,
        duration: TimeInterval? = nil,
        offsetAboveAnchor: CGFloat? = nil
    ) -> PillEffect {
        return .showToast(
            icon,
            title,
            subtitle,
            primary,
            secondary,
            duration,
            offsetAboveAnchor
        )
    }
}

struct ToastAction: Equatable {
    let title: String
    let eventToSend: PillEvent
    let variant: ToastActionVariant

    init(title: String, eventToSend: PillEvent, variant: ToastActionVariant) {
        self.title = title
        self.eventToSend = eventToSend
        self.variant = variant
    }
}

enum ToastActionVariant: Equatable {
    case primary
    case secondary
    case destructive
}

struct PillContext: Equatable {
    var isAlwaysOn = false
    var isCmdHeld = false
}

struct PillStateMachine {
    private(set) var state: PillState = .idle
    private(set) var ctx = PillContext()

    // Convenience to read current mode if in listening/transcribing
    var currentMode: PillMode {
        switch state {
        case .listening(let m), .transcribing(let m): return m
        default: return .dictation
        }
    }

    // Apply an event and get the side effects the controller needs to perform
    mutating func handle(_ event: PillEvent) -> [PillEffect] {
        var effects: [PillEffect] = []

        switch (state, event) {

        case (.idle, .pillHoverEnter):
            state = .hovered
            effects += [.setVisualStateHovered]

        case (.hovered, .pillHoverExit):
            state = .idle
            effects += [.setVisualStateIdle]

        case (.hovered, .quickActionRecordMeeting):
            let meetingId = UUID()
            state = .meetingRecording(meetingId, isPaused: false)
            effects += [
                .startMeetingRecording(meetingId),
                .setVisualStateMeetingRecording(meetingId, isPaused: false),
            ]

        case (.hovered, .quickActionDictation):
            ctx.isAlwaysOn = true
            state = .listening(.dictation)
            effects += [
                .startAudioCapture,
                .setVisualStateListening,
                .setAlwaysOn(true),
            ]

        case (.idle, .meetingDetected), (.hovered, .meetingDetected):
            state = .meetingDetected
            effects += [
                .setVisualStateMeetingDetected,
                .scheduleMeetingDetectionTimeout(10),
            ]

        // - IDLE
        case (.idle, .fnDown):
            let mode: PillMode = ctx.isCmdHeld ? .command : .dictation
            ctx.isCmdHeld = false  // dont let stale cmddown leak from cmd + v from paste from prev session
            state = .listening(mode)
            effects += [.startAudioCapture, .setVisualStateListening]

        case (.idle, .cmdDown):
            ctx.isCmdHeld = true
        // Noop until fn down starts a session

        case (.idle, .cmdUp), (.meetingDetected, .cmdUp),
            (.transcribing, .cmdUp),
            (.meetingRecording, .cmdUp):
            ctx.isCmdHeld = false

        case (.idle, .doubleTapFn):
            ctx.isAlwaysOn.toggle()
            effects += [
                .setAlwaysOn(ctx.isAlwaysOn),
                .showToast(
                    title: ctx.isAlwaysOn ? "Always-On enabled" : "Always-On disabled"),
            ]

        case (.meetingDetected, .meetingDetectionExpired),
            (.meetingDetected, .escapePressed),
            (.meetingDetected, .dismissMeetingDetection):
            state = .idle
            effects += [.setVisualStateIdle]

        case (.meetingDetected, .fnDown),
            (.meetingDetected, .quickActionRecordMeeting),
            (.meetingDetected, .pillClicked):
            let meetingId = UUID()
            state = .meetingRecording(meetingId, isPaused: false)
            effects += [
                .startMeetingRecording(meetingId),
                .setVisualStateMeetingRecording(meetingId, isPaused: false),
            ]

        case (.idle, .startMeetingRecording):
            let meetingId = UUID()
            state = .meetingRecording(meetingId, isPaused: false)
            effects += [
                .startMeetingRecording(meetingId),
                .setVisualStateMeetingRecording(meetingId, isPaused: false),
            ]

        // - LISTENING
        case (.listening(let mode), .fnUp):
            if ctx.isAlwaysOn {
                // stay listening even if the fn is released on always on mode
                break
            }
            // end capture and transcribe
            state = .transcribing(mode)
            effects += [.stopAudioCapture, .setVisualStateTranscribing, .startTranscription]

        // When were in always all mode hitting fn again will end the dictation
        case (.listening, .fnDown) where ctx.isAlwaysOn:
            ctx.isAlwaysOn = false
            state = .transcribing(currentMode)
            effects += [
                .setAlwaysOn(false), .stopAudioCapture, .setVisualStateTranscribing,
                .startTranscription,
            ]

        case (.listening, .stopButton):
            ctx.isAlwaysOn = false
            state = .transcribing(currentMode)
            effects += [
                .setAlwaysOn(false), .stopAudioCapture, .setVisualStateTranscribing,
                .startTranscription,
            ]

        case (.listening, .escapePressed):
            ctx.isAlwaysOn = false
            state = .idle
            ctx.isCmdHeld = false
            effects += [
                .setAlwaysOn(false), .stopAudioCapture, .setVisualStateIdle,
                .showToast(title: "Cancelled"),
            ]

        case (.listening, .cancelButton):
            ctx.isAlwaysOn = false
            state = .idle
            effects += [
                .setAlwaysOn(false), .stopAudioCapture, .setVisualStateIdle,
                .showToast(title: "Cancelled"),
            ]

        case (.listening(let mode), .cmdDown):
            guard !ctx.isAlwaysOn else { break }  // ignore cmd in always as its only for dictation
            // Cmd press toggles to command mode and stays there for the duration of the session
            ctx.isCmdHeld = true
            if mode != .command {
                state = .listening(.command)
                effects += [.setVisualStateListening]
            }

        case (.listening(let mode), .cmdUp):
            // Do nothing as command mode is sticky
            break

        // handle double-tap while already listening
        case (.listening(let mode), .doubleTapFn):
            if ctx.isAlwaysOn == false {
                // Enter Always-On, keep listening
                ctx.isAlwaysOn = true
                effects += [
                    .setAlwaysOn(true), .showToast(title: "Always-On enabled"),
                    .setVisualStateListening,
                ]
                // state remains .listening(mode)
            } else {
                // Already Always-On → treat as Done
                ctx.isAlwaysOn = false
                state = .transcribing(mode)
                effects += [
                    .setAlwaysOn(false), .stopAudioCapture, .setVisualStateTranscribing,
                    .startTranscription,
                ]
            }

        // - TRANSCRIBING
        case (.transcribing, .transcriptionSucceeded(let text)):
            let mode = currentMode
            state = .idle
            ctx.isCmdHeld = false
            effects.append(.setVisualStateIdle)
            switch mode {
            case .dictation:
                // controller will decide  paste vs copy depending on if theres a focused text box
                // We emit both options so the controller can decide but keep state machine pure
                effects += [.pasteText(text)]
            case .command:
                effects += [.sendToAgent(text)]
            case .meeting:
                // Do nothing since we handle meeting recording in a different state
                effects += []
            }

        case (.transcribing, .transcriptionFailed(let error)):
            state = .idle
            ctx.isCmdHeld = false
            effects += [.setVisualStateIdle, .showToast(title: "Transcription Failed: \(error)")]

        case (.meetingRecording(let meetingId, let isPaused), .pauseMeetingRecording)
        where !isPaused:
            state = .meetingRecording(meetingId, isPaused: true)
            effects += [
                .pauseMeetingRecording,
                .setVisualStateMeetingRecording(meetingId, isPaused: true),
            ]

        case (.meetingRecording(let meetingId, let isPaused), .resumeMeetingRecording)
        where isPaused:
            state = .meetingRecording(meetingId, isPaused: false)
            effects += [
                .resumeMeetingRecording,
                .setVisualStateMeetingRecording(meetingId, isPaused: false),
            ]

        case (.meetingRecording(let meetingId, _), .stopMeetingRecording):
            state = .idle
            effects += [
                .stopMeetingRecording,
                .setVisualStateIdle,
                .showToast(title: "Meeting recording stopped"),
                .openMeetingView(meetingId),
            ]

        case (.meetingRecording(let meetingId, _), .pillClicked):
            effects += [.openMeetingView(meetingId)]

        case (
            .meetingRecording(let meetingId, _),
            .meetingChunkReady(let speaker, let url, let index, let startedAt)
        ):
            effects += [.uploadMeetingChunk(meetingId, speaker, url, index, startedAt)]

        // - MEETING RECORDING → IDLE (escape/cancel)
        case (.meetingRecording, .escapePressed),
            (.meetingRecording, .cancelButton):
            state = .idle
            effects += [
                .stopMeetingRecording,
                .setVisualStateIdle,
                .showToast(title: "Meeting cancelled"),
            ]

        default:
            break

        }

        return effects

    }
}
