import Cocoa

final class HotkeyEventTap {
    var onHoldStart: (() -> Void)?
    var onHoldEnd: (() -> Void)?

    private var monitors: [Any] = []
    private var isHolding: Bool = false
    private(set) var isStarted: Bool = false

    func start() {
        guard !isStarted else { return }
        isStarted = true

        // Primary: Fn key via modifier flags changed
        if let flagsMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] event in
            guard let self = self else { return }
            let fnDown = event.modifierFlags.contains(.function)
            if fnDown && !self.isHolding {
                self.isHolding = true
                self.onHoldStart?()
            } else if !fnDown && self.isHolding {
                self.isHolding = false
                self.onHoldEnd?()
            }
        }) {
            monitors.append(flagsMonitor)
        }
    }

    func stop() {
        guard isStarted else { return }
        monitors.forEach { NSEvent.removeMonitor($0) }
        monitors.removeAll()
        isStarted = false
        if isHolding {
            isHolding = false
            onHoldEnd?()
        }
    }

    deinit {
        stop()
    }
}


