import Combine
import SwiftUI

private enum PillStyle {
    static let corner: CGFloat = 16
    static let fill = Color.black.opacity(0.92)  // deeper black
    static let stroke = Color.white.opacity(0.28)  // crisp white outline
    static let hairline = 1.0

    // Idle silhouette (very small)
    static let idleWidth: CGFloat = 40
    static let idleHeight: CGFloat = 10
    static let padXIdle: CGFloat = 6
    static let padYIdle: CGFloat = 3

    // Active states
    static let padXActive: CGFloat = 8
    static let padYActive: CGFloat = 4
    static let spacing: CGFloat = 8

    static let waveformWidth: CGFloat = 64  // compact
    static let waveformHeight: CGFloat = 14
}

// MARK: - Pill

struct PillView: View {
    @ObservedObject var viewModel: PillViewModel
    @State private var isHovered: Bool = false
    @State private var hoverExitWorkItem: DispatchWorkItem?
    @State private var isTransitioning: Bool = false  // Lock during transitions
    @State private var isDragging: Bool = false

    var body: some View {
        let isMeetingRecording: Bool = {
            if case .meetingRecording = viewModel.visualState { return true }
            return false
        }()

        Group {
            switch viewModel.visualState {
            case .idle:
                idle.transition(.opacity.animation(.easeOut(duration: 0.15)))
            case .hovered:
                hoveredQuickActions.transition(
                    .asymmetric(
                        insertion: .opacity.animation(.easeOut(duration: 0.18)),
                        removal: .opacity.animation(.easeIn(duration: 0.12))
                    )
                )
            case .listening(let mode):
                listening(mode: mode).transition(
                    .opacity.animation(.easeOut(duration: 0.15))
                )
            case .transcribing(let mode):
                transcribing(mode: mode).transition(
                    .opacity.animation(.easeInOut(duration: 0.15))
                )
            case .meetingDetected:
                meetingDetected.transition(
                    .opacity.animation(.easeOut(duration: 0.18))
                )
            case .upcomingMeeting(let meeting):
                upcomingMeetingView(meeting: meeting).transition(
                    .opacity.animation(.easeOut(duration: 0.18))
                )
            case .meetingRecording(let meetingId, let isPaused):
                // Background is handled inside meetingRecording() to wrap only content
                meetingRecording(meetingId: meetingId, isPaused: isPaused, isHovered: viewModel.showMeetingRecordingStopButton)

            case .agentSessionActive:
                agentSessionActive.transition(
                    .opacity.animation(.easeOut(duration: 0.15))
                )
            }
        }
        .padding(.horizontal, 0)
        .padding(.vertical, 0)
        .if(!isMeetingRecording) { view in
            // Non-meeting states get their background here
            view
                .background(
                    Capsule(style: .continuous)
                        .fill(PillStyle.fill)
                )
                .overlay(
                    Capsule(style: .continuous)
                        .inset(by: 0.5)
                        .stroke(PillStyle.stroke, lineWidth: PillStyle.hairline)
                )
                .fixedSize(horizontal: true, vertical: true)
        }
        .contentShape(Capsule())
        .animation(
            .spring(response: 0.25, dampingFraction: 0.88),
            value: viewModel.visualState
        )
        .onHover { hovering in
            isHovered = hovering

            // Notify view model if we're in meeting recording state
            if case .meetingRecording = viewModel.visualState {
                // Don't change hover state while dragging
                if isDragging { return }

                if hovering {
                    hoverExitWorkItem?.cancel()
                    hoverExitWorkItem = nil
                    viewModel.isMeetingRecordingHovered = true
                } else {
                    hoverExitWorkItem?.cancel()
                    let item = DispatchWorkItem { [weak viewModel] in
                        viewModel?.isMeetingRecordingHovered = false
                    }
                    hoverExitWorkItem = item
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: item)
                }
                return
            }

            if hovering {
                // Cancel any pending hover exit
                hoverExitWorkItem?.cancel()
                hoverExitWorkItem = nil

                // Skip hover if disabled (e.g., agent panel is open)
                guard !viewModel.isHoverDisabled else { return }

                // Only trigger hover enter if we're in idle state
                // This prevents re-triggering during transitions
                if case .idle = viewModel.visualState {
                    isTransitioning = true
                    viewModel.onHoverEnter?()

                    // Release transition lock after animation completes
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        isTransitioning = false
                    }
                }
            } else {
                // Ignore hover exit during transition to prevent flapping
                guard !isTransitioning else { return }

                hoverExitWorkItem?.cancel()
                let item = DispatchWorkItem { [weak viewModel] in
                    viewModel?.onHoverExit?()
                }
                hoverExitWorkItem = item
                // Longer debounce to prevent flapping
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: item)
            }
        }
        .onTapGesture {
            viewModel.onPillClicked?()
        }
    }

    // MARK: Idle — tiny pill

    // IDLE (narrower & shorter)
    private var idle: some View {
        // Thin ring
        Capsule()
            .stroke(Color.white.opacity(0.36), lineWidth: 1)
            .frame(
                width: PillStyle.idleWidth - 8,
                height: PillStyle.idleHeight - 2
            )
            .blendMode(.plusLighter)

    }

    // MARK: Agent Session Active — shows there's a minimized agent session
    private var agentSessionActive: some View {
        HStack(spacing: 5) {
            Image(systemName: "arrow.up.left.and.arrow.down.right")
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(.white.opacity(0.7))

            Text("Resume")
                .font(.system(size: 11, weight: .medium))
                .foregroundColor(.white.opacity(0.8))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    // Hovered state with labeled buttons
    private var hoveredQuickActions: some View {
        HStack(spacing: 6) {
            // Record Meeting
            QuickActionButton(
                icon: "record.circle",
                label: "Record"
            ) {
                viewModel.onQuickActionRecordMeeting?()
            }

            // Agent Chat
            QuickActionButton(
                icon: "sparkles",
                label: "Agent"
            ) {
                viewModel.onQuickActionAgentChat?()
            }

            // Dictation
            QuickActionButton(
                icon: "waveform",
                label: "Dictate"
            ) {
                viewModel.onQuickActionDictation?()
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
    }

    // MARK: Listening
    private func listening(mode: PillMode) -> some View {
        HStack(spacing: PillStyle.spacing) {
            if viewModel.isAlwaysOn {
                // Always-on: buttons flank the waveform
                Button {
                    viewModel.onRequestCancel?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(.plain)
            }

            DotWaveformView(viewModel: viewModel)
                .id("waveform")
                .frame(width: PillStyle.waveformWidth, height: PillStyle.waveformHeight)

            if viewModel.isAlwaysOn {
                Button {
                    viewModel.onRequestStop?()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            } else if mode == .command {
                // Temp-hold agent affordance (no toggle)
                AgentChip()
                    .transition(
                        .asymmetric(
                            insertion: .move(edge: .trailing).combined(with: .opacity),
                            removal: .opacity
                        ))
            }
        }
        .padding(.horizontal, PillStyle.padXActive)
        .padding(.vertical, PillStyle.padYActive)
    }

    // MARK: Transcribing — widen a touch and show typing dots

    private func transcribing(mode: PillMode) -> some View {
        HStack(spacing: PillStyle.spacing) {
            DotWaveformView(viewModel: viewModel)  // subtle steady center while uploading
                .frame(width: PillStyle.waveformWidth, height: PillStyle.waveformHeight)

            ProgressView()
                .scaleEffect(0.5)
                .frame(width: 8, height: 8)
                .colorInvert()

            if viewModel.isAlwaysOn {
                Button {
                    viewModel.onRequestCancel?()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(.white.opacity(0.9))
                }
                .buttonStyle(.plain)

                Button {
                    viewModel.onRequestStop?()
                } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundStyle(.red)
                }
                .buttonStyle(.plain)
            } else if mode == .command {
                AgentChip()
            }
        }
        .padding(.horizontal, PillStyle.padXActive + 2)  // tiny widen vs listening
        .padding(.vertical, PillStyle.padYActive)
    }

    private func upcomingMeetingView(meeting: UpcomingMeeting) -> some View {
        HStack(spacing: PillStyle.spacing) {
            Image(systemName: "calendar.badge.clock")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text(meeting.displayTitle)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                Text("Starting \(meeting.relativeTime)")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }

            // Single Join & Record button
            Button {
                viewModel.onJoinAndRecordUpcoming?(meeting)
            } label: {
                HStack(spacing: 4) {
                    Image(systemName: "video.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text("Join & Start")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Capsule().fill(Color.blue))
            }
            .buttonStyle(.plain)

            // Dismiss X
            Button {
                viewModel.onDismissUpcomingMeeting?()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, PillStyle.padXActive)
        .padding(.vertical, PillStyle.padYActive)
    }

    private var meetingDetected: some View {
        HStack(spacing: PillStyle.spacing) {
            Image(systemName: "waveform.badge.mic")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)

            VStack(alignment: .leading, spacing: 2) {
                Text("Meeting detected")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                Text("Tap Start or press fn to begin recording")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            }

            Button {
                viewModel.onQuickActionRecordMeeting?()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "record.circle")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Start")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(
                    Capsule()
                        .fill(Color.red.opacity(0.9))
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, PillStyle.padXActive)
        .padding(.vertical, PillStyle.padYActive)
    }

    @ViewBuilder
    private func meetingRecording(meetingId: UUID, isPaused: Bool, isHovered: Bool) -> some View {
        // Window is always 122px tall (room for animation).
        // Drag handle "lid" has higher z-index - stop button slides behind it.
        let dragHandleHeight: CGFloat = 30  // separator + drag handle + padding

        VStack(spacing: 0) {
            Spacer(minLength: 0)

            // Use ZStack so drag handle can be layered on top
            ZStack(alignment: .bottom) {
                // LAYER 0: Main content (behind drag handle)
                VStack(spacing: 0) {
                    // Logo - fixed position
                    Image("TossLogo")
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: 18, height: 18)
                        .padding(.top, 10)

                    // Waveform - fixed position
                    ThreeBarWaveformView(viewModel: viewModel)
                        .frame(width: 20, height: 28)
                        .padding(.top, 4)

                    // Stop button - slides behind the drag handle lid
                    if isHovered {
                        Button {
                            viewModel.onStopMeetingRecording?()
                        } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 22, height: 22)
                                .background(Circle().fill(Color.red))
                        }
                        .buttonStyle(.plain)
                        .onHover { hovering in
                            if hovering {
                                NSCursor.arrow.push()
                            } else {
                                NSCursor.pop()
                            }
                        }
                        .padding(.top, 6)
                        .padding(.bottom, 6)
                        .transition(.move(edge: .bottom))
                    }

                    // Reserve space for the drag handle overlay
                    Color.clear
                        .frame(height: dragHandleHeight)
                }
                .frame(width: 36)

                // LAYER 1: Drag handle "lid" - always on top, clips content behind it
                VStack(spacing: 0) {
                    // Full-width separator line - same color as pill stroke
                    Rectangle()
                        .fill(PillStyle.stroke)
                        .frame(height: 1)

                    // Drag handle dots
                    VerticalDragHandleView(
                        isDragging: $isDragging,
                        onDragStart: { viewModel.onDragStart?() },
                        onDragEnd: { viewModel.onDragEnd?() }
                    )
                    .padding(.top, 5)
                    .padding(.bottom, 6)
                }
                .frame(width: 36, height: dragHandleHeight)
                .background(PillStyle.fill)  // Solid fill to hide content sliding behind
            }
            .background(
                Capsule(style: .continuous)
                    .fill(PillStyle.fill)
            )
            .overlay(
                Capsule(style: .continuous)
                    .inset(by: 0.5)
                    .stroke(PillStyle.stroke, lineWidth: PillStyle.hairline)
            )
            .clipShape(Capsule(style: .continuous))  // Clip everything to pill shape
        }
        .animation(.easeInOut(duration: 0.2), value: isHovered)
        .frame(maxHeight: .infinity, alignment: .bottom)
        .frame(width: 36)
    }

}

// MARK: - Subviews

/// Minimal labeled button for hover state quick actions
private struct QuickActionButton: View {
    let icon: String
    let label: String
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .medium))
                Text(label)
                    .font(.system(size: 12, weight: .medium))
            }
            .foregroundColor(.white.opacity(isHovered ? 1.0 : 0.8))
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(
                Capsule()
                    .fill(Color.white.opacity(isHovered ? 0.15 : 0.08))
            )
            .overlay(
                Capsule()
                    .stroke(Color.white.opacity(isHovered ? 0.3 : 0.15), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .animation(.easeOut(duration: 0.1), value: isHovered)
    }
}

