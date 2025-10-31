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
}

enum PillState: Equatable {
    case idle
    case listening(PillMode)  // audio capture running, waveform shown
    case transcribing(PillMode)  // audio capture stopped, uploading/awaiting text transcription
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
    case showToast(String)
    case setVisualStateListening
    case setVisualStateTranscribing
    case setVisualStateIdle
    case setAlwaysOn(Bool)
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

        // - IDLE
        case (.idle, .fnDown):
            let mode: PillMode = ctx.isCmdHeld ? .command : .dictation
            state = .listening(mode)
            effects += [.startAudioCapture, .setVisualStateListening]

        case (.idle, .cmdDown):
            ctx.isCmdHeld = true
            // if the user already holding fn, we will switch on the next fn down otherwise noop
            effects += []

        case (.idle, .cmdUp):
            ctx.isCmdHeld = false

        case (.idle, .doubleTapFn):
            ctx.isAlwaysOn.toggle()
            effects += [
                .setAlwaysOn(ctx.isAlwaysOn),
                .showToast(ctx.isAlwaysOn ? "Always-On enabled" : "Always-On disabled")]

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
            effects += [.setAlwaysOn(false), .stopAudioCapture, .setVisualStateTranscribing, .startTranscription]

            
        case (.listening, .stopButton):
            ctx.isAlwaysOn = false
            state = .transcribing(currentMode)
            effects += [.setAlwaysOn(false), .stopAudioCapture, .setVisualStateTranscribing, .startTranscription]

        case (.listening, .cancelButton):
            ctx.isAlwaysOn = false
            state = .idle
            effects += [.setAlwaysOn(false), .stopAudioCapture, .setVisualStateIdle, .showToast("Cancelled")]

        case (.listening, .cmdDown):
            ctx.isCmdHeld = true
            // If they pressed cmd while already listening in dictating mode then convert it to command mode
            if case .listening(.dictation) = state {
                state = .listening(.command)
            }

        case (.listening, .cmdUp):
            ctx.isCmdHeld = false

        // handle double-tap while already listening
        case (.listening(let mode), .doubleTapFn):
          if ctx.isAlwaysOn == false {
              // Enter Always-On, keep listening
              ctx.isAlwaysOn = true
              effects += [.setAlwaysOn(true), .showToast("Always-On enabled"), .setVisualStateListening]
              // state remains .listening(mode)
          } else {
          // Already Always-On → treat as Done
              ctx.isAlwaysOn = false
              state = .transcribing(mode)
              effects += [.setAlwaysOn(false), .stopAudioCapture, .setVisualStateTranscribing, .startTranscription]
          }
            
        // - TRANSCRIBING
        case (.transcribing, .transcriptionSucceeded(let text)):
            let mode = currentMode
            state = .idle
            effects.append(.setVisualStateIdle)
            switch mode {
            case .dictation:
                // controller will decide  paste vs copy depending on if theres a focused text box
                // We emit both options so the controller can decide but keep state machine pure
                effects += [.pasteText(text)]
            case .command:
                effects += [.sendToAgent(text)]
            }

        case (.transcribing, .transcriptionFailed(let error)):
            state = .idle
            effects += [.setVisualStateIdle, .showToast("Transcription Failed: \(error)")]

        default:
            break

        }

        return effects

    }
}
