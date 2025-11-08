import Cocoa
import SwiftUI

@MainActor
final class ToastPanelController {
    private let panel: NSPanel
    private var dismissTask: Task<Void, Never>?
    private let anchorFrameProvider: () -> NSRect?

    var onToastAction: ((PillEvent) -> Void)?

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

    func show(
        icon: Image? = nil,
        title: String,
        subtitle: String? = nil,
        primary: ToastAction? = nil,
        secondary: ToastAction? = nil,
        duration: TimeInterval = 3.0,
        offsetAboveAnchor: CGFloat = 30
    ) {
        let root = RichToastView(
            icon: icon,
            title: title,
            subtitle: subtitle,
            primary: primary,
            secondary: secondary,
            onClose: { [weak self] in self?.panel.orderOut(nil) },
            onAction: { [weak self] event in self?.onToastAction?(event) },
            duration: primary == nil && secondary == nil ? duration : nil  // Only show progress if auto-dismissing

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
                try? await Task.sleep(for: .seconds(duration))
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
    let variant: ToastActionVariant
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
                .background(Capsule().fill(Color.white.opacity(0.14)))
                .overlay(Capsule().stroke(Color.white.opacity(0.18), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }
}

private struct RichToastView: View {
    let icon: Image?
    let title: String
    let subtitle: String?
    let primary: ToastAction?
    let secondary: ToastAction?
    let onClose: () -> Void
    let onAction: (PillEvent) -> Void
    let duration: TimeInterval?

    @State private var progress: Double = 0.0

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                if let icon = icon {
                    icon
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(.red)
                        .symbolRenderingMode(.hierarchical)
                }
                Text(title)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 8)
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.9))
                        .padding(8)
                        .background(Circle().fill(Color.white.opacity(0.14)))
                }
                .buttonStyle(.plain)
            }

            if let subtitle = subtitle {
                Text(subtitle)
                    .font(.system(size: 15))
                    .foregroundColor(.white.opacity(0.88))
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 12) {
                if let primary = primary {
                    CapsuleButton(
                        title: primary.title,
                        variant: primary.variant,
                        action: { onAction(primary.eventToSend) })
                }
                if let secondary = secondary {
                    CapsuleButton(
                        title: secondary.title, variant: secondary.variant,
                        action: { onAction(secondary.eventToSend) })
                }
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 16)
        .frame(minWidth: 420, idealWidth: 520, maxWidth: 560, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color.black.opacity(0.82))  // consistent dark card
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.10), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.35), radius: 24, x: 0, y: 12)
        )
        .overlay(alignment: .bottom) {
            // Progress bar as overlay at bottom
            if let duration = duration, duration > 0 {
                GeometryReader { geometry in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(Color.blue.opacity(0.6))
                            .frame(width: geometry.size.width * progress, height: 3)
                        Spacer(minLength: 0)
                    }
                }
                .frame(height: 3)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                        withAnimation(.linear(duration: duration)) {
                            progress = 1.0
                        }
                    }
                }
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .fixedSize(horizontal: false, vertical: true)
    }
}