/// Small "Agent" badge, purely indicative (no toggle).
private struct AgentChip: View {
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "sparkles")
                .font(.system(size: 11, weight: .semibold))
            Text("Agent")
                .font(.system(size: 11, weight: .semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.12))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(Color.white.opacity(0.2), lineWidth: 1)
        )
        .accessibilityLabel("Agent mode")
    }
}

private struct DotWaveformView: View {
    @ObservedObject var viewModel: PillViewModel
    private let barCount = 12
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 26
    private let barWidth: CGFloat = 3
    private let spacing: CGFloat = 3

    var body: some View {
        let level = Double(max(0.0, min(1.0, viewModel.levelRMS)))
        HStack(spacing: spacing) {
            ForEach(0..<barCount, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(.white.opacity(0.9))
                    .frame(
                        width: barWidth,
                        height: barHeight(at: index, level: level)
                    )
            }
        }
        .animation(.spring(response: 0.12, dampingFraction: 0.65), value: viewModel.levelRMS)
    }

    private func barHeight(at index: Int, level: Double) -> CGFloat {
        let center = Double(barCount - 1) / 2
        let distance = abs(Double(index) - center)

        // Gaussian envelope to bias the middle bars
        let sigma: Double = Double(barCount) / 5.0
        let envelope = exp(-pow(distance, 2) / (2 * pow(sigma, 2)))

        // Slight per-bar variation so they aren't perfectly mirrored
        let variation = 1 + 0.2 * sin(Double(index) * 1.25 + level * 6.0)

        // Amplify perceived loudness (gamma curve keeps quiet speech visible)
        let amplifiedLevel = pow(level, 0.65)

        let height =
            minHeight + envelope * variation * amplifiedLevel * Double(maxHeight - minHeight)
        return CGFloat(clamp(height, min: Double(minHeight), max: Double(maxHeight)))
    }

