import Cocoa
import SwiftUI

@MainActor
final class ToastPanelController {
    private let panel: NSPanel
    private var dismissTask: Task<Void, Never>?
    private let anchorFrameProvider: () -> NSRect?

    init(anchorFrameProvider: @escaping () -> NSRect?) {
        self.anchorFrameProvider = anchorFrameProvider
        let contentRect = NSRect(x: 0, y: 40, width: 480, height: 140)
        self.panel = NSPanel(
            contentRect: contentRect,
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false)
        panel.isFloatingPanel = true
        panel.level = .popUpMenu
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.hidesOnDeactivate = false
        panel.worksWhenModal = true
        panel.ignoresMouseEvents = false
    }

    // Simple text toast (kept for existing calls)
    func show(message: String, duration: TimeInterval = 2.0, onTap: (() -> Void)? = nil) {
        showRich(
            icon: Image(systemName: "checkmark.circle.fill"),
            title: message,
            subtitle: nil,
            primary: nil,
            secondary: nil,
            duration: duration
        )
    }

    struct ToastAction {
        let title: String
        let action: () -> Void
    }

    // Wispr-style toast
    func showRich(
        icon: Image? = Image(systemName: "exclamationmark.circle.fill"),
        title: String,
        subtitle: String? = nil,
        primary: ToastAction? = nil,
        secondary: ToastAction? = nil,
        duration: TimeInterval = 3.0,
        offsetAboveAnchor: CGFloat = 36
    ) {
        let root = RichToastView(
            icon: icon,
            title: title,
            subtitle: subtitle,
            primary: primary,
            secondary: secondary,
            onClose: { [weak self] in self?.panel.orderOut(nil) }
        )
        let hosting = NSHostingView(rootView: AnyView(root))
        panel.contentView = hosting
        sizeToFit(hosting: hosting, minWidth: 420, idealWidth: 520, maxWidth: 560)
        hosting.frame = NSRect(origin: .zero, size: panel.frame.size)
        hosting.autoresizingMask = [.width, .height]
        positionAboveAnchor(offset: offsetAboveAnchor)
        panel.orderFrontRegardless()

        dismissTask?.cancel()
        // Only auto-dismiss if no interactive actions
        if primary == nil && secondary == nil {
            dismissTask = Task { [weak self] in
                guard let self = self else { return }
                try? await Task.sleep(nanoseconds: UInt64(duration * 1_000_000_000))
                if Task.isCancelled { return }
                self.panel.orderOut(nil)
            }
        }
    }

    private func sizeToFit(
        hosting: NSHostingView<AnyView>, minWidth: CGFloat, idealWidth: CGFloat, maxWidth: CGFloat
    ) {
        hosting.invalidateIntrinsicContentSize()
        hosting.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.01))
        var size = hosting.fittingSize
        if size.width < 1 || size.height < 1 {
            size = NSSize(width: idealWidth, height: 120)
        }
        size.width = min(max(size.width, minWidth), maxWidth)
        var frame = panel.frame
        frame.size = size
        panel.setFrame(frame, display: true)
    }

    private func positionAboveAnchor(offset: CGFloat) {
        if let anchor = anchorFrameProvider(), anchor.width > 0, anchor.height > 0 {
            let x = anchor.midX - panel.frame.width / 2
            let y = anchor.maxY + offset
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        } else if let screen = NSScreen.main {
            let vf = screen.visibleFrame
            let x = vf.midX - panel.frame.width / 2
            let y = vf.minY + 120
            panel.setFrameOrigin(NSPoint(x: x, y: y))
        }
    }
}

private struct CapsuleButton: View {
    let title: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundColor(.white)
        .background(
            Capsule().fill(Color.white.opacity(0.14))
        )
        .overlay(
            Capsule().strokeBorder(Color.white.opacity(0.18), lineWidth: 1)
        )
    }
}

private struct RichToastView: View {
    let icon: Image?
    let title: String
    let subtitle: String?
    let primary: ToastPanelController.ToastAction?
    let secondary: ToastPanelController.ToastAction?
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            // Card background with blur + subtle border
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)  // blurred dark/light
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 12)

            // Close button
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.white.opacity(0.9))
                    .padding(8)
            }
            .buttonStyle(.plain)
            .background(Circle().fill(Color.white.opacity(0.12)))
            .padding(10)
        }
        .overlay(
            // Content
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .center, spacing: 10) {
                    if let icon = icon {
                        icon
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.red)
                            .symbolRenderingMode(.hierarchical)
                    }
                    Text(title)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.white)
                        .lineLimit(2)
                }

                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.system(size: 15))
                        .foregroundColor(.white.opacity(0.85))
                        .lineSpacing(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 14) {
                    if let primary = primary {
                        CapsuleButton(title: primary.title, action: primary.action)
                    }
                    if let secondary = secondary {
                        CapsuleButton(title: secondary.title, action: secondary.action)
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 18)
            .frame(minWidth: 420, idealWidth: 520, maxWidth: 560, alignment: .leading),
            alignment: .center
        )
        .fixedSize(horizontal: false, vertical: true)
    }
}
