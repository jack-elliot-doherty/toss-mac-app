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

                        // Swallow the down up the formed the double tap
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

                    // Pass actual cmd modifier state to avoid event ordering issues
                    onFnDown?(cmdIsDown)
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

                    let held = now.timeIntervalSince(lastFnDownAt ?? now)
                    if held >= minFnHold {
                        onFnUp?()
                    } else {
                        let delay = max(0, minFnHold - held)
                        pendingFnUpTimer?.invalidate()
                        pendingFnUpTimer = Timer.scheduledTimer(
                            withTimeInterval: delay, repeats: false
                        ) { [weak self] _ in
                            self?.onFnUp?()
                            self?.pendingFnUpTimer = nil
                        }
                        RunLoop.main.add(pendingFnUpTimer!, forMode: .common)  // don’t let UI interactions pause it

                    }

                }

                // --- Cmd edges ---
                if !cmdWasDown && cmdIsDown {
                    guard !self.shouldIgnoreCommandEvent() else {
                        self.previousFlags = flags
                        return
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

                print(flags)

                // --- Option edges (double-tap detection) ---
                if !optionWasDown && optionIsDown {
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
                    // Pass actual cmd modifier state to avoid event ordering issues
                    onFnDown?(cmdIsDown)
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

                    let held = now.timeIntervalSince(lastFnDownAt ?? now)
                    if held >= minFnHold {
                        onFnUp?()
                    } else {
                        let delay = max(0, minFnHold - held)
                        pendingFnUpTimer?.invalidate()
                        pendingFnUpTimer = Timer.scheduledTimer(
                            withTimeInterval: delay, repeats: false
                        ) { [weak self] _ in
                            self?.onFnUp?()
                            self?.pendingFnUpTimer = nil
                        }
                        RunLoop.main.add(pendingFnUpTimer!, forMode: .common)
                    }
                }

                // --- Cmd edges ---
                if !cmdWasDown && cmdIsDown {
                    guard !self.shouldIgnoreCommandEvent() else {
                        self.previousFlags = flags
                        return event
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
                    NSLog("[HotkeyEventTap] Global escape detected, fnHeld=\(self.previousFlags.contains(.function))")
                    // If Fn is currently held, swallow the next Fn up
                    if self.previousFlags.contains(.function) {
                        self.swallowFnUpAfterEscape = true
                        // Cancel any pending delayed Fn up
                        self.pendingFnUpTimer?.invalidate()
                        self.pendingFnUpTimer = nil
                    }
                    NSLog("[HotkeyEventTap] Calling onEscapePressed callback (isNil=\(self.onEscapePressed == nil))")
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
                    NSLog("[HotkeyEventTap] Local escape detected, fnHeld=\(self.previousFlags.contains(.function))")
                    // If Fn is currently held, swallow the next Fn up
                    if self.previousFlags.contains(.function) {
                        self.swallowFnUpAfterEscape = true
                        // Cancel any pending delayed Fn up
                        self.pendingFnUpTimer?.invalidate()
                        self.pendingFnUpTimer = nil
                    }
                    NSLog("[HotkeyEventTap] Calling onEscapePressed callback (isNil=\(self.onEscapePressed == nil))")
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

    deinit {
        stop()
    }
}