    private func clamp(_ value: Double, min: Double, max: Double) -> Double {
        Swift.max(min, Swift.min(max, value))
    }
}

private struct PulsingModifier: ViewModifier {
    @State private var isPulsing = false

    func body(content: Content) -> some View {
        content
            .opacity(isPulsing ? 0.4 : 1.0)
            .animation(
                .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true),
                value: isPulsing
            )
            .onAppear {
                isPulsing = true
            }
    }
}

/// 3-bar horizontal waveform for meeting recording (center bar tallest)
private struct ThreeBarWaveformView: View {
    @ObservedObject var viewModel: PillViewModel
    private let minHeight: CGFloat = 4
    private let maxHeight: CGFloat = 28  // Much taller for better voice activity range
    private let barWidth: CGFloat = 3
    private let spacing: CGFloat = 2

    var body: some View {
        let level = Double(max(0.0, min(1.0, viewModel.levelRMS)))
        // Use a gentler curve to show more dynamic range
        let amplifiedLevel = pow(level, 0.5)

        HStack(spacing: spacing) {
            // Left bar (shorter)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.white.opacity(0.9))
                .frame(width: barWidth, height: sideBarHeight(level: amplifiedLevel))

            // Center bar (tallest)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.white.opacity(0.9))
                .frame(width: barWidth, height: centerBarHeight(level: amplifiedLevel))

            // Right bar (shorter)
            RoundedRectangle(cornerRadius: 1.5)
                .fill(Color.white.opacity(0.9))
                .frame(width: barWidth, height: sideBarHeight(level: amplifiedLevel))
        }
        .animation(.spring(response: 0.12, dampingFraction: 0.65), value: viewModel.levelRMS)
    }

