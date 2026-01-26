import Cocoa

final class HotkeyEventTap {
    var onFnDown: ((_ isCmdHeld: Bool) -> Void)?
    var onFnUp: (() -> Void)?

    var onCmdDown: (() -> Void)?
    var onCmdUp: (() -> Void)?

    var onDoubleTapFn: (() -> Void)?
    var onDoubleTapOption: (() -> Void)?
    var onEscapePressed: (() -> Void)?

    private var monitors: [Any] = []
    private var isHoldingFn: Bool = false
    private var isHoldingCmd: Bool = false

    private var lastFnDownAt: Date?
    private var lastOptionDownAt: Date?
    private let doubleTapWindow: TimeInterval = 0.5
    private var cooldownUntil: Date?
    private var optionCooldownUntil: Date?
    private let minFnHold: TimeInterval = 0.5
    private var pendingFnUpTimer: Timer?

    private var swallowFnDownAfterDoubleTap = false
    private var swallowNextFnUp = false
    private var swallowFnUpAfterEscape = false

    // Our cmd v emissions for pasting dictations are causing us to enter command mode, so we need to ignore cmd events until the paste is complete
    private var ignoreCmdEventsUntil: Date? = nil

    private(set) var isStarted: Bool = false

    private var previousFlags: NSEvent.ModifierFlags = []

    // Track whether we started an Fn session (for preference-aware up handling)
    private var fnSessionStarted: Bool = false

    func start() {
        guard !isStarted else { return }
        isStarted = true

        // TODO: In a future pass, compute edges from previousFlags instead of isHolding*
        // Primary: Fn key via modifier flags changed
        if let flagsMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .flagsChanged,
            handler: { [weak self] event in
                guard let self = self else { return }

                let flags = event.modifierFlags
                let now = Date()

                let fnWasDown = previousFlags.contains(.function)
                let fnIsDown = flags.contains(.function)
                let cmdWasDown = previousFlags.contains(.command)
                let cmdIsDown = flags.contains(.command)
                let optionWasDown = previousFlags.contains(.option)
                let optionIsDown = flags.contains(.option)

                // --- Option edges (double-tap detection) ---
                if !optionWasDown && optionIsDown {
                    // Only detect double-tap if preference is enabled
                    if PreferencesManager.shared.doubleOptionShortcut == .enabled {
                        var isDouble = false
                        if let last = self.lastOptionDownAt,
                            now.timeIntervalSince(last) <= self.doubleTapWindow,
                            self.optionCooldownUntil.map({ now >= $0 }) ?? true
                        {
                            isDouble = true
                        }

                        if isDouble {
                            self.onDoubleTapOption?()
                            self.optionCooldownUntil = now.addingTimeInterval(0.35)
                            self.lastOptionDownAt = nil
                            self.previousFlags = flags
                            return
                        }
                    }

                    self.lastOptionDownAt = now
                }

                // --- Fn edges ---
                if !fnWasDown && fnIsDown {
                    // Double-tap check happens on the DOWN edge
                    var isDouble = false
                    if let last = self.lastFnDownAt,
                        now.timeIntervalSince(last) <= self.doubleTapWindow,
                        self.cooldownUntil.map { now >= $0 } ?? true
                    {
                        isDouble = true
                    }

                    if isDouble {
                        self.onDoubleTapFn?()
                        cooldownUntil = now.addingTimeInterval(0.35)

                        // Swallow the down and up that formed the double tap
                        self.swallowFnDownAfterDoubleTap = true
                        self.swallowNextFnUp = true

                        // ensure no delayed up from min hold
                        self.pendingFnUpTimer?.invalidate()
                        self.pendingFnUpTimer = nil
                        self.lastFnDownAt = nil

                        self.previousFlags = flags
                        return  // ← do NOT call onFnDown

                    }

                    // normal single down path
                    pendingFnUpTimer?.invalidate()
                    pendingFnUpTimer = nil
                    lastFnDownAt = now

                    // Check preferences to determine if we should start a session
                    let (shouldStart, isCmdMode) = self.shouldStartSession(isCmdHeld: cmdIsDown)
                    if shouldStart {
                        self.fnSessionStarted = true
                        onFnDown?(isCmdMode)
                    }
                }
                if fnWasDown && !fnIsDown {

                    if self.swallowFnUpAfterEscape {
                        self.swallowFnUpAfterEscape = false
                        self.previousFlags = flags
                        return
                    }

                    // If we just decided to swallow the post-double-tap UP, eat it and reset the flag
                    if self.swallowNextFnUp {
                        self.swallowNextFnUp = false
                        self.swallowFnDownAfterDoubleTap = false
                        self.previousFlags = flags
                        return
                    }

                    // Only fire onFnUp if we actually started a session
                    guard self.fnSessionStarted else {
                        self.previousFlags = flags
                        return
                    }

                    let held = now.timeIntervalSince(lastFnDownAt ?? now)
                    if held >= minFnHold {
                        self.fnSessionStarted = false
                        onFnUp?()
                    } else {
                        let delay = max(0, minFnHold - held)
                        pendingFnUpTimer?.invalidate()
                        pendingFnUpTimer = Timer.scheduledTimer(
                            withTimeInterval: delay, repeats: false
                        ) { [weak self] _ in
                            self?.fnSessionStarted = false
                            self?.onFnUp?()
                            self?.pendingFnUpTimer = nil
                        }
                        if let timer = pendingFnUpTimer {
                            RunLoop.main.add(timer, forMode: .common)  // don't let UI interactions pause it
                        }

                    }

                }

                // --- Cmd edges ---
                if !cmdWasDown && cmdIsDown {
                    guard !self.shouldIgnoreCommandEvent() else {
                        self.previousFlags = flags
                        return
                    }

                    // If Fn is held but no session started (e.g., dictation disabled),
                    // try to start agent mode session now
                    if fnIsDown && !self.fnSessionStarted {
                        let (shouldStart, isCmdMode) = self.shouldStartSession(isCmdHeld: true)
                        if shouldStart && isCmdMode {
                            self.fnSessionStarted = true
                            onFnDown?(true)  // Start agent mode
                        }
                    }

                    onCmdDown?()
                }
                if cmdWasDown && !cmdIsDown {
                    guard !self.shouldIgnoreCommandEvent() else {
                        self.previousFlags = flags
                        return
                    }
                    onCmdUp?()
                }

                // update snapshot
                previousFlags = flags

            })
        {
            monitors.append(flagsMonitor)
        }

