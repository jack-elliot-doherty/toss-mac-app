import Cocoa

final class HotkeyEventTap {
    var onFnDown: (() -> Void)?
    var onFnUp: (() -> Void)?

    var onCmdDown: (() -> Void)?
    var onCmdUp: (() -> Void)?

    var onDoubleTapFn: (() -> Void)?

    private var monitors: [Any] = []
    private var isHoldingFn: Bool = false
    private var isHoldingCmd: Bool = false

    private var lastFnDownAt: Date?
    private let doubleTapWindow: TimeInterval = 0.5
    private var cooldownUntil: Date?
    private let minFnHold: TimeInterval = 0.5
    private var pendingFnUpTimer: Timer?

    private var swallowFnDownAfterDoubleTap = false
    private var swallowNextFnUp = false

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

                print("[Hotkey] Flags:")
                print(flags)
                print("Fn was down: \(fnWasDown)")
                print("Fn is down: \(fnIsDown)")
                print("Cmd was down: \(cmdWasDown)")
                print("Cmd is down: \(cmdIsDown)")

                // --- Fn edges ---
                if !fnWasDown && fnIsDown {
                    print("[Hotkey] Fn DOWN")
                    // Double-tap check happens on the DOWN edge
                    var isDouble = false
                    if let last = self.lastFnDownAt,
                        now.timeIntervalSince(last) <= self.doubleTapWindow,
                        self.cooldownUntil.map { now >= $0 } ?? true
                    {
                        isDouble = true
                    }

                    if isDouble {
                        print("[Hotkey] Fn double tap")
                        self.onDoubleTapFn?()
                        cooldownUntil = now.addingTimeInterval(0.35)

                        // Swallow the down up the formed the double tap
                        self.swallowFnDownAfterDoubleTap = true
                        self.swallowNextFnUp = true

                        // ensure no delayed up from min hold
                        self.pendingFnUpTimer?.invalidate()
                        self.pendingFnUpTimer = nil
                        self.lastFnDownAt = nil

                        print("[Hotkey] (swallowing Fn DOWN/UP for double-tap)")
                        self.previousFlags = flags
                        return  // ← do NOT call onFnDown

                    }

                    // normal single down path
                    pendingFnUpTimer?.invalidate()
                    pendingFnUpTimer = nil
                    lastFnDownAt = now

                    onFnDown?()
                }
                if fnWasDown && !fnIsDown {

                    // If we just decided to swallow the post-double-tap UP, eat it and reset the flag
                    if self.swallowNextFnUp {
                        self.swallowNextFnUp = false
                        self.swallowFnDownAfterDoubleTap = false
                        print("[Hotkey] (swallowed Fn UP after double-tap)")
                        self.previousFlags = flags
                        return
                    }

                    print("[Hotkey] Fn UP")
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
                    print("[Hotkey] Cmd DOWN")
                    onCmdDown?()
                }
                if cmdWasDown && !cmdIsDown {
                    print("[Hotkey] Cmd UP")
                    onCmdUp?()
                }

                // update snapshot
                print("Flags")
                print(flags)
                previousFlags = flags

            })
        {
            monitors.append(flagsMonitor)
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

    deinit {
        stop()
    }
}