    private func centerBarHeight(level: Double) -> CGFloat {
        return minHeight + level * (maxHeight - minHeight)
    }

    private func sideBarHeight(level: Double) -> CGFloat {
        // Side bars are 60-70% of center bar height
        let centerHeight = centerBarHeight(level: level)
        return max(minHeight, centerHeight * 0.65)
    }
}

/// 2x3 grid drag handle for bottom of vertical pill (2 rows, 3 columns)
private struct VerticalDragHandleView: View {
    @Binding var isDragging: Bool
    var onDragStart: () -> Void
    var onDragEnd: () -> Void

    @State private var isHovered: Bool = false

    private let dotSize: CGFloat = 2.5
    private let spacing: CGFloat = 3

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(0..<2, id: \.self) { _ in
                HStack(spacing: spacing) {
                    ForEach(0..<3, id: \.self) { _ in
                        Circle()
                            .fill(Color.white.opacity(isHovered || isDragging ? 0.7 : 0.4))
                            .frame(width: dotSize, height: dotSize)
                    }
                }
            }
        }
        .frame(width: 24, height: 18)  // Hit area
        .contentShape(Rectangle())
        .onHover { hovering in
            isHovered = hovering
            if hovering {
                NSCursor.openHand.push()
            } else if !isDragging {
                NSCursor.pop()
            }
        }
        .gesture(
            DragGesture(minimumDistance: 1)
                .onChanged { _ in
                    if !isDragging {
                        isDragging = true
                        NSCursor.closedHand.push()
                        onDragStart()
                    }
                }
                .onEnded { _ in
                    isDragging = false
                    onDragEnd()
                    NSCursor.pop()
                    if !isHovered {
                        NSCursor.pop()
                    }
                }
        )
        .animation(.easeOut(duration: 0.15), value: isHovered)
        .animation(.easeOut(duration: 0.15), value: isDragging)
    }
}

extension View {
    @ViewBuilder
    func `if`<Transform: View>(_ condition: Bool, transform: (Self) -> Transform) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