        // Local monitor for when app is active
        if let localMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .flagsChanged,
            handler: { [weak self] event in
                guard let self = self else { return event }

                let flags = event.modifierFlags
                let now = Date()

                let fnWasDown = previousFlags.contains(.function)
                let fnIsDown = flags.contains(.function)
                let cmdWasDown = previousFlags.contains(.command)
                let cmdIsDown = flags.contains(.command)
                let optionWasDown = previousFlags.contains(.option)
                let optionIsDown = flags.contains(.option)


                // --- Option edges (double-tap detection) ---
                if !optionWasDown && optionIsDown {
                    // Only detect double-tap if preference is enabled
                    if PreferencesManager.shared.doubleOptionShortcut == .enabled {
                        var isDouble = false
                        if let last = self.lastOptionDownAt,
                            now.timeIntervalSince(last) <= self.doubleTapWindow,
                            self.optionCooldownUntil.map({ now >= $0 }) ?? true
                        {
                            isDouble = true
                        }

                        if isDouble {
                            self.onDoubleTapOption?()
                            self.optionCooldownUntil = now.addingTimeInterval(0.35)
                            self.lastOptionDownAt = nil
                            self.previousFlags = flags
                            return event
                        }
                    }

                    self.lastOptionDownAt = now
                }

                // --- Fn edges ---
                if !fnWasDown && fnIsDown {
                    var isDouble = false
                    if let last = self.lastFnDownAt,
                        now.timeIntervalSince(last) <= self.doubleTapWindow,
                        self.cooldownUntil.map { now >= $0 } ?? true
                    {
                        isDouble = true
                    }

                    if isDouble {
                        self.onDoubleTapFn?()
                        cooldownUntil = now.addingTimeInterval(0.35)
                        self.swallowFnDownAfterDoubleTap = true
                        self.swallowNextFnUp = true
                        self.pendingFnUpTimer?.invalidate()
                        self.pendingFnUpTimer = nil
                        self.lastFnDownAt = nil
                        self.previousFlags = flags
                        return event
                    }

                    pendingFnUpTimer?.invalidate()
                    pendingFnUpTimer = nil
                    lastFnDownAt = now

                    // Check preferences to determine if we should start a session
                    let (shouldStart, isCmdMode) = self.shouldStartSession(isCmdHeld: cmdIsDown)
                    if shouldStart {
                        self.fnSessionStarted = true
                        onFnDown?(isCmdMode)
                    }
                }

                if fnWasDown && !fnIsDown {
                    if self.swallowFnUpAfterEscape {
                        self.swallowFnUpAfterEscape = false
                        self.previousFlags = flags
                        return event
                    }

                    if self.swallowNextFnUp {
                        self.swallowNextFnUp = false
                        self.swallowFnDownAfterDoubleTap = false
                        self.previousFlags = flags
                        return event
                    }

                    // Only fire onFnUp if we actually started a session
                    guard self.fnSessionStarted else {
                        self.previousFlags = flags
                        return event
                    }

                    let held = now.timeIntervalSince(lastFnDownAt ?? now)
                    if held >= minFnHold {
                        self.fnSessionStarted = false
                        onFnUp?()
                    } else {
                        let delay = max(0, minFnHold - held)
                        pendingFnUpTimer?.invalidate()
                        pendingFnUpTimer = Timer.scheduledTimer(
                            withTimeInterval: delay, repeats: false
                        ) { [weak self] _ in
                            self?.fnSessionStarted = false
                            self?.onFnUp?()
                            self?.pendingFnUpTimer = nil
                        }
                        if let timer = pendingFnUpTimer {
                            RunLoop.main.add(timer, forMode: .common)
                        }
                    }
                }

                // --- Cmd edges ---
                if !cmdWasDown && cmdIsDown {
                    guard !self.shouldIgnoreCommandEvent() else {
                        self.previousFlags = flags
                        return event
                    }

                    // If Fn is held but no session started (e.g., dictation disabled),
                    // try to start agent mode session now
                    if fnIsDown && !self.fnSessionStarted {
                        let (shouldStart, isCmdMode) = self.shouldStartSession(isCmdHeld: true)
                        if shouldStart && isCmdMode {
                            self.fnSessionStarted = true
                            onFnDown?(true)  // Start agent mode
                        }
                    }

                    onCmdDown?()
                }
                if cmdWasDown && !cmdIsDown {
                    guard !self.shouldIgnoreCommandEvent() else {
                        self.previousFlags = flags
                        return event
                    }
                    onCmdUp?()
                }

                previousFlags = flags
                return event
            })
        {
            monitors.append(localMonitor)
        }

        if let escapeMonitor = NSEvent.addGlobalMonitorForEvents(
            matching: .keyDown,
            handler: { [weak self] event in
                guard let self = self else { return }
                // Escape key code is 53
                if event.keyCode == 53 {
                    NSLog(
                        "[HotkeyEventTap] Global escape detected, fnHeld=\(self.previousFlags.contains(.function))"
                    )
                    // If Fn is currently held, swallow the next Fn up
                    if self.previousFlags.contains(.function) {
                        self.swallowFnUpAfterEscape = true
                        self.fnSessionStarted = false
                        // Cancel any pending delayed Fn up
                        self.pendingFnUpTimer?.invalidate()
                        self.pendingFnUpTimer = nil
                    }
                    NSLog(
                        "[HotkeyEventTap] Calling onEscapePressed callback (isNil=\(self.onEscapePressed == nil))"
                    )
                    self.onEscapePressed?()
                }
            })
        {
            monitors.append(escapeMonitor)
        }

        // Local monitor for Escape when app is active
        if let localEscapeMonitor = NSEvent.addLocalMonitorForEvents(
            matching: .keyDown,
            handler: { [weak self] event in
                guard let self = self else { return event }
                // Escape key code is 53
                if event.keyCode == 53 {
                    NSLog(
                        "[HotkeyEventTap] Local escape detected, fnHeld=\(self.previousFlags.contains(.function))"
                    )
                    // If Fn is currently held, swallow the next Fn up
                    if self.previousFlags.contains(.function) {
                        self.swallowFnUpAfterEscape = true
                        self.fnSessionStarted = false
                        // Cancel any pending delayed Fn up
                        self.pendingFnUpTimer?.invalidate()
                        self.pendingFnUpTimer = nil
                    }
                    NSLog(
                        "[HotkeyEventTap] Calling onEscapePressed callback (isNil=\(self.onEscapePressed == nil))"
                    )
                    self.onEscapePressed?()
                    return nil  // Consume the event
                }
                return event
            })
        {
            monitors.append(localEscapeMonitor)
        }

    }

    func stop() {
        guard isStarted else { return }
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        isStarted = false

        //        cancel any pending delayed up event
        pendingFnUpTimer?.invalidate()
        pendingFnUpTimer = nil

        // clear swallow flags
        swallowFnDownAfterDoubleTap = false
        swallowNextFnUp = false
        swallowFnUpAfterEscape = false
        fnSessionStarted = false

        // If Fn was logically down, synthesize an up so the app isn't stuck
        if previousFlags.contains(.function) { onFnUp?() }
        if previousFlags.contains(.command) { onCmdUp?() }

        previousFlags = []

        if isHoldingFn {
            isHoldingFn = false
            onFnUp?()
        }

        if isHoldingCmd {
            isHoldingCmd = false
            onCmdUp?()
        }
    }

    func suppressCommandCallbacks(for duration: TimeInterval) {
        ignoreCmdEventsUntil = Date().addingTimeInterval(duration)
    }

    private func shouldIgnoreCommandEvent() -> Bool {
        if let until = ignoreCmdEventsUntil, Date() < until { return true }
        ignoreCmdEventsUntil = nil
        return false
    }

    /// Checks preferences and determines if we should start a session.
    /// Returns: (shouldStart: Bool, isCmdMode: Bool)
    private func shouldStartSession(isCmdHeld: Bool) -> (shouldStart: Bool, isCmdMode: Bool) {
        let prefs = PreferencesManager.shared
        let dictationEnabled = prefs.dictationShortcut == .enabled
        let agentModeEnabled = prefs.agentModeShortcut == .enabled

        // If both disabled, don't start
        if !dictationEnabled && !agentModeEnabled {
            return (false, false)
        }

        // If cmd is held, check agent mode preference
        if isCmdHeld {
            if agentModeEnabled {
                return (true, true)  // Start agent mode
            } else if dictationEnabled {
                return (true, false)  // Fall back to dictation if agent mode disabled
            } else {
                return (false, false)
            }
        }

        // Cmd not held - check dictation preference
        if dictationEnabled {
            return (true, false)  // Start dictation
        }

        // Dictation disabled, cmd not held - don't start
        return (false, false)
    }

    deinit {
        stop()
    }
}
