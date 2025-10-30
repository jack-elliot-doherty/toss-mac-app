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
    
    private var lastFnDownAt:Date?
    private let doubleTapWindow: TimeInterval = 0.30
    private var cooldownUntil :Date?
    
    private(set) var isStarted: Bool = false
    
    private var previousFlags: NSEvent.ModifierFlags = []
    
    
    func start() {
        guard !isStarted else { return }
        isStarted = true

        // TODO: In a future pass, compute edges from previousFlags instead of isHolding*
        // Primary: Fn key via modifier flags changed
        if let flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            guard let self = self else { return }
            
            let flags = event.modifierFlags
            let now = Date()

            let fnWasDown  = previousFlags.contains(.function)
            let fnIsDown   = flags.contains(.function)
            let cmdWasDown = previousFlags.contains(.command)
            let cmdIsDown  = flags.contains(.command)

            // --- Fn edges ---
            if !fnWasDown && fnIsDown {
                // Double-tap check
                if let last = lastFnDownAt,
                   now.timeIntervalSince(last) <= doubleTapWindow,
                   (cooldownUntil.map { now >= $0 } ?? true) {
                    print("[Hotkey] Fn double-tap")
                    onDoubleTapFn?()
                    cooldownUntil = now.addingTimeInterval(0.35)
                }
                lastFnDownAt = now
                print("[Hotkey] Fn DOWN")
                onFnDown?()
            }
            if fnWasDown && !fnIsDown {
                print("[Hotkey] Fn UP")
                onFnUp?()
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
//            
//            let fnDown = event.modifierFlags.contains(.function)
//            let cmdDown = event.modifierFlags.contains(.command)
//            if fnDown && !self.isHoldingFn {
//                self.isHoldingFn = true
//                
//                // Double-tap check on the Fn-down edge
//                               let now = Date()
//                               if let last = self.lastFnDownAt,
//                                  now.timeIntervalSince(last) <= self.doubleTapWindow,
//                                  (self.cooldownUntil.map { now >= $0 } ?? true) {
//                                   self.onDoubleTapFn?()
//                                   // small cooldown to avoid triple-tap toggling twice
//                                   self.cooldownUntil = now.addingTimeInterval(0.35)
//                               }
//                               self.lastFnDownAt = now
//                
//                self.onFnDown?()
//            } else if !fnDown && self.isHoldingFn {
//                self.isHoldingFn = false
//                self.onFnUp?()
//            }
//            
//            if cmdDown && !self.isHoldingCmd {
//                self.isHoldingCmd = true
//                self.onCmdDown?()
//            } else if !cmdDown && self.isHoldingCmd {
//                self.isHoldingCmd = false
//                self.onCmdUp?()
//            }
            
        }) {
            monitors.append(flagsMonitor)
        }
    }

    func stop() {
        guard isStarted else { return }
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        isStarted = false
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


