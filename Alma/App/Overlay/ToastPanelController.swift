import Cocoa
import SwiftUI

@MainActor
final class ToastPanelController {
    private let panel: NSPanel
    private var dismissTask: Task<Void, Never>?
    private let anchorFrameProvider: () -> NSRect?

    init(anchorFrameProvider: @escaping () -> NSRect?) {
        self.anchorFrameProvider = anchorFrameProvider
        let contentRect = NSRect(x: 0, y: 40, width: 260, height: 32)
        self.panel = NSPanel(contentRect: contentRect,
                              styleMask: [.nonactivatingPanel, .borderless],
                              backing: .buffered,
                              defer: false)
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.ignoresMouseEvents = false
    }
    
    func show(message: String, duration: TimeInterval = 2.0, onTap: (() -> Void)? = nil) {
        let root = LocalToastView(text: message)
            .onTapGesture {
                onTap?()
                self.panel.orderOut(nil)
            }
        let hosting = NSHostingView(rootView: AnyView(root))
        panel.contentView = hosting
        sizeToFit(hosting: hosting)
        positionAboveAnchor()
        panel.orderFrontRegardless()
        dismissTask?.cancel()
        dismissTask = Task { [weak self] in
            guard let self = self else { return }
            try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
            if Task.isCancelled { return }
            self.panel.orderOut(nil)
        }
    }

    private func sizeToFit(hosting: NSHostingView<AnyView>) {
        let size = hosting.fittingSize
        var frame = panel.frame
        frame.size = NSSize(width: size.width, height: size.height)
        panel.setFrame(frame, display: true)
    }

    private func positionAboveAnchor(offset: CGFloat = 8) {
        if let anchor = anchorFrameProvider() {
            let x = anchor.midX - panel.frame.width / 2
            let y = anchor.maxY + offset
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            let x = frame.midX - panel.frame.width / 2
            let y = frame.minY + 60
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}

private struct LocalToastView: View {
    let text: String
    var body: some View {
        Text(text)
            .font(.system(size: 13))
            .foregroundColor(.white)
            .padding(10)
            .background(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(Color.black.opacity(0.75))
            )
            .fixedSize(horizontal: false, vertical: true)
    }
}


